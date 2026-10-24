%% Conducted Wi-Fi RX PER test driver
% Edit the settings below, then click Run or type: run_rx_per
% Runs ONE power sweep. Results remain in workspace variable r.
% Unlike check_wifi_rx_per, this does not run additional validation sweeps.

%% Wi-Fi mode and channel
cfg = struct;
cfg.standard = '11ac';            % '11a', '11g', '11n', '11ac'
cfg.mcs = 3;                      % Standard-specific MCS index
cfg.band = '5GHz';                % '5GHz' or '2.4GHz'
cfg.channelNumber = 36;           % Center channel: 36/20 MHz, 42/80 MHz
cfg.bandwidth = 20;               % 20; HT: 20/40; VHT: 20/40/80/160 MHz
cfg.payloadBytes = 512;           % VHT uses APEP length; others PSDU length
cfg.guardInterval = 'Long';       % HT/VHT: 'Long' or 'Short'
cfg.coding = 'BCC';               % HT/VHT: 'BCC' or 'LDPC'

%% Input power and packet counting
cfg.inputPowerDBm = -100:5:0;     % DUT input dBm; change to -100:1:-50 for 1 dB steps
cfg.packetsPerLevel = 1000;       % Exactly this many at EVERY level; no early stop
cfg.perThreshold = 0.10;          % Passing threshold as fraction: 0.10 = 10% PER
cfg.seed = 17;                    % Repeatable random payloads/noise

%% Receiver noise and fixed gain
cfg.noiseFigureDB = 7;            % Input-referred NF; noise stays fixed across sweep
cfg.referenceInputDBm = -40;      % Input dBm giving unit sample power before RX errors
cfg.adcBits = Inf;                % Inf: ideal ADC; e.g. 10: quantization AND clipping
cfg.adcFullScale = 1;             % I/Q clipping limits for finite adcBits
% For a two-sided fixed-gain ADC bathtub, set cfg.adcBits = 10.
% With ideal ADC, high input power need not cause PER to rise.
% This model does not include AGC or measured hardware gain states.

%% RX impairments and calibration trims
cfg.rxDC = 0 + 0i;                % Complex offset in ADC waveform units
cfg.rxIQGainDB = 0;               % RX I/Q gain mismatch in dB
cfg.rxIQPhaseDeg = 0;             % RX quadrature phase error in degrees
cfg.dcTrim = false;              % Apply measured DC correction
cfg.iqTrim = false;              % Apply measured IQ correction
cfg.calibrationSamples = 8192;
cfg.calibrationSNRDB = 50;        % Dedicated calibration capture SNR

%% Frequency/phase errors and transmitter quality
cfg.cfoHz = 20000;                % Carrier frequency offset in Hz
cfg.phaseNoiseDeg = 0;            % Wiener phase increment std deviation per sample
cfg.txIQGainDB = 0;
cfg.txIQPhaseDeg = 0;
cfg.paBackoffDB = Inf;            % Inf: linear TX; finite value: Rapp PA compression

%% Receiver processing (one conducted SISO radio)
cfg.channel = 'awgn';             % Required for this conducted power test
cfg.nTx = 1;
cfg.nRx = 1;
cfg.nStreams = 1;
cfg.packetDelay = 80;             % Leading idle samples
cfg.synchronize = true;          % Packet detection, timing and CFO correction
cfg.equalizer = 'MMSE';           % 'MMSE' or 'ZF'
cfg.pilotTracking = 'PreEQ';      % 'PreEQ' or 'None'

%% Figures and saved output
cfg.makePlots = true;             % PER, received count, received SNR and EVM vs dBm
cfg.outputDir = fullfile(pwd,'results','rx_per');
% Existing files in this directory are replaced. Use a different folder per run.

%% Alternative mode examples -- uncomment ONE block to override settings
% 2.4 GHz 802.11g, channel 6, 20 MHz:
% cfg.standard = '11g'; cfg.mcs = 4;
% cfg.band = '2.4GHz'; cfg.channelNumber = 6; cfg.bandwidth = 20;

% 2.4 GHz 802.11n, single stream, channel 6, 20 MHz:
% cfg.standard = '11n'; cfg.mcs = 3;
% cfg.band = '2.4GHz'; cfg.channelNumber = 6; cfg.bandwidth = 20;

% 5 GHz 802.11a, channel 36, 20 MHz:
% cfg.standard = '11a'; cfg.mcs = 4;
% cfg.band = '5GHz'; cfg.channelNumber = 36; cfg.bandwidth = 20;

% 5 GHz 802.11ac, 80 MHz, center channel 42, 256-QAM with LDPC:
% cfg.standard = '11ac'; cfg.mcs = 8;
% cfg.band = '5GHz'; cfg.channelNumber = 42; cfg.bandwidth = 80;
% cfg.coding = 'LDPC'; cfg.guardInterval = 'Short';

% RX trim experiment (can be combined with any supported mode above):
% cfg.rxDC = 0.12 + 0.08i; cfg.rxIQGainDB = 1.5; cfg.rxIQPhaseDeg = 8;
% cfg.dcTrim = true; cfg.iqTrim = true;

%% Run the selected test once
r = wifi_rx_per(cfg);
% Summary is printed by wifi_rx_per. Additional results:
% r.summary                  % Counts, PER, received SNR, EVM at each input level
% r.lowestPassingDBm          % Lowest TESTED point meeting perThreshold
% r.passWindowsDBm            % Contiguous passing ranges
% r.noiseFloorDBm             % Fixed input-referred thermal noise + NF
