# VNA update rate and quiet startup — 2026-10-16

User reports: multiple windows during Real VNA use, and slower updates than the device display. The user subsequently confirmed the windows were black consoles, not MATLAB Command Windows. Work was measured on the existing COM6 VNA; no motor connection/motion/ZERO.

## Baseline and bottlenecks

Four101-point2.395–2.405GHz job timings before optimization:3.308,1.994,3.497,2.000s. Profiling showed every job rewrote the same sweep registers; some reconfigurations produced transitional FIFO data and required a whole-sweep retry. Every acquisition also imposed0.8s of fixed sleeps before/during double-clearing, in addition to actual acquisition time.

## Changes kept after measurement

1. The job configuration adapter skips device writes when the actual integer-Hz grid and values-per-frequency are unchanged. The cache is owned by the connected driver, includes start/step/points/values-per-frequency, and is invalidated on connect/disconnect and before programming a new configuration. A failed partial configuration cannot leave a reusable cache entry. Changing averaging alone does not restart the RF sweep.
2. Acquisition retains settling, clears stale FIFO once, and lets READFIFO wait for a complete fresh batch. Removed fixed0.3s/0.2s cycle waits and the second clear. The bridge still requires exactly one of every index, keeps complex samples paired, and rejects persistent invalid batches. It does not publish partial/merged traces. Whole-batch transition retry and its shared12s budget remain.

The clear-before-reading rule follows the [NanoRFE USB interface](https://www.nanorfe.com/nanovna-v2-user-manual.html). These tests establish transport/grid coverage; they do not establish calibrated RF accuracy or replace physical standard validation.

## Results

Same device/band, averages1, four jobs per case. Steady values below are medians of the final three jobs; first-use startup is excluded explicitly.

|101-point backend case | Steady median |
|---|---|
| Baseline |2.000s |
| Cache only |1.590s |
| Cache + single clear |1.178s |

Final baseline-to-optimized reduction is about41% for this small controlled sample. Some original reconfiguration/retry cases were3.3–3.5s. Both changes exceeded the measured steady variability and were retained. A temporary monkeypatch experiment was measured before changing production acquisition; it independently gave1.179s and is retained in the ignored local evidence directory.

| Final backend points | Steady median | Approximate sweeps/s |
|---|---|---|
|11 |0.247s |4.05 |
|51 |0.661s |1.51 |
|101 |1.178s |0.85 |

These are backend rates, not promises of identical GUI refresh rates. The actual MATLAB VNA tab delivered four101-point Real frames with intervals0.629,1.320,1.404s; the initial frame took14.438s in that fresh interactive process, including first-use initialization/rendering. The short first interval can reflect an already-running next acquisition; use the last two intervals for the steady UI observation. STOP drained in0.968s in that run. VNA disconnected afterward.

About0.97s of a steady101-point backend acquisition was spent waiting for the FIFO response; removing MATLAB drawing alone cannot remove that measured transport/device time. Lower points trade frequency resolution for refresh rate. Changing a calibrated grid requires a matching profile; the app does not silently reduce points.

## Command Window handling

The product launcher previously used `-nosplash -nodesktop -r`. It now uses the supported `-automation -r` mode, retaining interactive dialogs and starting MATLAB minimized. `WScript.Shell.Run` still uses hidden window style0. Console output is retained in `data/logs/matlab_runtime_YYYYMMDD_HHMMSS.txt` through `-logfile`. This mitigates Command Window focus/popups; it is not a compiled standalone executable or a guarantee that MATLAB creates no supporting windows/processes.

Verification used the same interactive startup mode, checked `~batchStartupOptionUsed`, created the app, connected Real VNA, ran Continuous/STOP and selected MATLAB tests, then exited0. Automation was launched via PowerShell `Start-Process -WindowStyle Hidden` with `-wait`. Future automated checks use background launch rather than repeated visible MATLAB startups. No existing user MATLAB process was closed or hidden.

Reference: installed MATLAB R2025b `matlab.exe -h`, and [MathWorks Windows startup documentation](https://www.mathworks.com/help/matlab/ref/matlabwindows.html). `-batch` was deliberately not used for the interactive product launcher because it disables some interactive dialogs.

The launcher change above addresses MATLAB startup only. It did not identify or fix the subsequently confirmed black consoles. Chromium helper counts are not evidence of visible windows.

### Black console startup: diagnosis and fix

A fresh isolated MATLAB process was observed while initializing the backend. MATLAB repeatedly launched the repo's `python.exe` with its installed `+python/+internal/pyinfo.py` script; those Python processes spawned `conhost.exe`. The initial import probe observed six such Python console hosts. Python audit hooks recorded no subprocess requests while importing the bridge and calibration modules after host startup. Separate Codex/MCP processes were also present, so their console processes were excluded from the MATLAB descendant evidence.

`vnaPythonBackend` now prefers `.venv-vna/Scripts/pythonw.exe` on Windows when it exists, retaining `python.exe` as fallback. The packages, virtual environment and OutOfProcess mode remain the same. Selection still happens only before Python loads; an existing loaded session is not terminated or replaced. This use of a windowless executable is consistent with the examples in the official [pyenv documentation](https://www.mathworks.com/help/matlab/ref/pyenv.html).

The startup regression first failed because the selected executable was `python.exe`, then passed with `pythonw.exe`; the same test also built/applied the SOL calibration engine. Two subsequent fresh interactive app processes each connected Real COM6, published three distinct11-point frames, stopped and disconnected, exiting0. Neither run observed a `python.exe` descendant or Python-owned console host. The positioner stayed disconnected. The hidden MATLAB launcher can have its own console host; it is counted separately from Python-created consoles.

Observation used process polling, so it can miss very brief processes and is not a screenshot-based guarantee about every visible window. During the first regression run after the change, the test and helper queried an old console-Python setting before selecting the new executable, so pre-selection consoles were still observed; subsequent fresh real-app runs used windowless Python throughout. Restart an old MATLAB session to apply the selector. Do not suppress unrelated windows or terminate unrelated processes.

Filtered process trees, before/after regression logs, two real-app logs and counts are preserved in `docs/verification/vna-performance-2026-10-16/console-startup/`. Full machine process inventories remain only in ignored diagnostic scratch. The existing Python3.13 compatibility warning is unchanged.

## Regression evidence

- Python full suite:76/76 PASS, exit0.
- Post-optimization real reconfiguration matrix:7/7 PASS, including401 points across50kHz..3GHz in4.554s, with all requested indices present. VNA disconnected afterward.
- Selected MATLAB workbench/controller/plotter tests passed in the interactive background verification, exit0.
- Deterministic performance guard: repeated same-grid jobs do not reconfigure; acquisition clears stale bytes, keeps full coverage, and avoids the old0.8s fixed-wait budget.
- Raw before/after timing and MATLAB frame data are preserved under `docs/verification/vna-performance-2026-10-16/`. Local experiment/run logs: `.superpowers/sdd/vna-performance-2026-10-16/`.
