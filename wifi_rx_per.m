function r = wifi_rx_per(settings)
%WIFI_RX_PER Conducted single-radio RX PER versus input power, LitePoint style.
% r=wifi_rx_per(struct('standard','11ac','mcs',3,'channelNumber',36, ...
%     'bandwidth',20,'inputPowerDBm',-100:1:-50,'packetsPerLevel',1000));
if nargin<1, settings=struct; end
defaults=wifi_defaults;
defaults.inputPowerDBm=-100:1:-50;
defaults.channelNumber=36; defaults.band='5GHz';
defaults.packetsPerLevel=1000; defaults.perThreshold=0.10;
defaults.outputDir=fullfile(pwd,'results','rx_per');
names=fieldnames(settings);
for k=1:numel(names)
    assert(isfield(defaults,names{k}),'Unknown setting: %s',names{k});
    defaults.(names{k})=settings.(names{k});
end
c=defaults;
assert(~isempty(c.inputPowerDBm),'Specify an input power vector in dBm.');
validateattributes(c.inputPowerDBm,{'numeric'},{'vector','real','finite'});
c.inputPowerDBm=c.inputPowerDBm(:).';
assert(all(diff(c.inputPowerDBm)>0),'Input powers must be strictly increasing.');
validateattributes(c.packetsPerLevel,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(c.perThreshold,{'numeric'},{'scalar','>',0,'<',1,'finite'});
validateattributes(c.channelNumber,{'numeric'},{'scalar','integer','positive','finite'});
assert(strcmpi(c.channel,'awgn') && c.nTx==1 && c.nRx==1 && c.nStreams==1, ...
    'This test is one conducted SISO radio; use AWGN and one TX/RX/stream.');
switch lower(c.band)
    case '2.4ghz'
        assert(any(c.channelNumber==1:14),'Invalid 2.4 GHz channel.');
        assert(~strcmpi(c.standard,'11a') && ~strcmpi(c.standard,'11ac'), ...
            'Use 11g or 11n for 2.4 GHz.');
        if c.channelNumber==14, error('Channel 14 is not supported for these OFDM modes.'); end
        center=2407+5*c.channelNumber;
    case '5ghz'
        assert(c.channelNumber>=32 && c.channelNumber<=177,'Invalid 5 GHz center channel.');
        assert(~strcmpi(c.standard,'11g'),'11g uses 2.4 GHz.');
        center=5000+5*c.channelNumber;
    otherwise, error('Use band 2.4GHz or 5GHz. HE/EHT/6 GHz are not supported.');
end
% Channel number is center-channel metadata; waveform remains complex baseband.
% No regional channel plan or channel-dependent RF response is synthesized.
base=c; base=rmfield(base,{'channelNumber','band','packetsPerLevel','perThreshold'});
base.maxPackets=c.packetsPerLevel; base.minPackets=c.packetsPerLevel;
base.maxPacketErrors=c.packetsPerLevel; % Exactly N packets, including weak levels.
base.makePlots=false; base.outputDir='';
fprintf('Conducted RX: %s MCS %d, %s CH %d (%.0f MHz), BW %d MHz\n', ...
    c.standard,c.mcs,c.band,c.channelNumber,center,c.bandwidth);
fprintf('%d packets per level; no early stopping.\n',c.packetsPerLevel);
link=wifi_sim(base);
r=struct('settings',c,'centerFrequencyMHz',center,'noiseFloorDBm',link.noiseFloorDBm);
r.sent=link.packets; r.received=link.packets-link.packetErrors;
r.lost=link.packetErrors; r.per=1-r.received./r.sent;
r.link=link;
r.summary=table(c.inputPowerDBm(:),link.settings.snrDB(:),r.sent(:),r.received(:), ...
    r.lost(:),r.per(:),100*r.per(:),link.perLower(:),link.perUpper(:), ...
    link.syncFailures(:),link.evmPercent(:),link.rxSNRDB(:),link.rxSNRPackets(:), ...
    'VariableNames',{'InputPowerDBm','SNRdB','Sent','ReceivedOK','LostOrBad','PER', ...
    'PERPercent','PERLower95','PERUpper95','SyncFailures','EVMPercent','ReceivedSNRdB','SNRPackets'});
% Report every contiguous observed pass window.
% No interpolation/extrapolation, and endpoints are explicitly censored.
pass=r.per<=c.perThreshold;
r.passWindowsDBm=zeros(0,2);
starts=find(diff([false pass(:).' false])==1);
ends=find(diff([false pass(:).' false])==-1)-1;
for k=1:numel(starts)
    r.passWindowsDBm(k,:)=c.inputPowerDBm([starts(k) ends(k)]);
end
r.lowestPassingDBm=NaN;
if any(pass), r.lowestPassingDBm=min(c.inputPowerDBm(pass)); end
r.lowerEdgeBracketed=any(pass) && ~pass(1);
r.upperEdgeBracketed=any(pass) && ~pass(end);
disp(r.summary);
fprintf('Input-referred integrated noise floor: %.2f dBm\n',r.noiseFloorDBm);
fprintf('Lowest tested passing power at PER <= %.1f%%: %g dBm\n', ...
    100*c.perThreshold,r.lowestPassingDBm);
if c.makePlots
    f=figure('Name','Conducted RX PER bathtub','Color','w', ...
        'Position',[70 70 1250 850],'PaperPositionMode','auto');
    subplot(2,2,1);
    errorbar(c.inputPowerDBm,100*r.per,100*(r.per-link.perLower), ...
        100*(link.perUpper-r.per),'o-'); hold on;
    plot(c.inputPowerDBm,100*c.perThreshold*ones(size(r.per)),'k--');
    grid on; ylim([0 100]); xlabel('DUT input power (dBm)'); ylabel('PER (%)');
    title(sprintf('%s MCS %d, CH %d, BW %d MHz, %d packets/level', ...
        c.standard,c.mcs,c.channelNumber,c.bandwidth,c.packetsPerLevel));
    subplot(2,2,2); plot(c.inputPowerDBm,r.received,'o-'); grid on;
    xlabel('DUT input power (dBm)'); ylabel('Successfully received packets');
    ylim([0 c.packetsPerLevel]); title('Acquisition failures + bad payloads count as lost');
    subplot(2,2,3); plot(c.inputPowerDBm,link.rxSNRDB,'o-'); grid on;
    xlabel('DUT input power (dBm)'); ylabel('Estimated received SNR (dB)');
    title('Received L-LTF estimate; no acquisition shown as gaps');
    subplot(2,2,4); plot(c.inputPowerDBm,link.evmPercent,'o-'); grid on;
    xlabel('DUT input power (dBm)'); ylabel('RMS EVM (%)');
    title('EVM of acquired packets; no acquisition shown as gaps');
end
if ~isempty(c.outputDir)
    if ~exist(c.outputDir,'dir'), mkdir(c.outputDir); end
    save(fullfile(c.outputDir,'rx_per.mat'),'r');
    writetable(r.summary,fullfile(c.outputDir,'rx_per.csv'));
    if c.makePlots, saveas(f,fullfile(c.outputDir,'rx_per.png')); end
end
end
