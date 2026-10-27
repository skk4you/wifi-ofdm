function check_wifi_compare_rx
%CHECK_WIFI_COMPARE_RX Compare stored grids, missing RX SNR and saved plans.
visible=get(0,'DefaultFigureVisible');
cleanup=onCleanup(@()set(0,'DefaultFigureVisible',visible)); %#ok<NASGU>
set(0,'DefaultFigureVisible','off');
root=wifi_run_folder(fullfile(pwd,'test_output','compare'),'fixtures');
a=struct('settings',struct('standard','11ac','mcs',3,'band','5GHz', ...
    'channelNumber',36,'bandwidth',20,'dcTrim',false,'iqTrim',false));
a.summary=table([-90;-80;-70],[1;.2;0],[NaN;10;20],[NaN;30;10], ...
    [100;100;100],[.9;.1;0],[1;.3;.04], ...
    'VariableNames',{'InputPowerDBm','PER','ReceivedSNRdB','EVMPercent','Sent','PERLower95','PERUpper95'});
b=a; b.settings.dcTrim=true; b.settings.iqTrim=true;
b.summary=table([-85;-75],[.5;0],[13;24],[25;5],[1000;1000], ...
    'VariableNames',{'InputPowerDBm','PER','ReceivedSNRdB','EVMPercent','Sent'});
legacy=a; legacy.summary=removevarsCompat(a.summary,'ReceivedSNRdB');
legacy.summary.SNRdB=999*ones(height(legacy.summary),1); % Must never be used.
mkdir(fullfile(root,'a')); r=a; save(fullfile(root,'a','rx_per.mat'),'r');
mkdir(fullfile(root,'b')); r=b; save(fullfile(root,'b','rx_per.mat'),'r');
o=struct('outputDir',fullfile(root,'output'),'makePlots',true);
c=wifi_compare_rx_runs({fullfile(root,'a'),fullfile(root,'b'),legacy}, ...
    {'Revision A - trim off','Revision B - trim on','Legacy - no RX SNR'},o);
assert(height(c.points)==8,'Power grids were resampled or points lost.');
assert(isequal(c.curves{1}.InputPowerDBm,[-90;-80;-70]));
assert(isequal(c.curves{2}.InputPowerDBm,[-85;-75]));
assert(isnan(c.curves{1}.ReceivedSNRdB(1)));
assert(all(isnan(c.curves{3}.ReceivedSNRdB)),'Injected SNR substituted for received SNR.');
assert(~c.manifest.HasReceivedSNREstimate(3));
assert(all(abs(c.curves{1}.PlottedSNRdB(2:end)+20*log10(c.curves{1}.EVMPercent(2:end)/100))<1e-10));
assert(isfinite(c.curves{3}.PlottedSNRdB(2))); % MER available, original LTF remains absent.
ltf=wifi_compare_rx_runs({legacy},{},struct('makePlots',false,'outputDir','','snrMetric','ltf'));
assert(all(isnan(ltf.curves{1}.PlottedSNRdB)));
v=wifi_evm_to_mer([10 1 0 NaN .1]);
assert(abs(v(1)-20)<1e-10 && abs(v(2)-40)<1e-10 && isinf(v(3)) && isnan(v(4)) && abs(v(5)-60)<1e-10); % No artificial 45 dB cap.
assert(strcmp(c.labels{2},'Revision B - trim on'));
assert(abs(c.manifest.SensitivityDBm(1)-(-75))<1e-10);
assert(exist(fullfile(c.outputDir,'comparison.png'),'file')==2);
assert(exist(fullfile(c.outputDir,'comparison.fig'),'file')==2);
assert(exist(fullfile(c.outputDir,'comparison_manifest.csv'),'file')==2);
assert(exist(fullfile(c.outputDir,'comparison_points.csv'),'file')==2);
assert(exist(fullfile(c.outputDir,'comparison.mat'),'file')==2);
plan=struct('results',{{a,[],b}},'summary',table({'first';'failed';'last'}, ...
    'VariableNames',{'Name'}));
mkdir(fullfile(root,'plan')); save(fullfile(root,'plan','plan_results.mat'),'plan');
p=wifi_compare_rx_runs({fullfile(root,'plan')},{},struct('makePlots',false,'outputDir',''));
assert(numel(p.curves)==2 && ~isempty(strfind(p.labels{2},'last')));
q=wifi_compare_rx_runs({a,b},{},struct('makePlots',false,'outputDir',fullfile(root,'output')));
assert(~strcmp(c.outputDir,q.outputDir),'Comparison overwrote a prior run.');
bad=a; bad.summary.InputPowerDBm(2)=bad.summary.InputPowerDBm(1);
caught=false;
try
    wifi_compare_rx_runs({bad},{},struct('makePlots',false,'outputDir',''));
catch e
    caught=~isempty(strfind(e.message,'duplicate'));
end
assert(caught,'Duplicate power points accepted.');
fprintf('\nAll saved RX comparison checks passed.\n');
fprintf('Verified comparison plot: %s\n',fullfile(c.outputDir,'comparison.png'));
end

function t=removevarsCompat(t,name)
t(:,name)=[];
end
