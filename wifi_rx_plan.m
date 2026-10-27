function plan = wifi_rx_plan(tests,common,options)
%WIFI_RX_PLAN Execute explicit single-radio test configurations in sequence.
% tests: cell array of override structs, optionally including a 'name' field.
% common: shared wifi_rx_per settings. options: outputDir, continueOnError.
if nargin<2, common=struct; end
if nargin<3, options=struct; end
o=struct('outputDir',fullfile(pwd,'results','rx_plan'),'continueOnError',true);
names=fieldnames(options);
for k=1:numel(names)
    assert(isfield(o,names{k}),'Unknown plan option: %s',names{k});
    o.(names{k})=options.(names{k});
end
assert(iscell(tests) && ~isempty(tests),'Provide a nonempty cell array of test structs.');
assert(isstruct(common) && isscalar(common),'common must be a scalar struct.');
assert(isscalar(o.continueOnError) && any(o.continueOnError==[0 1]), ...
    'continueOnError must be logical.');
for k=1:numel(tests), assert(isstruct(tests{k}) && isscalar(tests{k}),'Invalid test %d.',k); end
folder=wifi_run_folder(o.outputDir,'plan');
plan=struct('outputDir',folder,'tests',{tests},'common',common,'options',o, ...
    'results',{cell(size(tests))},'errors',{cell(size(tests))},'summary',table);
save(fullfile(folder,'plan_configuration.mat'),'tests','common','o');
fprintf('RX plan: %d tests. Output: %s\n',numel(tests),folder);
for k=1:numel(tests)
    c=common; override=tests{k}; label=sprintf('test_%03d',k);
    if isfield(override,'name')
        label=override.name; override=rmfield(override,'name');
        assert(ischar(label) && isrow(label),'Test name must be text.');
    end
    names=fieldnames(override);
    for j=1:numel(names), c.(names{j})=override.(names{j}); end
    path=fullfile(folder,sprintf('%03d_%s',k,regexprep(label,'[^a-zA-Z0-9_-]','_')));
    c.outputDir=path; c.uniqueOutputDir=false;
    status='completed'; sensitivityStatus=''; estimate=NaN; lowest=NaN; detail='';
    fprintf('\n=== Test %d/%d: %s ===\n',k,numel(tests),label);
    failure=[];
    try
        r=wifi_rx_per(c); plan.results{k}=r;
        sensitivityStatus=r.sensitivity.status;
        estimate=r.sensitivity.estimateDBm; lowest=r.lowestPassingDBm;
    catch e
        failure=e; status='failed'; detail=e.message;
        plan.errors{k}=getReport(e,'extended','hyperlinks','off');
        if ~exist(path,'dir'), mkdir(path); end
        save(fullfile(path,'failed_configuration.mat'),'c');
        fid=fopen(fullfile(path,'error.txt'),'w');
        if fid>=0, fprintf(fid,'%s\n',plan.errors{k}); fclose(fid); end
        fprintf('Test failed: %s\n',e.message);
    end
    defaults=struct('standard','11ac','mcs',3,'band','5GHz','channelNumber',36, ...
        'bandwidth',20,'dcTrim',false,'iqTrim',false);
    names=fieldnames(defaults);
    for j=1:numel(names), if ~isfield(c,names{j}), c.(names{j})=defaults.(names{j}); end; end
    % Malformed settings must not break failure reporting/checkpointing.
    display=c;
    for j=1:numel(names)
        v=c.(names{j});
        if ischar(defaults.(names{j}))
            if ~ischar(v) || ~isrow(v), display.(names{j})='<invalid>'; end
        elseif ~(isnumeric(v) || islogical(v)) || ~isscalar(v) || ~isreal(v) || ~isfinite(v)
            display.(names{j})=NaN;
        end
    end
    row=table(k,{label},{display.standard},display.mcs,{display.band},display.channelNumber,display.bandwidth, ...
        double(display.dcTrim),double(display.iqTrim),{status},{sensitivityStatus},estimate,lowest,{path},{detail}, ...
        'VariableNames',{'Index','Name','Standard','MCS','Band','CenterChannel','BandwidthMHz', ...
        'DCTrim','IQTrim','Status','SensitivityStatus','SensitivityDBm','LowestTestedPassDBm','OutputDir','Error'});
    if k==1, plan.summary=row; else, plan.summary=[plan.summary;row]; end %#ok<AGROW>
    % Checkpoint after each test so an interrupted long plan retains results.
    writetable(plan.summary,fullfile(folder,'plan_summary.csv'));
    save(fullfile(folder,'plan_results.mat'),'plan');
    if ~isempty(failure) && ~o.continueOnError, rethrow(failure); end
end
disp(plan.summary);
end
