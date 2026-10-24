function check_wifi_sim
%CHECK_WIFI_SIM Numerical integration and calibration regression tests.
visibility=get(0,'DefaultFigureVisible');
restore=onCleanup(@()set(0,'DefaultFigureVisible',visibility)); %#ok<NASGU>
set(0,'DefaultFigureVisible','off');
c=struct('snrDB',60,'maxPackets',3,'minPackets',3,'maxPacketErrors',3, ...
    'payloadBytes',128,'makePlots',false,'cfoHz',20000);
for standard={'11a','11g','11n','11ac'}
    c.standard=standard{1}; r=wifi_sim(c);
    assert(r.per==0 && r.berDecoded==0,'Clean link failed: %s',c.standard);
    assert(r.evmPercent<1,'Unexpected clean EVM: %s',c.standard);
end
c.standard='11ac'; c.channel='taps'; r=wifi_sim(c);
assert(r.per==0 && r.evmPercent<1,'Multipath equalization failed.');
c.channel='awgn'; c.bandwidth=80; c.mcs=8; c.coding='LDPC'; c.guardInterval='Short';
r=wifi_sim(c); assert(r.per==0,'80 MHz / LDPC / short GI recovery failed.');
c.bandwidth=20; c.mcs=3; c.coding='BCC'; c.guardInterval='Long';
c.channel='tgac'; c.nTx=2; c.nRx=2; c.nStreams=2; r=wifi_sim(c);
assert(r.per==0,'MIMO link failed.');
c.standard='11n'; c.channel='tgn'; c.mcs=11;
r=wifi_sim(c); assert(r.per==0,'HT two-stream MIMO failed.');
c.standard='11ac'; c.mcs=3;
c.channel='awgn'; c.nTx=1; c.nRx=1; c.nStreams=1;
c.rxDC=0.12+0.08i; c.rxIQGainDB=2; c.rxIQPhaseDeg=10;
a=wifi_sim(c); c.dcTrim=true; c.iqTrim=true; b=wifi_sim(c);
assert(b.evmPercent<a.evmPercent/5,'RX trims did not improve EVM.');
assert(b.per==0,'Trimmed packet recovery failed.');
d=wifi_defaults; d.rxDC=c.rxDC; d.rxIQGainDB=2; d.rxIQPhaseDeg=10;
d.dcTrim=true; d.iqTrim=true; d.calibrationSNRDB=100;
rng(44); x=randn(8192,1)+1i*randn(8192,1); y=wifi_rx_frontend(x,d);
assert(norm(y-x)/norm(x)<1e-4,'Independent RX trim inversion failed.');
c=struct('snrDB',[0 15 35],'maxPackets',20,'minPackets',20, ...
    'maxPacketErrors',20,'payloadBytes',128,'makePlots',false);
r=wifi_sim(c);
assert(r.per(1)>r.per(end),'PER does not improve with SNR.');
assert(r.evmPercent(end)<r.evmPercent(2),'EVM does not improve with SNR.');
assert(all(r.perUpper>r.perLower),'PER intervals invalid.');
assert(r.perUpper(end)>0,'Zero errors incorrectly imply zero uncertainty.');
c=struct('snrDB',35,'maxPackets',2,'minPackets',2,'maxPacketErrors',2, ...
    'payloadBytes',128,'makePlots',true,'outputDir',fullfile(pwd,'test_output'));
r=wifi_sim(c); assert(exist(fullfile(c.outputDir,'metrics.csv'),'file')==2);
% Close only figures created by this test, preserving existing user plots.
figures=findall(0,'Type','figure');
for k=1:numel(figures)
    if any(strcmp(get(figures(k),'Name'),{'Wi-Fi link metrics','Wi-Fi packet diagnostics'}))
        close(figures(k));
    end
end
fprintf('\nAll Wi-Fi simulator checks passed.\n');
end
