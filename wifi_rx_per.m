function r = wifi_rx_per(settings)
%WIFI_RX_PER Conducted single-radio RX PER versus input power, LitePoint style.
% r=wifi_rx_per(struct('standard','11ac','mcs',3,'channelNumber',36, ...
%     'bandwidth',20,'inputPowerDBm',-100:1:-50,'packetsPerLevel',1000));
if nargin<1, settings=struct; end
defaults=wifi_defaults;
defaults.inputPowerDBm=-100:1:-50;
defaults.channelNumber=36; defaults.band='5GHz';
defaults.packetsPerLevel=1000; defaults.perThreshold=0.10;
defaults.uniqueOutputDir=true;
defaults.snrMetric='mer'; % Effective received SNR from residual symbol error; 'ltf' for noise-only estimate.
defaults.refineSensitivity=false; defaults.refinementStepDB=1;
defaults.outputDir=fullfile(pwd,'results','rx_per');
names=fieldnames(settings);
for k=1:numel(names)
    assert(isfield(defaults,names{k}),'Unknown setting: %s',names{k});
    defaults.(names{k})=settings.(names{k});
end
c=defaults;
assert(ischar(c.snrMetric) && any(strcmp(c.snrMetric,{'mer','ltf'})), ...
    'snrMetric must be mer or ltf.');
assert(~isempty(c.inputPowerDBm),'Specify an input power vector in dBm.');
validateattributes(c.inputPowerDBm,{'numeric'},{'vector','real','finite'});
c.inputPowerDBm=c.inputPowerDBm(:).';
assert(all(diff(c.inputPowerDBm)>0),'Input powers must be strictly increasing.');
validateattributes(c.packetsPerLevel,{'numeric'},{'scalar','integer','positive','finite'});
validateattributes(c.perThreshold,{'numeric'},{'scalar','>',0,'<',1,'finite'});
validateattributes(c.refinementStepDB,{'numeric'},{'scalar','real','finite','positive'});
for flag={'uniqueOutputDir','refineSensitivity'}
    assert(isscalar(c.(flag{1})) && any(c.(flag{1})==[0 1]),'%s must be logical.',flag{1});
end
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
base=c; base=rmfield(base,{'channelNumber','band','packetsPerLevel','perThreshold', ...
    'uniqueOutputDir','refineSensitivity','refinementStepDB','snrMetric'});
base.maxPackets=c.packetsPerLevel; base.minPackets=c.packetsPerLevel;
base.maxPacketErrors=c.packetsPerLevel; % Exactly N packets, including weak levels.
base.makePlots=false; base.outputDir='';
fprintf('Conducted RX: %s MCS %d, %s CH %d (%.0f MHz), BW %d MHz\n', ...
    c.standard,c.mcs,c.band,c.channelNumber,center,c.bandwidth);
fprintf('%d packets per level; no early stopping.\n',c.packetsPerLevel);
outputDir=c.outputDir;
if ~isempty(outputDir)
    if c.uniqueOutputDir
        outputDir=wifi_run_folder(outputDir,sprintf('%s_mcs%d_ch%d_bw%d', ...
            c.standard,c.mcs,c.channelNumber,c.bandwidth));
    elseif ~exist(outputDir,'dir'), mkdir(outputDir); end
    save(fullfile(outputDir,'configuration.mat'),'c');
    fid=fopen(fullfile(outputDir,'configuration.json'),'w');
    assert(fid>=0,'Cannot write test configuration.');
    closer=onCleanup(@()fclose(fid)); %#ok<NASGU>
    fprintf(fid,'%s\n',jsonencode(jsonConfiguration(c))); clear closer
    fprintf('Output folder: %s\n',outputDir);
end
link=wifi_sim(base);
coarseLink=link;
coarseSensitivity=wifi_rx_sensitivity(c.inputPowerDBm,link.per,c.perThreshold);
refinement=struct('status','disabled','powerDBm',[],'link',[]);
if c.refineSensitivity
    refinement.status='unbracketed';
    if coarseSensitivity.bracketed
        bounds=coarseSensitivity.bracketDBm;
        extra=(bounds(1)+c.refinementStepDB):c.refinementStepDB:bounds(2);
        extra=extra(extra>bounds(1)+1e-9 & extra<bounds(2)-1e-9);
        if ~isempty(extra)
            extra=extra(all(abs(bsxfun(@minus,extra(:),c.inputPowerDBm))>1e-9,2));
        end
        refinement.status='already_resolved';
        if ~isempty(extra)
            fprintf('Sensitivity refinement enabled: %d NEW levels at %g dB steps, %d packets each.\n', ...
                numel(extra),c.refinementStepDB,c.packetsPerLevel);
            fine=base; fine.inputPowerDBm=extra(:).';
            fine.seed=mod(c.seed+1000003,2^32);
            fineLink=wifi_sim(fine);
            refinement=struct('status','completed','powerDBm',fine.inputPowerDBm,'link',fineLink);
            link=mergeLinks(link,fineLink);
        end
    end
end
x=link.settings.inputPowerDBm;
r=struct('settings',c,'outputDir',outputDir,'testedPowerDBm',x, ...
    'centerFrequencyMHz',center,'noiseFloorDBm',link.noiseFloorDBm, ...
    'coarseSensitivity',coarseSensitivity,'refinement',refinement,'coarseLink',coarseLink);
r.sent=link.packets; r.received=link.packets-link.packetErrors;
r.lost=link.packetErrors; r.per=1-r.received./r.sent;
r.link=link;
r.summary=table(x(:),link.settings.snrDB(:),r.sent(:),r.received(:), ...
    r.lost(:),r.per(:),100*r.per(:),link.perLower(:),link.perUpper(:), ...
    link.syncFailures(:),link.evmPercent(:),link.rxSNRDB(:),link.rxSNRPackets(:), ...
    'VariableNames',{'InputPowerDBm','SNRdB','Sent','ReceivedOK','LostOrBad','PER', ...
    'PERPercent','PERLower95','PERUpper95','SyncFailures','EVMPercent','ReceivedSNRdB','SNRPackets'});
r.summary.ReceivedMERdB=wifi_evm_to_mer(link.evmPercent(:));
r.summary.LTFNoiseSNRdB=link.rxSNRDB(:); % ReceivedSNRdB retained for backward compatibility.
r.plottedSNRDB=r.summary.ReceivedMERdB;
if strcmp(c.snrMetric,'ltf'), r.plottedSNRDB=r.summary.LTFNoiseSNRdB; end
r.sensitivity=wifi_rx_sensitivity(x,r.per,c.perThreshold);
r.passWindowsDBm=r.sensitivity.passWindowsDBm;
r.lowestPassingDBm=r.sensitivity.lowestPassingDBm;
r.lowerEdgeBracketed=r.sensitivity.bracketed;
r.upperEdgeBracketed=any(r.per<=c.perThreshold) && r.per(end)>c.perThreshold;
disp(r.summary);
fprintf('Input-referred integrated noise floor: %.2f dBm\n',r.noiseFloorDBm);
fprintf('Lowest tested passing power at PER <= %.1f%%: %g dBm\n', ...
    100*c.perThreshold,r.lowestPassingDBm);
fprintf('Sensitivity: %s; interpolated crossing %g dBm; bracket [%g, %g] dBm\n', ...
    r.sensitivity.status,r.sensitivity.estimateDBm,r.sensitivity.bracketDBm);
if c.makePlots
    f=figure('Name','Conducted RX PER bathtub','Color','w', ...
        'Position',[70 70 1250 850],'PaperPositionMode','auto');
    subplot(2,2,1);
    errorbar(x,100*r.per,100*(r.per-link.perLower), ...
        100*(link.perUpper-r.per),'o-'); hold on;
    plot(x,100*c.perThreshold*ones(size(r.per)),'k--');
    if r.sensitivity.bracketed
        plot(r.sensitivity.estimateDBm,100*c.perThreshold,'rp','MarkerSize',12,'LineWidth',2);
    end
    grid on; ylim([0 100]); xlabel('DUT input power (dBm)'); ylabel('PER (%)');
    title(sprintf('%s MCS %d, CH %d, BW %d MHz, %d packets/level', ...
        c.standard,c.mcs,c.channelNumber,c.bandwidth,c.packetsPerLevel));
    subplot(2,2,2); plot(x,r.received,'o-'); grid on;
    xlabel('DUT input power (dBm)'); ylabel('Successfully received packets');
    ylim([0 c.packetsPerLevel]); title('Acquisition failures + bad payloads count as lost');
    subplot(2,2,3); plot(x,r.plottedSNRDB,'o-'); grid on;
    xlabel('DUT input power (dBm)');
    if strcmp(c.snrMetric,'mer')
        ylabel('Effective received SNR / MER (dB)');
        title('Residual symbol error: -20 log10(EVM / 100)');
    else
        ylabel('Received L-LTF noise SNR (dB)');
        title('Repeated-training noise estimate (distortion may cancel)');
    end
    subplot(2,2,4); plot(x,link.evmPercent,'o-'); grid on;
    xlabel('DUT input power (dBm)'); ylabel('RMS EVM (%)');
    title('EVM of acquired packets; no acquisition shown as gaps');
end
if ~isempty(outputDir)
    save(fullfile(outputDir,'rx_per.mat'),'r');
    writetable(r.summary,fullfile(outputDir,'rx_per.csv'));
    sens=r.sensitivity;
    sensitivityTable=table({sens.status},sens.threshold,sens.estimateDBm,sens.lowestPassingDBm, ...
        sens.bracketDBm(1),sens.bracketDBm(2),sens.nonmonotonic, ...
        'VariableNames',{'Status','PERThreshold','InterpolatedDBm','LowestTestedPassDBm', ...
        'BracketLowDBm','BracketHighDBm','Nonmonotonic'});
    writetable(sensitivityTable,fullfile(outputDir,'sensitivity.csv'));
    if c.makePlots, saveas(f,fullfile(outputDir,'rx_per.png')); end
end
end

function a=mergeLinks(a,b)
% Merge only point metrics; keep full coarse/fine runs separately for audit.
[x,order]=sort([a.settings.inputPowerDBm b.settings.inputPowerDBm]);
fields={'packets','packetErrors','syncFailures','bitErrors','decodedBits', ...
    'decodedPackets','evmPackets','evmPercent','evmDB','effectiveSNRDB', ...
    'measuredSNRDB','rxSNRDB','rxSNRPackets','per','berDecoded','goodputMbps','perLower','perUpper'};
for k=1:numel(fields)
    values=[a.(fields{k}) b.(fields{k})]; a.(fields{k})=values(order);
end
t=[a.summary;b.summary]; a.summary=t(order,:);
a.settings.inputPowerDBm=x; a.settings.snrDB=x-a.noiseFloorDBm;
a.diagnostic=b.diagnostic;
end

function out=jsonConfiguration(c)
% MAT is the exact/reloadable configuration. JSON represents complex values
% explicitly and nonfinite controls (e.g. ideal ADC Inf) as strings.
out=c; names=fieldnames(c);
for k=1:numel(names)
    v=c.(names{k});
    if isnumeric(v) && ~isreal(v)
        out.(names{k})=struct('real',real(v),'imag',imag(v));
    elseif isnumeric(v) && isscalar(v) && ~isfinite(v)
        out.(names{k})=num2str(v);
    end
end
end
