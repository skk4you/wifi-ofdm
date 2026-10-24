# Wi-Fi TX/RX and RF calibration simulator

**Version 2.0.0** — conducted RX power sweeps, received-SNR estimation, and an editable single-sweep driver. See [CHANGELOG.md](CHANGELOG.md).

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

The test figure and exported `rx_per.png` show four plots versus DUT input power: PER, successfully received packet count, **estimated received SNR**, and RMS EVM (%). Received SNR uses the two received L-LTF symbols after the RX frontend and timing/CFO correction: their difference estimates noise power; their average estimates signal power after subtracting the average's noise bias. Signal and noise powers are summed across acquired packets before taking the dB ratio. `ReceivedSNRdB` and `SNRPackets` expose the estimate and its packet population; the existing `SNRdB` column retains the configured input SNR for comparison. No acquisition produces NaN/gaps rather than an injected-SNR substitute. This is occupied-L-LTF-carrier SNR, so it need not equal full-band input sample SNR. It assumes the channel/signal is stable across the repeated training symbols: static IQ/clipping distortion can cancel in the difference and is not fully represented as noise. Use EVM alongside it. Both estimates include acquired packets with bad payloads, and are conditional on acquisition.

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

Results include `lowestPassingDBm` (lowest **tested** point meeting `perThreshold`, default 10%), all contiguous `passWindowsDBm`, and flags indicating whether failing test points bracket the edges. No interpolation or extrapolation is used; inspect all pass windows for noisy/nonmonotonic results. The default export directory is `results/rx_per`, containing `rx_per.csv`, `rx_per.mat`, and `rx_per.png`. `check_wifi_rx_per` tests exact 1,000-packet accounting, thermal noise scaling, weak/strong input behavior, and an ADC overload bathtub. A 51-level sweep sends 51,000 waveforms and can take appreciably longer than the quick SNR demo.

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
