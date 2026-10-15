# Pan slow profile and hardware validation — 2026-10-14

Later follow-up: after the user repaired a broken Pan motor conductor in
the A1/A2 pair, the same slow profile passed the guarded 0..+90..0 test.
See `pan-wire-repair-validation-2026-10-14.md`. The failures below describe
the pre-repair condition.

The requested Pan-only slow profile is implemented and flashed to COM5.
**It did not resolve the measured Pan encoder mismatch.** Stall is not a
confirmed root cause. No driver-current, microstep or pulse-per-degree
compensation was applied.

## Configuration

| Setting | Pan / any dual-axis move with Pan pulses | Standalone Tilt |
|---|---:|---:|
| Cruise period | 5000 us | 2200 us |
| Start period | 9000 us | 5000 us |
| Maximum ramp | 150 steps | 100 steps |
| Nominal maximum speed | 8 output deg/s | 18.18 output deg/s |

Ramp remains `min(maxSteps/4, rampLimit)`; Pan5 uses125 pulses and a31-step
ramp. `STEPS_PER_DEG=25`, motor/output ratio5.625, command protocol,
encoder checks, STOP, HOLD and KEEPALIVE remain unchanged. Nominal output
speeds assume the existing pulse calibration is physically correct.

MATLAB `PositionerController.moveTimeoutSec` accepts case-insensitive AZ/PAN
and EL/TILT. Pan timeout is `max(6,abs(deltaDeg)/7+4)`; Tilt retains
`max(5,abs(deltaDeg)/18+3)`. Pan90 and180 budgets are16.8571 and29.7143 s.

## Software evidence

- New native timing test failed on the former Pan90 duration5.34003 s,
  then passed with11.9601 s after the profile change.
- Four native suites passed: motion timing, holding/lease, AS5600 packet
  validity and I2C firmware/retired-command handling. Timing tests exercise
  pure Pan/Tilt, shared-clock GOTO, short/reverse/zero moves, STOP while
  retaining drivers, Pan360 beyond30 s with periodic heartbeat, and lease
  expiry without heartbeat. Native timings are simulated, not oscilloscope
  measurements at the physical pins.
- New MATLAB tests first failed because the static helper did not exist.
  After implementation, selected mock regression:60 passed,0 failed.
- Python unit suite:39 passed. Its intentional negative-case diagnostic
  `VERDICT: [FAIL]` messages are not unittest failures.
- PlatformIO release build and upload succeeded; esptool verified the
  written flash hashes. Independent read-only review found no concrete
  defects in the scoped production/test changes.

## Firmware backup and restore

All artifacts are in `data/validation/pan_slow_20261014_2203/`.

- `pre_slow_flash.bin`: full4194304-byte pre-change flash backup,
  SHA256 `2a3436d69f148f8ff120a0bc63d2586156eebc30425e594fa7cfded31b90f570`.
- `pre_slow_application.bin`: prior application,
  SHA256 `37c86f8edfa7bec59b09f0d3eda1917a0d743aa86c13fd0d8af051102779322d`.
- `pan_slow_application.bin`: flashed slow-Pan application,
  SHA256 `e8d86a2795cc770e56c8639c4b3612894ff23445f59ee5c8d0bcb7ca55e5f90e`.

Firmware banner remains `V4.0_HOLD`; use the saved hash to identify this
build. The full backup can be restored with esptool `write_flash 0x0
pre_slow_flash.bin` on COM5 using the recorded toolchain; this resets the
device and requires a fresh manual ZERO afterward. No rollback was performed.

## Hardware evidence

The user confirmed the current pose as a safe test ZERO for both axes
through0..+90..0. Tests read both encoders, using fresh paired snapshots.

| Stationary state | Pan valid | Tilt valid | Maximum within-state span, motor deg |
|---|---:|---:|---:|
| Released before | 30/30 | 30/30 | 0.00 |
| Held | 100/100 | 100/100 | 0.09 |
| Released after | 30/30 | 30/30 | 0.09 |

The first guarded Pan5 move failed after1.0202 s: the controller measured
0.27 motor deg versus28.125 expected. Ten samples at ZERO and ten after the
fault remained valid; the median stabilized change was0.09 motor deg.
HOLD remained active with no release-count increment during those reads.
STOP was issued, then drivers released and COM5 closed. There was no
automatic return, larger sweep, or Tilt movement.

The user then explicitly requested a visible30 or45 degree retry. This
superseded the original no-retry instruction for one observation only.
The smaller30-degree trial was performed from a fresh current-pose ZERO,
with the existing controller encoder guard retained. It also failed:

| Pan30 observation | Result |
|---|---:|
| Host command/check duration | 4.6057392 s |
| Expected motor angle magnitude | 168.75 deg |
| Controller immediate encoder change | 7.03 deg |
| Median change over10 before/10 after samples | +7.21 deg |
| Implied output change if ratio5.625 is correct | 1.2818 deg |
| Tilt median change | 0.00 deg |

The difference between immediate and median readings is retained explicitly;
neither is a physical measurement of the table angle. The software's logical
position30 is a pulse-count target, not proof of30 degrees of actual travel.
STOP and release followed; no automatic return or additional move occurred.

## Outcome and remaining limits

The slowed firmware remains loaded. Pan did not qualify, so the conditional
Pan90 return and Tilt90 return tests were not executed. Full hardware3D
operation remains unqualified. Reducing commanded speed alone has not fixed
the discrepancy; these data do not establish whether the cause is stall,
driver configuration, transmission, or another hardware issue.

The final read-only POS probe checks `HOLD:0` and closes COM5. Reopening the
GUI/controller is required to use the edited MATLAB class; any new physical
test requires a fresh ZERO after release.

User observation after the30-degree trial: neither motor felt stiff, both
appeared released, and no movement was visible. Release at the end was
intentional and is confirmed by the final `HOLD:0` probe. This observation
does not establish whether physical holding torque was present during the
command. `HOLD:1` telemetry and an unchanged release counter during the
trial confirm firmware state only, not electrical enable at the driver or
actual motor torque. Smoothness and effective holding remain unverified.

Raw evidence: `stationary.json/.log`, `motion.json/.mat/.csv`,
`motion_console.log`, `pan30_observation.json/.mat`, `pan30_before.csv`,
`pan30_after.csv`, `pan30_console.log`, `final_state*.log`, plus build,
upload, backup and regression logs in the artifact directory above.
