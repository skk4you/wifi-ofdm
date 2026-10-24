function r = wifi_sim(settings)
%WIFI_SIM Standards-based Wi-Fi link and RF impairment laboratory.
% r=wifi_sim(struct('standard','11n','snrDB',10:5:30));
% Requires WLAN System Toolbox/WLAN Toolbox. See README.md.
if nargin<1, settings=struct; end
c=wifi_defaults; names=fieldnames(settings);
for k=1:numel(names)
    assert(isfield(c,names{k}),'Unknown setting: %s',names{k});
    c.(names{k})=settings.(names{k});
end
validate(c);
assert(exist('wlanWaveformGenerator','file')==2, ...
    'WLAN System Toolbox / WLAN Toolbox is required.');
previous=rng; restore=onCleanup(@()rng(previous)); %#ok<NASGU>
rng(c.seed,'twister');
[phy,format,dataField]=configuration(c);
fs=wlanSampleRate(phy); ind=wlanFieldIndices(phy);
powerSweep=~isempty(c.inputPowerDBm);
if powerSweep
    assert(strcmpi(c.channel,'awgn') && c.nTx==1 && c.nRx==1, ...
        'Conducted input-power mode currently requires SISO AWGN.');
    % Complex baseband spans fs Hz; NF is referenced to 290 K.
    noiseFloorDBm=10*log10(1.380649e-23*290*fs)+30+c.noiseFigureDB;
    c.snrDB=c.inputPowerDBm-noiseFloorDBm;
else
    noiseFloorDBm=NaN;
end
if strcmp(format,'VHT'), nBits=8*phy.PSDULength; else, nBits=8*c.payloadBytes; end
rec=wlanRecoveryConfig('EqualizationMethod',c.equalizer, ...
    'PilotPhaseTracking',c.pilotTracking);
[~,cal]=wifi_rx_frontend(zeros(16,c.nRx),c);
channel=makeChannel(c,fs,phy);
nSNR=numel(c.snrDB);
r=struct('settings',c,'phy',phy,'sampleRate',fs,'calibration',cal);
r.noiseFloorDBm=noiseFloorDBm;
% Independent tone at a different frequency/amplitude from calibration.
nn=(0:c.calibrationSamples-1).';
probe=0.5*exp(2i*pi*293*nn/c.calibrationSamples);
probeOut=wifi_rx_frontend(probe,c,cal);
probeFit=[probe conj(probe) ones(size(probe))]\probeOut;
r.frontendMetrics=struct('residualDC',probeFit(3), ...
    'imageRejectionDB',20*log10(abs(probeFit(1))/max(abs(probeFit(2)),eps)), ...
    'toneEVMPercent',100*norm(probeOut-probe)/norm(probe));
fields={'packets','packetErrors','syncFailures','bitErrors','decodedBits', ...
    'decodedPackets','evmPackets','evmPercent','evmDB','effectiveSNRDB', ...
    'measuredSNRDB','rxSNRDB','rxSNRPackets','per','berDecoded','goodputMbps','perLower','perUpper'};
for k=1:numel(fields), r.(fields{k})=zeros(1,nSNR); end
r.diagnostic=struct;
for s=1:nSNR
    errorEnergy=0; referenceEnergy=0; signalEnergy=0; noiseEnergy=0; airtime=0;
    trainingSignal=0; trainingNoise=0;
    while r.packets(s)<c.maxPackets
        if r.packets(s)>=c.minPackets && r.packetErrors(s)>=c.maxPacketErrors, break; end
        bits=randi([0 1],nBits,1);
        tx=wlanWaveformGenerator(bits,phy,'NumPackets',1,'IdleTime',0);
        % A clean independent receiver supplies transmitted reference symbols.
        [~,reference]=decode(tx,phy,format,dataField,ind,rec);
        impaired=txImpair(tx,c);
        tail=max(512,ceil(fs*10e-6));
        padded=[impaired; zeros(tail,c.nTx)];
        if ischar(channel)
            if strcmp(channel,'awgn'), propagated=padded;
            else, propagated=filter(c.channelTaps(:)/norm(c.channelTaps),1,padded); end
        else
            % Independent seeded block fading per packet, with fresh filter
            % state. Reusing reset alone would repeat the same channel draw.
            release(channel);
            channel.Seed=c.seed+1+100003*(s-1)+r.packets(s);
            propagated=channel(padded);
        end
        propagated=[zeros(c.packetDelay,c.nRx); propagated];
        t=(0:size(propagated,1)-1).'/fs;
        phase=cumsum(c.phaseNoiseDeg*pi/180*randn(size(t)));
        propagated=bsxfun(@times,propagated,exp(1i*(2*pi*c.cfoHz*t+phase)));
        % Input SNR is average occupied-packet time-domain sample SNR,
        % before RX IQ/DC/ADC; never includes idle padding in power estimate.
        active=propagated(c.packetDelay+(1:size(tx,1)),:);
        power=mean(abs(active(:)).^2);
        if powerSweep
            % Normalize generator power at the DUT input reference plane,
            % then apply fixed receiver gain. Noise never follows signal.
            target=10^((c.inputPowerDBm(s)-c.referenceInputDBm)/10);
            propagated=propagated*sqrt(target/power);
            active=propagated(c.packetDelay+(1:size(tx,1)),:);
            nv=10^((noiseFloorDBm-c.referenceInputDBm)/10);
        else
            nv=power*10^(-c.snrDB(s)/10);
        end
        noise=sqrt(nv/2)*(randn(size(propagated))+1i*randn(size(propagated)));
        rx=wifi_rx_frontend(propagated+noise,c,cal);
        signalEnergy=signalEnergy+sum(abs(active(:)).^2);
        noiseEnergy=noiseEnergy+numel(active)*nv;
        r.packets(s)=r.packets(s)+1; airtime=airtime+size(tx,1)/fs;
        [aligned,status,sync]=synchronize(rx,phy,ind,size(tx,1),fs,c);
        if ~status
            r.syncFailures(s)=r.syncFailures(s)+1;
            r.packetErrors(s)=r.packetErrors(s)+1;
            continue
        end
        % Do not hide implementation exceptions as packet errors.
        [received,equalized,h,nvar,ltfSignal,ltfNoise]=decode(aligned,phy,format,dataField,ind,rec);
        if isfinite(ltfSignal) && isfinite(ltfNoise) && ltfNoise>0
            trainingSignal=trainingSignal+ltfSignal;
            trainingNoise=trainingNoise+ltfNoise;
            r.rxSNRPackets(s)=r.rxSNRPackets(s)+1;
        end
        assert(numel(received)==numel(bits),'Recovered PSDU length mismatch.');
        be=sum(double(received(:))~=bits);
        r.bitErrors(s)=r.bitErrors(s)+be;
        r.decodedBits(s)=r.decodedBits(s)+numel(bits);
        r.decodedPackets(s)=r.decodedPackets(s)+1;
        r.packetErrors(s)=r.packetErrors(s)+(be>0);
        if all(isfinite(equalized(:))) && isequal(size(equalized),size(reference))
            e=abs(equalized-reference).^2; ref=abs(reference).^2;
            errorEnergy=errorEnergy+sum(e(:)); referenceEnergy=referenceEnergy+sum(ref(:));
            r.evmPackets(s)=r.evmPackets(s)+1;
            d=struct('tx',impaired,'referenceTx',tx,'rx',rx,'equalized',equalized,'reference',reference, ...
                'channelEstimate',h,'noiseVariance',nvar,'sync',sync, ...
                'snrDB',c.snrDB(s),'perCarrierEVM',100*sqrt(sum(e,2)./max(sum(ref,2),eps)), ...
                'perSymbolEVM',100*sqrt(sum(e,1)./max(sum(ref,1),eps)));
            r.diagnostic=d; % Last finite decoded packet; includes incorrect payloads.
        end
    end
    r.per(s)=r.packetErrors(s)/r.packets(s);
    [r.perLower(s),r.perUpper(s)]=wilson(r.packetErrors(s),r.packets(s));
    r.berDecoded(s)=r.bitErrors(s)/max(r.decodedBits(s),1);
    if r.decodedBits(s)==0, r.berDecoded(s)=NaN; end
    if referenceEnergy>0
        ratio=errorEnergy/referenceEnergy;
        r.evmPercent(s)=100*sqrt(ratio); r.evmDB(s)=10*log10(max(ratio,realmin));
        r.effectiveSNRDB(s)=-r.evmDB(s);
    else
        r.evmPercent(s)=NaN; r.evmDB(s)=NaN; r.effectiveSNRDB(s)=NaN;
    end
    r.measuredSNRDB(s)=10*log10(signalEnergy/max(noiseEnergy,realmin));
    r.rxSNRDB(s)=NaN;
    if r.rxSNRPackets(s)>0
        r.rxSNRDB(s)=10*log10(max(trainingSignal,realmin)/trainingNoise);
    end
    r.goodputMbps(s)=nBits*(r.packets(s)-r.packetErrors(s))/airtime/1e6;
    if powerSweep, fprintf('Input %g dBm | ',c.inputPowerDBm(s)); end
    fprintf('%s SNR %3g dB: PER %.3f (%d/%d), EVM %.2f%%, decoded BER %.3g, sync fails %d\n', ...
        c.standard,c.snrDB(s),r.per(s),r.packetErrors(s),r.packets(s), ...
        r.evmPercent(s),r.berDecoded(s),r.syncFailures(s));
end
r.summary=table(c.snrDB(:),r.packets(:),r.packetErrors(:),r.per(:), ...
    r.perLower(:),r.perUpper(:),r.berDecoded(:),r.evmPercent(:),r.evmDB(:), ...
    r.effectiveSNRDB(:),r.goodputMbps(:),r.syncFailures(:),r.evmPackets(:), ...
    'VariableNames',{'SNRdB','Packets','PacketErrors','PER','PERLower95','PERUpper95', ...
    'BERDecoded','EVMPercent','EVMdB','EffectiveSNRdB','GoodputMbps','SyncFailures','EVMPackets'});
if c.makePlots, wifi_plot(r); end
if ~isempty(c.outputDir)
    if ~exist(c.outputDir,'dir'), mkdir(c.outputDir); end
    save(fullfile(c.outputDir,'results.mat'),'r');
    writetable(r.summary,fullfile(c.outputDir,'metrics.csv'));
end
end

function [phy,format,dataField]=configuration(c)
bw=sprintf('CBW%d',c.bandwidth);
switch lower(c.standard)
    case {'11a','11g'}
        assert(c.nTx==1 && c.nStreams==1,'Non-HT supports one transmitter/stream here.');
        assert(c.bandwidth==20,'11a/g OFDM requires 20 MHz.');
        phy=wlanNonHTConfig('MCS',c.mcs,'PSDULength',c.payloadBytes);
        format='NonHT'; dataField='NonHTData';
    case '11n'
        phy=wlanHTConfig('ChannelBandwidth',bw,'MCS',c.mcs,'PSDULength',c.payloadBytes, ...
            'NumTransmitAntennas',c.nTx,'NumSpaceTimeStreams',c.nStreams, ...
            'GuardInterval',c.guardInterval,'ChannelCoding',c.coding);
        format='HT'; dataField='HTData';
    case '11ac'
        phy=wlanVHTConfig('ChannelBandwidth',bw,'MCS',c.mcs,'APEPLength',c.payloadBytes, ...
            'NumTransmitAntennas',c.nTx,'NumSpaceTimeStreams',c.nStreams, ...
            'GuardInterval',c.guardInterval,'ChannelCoding',c.coding);
        format='VHT'; dataField='VHTData';
    otherwise
        error('wifi:Standard','Supported: 11a, 11g (OFDM), 11n, 11ac. HE/EHT require a newer backend.');
end
end

function channel=makeChannel(c,fs,phy)
switch lower(c.channel)
    case {'awgn','taps'}
        assert(c.nTx==1 && c.nRx==1,'AWGN/taps mode is SISO; use tgn/tgac for MIMO.');
        channel=lower(c.channel);
    case {'tgn','tgac'}
        args={'SampleRate',fs,'NumTransmitAntennas',c.nTx,'NumReceiveAntennas',c.nRx, ...
            'DelayProfile',c.delayProfile,'LargeScaleFadingEffect','None', ...
            'RandomStream','mt19937ar with seed','Seed',c.seed+1};
        if strcmpi(c.channel,'tgn'), channel=wlanTGnChannel(args{:});
        else, channel=wlanTGacChannel(args{:},'ChannelBandwidth',phy.ChannelBandwidth); end
    otherwise, error('Unknown channel. Use awgn, taps, tgn or tgac.');
end
end

function y=txImpair(x,c)
g=10^(c.txIQGainDB/20); p=c.txIQPhaseDeg*pi/180;
y=real(x)+1i*g*(sin(p)*real(x)+cos(p)*imag(x));
if isfinite(c.paBackoffDB)
    saturation=sqrt(mean(abs(y(:)).^2))*10^(c.paBackoffDB/20);
    y=y./(1+(abs(y)/saturation).^6).^(1/6); % Rapp PA, p=3
end
end

function [out,ok,d]=synchronize(rx,phy,ind,n,fs,c)
bw=phy.ChannelBandwidth; ok=false; out=[];
d=struct('packetOffset',NaN,'coarseCFOHz',0,'fineCFOHz',0);
if c.synchronize
    offset=wlanPacketDetect(rx,bw);
    if isempty(offset) || offset+ind.LSIG(2)>size(rx,1), return; end
    d.coarseCFOHz=wlanCoarseCFOEstimate(rx(offset+(ind.LSTF(1):ind.LSTF(2)),:),bw);
    rx=rotate(rx,-d.coarseCFOHz,fs);
    fine=wlanSymbolTimingEstimate(rx(offset+(ind.LSTF(1):ind.LSIG(2)),:),bw);
    if isempty(fine), return; end
    offset=offset+fine;
else
    offset=c.packetDelay; % Known timing only; CFO correction disabled.
end
if offset<0 || offset+n>size(rx,1), return; end
if c.synchronize
    d.fineCFOHz=wlanFineCFOEstimate(rx(offset+(ind.LLTF(1):ind.LLTF(2)),:),bw);
    rx=rotate(rx,-d.fineCFOHz,fs);
end
d.packetOffset=offset; out=rx(offset+(1:n),:); ok=true;
end

function y=rotate(x,hz,fs)
y=bsxfun(@times,x,exp(2i*pi*hz*(0:size(x,1)-1).'/fs));
end

function [bits,eq,h,nv,ltfSignal,ltfNoise]=decode(rx,phy,format,dataField,ind,rec)
lltf=wlanLLTFDemodulate(rx(ind.LLTF(1):ind.LLTF(2),:),phy.ChannelBandwidth);
delta=lltf(:,1,:)-lltf(:,2,:); nv=mean(abs(delta(:)).^2)/2;
% Two repeated received L-LTF symbols: difference cancels the stationary
% channel/signal. Their average contains half the single-symbol noise power.
ltfMean=(lltf(:,1,:)+lltf(:,2,:))/2;
ltfNoise=nv;
ltfSignal=max(mean(abs(ltfMean(:)).^2)-ltfNoise/2,0);
switch format
    case 'NonHT', h=wlanLLTFChannelEstimate(lltf,phy.ChannelBandwidth);
    case 'HT'
        lt=wlanHTLTFDemodulate(rx(ind.HTLTF(1):ind.HTLTF(2),:),phy);
        h=wlanHTLTFChannelEstimate(lt,phy);
    case 'VHT'
        lt=wlanVHTLTFDemodulate(rx(ind.VHTLTF(1):ind.VHTLTF(2),:),phy);
        h=wlanVHTLTFChannelEstimate(lt,phy);
end
if ~strcmp(format,'NonHT'), nv=nv*size(h,1)/size(lltf,1)*phy.NumSpaceTimeStreams; end
nv=max(nv,1e-12); range=ind.(dataField); data=rx(range(1):range(2),:);
switch format
    case 'NonHT', [bits,eq]=wlanNonHTDataRecover(data,h,nv,phy,rec);
    case 'HT', [bits,eq]=wlanHTDataRecover(data,h,nv,phy,rec);
    case 'VHT', [bits,~,eq]=wlanVHTDataRecover(data,h,nv,phy,rec);
end
end

function [lo,hi]=wilson(errors,n)
z=1.95996398454005; p=errors/n; den=1+z*z/n;
center=(p+z*z/(2*n))/den; radius=z*sqrt(p*(1-p)/n+z*z/(4*n*n))/den;
lo=max(0,center-radius); hi=min(1,center+radius);
end

function validate(c)
validateattributes(c.snrDB,{'numeric'},{'vector','real','finite','nonempty'});
if ~isempty(c.inputPowerDBm)
    validateattributes(c.inputPowerDBm,{'numeric'},{'vector','real','finite','nonempty'});
end
validateattributes(c.noiseFigureDB,{'numeric'},{'scalar','real','finite','nonnegative'});
validateattributes(c.referenceInputDBm,{'numeric'},{'scalar','real','finite'});
for f={'maxPackets','minPackets','maxPacketErrors','payloadBytes','nTx','nRx','nStreams','calibrationSamples'}
    validateattributes(c.(f{1}),{'numeric'},{'scalar','integer','positive'});
end
assert(c.minPackets<=c.maxPackets,'minPackets must not exceed maxPackets.');
assert(c.nStreams<=c.nTx && c.nStreams<=c.nRx,'Streams must not exceed TX/RX antennas.');
validateattributes(c.packetDelay,{'numeric'},{'scalar','integer','nonnegative'});
validateattributes(c.seed,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(c.mcs,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(c.bandwidth,{'numeric'},{'scalar','integer','positive','finite'});
for f={'dcTrim','iqTrim','synchronize','makePlots'}
    assert(isscalar(c.(f{1})) && any(c.(f{1})==[0 1]),'%s must be scalar logical.',f{1});
end
validateattributes(c.rxDC,{'numeric'},{'scalar','finite'});
validateattributes(c.channelTaps,{'numeric'},{'vector','finite','nonempty'});
assert(norm(c.channelTaps)>0,'Channel taps must have nonzero energy.');
for f={'cfoHz','phaseNoiseDeg','txIQGainDB','txIQPhaseDeg','rxIQGainDB','rxIQPhaseDeg','calibrationSNRDB'}
    validateattributes(c.(f{1}),{'numeric'},{'scalar','real','finite'});
end
assert(c.phaseNoiseDeg>=0,'Phase noise must be nonnegative.');
assert(isinf(c.adcBits) || (c.adcBits>=2 && c.adcBits<=24 && c.adcBits==fix(c.adcBits)), ...
    'adcBits must be Inf or integer 2..24.');
validateattributes(c.adcFullScale,{'numeric'},{'scalar','real','finite','positive'});
assert(isscalar(c.paBackoffDB) && isreal(c.paBackoffDB) && ~isnan(c.paBackoffDB),'Invalid PA backoff.');
end
