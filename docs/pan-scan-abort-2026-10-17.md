# Pan encoder mismatch near completion —2026-10-17

## Original scan failure

Sources: `data/logs/system_log_20261017_051101.txt` and `data/logs/matlab_runtime_20261017_031154.txt`. Times below are Asia/Bangkok.

- A2D scan completed181/181 points at03:33:34.
- The3D scan started03:39:00 with37Tilt rows ×73Pan samples =2701 points.
- At05:04:17, after85minutes17seconds, `PositionerController:EncoderMismatch` stopped acquisition after2608 committed points (96.56%).
- The incomplete move was Pan100→95 degrees on row36, Tilt85 degrees/theta175 degrees. There were53 committed points in that row;93 total grid points remained unmeasured.
- The motor encoder changed15.47 degrees; a5-degree antenna move with ratio5.625 requires28.125 motor degrees. The12.655-degree difference exceeded the existing10-degree motor-encoder tolerance for that move.

This confirms a failed motion-feedback consistency check. It does not distinguish actual motor undertravel from a transient encoder error. The circular-difference calculation already handles the0/360 encoder boundary. No recorded VNA exception, range violation, move timeout or hold-watchdog message explains this stop. Absence of a watchdog message in the app log is not proof that one never occurred.

The mismatch handler invalidates the mechanical reference and stops the scan; that branch does not issue HOLD OFF. It retains the partial data in the app for export. No threshold was loosened and no failed sample was committed to make the grid appear complete.

## Later release observations

Afterward, the runtime log records LOCK/ZERO actions at05:14:27,05:14:30,05:14:34,05:14:37,05:14:39 and release actions at05:14:29,05:14:33,05:14:38,05:14:40. The operator subsequently observed the app's released status and physically soft motors. The latest recorded explicit release explains the later state; that later observation cannot establish that both motors released at05:04:17.

The operator initially said the torque had not been checked at the failure time. A new baseline release counter from before the85-minute scan is unavailable, so later counter values cannot establish its complete release history across possible board resets.

## Stationary hold check

The operator confirmed saving/exporting and disconnecting Positioner to free COM5. Enumeration found CH340 COM5; no diagnostic serial connection was already open. A stationary serial check then used only POS, HOLD ON, PING and HOLD OFF. No PAN, TILT, GOTO, ZERO or firmware operation was performed.

- Initial POS: HOLD0/CAL_REQUIRED1, both encoders valid, RELEASES4, firmwareV4.0_HOLD.
- HOLD ON acknowledged. The operator confirmed **both motors physically held** during this test.
- Eight PING replies were PONG. Eight repeated POS snapshots were HOLD1 with valid Pan/Tilt encoders and RELEASES4 unchanged. Including the initial held POS, held observations span57.857s, beyond the30-second lease; repeated samples themselves span about36s.
- After the initial holding alignment, the eight repeated samples were Pan23.20 and Tilt191.60 motor degrees, both constant at the firmware's displayed resolution.
- HOLD OFF acknowledged; COM5 closed. Final state is intentionally released and disconnected, with no usable mechanical reference established by this test.

Raw tool responses and timestamps: `docs/verification/pan-abort-2026-10-17/stationary-hold.json`. A commanded HOLD bit is not a torque sensor; the separate operator confirmation supplies the physical observation. This is a stationary check, not a recreation of a late scan failure under motion/load or an85-minute endurance qualification.

## Remaining diagnosis

Actual missed motion, an intermittent motor/power connection, load or driver behavior, and erroneous encoder feedback remain possibilities rather than established causes. A short targeted motion reproduction needs a new operator-established physical reference and known clearance because the post-failure ZERO/release actions replaced the original reference. No such motion has been attempted.

The operator subsequently clarified that the dataset was not exported because the RF source was Mock. This agrees with the startup default, lack of a recorded VNA-mode switch and absence of an export-success message. The generic UI message `Connected to VNA on COM6 (Variant:0x02)` also occurs in Mock mode and does not establish real RF acquisition. Positioner mode, encoder feedback and the motion failure were real ESP32 hardware.

Recovery check found no new scan .mat in the current repository or the alternate project workspace, no root `matlab.mat`, and no recent .mat in the top-level temporary folder. The surviving settings .mat stores scan configuration, not individual encoder samples. The actual MATLAB process for the03:12/03:39 run has exited; the remaining MATLAB process started the previous day and does not establish survival of this scan. Source inspection confirms LastScanData is held in app/orchestrator memory and written by explicit export, with no scan checkpoint/autosave path implemented. These checks did not recover the full2608-sample encoder history. Text logs retain row progression and the failing-motion summary, not each encoder pair; they cannot reconstruct the missing measured arrays. Mock RF may be regenerated only as a new simulation and must not be substituted for the original motor encoder record.

A web-controller destructor warning also appeared on subsequent app close; it occurs after the scan failure and is not established as its cause.

No production software or firmware change was made during this investigation. User logs and existing raw data were preserved.
