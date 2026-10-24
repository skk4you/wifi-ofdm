function check_wifi_rx_per
%CHECK_WIFI_RX_PER Power calibration, fixed counts, noise and overload checks.
visibility=get(0,'DefaultFigureVisible');
cleanup=onCleanup(@()set(0,'DefaultFigureVisible',visibility)); %#ok<NASGU>
set(0,'DefaultFigureVisible','off');
% c=struct('inputPowerDBm',[-100 -82 -60],'packetsPerLevel',1000, ...
%     'payloadBytes',128,'makePlots',true,'outputDir',fullfile(pwd,'test_output','rx_per'));
c=struct('inputPowerDBm',[-100:5:0],'packetsPerLevel',1000, ...
    'payloadBytes',128,'makePlots',true,'outputDir',fullfile(pwd,'test_output','rx_per'));
r=wifi_rx_per(c);
assert(all(r.sent==1000),'Not exactly 1000 transmitted packets per level.');
assert(all(r.received+r.lost==1000),'Packet accounting mismatch.');
assert(max(abs(r.per-r.lost./r.sent))<1e-12,'PER denominator mismatch.');
assert(r.per(1)>0.9 && r.per(end)<0.1,'Sensitivity transition missing.');
expected=10*log10(1.380649e-23*290*20e6)+30+7;
assert(abs(r.noiseFloorDBm-expected)<1e-10,'Wrong thermal noise budget.');
assert(max(abs(r.link.measuredSNRDB-(c.inputPowerDBm-expected)))<1e-8, ...
    'dBm conversion does not match actual injected signal/noise ratio.');
assert(r.link.perUpper(end)>0,'Zero errors must retain nonzero uncertainty.');
assert(isnan(r.link.rxSNRDB(1)) && r.link.rxSNRPackets(1)==0, ...
    'Failed acquisitions must not be assigned an injected SNR.');
assert(r.link.rxSNRDB(end)>r.link.rxSNRDB(2)+15, ...
    'Received training-field SNR does not track the received signal.');
assert(abs(r.link.rxSNRDB(end)-r.link.settings.snrDB(end))<3, ...
    'High-SNR AWGN training estimate is inconsistent with the link budget.');
% Fixed ADC gain intentionally creates strong-input clipping/overload.
c.inputPowerDBm=[-100 -65 -5]; c.packetsPerLevel=20;
c.adcBits=10; c.adcFullScale=1; c.referenceInputDBm=-40;
c.outputDir=fullfile(pwd,'test_output','rx_bathtub');
b=wifi_rx_per(c);
assert(b.per(1)>0.9 && b.per(2)<0.1 && b.per(3)>0.9,'ADC bathtub edges missing.');
% Increasing NF must increase the input-referred noise floor by the same dB.
c.inputPowerDBm=-65; c.packetsPerLevel=2; c.makePlots=false; c.outputDir='';
c.noiseFigureDB=10; q=wifi_rx_per(c);
assert(abs(q.noiseFloorDBm-r.noiseFloorDBm-3)<1e-10,'NF not reflected in noise floor.');
fprintf('\nAll conducted RX PER checks passed.\n');
end
