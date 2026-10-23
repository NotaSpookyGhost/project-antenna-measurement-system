# Acceptance corrections

Spec: output/review-2026-10-22/acceptance-review.md (five reproduced findings).

1. Add failing MATLAB regression tests for independent poles, unmeasured poles, and closed-circle SLL with/without a duplicated endpoint; retain sector behavior. Fix ScanGeometry and PatternAnalyzer without losing vectorized performance.
2. Add failing Python regression tests for configuration, FIFO-clear transport exceptions and cancellation concurrent with transport failure. Preserve TRANSPORT through terminal job results even when cancelled; never publish cancelled raw data. Fix nanovna_bridge and vna_jobs.
3. Test and fix MATLAB VNAController consumption of transport loss on CANCELLED and FAILED jobs, invalidating connection and calibration.
4. Run complete Python unit discovery, MATLAB software allowlist and any additional safe software tests, firmware native checks if the configured local toolchain supports them. Review changes independently and resolve findings.
5. Hardware tests are staged: confirm actual ports and operator readiness, stationary VNA/encoder tests first, then specifically confirmed Pan motion. Never silently ZERO, release a manually established reference, change firmware, or run all hardware scripts blindly. Preserve measurement artifacts and record exact test limits.

Reuse the existing feature checkout on branch codex/acceptance-fixes-20261023 so the operator tests the same installation. No unrelated working-tree data changes are included. Commit and push only on explicit user request, subsequently granted after the test report.

## Execution record

Tasks1–4 complete: red/green regressions;147 MATLAB tests across all24 allowlisted classes plus3 scripts pass;85 Python tests plus7 supplementary harness tests pass; all5 firmware native suites pass. Review also found and corrected Cartesian saved-analysis consistency in GUI, export and standalone viewer.

Task5 executed to first real motion fault: VNA9/9 stationary sweeps, real async STOP4.329s,30 valid held paired encoder snapshots and small Pan/Tilt moves passed. Panfull-turn attempt aborted at330 with11/13 RF points preserved due to firmware Tilt validity0. No3D or further motion after fault. Post-fault stationary diagnosis confirms Pan160/160, Tilt0/160; motors released. Physical sensor inspection is required before completing hardware acceptance. See docs/acceptance-fixes-2026-10-23.md and raw validation folders. User subsequently requested committing and pushing the verified corrections; raw measurements and machine logs remain outside source commits.
