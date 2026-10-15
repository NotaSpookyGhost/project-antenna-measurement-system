# Pan-only slow motion implementation

Spec: user-approved plan in this conversation, 2026-10-14.

- Firmware: Pan 5000/9000 us, ramp 150; Tilt 2200/5000 us, ramp 100.
- MATLAB: axis-specific moveTimeoutSec, preserving encoder/STOP/heartbeat checks.
- Verification: native timing/pulses/lease, MATLAB regressions, build, flash backup and upload, stationary sensors, guarded Pan 0..90..0 then Tilt if Pan passes.
- Ruling: reuse the current codex branch and workspace, which contains the GUI repair from this conversation; preserve all pre-existing changes and raw data.
- No firmware flash or motion until software verification and review pass.

Status: writing regression tests before implementation.

Software complete: new tests failed against old implementation, then passed after the scoped change. Native timing/Pan90=11.9601 s; 4 native suites PASS; 60 MATLAB mock tests PASS; 39 Python unit tests PASS; PlatformIO build/upload PASS. Independent read-only review found no concrete defects. Full 4 MiB flash backup and application binaries saved with SHA256 hashes. User confirmed the present ZERO and 0..+90..0 travel safe for both axes.
Hardware stationary passed 160/160 for both axes. Original guarded plan stopped at Pan5: immediate motor encoder delta0.27 vs28.125 expected; fault capture median shift0.09 motor degrees. Drivers released, COM5 closed, final POS HOLD:0 verified. No Tilt trial.
Ruling: user explicitly requested a visible 30 or45 degree retry after the failed5 degree trial. Perform exactly one30 degree Pan trial from a fresh current-pose ZERO, retaining controller encoder check and no automatic return. This supersedes the original stop-without-retry instruction only for this requested observation. It does not qualify the hardware or authorize pulse compensation.
User-requested Pan30 observation completed with encoder guard intact: 4.6057392 s, immediate7.03 motor degrees versus168.75 expected; before/after10-sample medians changed7.21 Pan /0 Tilt degrees. No return or further movement. Final read-only POS confirmed HOLD:0, CAL_REQUIRED:1; COM5 closed. Implementation and verification protocol complete with a FAILED hardware acceptance result. Full90-degree sweeps are intentionally unexecuted due to failed Pan gate. Report: docs/pan-slow-validation-2026-10-14.md. User smoothness observation pending.
User final observation: both motors felt released, no visible movement. Explained deliberate end-of-test release; physical holding during the move is not established by HOLD telemetry. Recorded in the report. No further hardware command sent.
