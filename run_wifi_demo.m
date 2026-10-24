function run_wifi_demo
%RUN_WIFI_DEMO Save a baseline sweep and RX DC/IQ trim comparison.
r=wifi_sim(struct('maxPackets',20,'minPackets',20, ...
    'outputDir',fullfile(pwd,'results','baseline'))); %#ok<NASGU>
trims=wifi_trim_study(struct('snrDB',15:10:45,'maxPackets',10, ...
    'minPackets',10,'outputDir',fullfile(pwd,'results','rx_trim')));
folder=fullfile(pwd,'results','rx_trim');
save(fullfile(folder,'comparison.mat'),'trims');
saveas(gcf,fullfile(folder,'comparison.png'));
end
