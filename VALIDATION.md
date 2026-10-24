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
