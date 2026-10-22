# Motor journal verification —2026-10-17

MATLAB R2025b25.2.0.2998904. Final selected software gate: **120/120 unit tests and3/3 Mock scripts PASS**, process exit0. No VNA poll/calibration timer leaks. No physical COM connection, motor movement, ZERO or firmware test was performed for this implementation. Hardware-mode journal selection was exercised through a fixture that forbids opening a serial port.

The final gate includes16 new journal/reference/integration tests and the existing selected VNA, calibration, geometry, positioner, homing, STOP and GUI tests. New tests cover immediate durable reads, failed-move records before RF commit, fixed-baseline drift/wrap, Pan360 versus Pan0, repeated scans, explicit reference changes, unavailable references, release/counter invalidation, startup I/O failure and primary-error preservation even with warning-as-error settings.

RED/GREEN evidence is retained alongside this report. Initial2D failure tests incorrectly assumed the existing API returned partial data for all errors; source inspection showed2D rethrows encoder mismatch, while3D returns partial data. Tests were corrected to preserve those established semantics. A separate journal completion counter records committed points even for a rethrown2D failure.

Independent review found two state defects; both and a warning-as-error defect were reproduced before fixes, then their3 focused regressions passed. The reviewer approved the fix pass; see review.md. The final full gate ran after those fixes.

The generated `motor_*.jsonl` sample in this directory comes from the actual new scan code path with **both instruments explicitly Mock**, a2-point5→0 scan. It preserves the same reference id and a completed terminal record. It is a software example, not RF measurement or physical motor evidence.

Source hashes are in source-hashes.json. `git diff --check` passed. Tests wrote their temporary datasets/journals into temp folders; the hardware-mode/no-I/O fixture's generated journal was collected into its temporary folder and removed by fixture teardown. Existing user data/logs were preserved. No firmware or Python files were changed for this feature.

This feature records and warns about motion evidence. It does not establish the physical cause of the original late-scan Pan failure, independently measure antenna-table angle, or qualify long-duration real motion. User workflow: docs/motor-encoder-journal-user-guide.md.
