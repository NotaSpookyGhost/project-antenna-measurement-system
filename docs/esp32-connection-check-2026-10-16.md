# ESP32 connection check — 2026-10-16 (Asia/Bangkok)

Reported symptom: MATLAB app reports connected, but the motors do not hold.

## Observed hardware evidence

Serial enumeration found COM9 (CH340, VID:PID1A86:7523), COM6 (VNA) and Bluetooth COM3/COM4. COM5 was absent. Opening COM9 at115200 succeeded; a `POS` query returned the following, in two read chunks (`P` then the remainder):

```text
PAN:  0.00 TILT:  0.00 RAW_PAN: -1.00 (AGC:255) RAW_TILT:208.30 (AGC:128) HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1 SENSOR_CACHED:0 ENC_PAN_VALID:0 ENC_TILT_VALID:1 RELEASES:1 FW:V4.0_HOLD SCAN3D_CAP:1 PAN_MIN:-360 PAN_MAX:360 TILT_MIN:-180 TILT_MAX:180 RAMP_CAP:1 RAMP_PAN:150 RAMP_TILT:100
ESP32-ANTENNA>
```

A subsequent attempt to write `HOLD ON` failed in Windows:

```text
WriteFile failed (PermissionError(13, 'Access is denied.', None, 5))
```

There was no HOLD acknowledgement. The diagnostic serial connection `sea12ab8f` was closed. No motion, ZERO, firmware upload, driver-release command or confirmed hold change occurred during this probe. This does not prove the physical driver supply, wiring or torque is working. Pan encoder feedback was invalid in the observed snapshot; Tilt feedback was valid. One snapshot does not establish continuous sensor reliability.

## Source observations

- `matlab/app/AntennaMeasurementApp.m:127` constructs both instruments in Mock by default; Mock connect at `matlab/classes/PositionerController.m:181` does not open hardware. The currently selected UI mode still needs user/log confirmation.
- The running app process command names this repository as its startup directory. An alternate checkout has not been established as the cause.
- Hardware connect sends `HOLD ON` at `matlab/classes/PositionerController.m:209`, starts keepalive after acknowledgement, and does not redefine ZERO.
- The firmware has a30s hold lease and reports commanded HOLD status. A reported HOLD bit is not a physical torque measurement.
- `matlab/classes/PositionerController.m:816` checks a decoded missing encoder with `<0`; the decoder represents explicit invalid telemetry as NaN. That check does not reject NaN. This is a separate code observation, not an established cause of the reported absent holding torque.

## Pending verification

Keep USB connected and disconnect Positioner in the MATLAB app before a single-client stationary hold test. Confirm the selected mode and current log. Then query POS, verify HOLD acknowledgement and sustained keepalive, and obtain operator confirmation of actual holding. Do not use LOCK ZERO or motion to diagnose this connection issue.

No production code was changed during the initial check above. The later results below supersede its pending hardware status.

## Follow-up with the app closed

The user's log confirmed Hardware mode and COM9 after a failed COM5 attempt. It also showed a false positive: “Đã nhận cả hai encoder” followed by Pan NaN, and later ZERO success messages with both encoders NaN. Source cause: explicit invalid telemetry becomes NaN in the decoder, but the connection check used only `<0`, which does not reject NaN. The GUI enabled Tilt based solely on its cached Tilt sample.

Before wire repair, direct COM9 testing received HOLD ON acknowledgement, 8/8 POS snapshots with HOLD:1, 8/8 PONG replies, and 0/8 valid Pan/Tilt pairs. The operator reported both motors still loose. HOLD OFF was acknowledged and the port closed. The control replies alone did not establish physical torque.

The user then reported reconnecting a loose wire. Retesting the same firmware and commands produced 8/8 valid Pan/Tilt pairs, HOLD:1 throughout, 8/8 PONG replies, and an unchanged RELEASES:3 across the held snapshots. Samples span34.612s, beyond the30s hold lease. The operator confirmed **both motors now hold**. HOLD OFF was acknowledged and COM9 closed afterward. No motion or ZERO was sent. This supports the repaired connection as the cause of the physical symptom in this test; it does not identify which electrical conductor had been loose or qualify angular accuracy.

Raw serial tool results: [before repair](verification/esp32-hold-2026-10-16.json), [after repair](verification/esp32-hold-after-wire-repair-2026-10-16.json). UTC timestamps are included in the JSON; local date is2026-10-16 Asia/Bangkok.

## Software correction

- `PositionerController.requireEncoderFeedback` rejects NaN/Inf and out-of-range encoder angles; hardware POS validation uses this guard before accepting a snapshot. Disabled Tilt retains the existing Pan-only path.
- `AntennaMeasurementApp.connectPositioner` requires both encoder values to be finite before announcing both encoders and enabling Tilt.
- Three new regression cases cover invalid Pan, invalid Tilt with Tilt enabled/disabled, and valid/negative feedback. New tests failed first; the fixed software passed **49/49 selected MATLAB tests**, including response parsing, manual homing, limits, scans, STOP and move timeout. No hardware is opened by those unit tests.
- Local RED/GREEN logs are in `.superpowers/sdd/esp32-2026-10-16/`. Existing user logs under `data/logs/` were preserved. No firmware upload, Python environment migration or driver-current adjustment was performed.

## Final MATLAB/app stationary verification

The actual app's `connectPositioner('COM9')` path was run in a new MATLAB R2025b process with Hardware Positioner and Mock VNA. It connected successfully, confirmed HOLD, and obtained both finite encoder samples. No position query was issued during a35s pause, so the production keepalive timer alone maintained the hold lease.

```text
MATLAB_HOLD_INITIAL connected=1 hold=1 zero_required=1 pan_encoder=323.17 tilt_encoder=215.68 releases=0
MATLAB_HOLD_AFTER_35S hold=1 pan_encoder=322.47 tilt_encoder=216.04 releases=0
MATLAB_STATIONARY_HOLD PASS; no motion or ZERO; disconnected and released.
```

Release count reset on the new hardware session; only the unchanged count within that session is compared. The GUI lamp was `CẦN ZERO`, correctly reflecting the missing mechanical reference while HOLD was active. HOLD describes the commanded/acknowledged driver state; physical holding was confirmed separately by the operator during the direct retest.

MATLAB hardware verification exit0; selected49-test software gate exit0; diff whitespace check passed. Persistent [MATLAB transcript](verification/esp32-matlab-hold-2026-10-16.txt). Neither this stationary test nor the sensor-valid flags qualify angular accuracy or a complete scan. The final session was disconnected and drivers released.

Next use: reopen the app, select ESP32 hardware and COM9. Confirm holding, then align and set the mechanical ZERO through the existing workflow before scanning. Do not reuse a previous travel confirmation after reset/release.
