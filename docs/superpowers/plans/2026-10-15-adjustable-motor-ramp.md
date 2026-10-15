# Adjustable Motor Ramp Implementation Plan

> **For agentic workers:** Execute in the current session with test driven development. Preserve existing uncommitted user changes.

**Goal:** Let the operator change Pan and Tilt acceleration from the MATLAB GUI within firmware enforced safe bounds.

**Architecture:** Keep the existing linear pulse period ramp and cruise speeds. Expose the ramp length in steps (lower means faster acceleration) through one atomic `RAMP <pan> <tilt>` serial command. Advertise support and current values in `POS`; MATLAB validates and sends the command; a GUI dialog applies both values while idle.

**Tech Stack:** ESP32 Arduino C++, MATLAB R2025b, native C++ tests and MATLAB mock tests.

**Spec:** User request and answer on 2026-10-15; existing `docs/pan-slow-validation-2026-10-14.md` profile.

## Global Constraints

- Default ramp remains Pan 150 and Tilt 100 steps, with unchanged start/cruise pulse periods.
- Allow Pan 100..600 and Tilt 75..300 ramp steps. Firmware and MATLAB both reject values outside these bounds.
- A setting change produces no motor steps and is blocked during a scan or motor movement.
- Keep STOP, HOLD, ZERO, encoder checks, and existing user changes intact.
- Do not flash firmware or move motors during software verification.

## Review Focus

- The firmware rejects malformed and out of range commands without changing either axis.
- Accepted values change the next move profile but cause no motion when configured.
- Both values are applied together, avoiding a half updated profile.
- Old firmware without `RAMP_CAP:1` fails clearly in MATLAB.
- Short moves use the configured ramp slope without compressing it into a faster ramp.

---

### Task 1: Firmware protocol and waveform

**Files:** `firmware/positioner_v3_hold/src/main.cpp`, `firmware/positioner_v3_hold/test/native/test_motion_timing.cpp`.

- [x] Add failing native tests for default telemetry, accepted/rejected commands, and changed pulse ramp.
- [x] Implement mutable bounded ramp limits, `RAMP` command, and `POS` telemetry.
- [x] Run native motion and hold tests, then compile the ESP32 release firmware.

### Task 2: MATLAB controller

**Files:** `matlab/classes/PositionerController.m`, `matlab/tests/TestPositionerResponse.m`.

- [x] Add failing mock tests for limits and atomic state update.
- [x] Implement `setRampSteps(pan,tilt)`, capability detection, and hardware acknowledgement.
- [x] Run selected MATLAB controller tests.

### Task 3: GUI control

**Files:** `matlab/app/AntennaMeasurementApp.m`, `matlab/tests/TestScan3DGUI.m`.

- [x] Add failing GUI tests for the control and bounded application.
- [x] Add a `Gia tốc...` button with a two-value dialog and a clear note that fewer steps mean faster acceleration.
- [x] Run selected mock GUI tests and inspect the final diff/status.
