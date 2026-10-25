# Changelog

## 3.0.0 — 2026-10-25

- Added `run_rx_plan.m` and `wifi_rx_plan` for mode/MCS/channel/bandwidth/trim test matrices, with per-test results and checkpointed plan summaries.
- Added timestamped output directories by default for conducted RX runs, full MAT/JSON configuration capture, and an explicit overwrite-in-place opt-out.
- Added threshold-based sensitivity extraction, measured brackets, interpolation, unbracketed status flags, pass windows, and sensitivity CSV export.
- Added opt-in fine-step sensitivity refinement that measures only new points inside the coarse bracket and retains coarse/fine provenance.
- Added workflow regression checks and updated the single-test driver/documentation.

## 2.0.0 — 2026-10-25

- Added conducted single-radio RX PER testing versus DUT input power in dBm, with a fixed thermal-noise/noise-figure budget.
- Added exact packet-count testing at every input level, PER confidence intervals, passing-power windows, and CSV/MAT/PNG export.
- Added received-SNR estimation from repeated received L-LTF symbols, with acquisition counts and NaN values when no packet is acquired.
- Added PER, received packet count, received SNR, and RMS EVM plots versus input power.
- Added configurable ADC quantization/clipping to the conducted test for fixed-gain overload bathtub experiments.
- Added the editable `run_rx_per.m` driver with settings and examples for 11a/g/n/ac. Output follows the MATLAB current folder, including when the source is added using `addpath`.
- Added conducted RX regression tests and documented the difference between the measurement driver and multi-case validation script.

Source code, test scripts, and documentation are included. Generated plots, MAT/CSV results, logs, and MATLAB runtime/preferences directories are excluded.

## 1.0.0

Initial Wi-Fi 11a/g/n/ac TX/RX simulator, SISO/MIMO channels, RF impairments, RX DC/IQ calibration trims, metrics, examples, and numerical checks.
