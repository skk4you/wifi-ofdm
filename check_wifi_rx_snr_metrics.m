function check_wifi_rx_snr_metrics
%CHECK_WIFI_RX_SNR_METRICS Effective SNR must follow actual RX residual EVM.
visibility=get(0,'DefaultFigureVisible');
cleanup=onCleanup(@()set(0,'DefaultFigureVisible',visibility)); %#ok<NASGU>
set(0,'DefaultFigureVisible','off');
c=struct('inputPowerDBm',[-100 -60 -10],'packetsPerLevel',20, ...
    'payloadBytes',128,'adcBits',10,'adcFullScale',1,'rxIQGainDB',1, ...
    'rxIQPhaseDeg',5,'makePlots',true,'outputDir',fullfile(pwd,'test_output','snr_metrics'));
r=wifi_rx_per(c);
assert(strcmp(r.settings.snrMetric,'mer'));
axesList=findall(gcf,'Type','axes'); plotted=[];
for a=axesList.'
    if strcmp(get(get(a,'YLabel'),'String'),'Effective received SNR / MER (dB)')
        plotted=findall(a,'Type','line'); break;
    end
end
assert(~isempty(plotted),'Figure still shows the old training-noise metric.');
displayed=get(plotted(1),'YData');
assert(isequaln(displayed(:),r.plottedSNRDB(:)),'Wrong data in plotted SNR curve.');
valid=isfinite(r.summary.EVMPercent) & r.summary.EVMPercent>0;
assert(max(abs(r.plottedSNRDB(valid)+20*log10(r.summary.EVMPercent(valid)/100)))<1e-10);
assert(all(isnan(r.plottedSNRDB(~valid))));
assert(r.plottedSNRDB(2)>r.plottedSNRDB(3)+5,'Overload is not reflected in effective SNR.');
ltf=r.link.rxSNRDB(:);
assert(any(abs(ltf(valid)-r.plottedSNRDB(valid))>1),'Training-noise and residual-error metrics not separated.');
c.inputPowerDBm=-60; c.packetsPerLevel=2; c.makePlots=false; c.outputDir=''; c.snrMetric='ltf';
q=wifi_rx_per(c);
assert(isequal(q.plottedSNRDB,q.link.rxSNRDB(:)));
assert(isequal(q.summary.ReceivedSNRdB,q.summary.LTFNoiseSNRdB));
fprintf('\nAll RX SNR metric checks passed.\n');
fprintf('Verified SNR plot: %s\n',fullfile(r.outputDir,'rx_per.png'));
end
