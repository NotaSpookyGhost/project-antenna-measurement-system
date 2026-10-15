# VNA Frequency Grid Fix Implementation Plan

> **For agentic workers:** Use test driven development and execute this plan task by task in the current session.

**Goal:** Keep repeated NanoVNA sweeps aligned by frequency so a valid 3D scan does not stop when FIFO records arrive in a different order.

**Architecture:** Preserve raw FIFO order in the low level driver. At the MATLAB bridge boundary, require one record per configured `freq_index`, then order complete records by index before deriving frequency and S parameters. Keep the orchestrator's frequency consistency guard.

**Tech Stack:** Python 3 `unittest`, MATLAB R2025b.

**Spec:** User's 2026-10-15 screenshots and request; `docs/automatic-antenna-measurement-system-master-v4.md` section 9; `CODEX_GUIDE.md` hardware test rules.

## Global Constraints

- Preserve raw scan and validation data.
- Run only mock/software tests; do not access COM5 or COM6 during routine verification.
- Keep the AS5600 encoder gate and the 3D frequency consistency guard.

## Review Focus

- FIFO starts at nonzero index: frequency, S11 and S21 stay paired after ordering.
- Missing or duplicate index: bridge rejects an incomplete sweep.
- Normal ordered sweep: existing result shape remains unchanged.
- Repeated complete sweeps with different FIFO phases: MATLAB receives the same frequency grid.
- Partial 3D scan on other failures: existing abort behavior remains intact.

---

### Task 1: Normalize complete sweeps at the Python bridge

**Files:**
- Modify: `python/nanovna_bridge.py:_result_to_dict`
- Test: `python/tests/test_sweep_integrity.py`

**Interfaces:**
- Consumes: `SweepResult.records`, each `FIFORecord.freq_index`, `SweepResult.complete`.
- Produces: existing MATLAB dictionary fields with frequency and S parameter arrays ordered by ascending `freq_index`; incomplete sweeps return an error dictionary.

- [x] Add tests for rotated complete records with distinct S11/S21 and for duplicate/missing indices.
- [x] Run `python -X utf8 -m unittest python.tests.test_sweep_integrity -v` and observe the expected failure.
- [x] Implement ordering and integrity rejection in `_result_to_dict`.
- [x] Rerun the targeted test and the Python unit suite.

### Task 2: Verify the 3D consumer keeps its data guard

**Files:**
- Modify: `matlab/classes/MeasurementOrchestrator.m` only if the existing guard accepts incomplete sweeps.
- Test: relevant mock MATLAB 3D tests.

**Interfaces:**
- Consumes: `VNAController.acquireSingle()` result with `Complete` and aligned arrays.
- Produces: a partial 3D scan with an explicit invalid-sweep abort when a sweep is incomplete.

- [x] Consumer change unnecessary: bridge now rejects incomplete sweeps before `VNAController` returns a result.
- [x] Run selected mock 3D tests from `CODEX_GUIDE.md` (19 passed).
- [x] Inspect `git diff` and `git status`; existing user changes and data remain untouched.
