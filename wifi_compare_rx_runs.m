function comparison = wifi_compare_rx_runs(inputs,labels,options)
%WIFI_COMPARE_RX_RUNS Overlay saved conducted RX runs without rerunning packets.
% Inputs: cell array of run folders, rx_per.mat files, in-memory RX results,
% or plan folders/plan_results.mat files (completed tests expand automatically).
% labels: optional cell array with one label per expanded run.
if nargin<2, labels={}; end
if nargin<3, options=struct; end
o=struct('outputDir',fullfile(pwd,'results','compare_rx'),'makePlots',true, ...
    'title','RX run comparison','perThreshold',0.10,'showPERConfidence',true,'snrMetric','mer');
names=fieldnames(options);
for k=1:numel(names)
    assert(isfield(o,names{k}),'Unknown comparison option: %s',names{k});
    o.(names{k})=options.(names{k});
end
assert(ischar(o.snrMetric) && any(strcmp(o.snrMetric,{'mer','ltf'})), ...
    'snrMetric must be mer or ltf.');
if ischar(inputs) || isstruct(inputs), inputs={inputs}; end
assert(iscell(inputs) && ~isempty(inputs),'Select at least one saved run or plan.');
validateattributes(o.perThreshold,{'numeric'},{'scalar','real','finite','>',0,'<',1});
for flag={'makePlots','showPERConfidence'}
    assert(isscalar(o.(flag{1})) && any(o.(flag{1})==[0 1]),'%s must be logical.',flag{1});
end
assert(ischar(o.outputDir) && ischar(o.title),'outputDir and title must be character text.');
runs={}; sources={}; suggested={};
for k=1:numel(inputs)
    item=inputs{k};
    if isstruct(item)
        data=item; source=sprintf('workspace input %d',k);
    else
        assert(ischar(item),'Each input must be a path or a result struct.');
        source=item;
        if exist(source,'dir')
            if exist(fullfile(source,'rx_per.mat'),'file')
                source=fullfile(source,'rx_per.mat');
            elseif exist(fullfile(source,'plan_results.mat'),'file')
                source=fullfile(source,'plan_results.mat');
            else
                error('No rx_per.mat or plan_results.mat in %s',source);
            end
        end
        assert(exist(source,'file')==2,'Saved run not found: %s',source);
        [ok,attributes]=fileattrib(source);
        if ok, source=attributes.Name; end
        loaded=load(source);
        if isfield(loaded,'r'), data=loaded.r;
        elseif isfield(loaded,'plan'), data=loaded.plan;
        else, error('Expected variable r or plan in %s',source); end
    end
    if isfield(data,'results') && iscell(data.results)
        added=0;
        for j=1:numel(data.results)
            candidate=data.results{j};
            if isempty(candidate), continue; end % Failed/incomplete plan tests.
            assert(isstruct(candidate) && isfield(candidate,'summary'),'Invalid plan result %d.',j);
            runs{end+1}=candidate; %#ok<AGROW>
            sources{end+1}=sprintf('%s [test %d]',source,j); %#ok<AGROW>
            name='';
            if isfield(data,'summary') && istable(data.summary) && height(data.summary)>=j ...
                    && ismember('Name',data.summary.Properties.VariableNames)
                name=data.summary.Name{j};
            end
            suggested{end+1}=name; added=added+1; %#ok<AGROW>
        end
        assert(added>0,'No completed tests available in plan %s',source);
    else
        assert(isstruct(data) && isscalar(data) && isfield(data,'summary'), ...
            'Expected a conducted RX result with a summary table: %s',source);
        runs{end+1}=data; sources{end+1}=source; suggested{end+1}=''; %#ok<AGROW>
    end
end
if ischar(labels), labels={labels}; end
assert(iscell(labels) && (isempty(labels) || numel(labels)==numel(runs)), ...
    'Supply one label per expanded run, or leave labels empty for automatic labels.');
comparison=struct('options',o,'outputDir','','curves',{cell(1,numel(runs))}, ...
    'sources',{sources},'labels',{cell(1,numel(runs))},'manifest',table,'points',table);
for k=1:numel(runs)
    r=runs{k}; t=r.summary;
    assert(istable(t) && height(t)>0,'Run %d has no measurement rows.',k);
    required={'InputPowerDBm','PER','EVMPercent'};
    assert(all(ismember(required,t.Properties.VariableNames)), ...
        'Run %d is not a conducted RX power sweep (missing required columns).',k);
    x=t.InputPowerDBm(:); y=t.PER(:); evm=t.EVMPercent(:);
    validateattributes(x,{'numeric'},{'vector','real','finite'});
    validateattributes(y,{'numeric'},{'vector','real','finite','>=',0,'<=',1});
    validateattributes(evm,{'numeric'},{'vector','real'});
    assert(all(isnan(evm) | (isfinite(evm) & evm>=0)),'Invalid EVM in run %d.',k);
    [x,order]=sort(x); y=y(order); evm=evm(order);
    assert(all(diff(x)>0),'Run %d has duplicate input powers.',k);
    snr=NaN(size(x)); available=false;
    if ismember('ReceivedSNRdB',t.Properties.VariableNames)
        snr=t.ReceivedSNRdB(order); available=true;
    elseif isfield(r,'link') && isfield(r.link,'rxSNRDB') && numel(r.link.rxSNRDB)==numel(x)
        raw=r.link.rxSNRDB(:); snr=raw(order); available=true;
    end
    validateattributes(snr,{'numeric'},{'vector','real'});
    % Never substitute configured SNRdB, measuredSNRDB (injected), or -EVMdB.
    sent=NaN(size(x));
    if ismember('Sent',t.Properties.VariableNames), sent=t.Sent(order); end
    lo=NaN(size(x)); hi=lo;
    if all(ismember({'PERLower95','PERUpper95'},t.Properties.VariableNames))
        lo=t.PERLower95(order); hi=t.PERUpper95(order);
        assert(all(isnan(lo) | (lo>=0 & lo<=y+1e-12)) && ...
            all(isnan(hi) | (hi>=y-1e-12 & hi<=1)),'Invalid PER bounds in run %d.',k);
    end
    cfg=struct; if isfield(r,'settings'), cfg=r.settings; end
    standard=textSetting(cfg,'standard','unknown'); band=textSetting(cfg,'band','unknown');
    mcs=numberSetting(cfg,'mcs'); channel=numberSetting(cfg,'channelNumber');
    bw=numberSetting(cfg,'bandwidth'); dc=numberSetting(cfg,'dcTrim'); iq=numberSetting(cfg,'iqTrim');
    if isempty(labels)
        name=suggested{k};
        if isempty(name)
            name=sprintf('%s MCS%g CH%g BW%g DC%g IQ%g',standard,mcs,channel,bw,dc,iq);
        end
        label=sprintf('%d: %s',k,name);
    else
        label=labels{k}; assert(ischar(label) && isrow(label),'Labels must be character text.');
    end
    comparison.labels{k}=label;
    sensitivity=wifi_rx_sensitivity(x,y,o.perThreshold);
    curve=table(x,y,100*y,snr(:),evm,sent(:),lo(:),hi(:), ...
        'VariableNames',{'InputPowerDBm','PER','PERPercent','ReceivedSNRdB','EVMPercent','Sent','PERLower95','PERUpper95'});
    curve.EffectiveSNRdB=wifi_evm_to_mer(evm);
    curve.PlottedSNRdB=curve.EffectiveSNRdB;
    if strcmp(o.snrMetric,'ltf'), curve.PlottedSNRdB=curve.ReceivedSNRdB; end
    comparison.curves{k}=curve;
    row=table(k,{label},{sources{k}},{standard},mcs,{band},channel,bw,dc,iq, ...
        numberSetting(cfg,'payloadBytes'),{textSetting(cfg,'coding','unknown')}, ...
        {textSetting(cfg,'guardInterval','unknown')},numberSetting(cfg,'noiseFigureDB'), ...
        numberSetting(cfg,'adcBits'),x(1),x(end),numel(x),available, ...
        o.perThreshold,{sensitivity.status},sensitivity.estimateDBm,sensitivity.lowestPassingDBm, ...
        'VariableNames',{'Run','Label','Source','Standard','MCS','Band','CenterChannel', ...
        'BandwidthMHz','DCTrim','IQTrim','PayloadBytes','Coding','GuardInterval','NoiseFigureDB', ...
        'ADCBits','PowerMinDBm','PowerMaxDBm','Levels','HasReceivedSNREstimate', ...
        'ComparisonPERThreshold','SensitivityStatus','SensitivityDBm','LowestTestedPassDBm'});
    row.SNRMetric={o.snrMetric};
    points=[table(k*ones(height(curve),1),repmat({label},height(curve),1), ...
        'VariableNames',{'Run','Label'}) curve];
    if k==1, comparison.manifest=row; comparison.points=points;
    else
        comparison.manifest=[comparison.manifest;row];
        comparison.points=[comparison.points;points];
    end
    if ~available && strcmp(o.snrMetric,'ltf')
        fprintf('Run %d has no saved received-SNR estimate; its SNR curve is omitted.\n',k);
    end
end
if o.makePlots
    f=figure('Name',o.title,'Color','w','Position',[50 80 1550 580],'PaperPositionMode','auto');
    colors=lines(numel(runs)); styles={'-o','--s','-.^',':d','-v','-->'};
    for k=1:numel(runs)
        t=comparison.curves{k}; style=styles{1+mod(k-1,numel(styles))};
        subplot(1,3,1); hold on;
        if o.showPERConfidence && any(isfinite(t.PERLower95) & isfinite(t.PERUpper95))
            errorbar(t.InputPowerDBm,t.PERPercent,100*max(t.PER-t.PERLower95,0), ...
                100*max(t.PERUpper95-t.PER,0),style,'Color',colors(k,:),'LineWidth',1);
        else
            plot(t.InputPowerDBm,t.PERPercent,style,'Color',colors(k,:),'LineWidth',1);
        end
        subplot(1,3,2); hold on;
        plot(t.InputPowerDBm,t.PlottedSNRdB,style,'Color',colors(k,:),'LineWidth',1);
        subplot(1,3,3); hold on;
        plot(t.InputPowerDBm,t.EVMPercent,style,'Color',colors(k,:),'LineWidth',1);
    end
    low=min(comparison.points.InputPowerDBm); high=max(comparison.points.InputPowerDBm);
    for ax=1:3
        subplot(1,3,ax); grid on; xlabel('DUT input power (dBm)');
        if high>low, xlim([low high]); end
        legend(comparison.labels,'Interpreter','none','Location','southoutside','FontSize',8);
    end
    subplot(1,3,1); ylim([0 100]); ylabel('PER (%)'); title('Packet error rate');
    plot([low high],100*o.perThreshold*[1 1],'k--','HandleVisibility','off');
    subplot(1,3,2);
    if strcmp(o.snrMetric,'mer')
        ylabel('Effective received SNR / MER (dB)'); title('Inverse of residual EVM (MER)');
    else
        ylabel('Received L-LTF noise SNR (dB)'); title('Repeated-training noise estimate');
    end
    subplot(1,3,3); ylabel('RMS EVM (%)'); title('EVM of acquired packets');
end
if ~isempty(o.outputDir)
    comparison.outputDir=wifi_run_folder(o.outputDir,'comparison');
    save(fullfile(comparison.outputDir,'comparison.mat'),'comparison');
    writetable(comparison.manifest,fullfile(comparison.outputDir,'comparison_manifest.csv'));
    writetable(comparison.points,fullfile(comparison.outputDir,'comparison_points.csv'));
    if o.makePlots
        saveas(f,fullfile(comparison.outputDir,'comparison.png'));
        savefig(f,fullfile(comparison.outputDir,'comparison.fig'));
    end
    fprintf('Comparison output: %s\n',comparison.outputDir);
end
disp(comparison.manifest);
end

function v=textSetting(c,name,fallback)
v=fallback;
if isfield(c,name) && ischar(c.(name)), v=c.(name); end
end

function v=numberSetting(c,name)
v=NaN;
if isfield(c,name) && (isnumeric(c.(name)) || islogical(c.(name))) && isscalar(c.(name))
    v=double(c.(name));
end
end
