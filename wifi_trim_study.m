function results = wifi_trim_study(settings)
%WIFI_TRIM_STUDY Compare DC/IQ trim with identical channel and noise seeds.
if nargin<1, settings=struct; end
previous=rng; restore=onCleanup(@()rng(previous)); %#ok<NASGU>
if ~isfield(settings,'rxDC'), settings.rxDC=0.12+0.08i; end
if ~isfield(settings,'rxIQGainDB'), settings.rxIQGainDB=1.5; end
if ~isfield(settings,'rxIQPhaseDeg'), settings.rxIQPhaseDeg=8; end
settings.makePlots=false;
labels={'Untrimmed','DC trim','IQ trim','DC + IQ trim'};
results=cell(1,4);
for k=1:4
    settings.dcTrim=ismember(k,[2 4]); settings.iqTrim=ismember(k,[3 4]);
    variant=settings;
    if isfield(variant,'outputDir') && ~isempty(variant.outputDir)
        variant.outputDir=fullfile(variant.outputDir,sprintf('trim_%d',k));
    end
    results{k}=wifi_sim(variant);
end
figure('Name','RX DC and IQ trim comparison','Color','w', ...
    'Position',[80 80 1100 500],'PaperPositionMode','auto');
for k=1:4
    r=results{k}; x=r.settings.snrDB;
    subplot(1,2,1); hold on; plot(x,r.evmDB,'o-');
    subplot(1,2,2); hold on; plot(x,r.per,'o-');
end
subplot(1,2,1); grid on; xlabel('Input SNR (dB)'); ylabel('RMS EVM (dB)'); legend(labels,'Location','best');
subplot(1,2,2); grid on; xlabel('Input SNR (dB)'); ylabel('PER'); ylim([0 1]); legend(labels,'Location','best');
% Independent post-trim tone measurement, including ADC and calibration noise.
c=results{4}.settings; rng(c.seed+100,'twister');
n=(0:c.calibrationSamples-1)'; tone=0.5*exp(2i*pi*293*n/numel(n));
raw=c; raw.dcTrim=false; raw.iqTrim=false;
y0=wifi_rx_frontend(tone,raw,results{4}.calibration);
y1=wifi_rx_frontend(tone,c,results{4}.calibration);
design=[tone conj(tone) ones(size(tone))]; a=design\y0; b=design\y1;
fprintf('\nIndependent RX tone check:\n');
fprintf('DC magnitude: %.5g -> %.5g\n',abs(a(3)),abs(b(3)));
fprintf('Image rejection: %.2f -> %.2f dB\n', ...
    20*log10(abs(a(1))/max(abs(a(2)),eps)),20*log10(abs(b(1))/max(abs(b(2)),eps)));
fprintf('Tone RMS error: %.3f%% -> %.3f%%\n', ...
    100*norm(y0-tone)/norm(tone),100*norm(y1-tone)/norm(tone));
end
