%% Compare saved RX runs -- no packets are transmitted or simulated
% Edit runFolders and labels below, then click Run or type run_compare_rx.
% Each entry can be an individual run folder/rx_per.mat, or an entire
% plan folder/plan_results.mat (all completed tests expand automatically).
runFolders = {};
% Example: paths may point to different test folders or software revisions:
% runFolders = {
%     'C:\MyTests\TrimOff\results\rx_per\11ac_mcs3_ch36_bw20_TIMESTAMP'
%     'C:\MyTests\TrimOn\results\rx_per\11ac_mcs3_ch36_bw20_TIMESTAMP'
% };

labels = {}; % Empty: automatic mode/trim labels.
% labels = {'Version 3 - trim off','Version 3 - trim on'};
% For a plan, provide one label per COMPLETED test, not one label per plan.
% Software revisions are user labels; they are not inferred from current code.

%% Interactive selection when no paths were entered
% Select an individual saved run folder (or plan folder) each time.
% Cancel after selecting the desired runs. Cancel immediately exits.
if isempty(runFolders)
    startFolder = pwd;
    while true
        selected = uigetdir(startFolder,'Select an RX run or plan folder; Cancel when finished');
        if isequal(selected,0), break; end
        runFolders{end+1} = selected; %#ok<SAGROW>
        startFolder = fileparts(selected);
    end
end

%% Comparison settings
options = struct;
options.outputDir = fullfile(pwd,'results','compare_rx'); % Timestamped subfolder
options.makePlots = true;
options.snrMetric = 'mer';      % 'mer': inverse saved EVM; 'ltf': saved L-LTF noise SNR
options.showPERConfidence = true;
options.perThreshold = 0.10;  % Common sensitivity threshold for comparison summary
options.title = 'RX run comparison';
% All measured power grids and NaN gaps are retained. No resampling or
% injected SNR is substituted. MER is explicitly derived from saved RX EVM.
% With snrMetric='ltf', missing L-LTF estimates remain blank.
if isempty(runFolders)
    disp('No saved runs selected. Comparison cancelled.');
else
    comparison = wifi_compare_rx_runs(runFolders,labels,options);
end
% comparison.manifest   % Settings, sources and common-threshold sensitivity
% comparison.curves{1}  % Original measured grid for the first run
% comparison.outputDir  % Saved PNG/FIG, manifest/points CSV and MAT
