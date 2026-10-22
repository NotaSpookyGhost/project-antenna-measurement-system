# Motor Journal Implementation Plan

> **For agentic workers:** Use executing-plans inline, task by task. Preserve the existing uncommitted feature work; do not commit or reset unrelated changes.

**Goal:** Persist scan motor feedback and diagnose Pan return drift without changing ZERO or moving hardware.
**Architecture:** MotorScanJournal owns durable JSONL and closure math; PositionerController owns the fixed manual reference; MeasurementOrchestrator wraps scan moves; the app enables the journal for hardware positioners.
**Tech Stack:** MATLAB R2025b, existing Mock fixtures, JSONL.
**Spec:** docs/superpowers/specs/2026-10-17-motor-journal-design.md

## Global Constraints

No real motion/ZERO/firmware test. No changed stop/travel thresholds. Reference stays fixed. Mock RF and real positioner remain explicit. Preserve all user data and current work.

## Review Focus

- Encoder wrap and different shaft phase at antenna360 must not create false closure errors.
- New scans, missing references and release/re-ZERO must not silently rebase an old reference.
- Failed moves must be recorded even though their RF sample is never committed.
- Journal I/O errors must not mask the primary movement fault or permit silent unlogged motion.
- Logging must avoid new COM transactions, timer/port races, and misleading Mock shaft units.

### Task1: Durable journal and closure calculation

Files: create matlab/classes/MotorScanJournal.m and matlab/tests/TestMotorScanJournal.m.
Interface: constructor(directory,metadata), recordMove(axis,target,before,after,status,errorId,errorMessage), finish(state,completed); read-only Path. Snapshot contains both cached axes, fixed Pan reference/id and hold/release state. Closure result returned to the caller for a concise UI warning.

- [x] Write and run failing tests for immediate readable appends, fixed-baseline repeated drift, wrap, nonzero360 endpoint, unavailable/reference-change cases and unique files.
- [x] Implement the smallest logger and rerun the tests.

### Task2: Reference capture and scan integration

Files: modify PositionerController.m, MeasurementOrchestrator.m, AntennaMeasurementApp.m; add TestMotorJournalIntegration.m and a Mock fixture if needed.
Interfaces: PositionerController.PanZeroEncoderDeg/PanZeroId; orchestrator.MotorLogDirectory/LastMotorLogPath; private scan movement wrapper records cached telemetry and preserves exceptions. The hardware app selects data/logs/motor; direct Mock tests explicitly select temporary paths.

- [x] Write and run failing reference/integration tests for repeated scans, explicit re-ZERO, 2D/3D journal writes and a failed uncommitted move.
- [x] Implement reference capture and the scan wrapper; test, then enable the hardware app path and metadata link.

### Task3: Verification and handover

- [x] Run the new tests plus the selected existing Mock positioner, scan, STOP, geometry and GUI gates; inspect generated artifacts and diff.
- [x] Obtain a fresh review of this task's changes; resolve concrete findings and verify the affected cases.
- [x] Document log location, warning meaning, Mock distinction and lack of real-motion qualification. Preserve evidence.
