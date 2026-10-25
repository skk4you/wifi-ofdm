# Validation on the installed MATLAB R2018a

`check_wifi_sim` completed successfully. The log is `matlab_final.log`.

Checked cases:

- 802.11a, 11g OFDM, 11n and 11ac at 60 dB input sample SNR, with 20 kHz carrier offset: no payload errors in the three-packet smoke tests.
- Normalized FIR multipath: successful synchronization, channel estimation and payload recovery.
- 80 MHz 802.11ac, MCS 8, LDPC, short guard interval: successful recovery.
- Two-stream 2x2 TGac/VHT and TGn/HT fading: successful recovery.
- RX imbalance of 2 dB and 10 degrees plus DC of 0.12 + 0.08j: EVM about 20.05% before trim and 0.15% after combined trim at 60 dB. The separate synthetic calibration inversion check also passed.
- A 20-packet-per-point sweep at 0, 15 and 35 dB: PER 1, 0 and 0 respectively; 0 dB failed acquisition for all packets. EVM at acquired points fell from 24.21% to 2.45%.
- PER confidence bounds, CSV/MAT export, and both metric and packet-diagnostic PNG plots. Diagnostic PNG layout was visually inspected and adjusted to avoid clipping/overlap.

These are deterministic integration/smoke tests, not exhaustive MCS, channel, hardware or IEEE conformance validation. The small packet counts do not establish low error-rate performance. RX calibration uses a dedicated known calibration tone, as described in README.md.

`run_wifi_demo` creates additional example baseline and trim sweeps under `results/` for inspection. Repeat with a larger packet budget for statistical studies.

The saved demo completed too: combined trim reduced independent tone DC magnitude from 0.14422 to 0.000034836, improved image rejection from 19.10 to 90.66 dB, and reduced tone RMS error from 33.546% to 0.008%. These values reflect the specified idealized frequency-flat receiver model and dedicated calibration capture, not measured hardware.

## Conducted power sweep

`check_wifi_rx_per` passed in `matlab_rx_per_final.log`. For 11ac MCS 3, 20 MHz, center channel 36, 7 dB NF, 128-byte payload setting, and exactly 1,000 packets per power level:

| DUT input (dBm) | Sent | Received OK | PER |
|---|---:|---:|---:|
| -100 | 1000 | 0 | 100% |
| -82 | 1000 | 847 | 15.3% |
| -60 | 1000 | 1000 | 0% observed |

Tests verify the -93.96 dBm integrated noise floor, unchanged noise power as input power changes, calculated versus injected SNR, exact packet accounting, and nonzero confidence bounds after zero errors. An additional 20-packet-per-point, fixed-gain 10-bit ADC test produced PER 100%, 0%, and 100% at -100, -65, and -5 dBm, confirming simulated sensitivity and overload edges. Increasing NF by 3 dB increased the noise floor by 3 dB. The exported power-sweep and bathtub figures were visually inspected.

These widely spaced smoke-test points do not measure a 1 dB-resolution sensitivity boundary. Use the full power sweep and an appropriate DUT impairment/noise budget for that experiment.

## Version 3 workflow checks

`check_wifi_rx_workflow` and the existing `check_wifi_sim` passed in `matlab_workflow.log` on MATLAB R2018a. The workflow test validates synthetic bracketed/unbracketed and nonmonotonic crossings, then runs an actual -85/-75 dBm coarse test with 1 dB refinement at 20 packets per level. Exactly 220 packets were counted at 11 unique levels; the final measured bracket was [-83, -82] dBm and the interpolated crossing was about -82.14 dBm. This is a small-budget integration result, not a hardware sensitivity claim.

Two consecutive identical settings received separate timestamped directories. Configuration MAT/JSON files preserved complex DC settings. A three-case plan completed its first test, recorded an intentionally invalid second mode, then completed its third test and saved the summary/checkpoint and error record. The refined four-panel PNG was visually inspected.

An additional `addpath` test launched from `test_output/external_run` saved both a single run and a plan beneath that current folder. A malformed vector-valued MCS was recorded as a failed row with NaN MCS; the following valid test completed. This passed in `matlab_plan_paths.log`.
