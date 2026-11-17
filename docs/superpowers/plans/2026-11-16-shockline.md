# ShockLine MATLAB Implementation Plan

> Execute inline using executing-plans, with a fresh final reviewer.

**Goal:** Connect the existing MATLAB GUI to ShockLine for static S11/S21 and fresh antenna-scan acquisitions.
**Architecture:** Native MATLAB TCP adapter behind VNAController; explicit snapshot/fresh acquisition; preserve existing Mock/NanoVNA paths.
**Tech Stack:** MATLAB R2025b tcpclient, matlab.unittest, existing Python regressions.
**Spec:** docs/shockline-matlab-integration-design-2026-11-16.md (user approved).

## Global constraints
- No hardware commands during implementation/testing. No motor access.
- Connect queries only; no implicit trigger/configuration/power/calibration/reset.
- Definite-length blocks may contain embedded newlines; close on framing failure.
- Preserve existing uncommitted data; no automatic resume from HOLD.

## Review focus
- Truncated/malformed blocks and stale replies.
- Missing S21 trace and invalid/nonfinite data.
- Snapshot mistaken for fresh sweep.
- Confirmation before VNA/motor side effects.
- Actual frequency grids and corrected-data provenance in both scan paths.

## Tasks
- [x] Add failing offline tests with an injected byte stream for SCPI framing and scripted instrument replies; run MATLAB and observe failures.
- [x] Implement ShockLineTransport and ShockLineClient; tests cover multilines, truncated blocks, identity, missing trace, snapshot and single sweep.
- [x] Integrate VNAController mode, static GUI actions/save, pre-scan confirmation, scan validation/provenance; add offline GUI tests.
- [x] Run selected MATLAB mock suites and Python unit suite. Review diff with fresh reviewer; fix substantive findings and rerun affected tests.
- [x] Document usage and test evidence. Hardware acceptance remains separately approved.

## Rulings / execution ledger
- Work directly in the user's current checkout: this is the installed app workspace, with extensive pre-existing untracked measurement evidence. Preserve it and keep changes reviewable; do not move or clean files.
- Frequency writes are conservatively limited to the initial connected sweep band (readback), rather than inferring installed options from model ID. Reconnect after deliberately expanding the band in ShockLine.
- No commits/push/merge in this delivery; leave the patch for user review.
- Validation: 13 new MATLAB tests passed (10 protocol/provenance, 1 GUI, 2 scan readback), together with selected existing mock suites and pattern/orchestrator/direction scripts. Python unit discovery exited 0. The Python suite prints intentional failure-case verdicts; those are expected assertions, not failing unit tests.
- Actual tcpclient loopback checks passed: snapshot plus configure/single, full three-position scan, and second-trigger disconnect preserving one point with NaN pattern metrics. These used ephemeral fixture ports 59196, 63481 and 50548, never the instrument port.
- Fresh reviewer findings fixed: one-point preservation, committed provenance consistency, numeric readback confirmation. Follow-up review found no additional substantive issues.
- Final GUI test passed after layout adjustment; preview visually inspected. App left open OFFLINE with ShockLine selected and Mock positioner. No VNA or motor commands issued in this implementation turn.
- Existing trace changes and measurement files preserved. Test-generated tracked pattern PNG copied to output/shockline-validation before restoring its pre-test bytes; other generated mock artifacts kept out of source changes.
