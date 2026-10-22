# VNA log diagnosis and fixes — 2026-10-16

Input: `data/logs/system_log_20261016_003940.txt`, saved00:39:40 Asia/Bangkok. The log was preserved. No MATLAB upgrade was used for these fixes.

## What the log establishes

| Log lines | Meaning | Assessment |
|---|---|---|
| 4–6 | COM9 connection, both finite encoders, LOCK ZERO acknowledged | No connection/NaN failure shown in this session |
| 11–18 | Scan started, user paused, then STOP;10 of181 points retained | Expected partial-scan behavior; Pause continues to own the VNA |
| 19–33 | Repeated invalid FIFO batches, duplicate old indices and missing new indices | Driver/acquisition transition defect; not a calibration or operator error |
| 28,41 | BUSY while another acquisition was pending | Expected ownership guard; wait or STOP before another operation |
| 35–36 | Request validation rejected an input | Invalid request, but the log does not record entered values, so the particular field cannot be identified |
| 39,42 | MATLAB:catenate:dimensionMismatch during VNA acquisition/display | App rendering defect, not evidence that MATLAB itself requires replacement |

## Reproduced and corrected

### FIFO transition and wire framing

With the app closed, the original code was tested on the real COM6 VNA:11 points succeeded, changing to101 points produced duplicate0..10 sequences followed by only part of the new grid. Register readback confirmed the requested101 points and100kHz step. The reproduction is retained in the local hardware-before transcript.

The bridge now rejects the entire transitional batch and performs at most one fresh whole-sweep acquisition under a shared12s budget. It never merges/deduplicates samples from different sweeps. Persistent invalid coverage remains an error. Partial-byte transport failures close the connection instead of allowing a pending FIFO reply to mix with a new command.

The driver also now sends the documented one-byte READFIFO count and splits larger requests into chunks of at most255 records. The old16-bit count could not correctly request the supported401-point UI range. References: [NanoRFE USB protocol](https://www.nanorfe.com/nanovna-v2-user-manual.html), [DiSlord command parser](https://github.com/DiSlord/NanoVNA-V2-firmware/blob/master/command_parser.cpp). This is a targeted change to the old driver; earlier reports that the wire driver was unchanged describe the previous implementation milestone.

An initial2s retry eligibility limit repaired101-point tests but rejected the slower401-point transition. It was replaced with the shared12s budget; final7/7 real job cases passed, including401 points across50kHz..3GHz in9.714s. This is acquisition coverage, not calibrated RF accuracy.

### Multiline metrics rendering

For raw S11 with magnitude above1, the workbench appended warning text to the graphics control's `String` property after setting multiline content. MATLAB can return that property as multiple rows/cells, causing the concatenation failure. The warning is now appended to a local character vector before assigning `String` once. A regression fixture explicitly supplies magnitude1.1 and verifies the warning is visible, acquisition completes and ownership is released.

The first regression attempt used the legacy Mock model over the full3GHz span; that model overflowed before reaching the rendering path. The fixture was corrected to provide finite valid raw data with magnitude above1. The corrected test reproduced the actual multiline failure before the production fix.

## Verification

- Python final full fake-device/unit suite: **73/73 PASS**, exit0.
- MATLAB workbench/plotter/request tests: **9/9 PASS**, exit0.
- Real COM6 asynchronous jobs: **7/7 PASS**:11→101→101→90 points near2.4GHz,101 and401 points across50kHz..3GHz, then11 near2.4GHz again. Data coverage/grid verified; no RF accuracy claim.
- Local RED/GREEN command output: `.superpowers/sdd/vna-log-2026-10-16/`.
- The actual MATLAB app then measured and rendered both101-point2.4GHz and401-point50kHz..3GHz traces: **2/2 PASS**, no dimension mismatch; the VNA was disconnected. [Persistent hardware/UI evidence](verification/vna-log-2026-10-16/real-ui-final.txt), [job coverage](verification/vna-log-2026-10-16/hardware-jobs-after.json), [original reproduction](verification/vna-log-2026-10-16/hardware-before.txt).
- No ESP32 connection, motion, ZERO, firmware upload or calibration-standard change was required for these VNA tests. Test connections are closed afterward.

## Operating sequence

1. Reopen MATLAB/app so the edited MATLAB classes and Python bridge load fresh.
2. Connect VNA Real COM6; use Start2395MHz, Stop2405MHz, Points101, Averages1; Correction off for the initial raw check.
3. Press Single once and wait for completion. Stop a scan completely before using standalone VNA; Pause retains its VNA ownership.

Request limits: Start/Stop0.05..3000MHz, Stop greater than Start,2..401 integer points,1..16 integer averages, at least1Hz step. These are input limits, not a requirement to calibrate before RAW measurement.
