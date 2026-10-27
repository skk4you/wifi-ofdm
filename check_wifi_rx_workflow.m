function check_wifi_rx_workflow
%CHECK_WIFI_RX_WORKFLOW Small deterministic V3 workflow integration tests.
visibility=get(0,'DefaultFigureVisible');
cleanup=onCleanup(@()set(0,'DefaultFigureVisible',visibility)); %#ok<NASGU>
set(0,'DefaultFigureVisible','off');
s=wifi_rx_sensitivity([-90 -85 -80 -75],[1 .5 .05 0],.1);
assert(s.bracketed && abs(s.estimateDBm-(-80.5555555556))<1e-8);
assert(isequal(s.bracketDBm,[-85 -80]));
s=wifi_rx_sensitivity([-90 -80],[.05 0],.1);
assert(strcmp(s.status,'below_sweep') && isnan(s.estimateDBm));
s=wifi_rx_sensitivity([-90 -80],[1 .5],.1);
assert(strcmp(s.status,'no_pass') && isnan(s.estimateDBm));
s=wifi_rx_sensitivity([-90 -85 -80 -75],[1 .05 .2 0],.1);
assert(s.nonmonotonic && size(s.passWindowsDBm,1)==2);

root=fullfile(pwd,'test_output','workflow');
c=struct('inputPowerDBm',[-85 -75],'packetsPerLevel',20,'payloadBytes',128, ...
    'makePlots',true,'refineSensitivity',true,'refinementStepDB',1,'outputDir',root);
r=wifi_rx_per(c);
assert(strcmp(r.refinement.status,'completed'));
assert(isequal(r.refinement.powerDBm,-84:-76),'Unexpected refinement levels.');
assert(numel(r.testedPowerDBm)==11 && all(diff(r.testedPowerDBm)>0));
assert(all(r.sent==20) && sum(r.sent)==220,'Repeated endpoints or wrong packet count.');
assert(all(r.link.packets==r.summary.Sent.'));
assert(r.sensitivity.bracketed && diff(r.sensitivity.bracketDBm)<=1+eps);
assert(exist(fullfile(r.outputDir,'configuration.mat'),'file')==2);
assert(exist(fullfile(r.outputDir,'configuration.json'),'file')==2);
assert(exist(fullfile(r.outputDir,'sensitivity.csv'),'file')==2);
assert(exist(fullfile(r.outputDir,'rx_per.png'),'file')==2);

c.inputPowerDBm=-60; c.packetsPerLevel=2; c.makePlots=false;
c.rxDC=.1+.05i; c.dcTrim=true; c.iqTrim=true;
a=wifi_rx_per(c); b=wifi_rx_per(c);
assert(~strcmp(a.outputDir,b.outputDir),'Repeated runs overwrite a folder.');
assert(strcmp(a.refinement.status,'unbracketed'));
assert(strcmp(a.sensitivity.status,'below_sweep'));
loaded=load(fullfile(a.outputDir,'configuration.mat'));
assert(loaded.c.rxDC==c.rxDC,'Complex configuration was not preserved.');
json=jsondecode(fileread(fullfile(a.outputDir,'configuration.json')));
assert(json.rxDC.real==.1 && json.rxDC.imag==.05);

tests={struct('name','legacy','standard','11a','mcs',4), ...
    struct('name','invalid','standard','invalid'), ...
    struct('name','vht_trimmed','standard','11ac','mcs',3,'dcTrim',true,'iqTrim',true)};
common=struct('inputPowerDBm',[-100 -60],'packetsPerLevel',3, ...
    'payloadBytes',128,'makePlots',false,'rxDC',.1+.05i);
p=wifi_rx_plan(tests,common,struct('outputDir',root));
assert(isequal(p.summary.Status,{'completed';'failed';'completed'}));
assert(all(p.results{1}.sent==3) && all(p.results{3}.sent==3));
assert(exist(fullfile(p.outputDir,'plan_summary.csv'),'file')==2);
assert(exist(fullfile(p.outputDir,'plan_results.mat'),'file')==2);
assert(exist(fullfile(p.summary.OutputDir{2},'error.txt'),'file')==2);
fprintf('\nAll RX workflow checks passed.\n');
end
