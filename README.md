# Wi-Fi TX/RX and RF calibration simulator

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
