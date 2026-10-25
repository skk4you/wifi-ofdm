%% RX test-plan driver -- edit this file, then click Run or type run_rx_plan
% Each combination below is a SEPARATE test with its own output folder.
% One radio is active at a time. This is not a concurrent-radio simulation.

%% Shared settings (all wifi_rx_per controls are accepted)
common = struct;
common.inputPowerDBm = -100:5:-50;
common.packetsPerLevel = 1000;
common.payloadBytes = 512;
common.perThreshold = 0.10;
common.noiseFigureDB = 7;
common.adcBits = Inf;
common.cfoHz = 20000;
common.makePlots = true;
common.refineSensitivity = false; % true: explicitly add NEW levels near crossing
common.refinementStepDB = 1;

%% Mode groups -- use valid CENTER channels for each bandwidth
% Default: 2 MCS choices x 2 channels x 2 trim states = 8 tests.
modes = {struct('standard','11ac','band','5GHz','bandwidth',20, ...
    'mcsList',[0 3],'channels',[36 149])};
% Add groups as needed, e.g.:
% modes{end+1} = struct('standard','11n','band','2.4GHz', ...
%     'bandwidth',20,'mcsList',[0 3],'channels',[1 6 11]);
% modes{end+1} = struct('standard','11ac','band','5GHz', ...
%     'bandwidth',80,'mcsList',[0 3],'channels',[42 155]);
% modes{end+1} = struct('standard','11a','band','5GHz', ...
%     'bandwidth',20,'mcsList',[0 4],'channels',[36]);
% MCS indexes differ between legacy and HT/VHT; choose modulation/coding
% deliberately when comparing standards. RF channel number is metadata.

%% Calibration states -- simulated mismatch is common, trims vary per test
common.rxDC = 0.12 + 0.08i;
common.rxIQGainDB = 1.5;
common.rxIQPhaseDeg = 8;
trims = {struct('name','untrimmed','dcTrim',false,'iqTrim',false), ...
         struct('name','trimmed','dcTrim',true,'iqTrim',true)};
% To test only one state: trims = trims(1);

%% Build explicit test list
tests = {};
for modeIndex = 1:numel(modes)
    mode = modes{modeIndex};
    for mcs = mode.mcsList
        for channelNumber = mode.channels
            for trimIndex = 1:numel(trims)
                trim = trims{trimIndex};
                test = struct('standard',mode.standard,'band',mode.band, ...
                    'bandwidth',mode.bandwidth,'mcs',mcs,'channelNumber',channelNumber, ...
                    'dcTrim',trim.dcTrim,'iqTrim',trim.iqTrim);
                test.name = sprintf('%s_mcs%d_ch%d_bw%d_%s', ...
                    mode.standard,mcs,channelNumber,mode.bandwidth,trim.name);
                tests{end+1} = test; %#ok<SAGROW>
            end
        end
    end
end

%% Run plan; results are under the MATLAB CURRENT folder, even with addpath
options = struct('outputDir',fullfile(pwd,'results','rx_plan'), ...
    'continueOnError',true); % Failed configurations are recorded; others continue.
plan = wifi_rx_plan(tests,common,options);
% plan.summary       % One row per test, sensitivity, status and output path
% plan.results{1}    % Full result of first completed test; [] if failed
% plan.outputDir     % Unique timestamped plan folder
