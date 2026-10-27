# Wi-Fi TX/RX and RF calibration simulator

Start here: [Training guide](TRAINING_GUIDE.md) — walkthroughs, measurement definitions, labs, and troubleshooting.

**Version 3.1.0** — saved-run overlays for PER, received SNR and EVM, alongside test plans and sensitivity refinement. See [CHANGELOG.md](CHANGELOG.md).

MATLAB R2018a with **WLAN System Toolbox** (renamed WLAN Toolbox in later releases). This project uses the installed standard-specific packet generator and receivers; it does not substitute arbitrary OFDM tone allocations for Wi-Fi packets.

Open `C:\Codex\ofdm-wifi` in MATLAB and run:

```matlab
r = wifi_sim;                  % 11ac, 20 MHz, MCS 3, SNR sweep
disp(r.summary)
wifi_examples('trim')          % RX DC / IQ calibration comparison
wifi_examples('standards')     % 11a, 11n, 11ac comparison
check_wifi_sim                 % numerical and integration checks
run_wifi_demo                  % save baseline + trim curves under results/
```

The quick default uses only 20–40 packets per SNR point. For useful low-PER measurements increase the packet budget:

```matlab
r = wifi_sim(struct('snrDB',15:2:35, 'maxPackets',2000, ...
    'minPackets',200, 'maxPacketErrors',100, 'outputDir','results/ac'));
```

## Conducted RX PER versus input power (LitePoint-style)

For an editable driver, open **`run_rx_per.m`**, adjust the settings, and click **Run** (or type `run_rx_per`). It runs a single sweep, defaults to -100:5:0 dBm with 1,000 packets per level, and leaves results in `r`. It includes receiver/ADC/trim controls and commented examples for 11a/g/n/ac. The `check_wifi_rx_per` function is a multi-case regression test, not the measurement driver.

```matlab
r = wifi_rx_per(struct('standard','11ac','mcs',3, ...
    'band','5GHz','channelNumber',36,'bandwidth',20, ...
    'inputPowerDBm',-100:1:-50,'packetsPerLevel',1000));
disp(r.summary)
```

This sends exactly 1,000 simulated packets at **every** input level, with no error-count early stop. `ReceivedOK` counts packets that synchronize and recover the entire known PSDU correctly. `LostOrBad = Sent - ReceivedOK`, and `PER = LostOrBad / Sent`; both fractional PER and PER percent are exported. A missing acquisition counts as a packet error. The 95% Wilson bounds describe the finite packet count; zero errors in 1,000 packets still has an upper bound near 0.38%.

The RX figure and exported `rx_per.png` show PER, received packet count, effective received SNR, and RMS EVM versus DUT input power. By default, `snrMetric='mer'` plots **MER = -20*log10(EVMPercent/100)**, using actual received/equalized symbol errors against the simulation reference. This is a reference-assisted effective SNR including noise and distortion; it is exactly the negative of EVM in dB, not an independent DUT firmware SNR statistic. The curve falls when residual EVM worsens through overload. `ReceivedMERdB` exports it. No-acquisition points remain NaN/gaps. Choosing `snrMetric='ltf'` instead plots the received L-LTF noise estimate from the repeated training-symbol difference. Static distortion can cancel in that difference, so it may keep rising even while payload EVM worsens. `LTFNoiseSNRdB` explicitly names that estimate; the older `ReceivedSNRdB` column remains its backward-compatible alias, and `SNRPackets` records its sample population. The `SNRdB` column remains the configured input link budget. MER/EVM include acquired packets with bad payloads. Neither metric is artificially clipped at 45 dB: a 45 dB MER corresponds to about 0.562% residual EVM and requires the corresponding receiver impairment floor. An otherwise ideal AWGN receiver can still yield a nearly linear effective-SNR curve. See [MathWorks modulation accuracy guidance](https://www.mathworks.com/help/comm/ug/measure-modulation-accuracy.html) for the distinction between MER and noise-only SNR.

The input power is at the DUT connector/reference plane, not the generator before cable loss. The receiver noise floor is held fixed at `10*log10(k*290*Fs)+30+noiseFigureDB` dBm, using the full complex-sample bandwidth `Fs`. At 20 MHz and 7 dB NF this is about -94 dBm. Each packet's generator waveform is normalized to the requested average packet power, then amplified with fixed gain. Changing input power changes SNR; noise is **not** scaled to follow it. The 290 K noise-figure model follows [MathWorks thermal noise guidance](https://www.mathworks.com/help/comm/ref/receiverthermalnoise.html).

`channelNumber` is the **center channel** (e.g. 36 at 20 MHz, 42 for an 80 MHz block), with `band='2.4GHz'` or `'5GHz'`. It records center frequency; baseband processing does not simulate RF tuning, regional channel legality, channel-specific matching/filter loss, or frequency-dependent NF. Set NF/impairments from your measurements when comparing channels. This test is one conducted SISO radio, not simultaneous/concurrent radios or MIMO.

Receiver DC/IQ trim, CFO, PA/TX IQ, and other existing settings can be passed to `wifi_rx_per`. `referenceInputDBm` (default -40 dBm) defines the DUT input power giving unit average complex-sample power at the ADC input, before RX errors; it represents a fixed gain setting. ADC clipping and quantization are disabled by default (`adcBits=Inf`). Therefore an ideal run shows a sensitivity waterfall and can remain error free at stronger powers; a two-sided bathtub is not artificially imposed.

To include a modeled overload edge from a fixed-gain ADC:

```matlab
b = wifi_rx_per(struct('standard','11ac','mcs',3, ...
    'channelNumber',36,'bandwidth',20,'inputPowerDBm',-100:1:-5, ...
    'packetsPerLevel',1000,'adcBits',10,'adcFullScale',1, ...
    'referenceInputDBm',-40,'outputDir','results/rx_bathtub'));
```

This is a simplified fixed-gain clipping experiment, not an AGC/LNA gain-state or calibrated DUT compression model. A real radio's upper bathtub edge requires measured AGC/compression/blocker behavior. `rxDC` remains in ADC waveform units, so its relative effect changes with input power. Cable loss can be handled by supplying DUT-plane powers directly. The modeled channel and bandwidth alone cannot predict a particular chip's absolute sensitivity without an appropriate noise figure and impairment budget.

Results include `lowestPassingDBm` (lowest **tested** point meeting `perThreshold`, default 10%), all contiguous `passWindowsDBm`, and a separate interpolated sensitivity estimate described below. The default output parent is `results/rx_per`; each run gets a timestamped subfolder containing `rx_per.csv`, `rx_per.mat`, `rx_per.png` (when plotting), `sensitivity.csv`, and full configuration files. `check_wifi_rx_per` tests exact packet accounting, thermal noise scaling, weak/strong input behavior, and an ADC overload bathtub. A 51-level sweep sends 51,000 waveforms at 1,000 packets per level and can take appreciably longer than the quick SNR demo.

## Version 3 test workflow

### Single tests and separate folders

Edit `run_rx_per.m` and run it normally. By default, `uniqueOutputDir=true` reserves a new folder for every invocation, even for identical settings:

```text
<MATLAB current folder>/results/rx_per/
    11ac_mcs3_ch36_bw20_20261025_123456_789/
        configuration.mat
        configuration.json
        rx_per.mat
        rx_per.csv
        rx_per.png
        sensitivity.csv
```

Use `r.outputDir` for the actual path; `r.settings.outputDir` records the requested parent. `configuration.mat` is the exact reloadable configuration, including complex values and Inf. The readable JSON represents complex values as real/imaginary fields and scalar nonfinite controls such as Inf as strings. `rx_per.mat` includes the configuration and results too. Setting `outputDir=''` disables file output; `uniqueOutputDir=false` explicitly restores the old overwrite-in-place behavior.

When running from another folder, use `addpath('C:\Codex\ofdm-wifi')`, then `run_rx_per` or `run_rx_plan` **by name**. Outputs are based on `pwd`, so they belong to that test folder. MATLAB's `run('full/path/script.m')` can temporarily change folders and should not be used for this workflow.

### Test plans

Open `run_rx_plan.m`, edit the mode groups and trim states, then click Run or type:

```matlab
run_rx_plan
disp(plan.summary)
```

The supplied driver builds **8 separate tests**: 11ac/20 MHz, MCS 0 and 3, center channels 36 and 149, each with trims off and on. Its comments show how to add 11a/n and other bands/bandwidths. There is one active SISO radio per test. The default is 11 coarse power levels and 1,000 packets per level, or 88,000 total packets for the sample plan before any optional refinement. Reduce the matrix/packet count for a quick trial. Channel comparisons share the same baseband receiver model; no channel-dependent RF response is invented.

Every plan has a timestamped parent, with a numbered folder per test. `plan_summary.csv` records mode, MCS, channel, bandwidth, trims, execution status, sensitivity status/estimate, and the output path. `plan_results.mat` is checkpointed after each test. The original test list/common settings/options are saved in `plan_configuration.mat`. Each successful test saves its full resolved configuration and measurements. With `continueOnError=true`, invalid configurations are recorded as failed with `error.txt` and other tests continue; execution status `completed` does not mean the PER specification passed. Setting it false saves the failure/checkpoint then stops. Completed earlier tests remain available if a later test is interrupted. There is no automatic resume/restart feature.

You can also provide an explicit plan:

```matlab
tests = {struct('name','vht_mcs3','standard','11ac','mcs',3), ...
         struct('name','ht_mcs3','standard','11n','mcs',3)};
common = struct('band','5GHz','channelNumber',36,'bandwidth',20, ...
    'inputPowerDBm',-100:5:-50,'packetsPerLevel',1000);
plan = wifi_rx_plan(tests,common,struct('outputDir','results/my_plan'));
```

Each test overrides `common`; the plan owns the per-test output paths. Mode/coding values must form a valid configuration for the installed toolbox. There is no automatic translation between MCS indices across standards.

### Sensitivity and optional 1 dB refinement

`r.sensitivity` reports the first observed low-power crossing of `perThreshold` (default 10%):

- `bracketed`: a failing power immediately precedes the lowest tested passing power. `bracketDBm` gives these measured endpoints; `estimateDBm` linearly interpolates PER versus dBm between them.
- `below_sweep`: the weakest tested point already passes. The crossing is unbracketed and `estimateDBm` is NaN; extend the sweep toward weaker inputs.
- `no_pass`: no tested point passes. The crossing is unbracketed and the estimate is NaN; extend toward stronger inputs or investigate impairments.

`lowestPassingDBm` remains a measured grid point, distinct from the interpolated estimate. All contiguous pass windows and a `nonmonotonic` flag are retained, including when overload produces a second edge. The reported sensitivity concerns the first weak-input edge, not the upper overload limit. Interpolation is an estimate, not an extra measurement, IEEE certification, or a sensitivity confidence interval. The PER confidence bounds still describe each measured packet count. Inspect nonmonotonic/noisy curves before interpreting a crossing.

In either driver, explicitly enable:

```matlab
cfg.refineSensitivity = true;  % use common.refineSensitivity in run_rx_plan
cfg.refinementStepDB = 1;
```

The coarse sweep runs first. Only if it brackets a crossing does the simulator announce and measure **new** interior points at the requested step, using the same `packetsPerLevel`. Existing endpoints are never repeated. For a coarse bracket [-85, -80] dBm, refinement measures -84, -83, -82, and -81 dBm. Results are merged/sorted and sensitivity is recalculated. Refinement is one pass inside the coarse bracket; it does not extrapolate beyond that bracket or automatically extend the sweep. If the bracket is already narrow enough, or unbracketed, no extra packets are sent. No hidden refinement runs occur by default (`refineSensitivity=false`).

`r.testedPowerDBm` and `r.summary` contain all coarse and fine points; `r.settings.inputPowerDBm` preserves the requested coarse sweep. `r.coarseLink`, `r.coarseSensitivity`, and `r.refinement` retain provenance, including the distinct refinement seed. `check_wifi_rx_workflow` validates interpolation, unbracketed states, refinement accounting/merging, repeat-run isolation, complex configuration export, and test-plan continuation/checkpointing with small packet budgets.


## Compare saved RX runs

Open `run_compare_rx.m` and click Run (or type `run_compare_rx`). Set `runFolders` to individual timestamped RX run directories or `rx_per.mat` files. If left empty, the driver opens a folder picker repeatedly; select each desired run and then Cancel to finish. An entire test-plan directory or `plan_results.mat` is also accepted: completed tests expand into individual curves and failed/empty tests are skipped.

The figure overlays **PER (%), effective received SNR/MER (dB), and RMS EVM (%) versus DUT input power**, using matching colors/styles across panels. Measured grids and missing-acquisition gaps are preserved; no packets are simulated. The default `snrMetric='mer'` explicitly derives effective SNR from the saved received EVM, including for older runs. To compare the separate repeated-training noise estimate, choose `snrMetric='ltf'`: missing legacy L-LTF estimates then stay blank and are never replaced with injected SNR or MER. Both quantities are retained separately in exported comparison points as `EffectiveSNRdB` and `ReceivedSNRdB`; `PlottedSNRdB` and the manifest `SNRMetric` identify the selected curve. PER confidence bars are shown when saved bounds are available.

```matlab
comparison = wifi_compare_rx_runs( ...
    {'C:\MyTests\TrimOff\results\rx_per\RUN_FOLDER', ...
     'C:\MyTests\TrimOn\results\rx_per\RUN_FOLDER'}, ...
    {'Revision A - trim off','Revision B - trim on'});

% In-memory results work too:
comparison = wifi_compare_rx_runs({rOff,rOn},{'Trim off','Trim on'});

% Or compare every completed test in a saved plan:
comparison = wifi_compare_rx_runs({plan.outputDir});
```

Labels are optional; automatic labels identify mode/MCS/channel/bandwidth/trim settings or plan test names. For software revisions, assign explicit labels in the driver: historical version information cannot be inferred reliably from the current code. When using plans, custom label count must match the number of expanded completed runs.

Each comparison gets its own timestamped folder under `<MATLAB current folder>/results/compare_rx`, containing `comparison.png`, editable `comparison.fig`, `comparison.mat`, `comparison_manifest.csv`, and a long-form `comparison_points.csv`. Source measurements are not modified. The manifest records source paths, settings (including packet mode, payload, coding, GI, NF, ADC and trims), measured power ranges, received-SNR availability, and sensitivity recomputed at a **common** comparison PER threshold (default 10%). Different modes/grids/packet counts may be compared, but this does not imply equivalent modulation/coding or hardware conditions; inspect the manifest and confidence bounds.

Options: `snrMetric='mer'` (default) or `'ltf'` selects the signal-quality metric; `makePlots=false` skips figures; `outputDir=''` skips export; `showPERConfidence=false` hides confidence bars; `perThreshold` sets the common sensitivity threshold; `title` sets the figure name. `comparison.curves` retains each original sorted grid, `comparison.points` contains combined labeled rows, and `comparison.outputDir` gives the actual export folder. `check_wifi_compare_rx` validates mixed grids, NaN gaps, legacy received-SNR omissions, plan expansion, labels and exports without transmitting any new packets.

## Implemented signal chain

Random PSDU bits → standards-specific service, scrambling, coding, interleaving, constellation mapping, pilots, OFDM, cyclic prefix, preamble/signaling and spatial mapping → TX IQ imbalance → Rapp PA compression → AWGN, normalized FIR multipath, TGn or TGac fading → packet delay, CFO and phase noise → AWGN → RX IQ imbalance and DC offset → ADC clipping/quantization → measured DC/IQ trims → packet detection → coarse CFO correction → fine timing → fine CFO correction → L-LTF/HT-LTF/VHT-LTF channel estimation → MMSE/ZF equalization, pilot phase tracking and soft decoding → PSDU comparison.

TX/RX IQ convention: `Iout = I`, `Qout = g*(sin(phi)*I + cos(phi)*Q)`, where `g=10^(gainDB/20)` and `phi` is quadrature error in degrees. A positive phase setting therefore means departure from ideal quadrature in this specific model.

## Standards and configurations

| Setting | Supported behavior |
|---|---|
| `standard='11a'` or `'11g'` | Non-HT OFDM, 20 MHz, MCS 0–7, one TX/stream. 11g here is its OFDM PHY only. |
| `standard='11n'` | HT mixed format, 20/40 MHz, BCC or LDPC, long/short GI; MCS must agree with stream count (e.g. MCS 11 for two streams and 16-QAM 1/2). |
| `standard='11ac'` | Single-user VHT, 20/40/80/160 MHz, MCS 0–9 subject to standard restrictions, BCC/LDPC, long/short GI. |
| `nTx`, `nRx`, `nStreams` | SISO or spatial multiplexing with TGn/TGac. Use valid configurations accepted by the installed toolbox; streams cannot exceed either antenna count. |
| `channel` | `awgn`, `taps` (SISO FIR), `tgn`, `tgac`. Fading is independently seeded per packet. |

802.11ax/HE and 802.11be/EHT are **not implemented** in this backend. R2018a has draft HE examples, but not the current production HE/EHT APIs. This simulator also does not implement MU/OFDMA scheduling, MAC contention/ACK/retries, beamforming feedback, AGC, sampling-clock offset, or standards compliance certification. Its receiver knows the configured format/MCS/length rather than decoding signaling to discover them. PER is a known-transmitted-PSDU comparison, including acquisition failures, rather than a simulated MAC FCS decision. These are link-level measurements.

## RX DC and IQ trims

```matlab
results = wifi_trim_study(struct('rxDC',0.12+0.08i, ...
    'rxIQGainDB',1.5,'rxIQPhaseDeg',8,'snrDB',10:5:40));

% A single trimmed experiment:
r = wifi_sim(struct('rxDC',0.1+0.05i, 'rxIQGainDB',2, ...
    'rxIQPhaseDeg',10, 'dcTrim',true, 'iqTrim',true));
disp(r.calibration)
disp(r.frontendMetrics)         % independent post-trim DC, IRR, tone EVM
```

The receiver is calibrated once per run using a separate known complex tone, bypassing TX errors and propagation. A least-squares widely linear fit estimates `y = alpha*x + beta*conj(x) + dc`, with adjustable `calibrationSamples` and `calibrationSNRDB`. The same ADC model is included in calibration. Digital trim subtracts measured DC and inverts the measured IQ matrix. This represents a loopback/test-tone calibration facility, not blind over-the-air estimation or analog trim register codes. It cannot undo analog/ADC clipping, and a single constant coefficient does not model frequency-dependent IQ mismatch.

`wifi_trim_study` compares no trim, DC only, IQ only, and combined trim, and prints independent tone residual DC, image rejection, and RMS error. The channel/noise seeds are shared across variants; when PER stopping differs, only their common initial packets are paired. IQ-only trim deliberately preserves the original DC. DC is in waveform amplitude units (absolute complex baseband offset), not dB. Wi-Fi leaves the DC carrier unused, so constant DC alone may barely change data EVM; its effects appear through clipping, synchronization and nonideal windows. Inspect residual DC directly as well as PER.

## Other experiments

```matlab
wifi_examples('multipath')
wifi_examples('mimo')
wifi_examples('pa')
wifi_examples('adc')

% Two-stream HT:
r = wifi_sim(struct('standard','11n','mcs',11,'nTx',2,'nRx',2, ...
    'nStreams',2,'channel','tgn','snrDB',10:5:35));

% 80 MHz 256-QAM VHT:
r = wifi_sim(struct('bandwidth',80,'mcs',8,'snrDB',20:5:45));

% Receiver architecture experiments:
r = wifi_sim(struct('equalizer','ZF','pilotTracking','None', ...
    'cfoHz',40000,'phaseNoiseDeg',0.05));

% TX errors are not removed by RX-only calibration:
r = wifi_sim(struct('txIQGainDB',1,'txIQPhaseDeg',5,'paBackoffDB',4));

% All settings are returned by this function; unknown fields are errors:
c = wifi_defaults;
c.adcBits = 8; c.adcFullScale = 2; c.makePlots = false;
r = wifi_sim(c);
wifi_plot(r)
```

`phaseNoiseDeg` is the standard deviation of Wiener phase increments **per sample**, not an oscillator phase-noise mask. `paBackoffDB` sets the Rapp saturation amplitude relative to input RMS, with smoothness p=3; it is not a measured RF amplifier model. `adcBits=Inf` bypasses both ADC quantization and clipping. With finite bits, I and Q independently clip at `adcFullScale`. TX/RX imbalance, PA and calibration parameters are constant across antennas. `synchronize=false` uses known packet timing and disables CFO correction; use it primarily with SISO AWGN/taps, since fading filter delay is not compensated in this mode.

## Measurements and plots

- PER with packet/error counts and approximate 95% Wilson intervals. Zero observed errors still has a nonzero upper confidence limit. Error-based early stopping makes the fixed-sample Wilson interval approximate; use `minPackets=maxPackets` for fixed-count trials.
- Decoded BER: synchronization failures have no recovered bits and are excluded. Their count and PER remain visible. Failed decoded packets are included in BER and EVM.
- RMS EVM: `100*sqrt(sum(abs(eq-ref).^2)/sum(abs(ref).^2))`, aggregated over all finite equalized symbols. References are generated by clean reception of the transmitted packet, not nearest-constellation decisions. No fitted gain/phase is removed beyond the actual receiver processing. EVM is conditional on acquisition; `EVMPackets` exposes its sample population.
- EVM dB: `20*log10(EVMPercent/100)`. Effective SNR is negative EVM dB; this is an error-ratio metric, not an independent noise measurement, especially with nonlinear distortion.
- Input SNR is time-domain packet sample signal power divided by injected complex AWGN variance, measured before RX IQ/DC/ADC and excluding idle padding. It is neither Eb/N0 nor per-subcarrier Es/N0. Deep-fade SNR is normalized per packet; path-loss/outage with fixed receiver noise is not modeled. `measuredSNRDB` records the configured power ratio, not a pilot-derived estimate.
- PHY goodput counts only error-free PSDU bits divided by generated packet airtime, including preamble and padding. It excludes MAC ACKs, interframe gaps, contention and calibration overhead. VHT PSDU may include toolbox-required APEP padding; inspect `r.phy.PSDULength`.
- Diagnostic plots: constellation, EVM per data carrier and OFDM symbol, channel response, TX/RX PSD, and instantaneous power CCDF. The representative packet is the last finite decoded packet; its SNR is labeled. It may contain payload errors. Carrier axes are array indices, not physical tone numbers.

PSD is a native-rate Hann-window periodogram average in relative amplitude units/Hz. PAPR/CCDF uses native samples and can underestimate continuous-time peaks; neither plot constitutes spectral-mask/ACLR compliance testing. Failed acquisition points show NaN EVM rather than a fabricated value.

## Files and export

`wifi_defaults.m` contains controls, `wifi_sim.m` implements the experiment, `wifi_rx_frontend.m` implements RX hardware/trim, `wifi_trim_study.m` compares calibration modes, `wifi_plot.m` generates plots, and `wifi_examples.m` provides entry points.

Set `outputDir` to export `results.mat`, `metrics.csv` and, when plotting is enabled, two PNG figures. Results contain the settings, PHY configuration, summary table, calibration estimates, raw counters, and a representative packet's TX/RX/reference/equalized symbols and channel estimates. Entire Monte Carlo waveform history is not retained. Every run restores the caller's RNG state.

The implementation targets the **R2018a recovery API**, including `wlanRecoveryConfig` and the three-output VHT receiver. Newer MATLAB releases may require receiver API adaptation; they are not claimed tested.

## References

- [MathWorks packet recovery](https://www.mathworks.com/help/wlan/gs/packet-recovery.html)
- [Non-HT data recovery](https://www.mathworks.com/help/wlan/ref/wlannonhtdatarecover.html)
- [HT data recovery](https://www.mathworks.com/help/wlan/ref/wlanhtdatarecover.html)
- [Reference-normalized EVM](https://www.mathworks.com/help/comm/ref/comm.evm-system-object.html)

The installed R2018a function documentation was used for release-specific signatures.
