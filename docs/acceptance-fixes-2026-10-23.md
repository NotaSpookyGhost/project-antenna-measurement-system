# Acceptance corrections — 2026-10-23

Baseline: aeb1b9f67805d2004c694f63e8a835b0003a8112. Working branch: codex/acceptance-fixes-20261023.

## Behavior corrected

- Surface amplitudes at theta0 and theta180 are averaged separately; unmeasured poles remain missing. Vectorized cell aggregation is retained.
- SLL accepts full-circle grids with or without duplicate closure, including descending and offset grids. An optional fourth `fullCircle` argument declares topology explicitly; orchestrator and 3D slices pass their completed scan topology, preserving sector/incomplete-scan edges.
- `plotCartesian` accepts optional sixth `analysis`; final GUI, export and standalone viewer reuse the saved analysis instead of inferring topology again.
- Configuration and acquisition serial failures propagate `TRANSPORT` and close the failed backend transport. Cancellation retains terminal errors independently from state `CANCELLED`, and always discards late raw data.
- MATLAB consumes terminal `TRANSPORT` even on cancelled jobs, marks the connection offline and calibration stale. Ordinary cancellation preserves a working connection/calibration.

## Verification record

Red/green evidence and execution logs: `output/fixes-2026-10-23/`.

- Python discovery:85 tests PASS, including new transport regression cases; supplementary validation harness7 tests PASS; compileall PASS.
- Firmware: all5 native C++ suites built with g++ and passed (AS5600, hold, retired-PWM/I2C, motion timing, motor ramp). No firmware upload or source changes.
- Geometry focused:16 tests PASS plus7 existing analyzer checks. Surface37x73 timeit0.012554709s; required budget0.02s.
- Cartesian regression:7 tests PASS, including sector/stopped-turn GUI and 3D slice annotations.
- MATLAB full allowlist:147/147 tests and3/3 Mock scripts PASS; no VNA timer leaks; all six process exit codes0. First combined run exited out-of-memory, not counted as PASS. Same24 classes and3 scripts were run in six fresh MATLAB processes, without weakening assertions or removing tests. Group JSON and exit codes retain exact coverage.
- Real VNA COM6:9/9 sweeps PASS at11/101/401 points,3 repeats each. Raw JSON at `data/validation/acceptance_rf_20261023_225339/result.json`. Sweep durations0.23–0.39s,1.17–2.37s,4.30–4.42s respectively.
- Combined ESP32 COM9/VNA COM6 hardware acceptance: FAIL due to unavailable Tilt feedback. Explicit reusable runner: `test_acceptance_hardware(positionerPort,vnaPort,outputDir)`. Real stationary RF, asynchronous STOP (4.3290175s),30 held paired encoder snapshots and Pan/Tilt0→10→0 succeeded. Pan0..360 step30 retained11/13 RF points, then aborted while moving to330 because ESP32 reported `ENC_TILT_VALID:0`, `RAW_TILT:-1`, `AGC:255`; Pan remained valid and HOLD remained on without a release during the scan. The invalid AGC placeholder is not a magnet-strength measurement. The small3D stage was NOT_RUN. Cleanup released motors/disconnected, without recovery motion after the fault. Test ZERO was at the operator-authorized starting pose; the mechanism was not returned to its starting mark after this fault.
- Raw combined-run evidence: `data/validation/acceptance_system_20261023_160241_UTC/result.mat`, `hardware.log` and `motor/*.jsonl`; summary `output/fixes-2026-10-23/hardware-summary.json`. Preserve all11 completed points.
- Stationary post-fault diagnosis: Pan160/160 valid, Tilt0/160 valid across30 released,100 held,30 released samples. No motion or ZERO. Final HOLD OFF confirmed. Evidence: `data/validation/acceptance_encoder_20261023_230625/raw.jsonl` and `summary.json`. An earlier probe stopped on a Windows file-write error; its partial raw evidence at `acceptance_encoder_20261023_230526/raw.json` is retained and not counted as a complete pass.

## Acceptance outcome

The five software review defects and consistent SLL annotations across GUI/export/viewer are corrected and regression-tested. Software acceptance passes. Full hardware motion/3D acceptance does not pass: the firmware currently reports unavailable Tilt feedback even without movement. Sensor power/GND, connections and magnetic alignment need physical inspection before further scans; neither the host guard nor firmware limits were weakened to obtain a pass.

## Scope limits

Real RAW I/O pass does not establish calibrated RF accuracy, gain, physical antenna-table closure, or full Tilt travel. These need independent standards/operator evidence. The hardware runner tests Tilt0..10 degrees under declared travel; it never widens firmware guards to reach a user-stated mechanical limit. MATLAB's Python3.13 support warning is retained in the logs.
