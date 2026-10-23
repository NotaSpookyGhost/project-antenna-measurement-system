# Codex setup for antenna-v3

## Acceptance corrections — 2026-10-23

Pole aggregation, circular/sector SLL and plot annotation consistency, and
transport-loss propagation through cancellation are corrected. See
`docs/acceptance-fixes-2026-10-23.md` for red/green evidence, complete test
coverage and separate real-device results. Cancelled VNA jobs may retain an
error even though late raw data is discarded; consume transport loss
independently of terminal cancellation state.

## Live plot callback recovery — 2026-10-22

The scan status bar now has a persistent **Lỗi live plot** menu with three
policies: continue measurement with live rendering disabled, retry once at the
next point then disable, or abort while retaining completed points. The
default is continue-and-disable. The selection is stored with `scan3DConfig`
in `antenna-ver2-settings.mat`.

A callback failure is a visualization fault, not an RF measurement fault.
Policies `CONTINUE` and `RETRY_ONCE` keep acquiring data; `ABORT` records
`LivePlotCallbackFailure` with the original callback error. Unexpected
non-callback scan faults now normalize active state to `ERROR`.

Live plots reuse line/scatter handles. The 3D surface is recomputed only when a
Pan row completes, and `ScanGeometry.surface()` uses vectorized binning. VNA
transport failures use the stable `TRANSPORT` job code, mark the controller
offline and invalidate calibration. Python unit-test artifacts default to a
temporary directory unless `ANTENNA_VALIDATION_DIR` is set explicitly.
Local warm benchmarks after the change were about0.0245s per calibration
application and0.0129s per full37x73 surface (previously about0.2646s and
0.0499s respectively).

## Motor encoder journal —2026-10-17

Hardware-positioner scans now append durable JSONL under data/logs/motor,
including when RF is Mock. Move attempts/results/faults retain both cached
encoders, raw POS, HOLD, release count, fixed manual ZERO and scan point/row.
The app reports estimated closure error on completed Pan0 targets, warning
above1 antenna degree without automatic ZERO, correction, or changed stops.
Explicit home/Lock+ZERO captures the reference; observed releases and counter
discontinuities invalidate it. A new scan never silently rebases it.
Mock-only tests opt in with MotorLogDirectory pointing to a temp folder;
legacy Mock encoder scale1 is labelled separately from hardware5.625.
See `docs/motor-encoder-journal-user-guide.md` and the motor-journal plan/evidence.

## Full180-degree Tilt setup —2026-10-17

Motor Tilt+90..−90 requires polar theta90 at a horizontal mechanical ZERO.
Polar theta0 declares an upward ZERO and correctly rejects negative theta.
The3D/ZERO form now labels this explicitly, offers a horizontal-ZERO preset
for the pending form only, and explains valid ranges in Vietnamese. Travel
and firmware guards remain; no automatic homing, confirmation or motion.
The requested5-degree grid has37Tilt rows ×73Pan samples =2701 points.
See `docs/tilt-180-configuration-2026-10-17.md` for verification and limits.

## VNA refresh and launcher — 2026-10-16

Use `Open Antenna App.vbs` to start the interactive app with MATLAB minimized
(`-automation -r`), preserving dialogs. Console output is retained under
`data/logs/matlab_runtime_*.txt`; do not replace the interactive launcher with
`-batch`, which disables some interactive dialogs. Automated MATLAB checks
must launch in the background, retain logs and confirm their own exit code.

Black console popups were traced separately to MATLAB's repeated `pyinfo.py`
probes of the repo's console `python.exe`. `vnaPythonBackend` now prefers
`.venv-vna/Scripts/pythonw.exe` on Windows before Python loads. It uses the same
environment/packages and preserves an already-loaded Python session; restart
MATLAB to apply it to an old session. Two fresh Real COM6 app runs passed with
three frames each and no observed Python console hosts. Evidence and limitations
are in the console-startup section of the performance report below.

Repeated VNA jobs now reuse an unchanged actual grid and acquire after one
FIFO clear, without the old fixed cycle delays. Real COM6 backend steady
medians:11 points0.247s,51 points0.661s,101 points1.178s near2.4GHz/averages1.
The MATLAB101-point tab updated about1.3–1.4s in the measured steady portion;
first-use initialization/rendering remains slower. Complete coverage checks
and bounded transition reacquisition remain. See
`docs/vna-performance-2026-10-16.md` for measurements, scope and caveats.

## ESP32 connection/hold recheck — 2026-10-16

The connected CH340 ESP32 currently enumerates as COM9 (COM5 was absent).
Check enumeration after USB changes; do not assume the historical COM5 default.
After the user reconnected a loose wire, both motors physically held and8/8
stationary paired encoder samples were valid. The actual MATLAB app Hardware
connection then maintained HOLD for35s using its production keepalive timer,
with no release-count increase. Both tests ended released/disconnected; no
motion or ZERO. `CẦN ZERO` can coexist with active HOLD after a new connection.

The NaN feedback guard was fixed so invalid encoder telemetry cannot pass
the connection snapshot check; the GUI requires both finite encoders before
enabling Tilt. Selected49 MATLAB tests passed. See
`docs/esp32-connection-check-2026-10-16.md` for raw evidence and limits.

## VNA Workbench — 2026-10-15

The app now includes a VNA tab sharing the existing controller: Single/Continuous/STOP,
Smith/LogMag/Phase/VSWR, SOL and forward SOLT T/R enhanced-response calibration,
self-contained .vnacal.json profiles and explicit RAW/SOL/TR scan policy. Raw S11/S21
remain separate from corrected arrays. Software and hardware qualification are tracked
separately in docs/vna-workbench-implementation-log.md; do not infer real RF accuracy
from Mock results. User workflow: docs/vna-workbench-user-guide.md.

Dependencies live in .venv-vna (scikit-rf2.1.0, pyserial3.5). The helper selects it
before Python loads; an already-loaded environment is checked rather than terminated.
This MATLAB installation warns about Python3.13 support; retain the warning and check
the actual verification log. RAW/Mock does not import the calibration engine.

Software gate, from repository root (no COM/motion):

```powershell
& ./.venv-vna/Scripts/python.exe -X utf8 -m unittest discover -s python/tests -p 'test_*.py' -v
matlab -batch "addpath('matlab/classes','matlab/app','matlab/tests','matlab/tests/fixtures'); run_vna_software_tests"
```

The allowlist runner includes selected legacy classes and three Mock scripts; it never
runs the hardware-capable master runner. Mock GUI evidence can be regenerated with
create_vna_workbench_mock_demo(outputDir) from matlab/tests. Stationary hardware
qualification is described in docs/vna-workbench-hardware-qualification.md and remains
NOT_RUN until there is operator evidence. Positioner safety guards remain mandatory.

## Adjustable acceleration on COM5 — 2026-10-15

The MATLAB GUI now offers **Gia tốc...** to set Pan/Tilt ramp lengths while
idle. Default values remain Pan 150 and Tilt 100 steps; lower values
accelerate faster, bounded to Pan 100..600 and Tilt 75..300. Five native
tests, 39 selected MATLAB mock tests, and the PlatformIO release build
passed. The firmware was uploaded to COM5; esptool verified the flash
hashes, and a no-motion serial probe confirmed capability, bounds and
setting changes. The GUI was reopened in Mock mode. Reconnect ESP32 and
manually set the mechanical ZERO before scanning. See
`docs/motor-ramp-control-2026-10-15.md` for timing estimates and usage.

## Latest Pan result after wire repair — 2026-10-14, about 23:05 onward

The user repaired a broken Pan motor conductor in the A1/A2 pair. With the
same slow-Pan firmware and unchanged encoder guards, Pan passed 21 positions
through 0..+90..0, with 210/210 valid paired snapshots and uninterrupted
commanded hold. Maximum encoder-derived output error was 0.218667 degrees;
Pan closure was −0.09 motor degrees (0.016 output degrees in magnitude).
The user confirmed smooth movement and return to the physical mark. Both
encoders also passed the stationary 30/100/30 test. Drivers were released
and COM5 closed afterward; recalibrate ZERO before measurement. This run
did not move Tilt or perform a complete 3D RF scan. See
`docs/pan-wire-repair-validation-2026-10-14.md` and
`data/validation/pan_wire_repair_20261014_230557/`. Earlier Pan failures below
predate the physical wire repair.

## Latest Pan slow trial — 2026-10-14 evening

COM5 now runs the Pan-only slow profile:5000/9000 us and ramp150;
standalone Tilt keeps2200/5000 us and ramp100. MATLAB has axis-specific
move timeouts. Firmware banner remains V4.0_HOLD; hashes identify the build.
Software verification passed (4 native suites,60 MATLAB mock tests,39 Python
tests, release build and verified upload). Both encoders passed160/160
stationary samples, but Pan5 and the user's subsequent visible Pan30 trial
still failed the unchanged encoder guard. Pan30 changed only7.21 motor
degrees by before/after sample medians versus168.75 expected. No Pan90 or
conditional Tilt90 trial followed. The motor drivers were released and COM5
closed. This change does not qualify real3D or confirm stall as the cause.
See `docs/pan-slow-validation-2026-10-14.md` and
`data/validation/pan_slow_20261014_2203/` for results and full flash backup.

## Current Tilt transport: I2C only — 2026-10-14

After the user shortened the Tilt cable to 1 m and removed the external
2.5 kohm SDA pull-up, I2C and PWM both passed stationary 30/100/30 reads.
Real MATLAB Tilt then passed 33 positions through 0..+90..0..-90..0,
330/330 fresh snapshots, continuous hold, motor-tail closure -0.17 deg.
The user declared this travel safe from the present test pose. Physical
output angle and RF/3D accuracy were not independently measured.

The main firmware now uses I2C for both axes (`FW:V4.0_HOLD`); the optional
PWM implementation/environment/scripts have been removed after these tests.
Build/upload the default `esp32doit-devkit-v1` environment. GPIO23/OUT is
unneeded. Retired `TILT PWM ...` commands are rejected without movement.
Read `docs/tilt-i2c-validation-2026-10-14.md` for raw evidence, wiring and
the archived PWM trial. Recalibrate manually after reset/release and confirm
travel again if the physical ZERO changes. `ver1/` remains frozen.

## Historical Tilt PWM trial — 2026-10-14 (retired)

The following describes the archived trial at commit `799e252`; its
`tilt-pwm` environment and hardware script do not exist in the current
production firmware. See the current I2C section above.

An explicit `tilt-pwm` PlatformIO environment uses GPIO23 / AS5600 OUT at
230 Hz for Tilt (`FW:V4.1_PWM_HOLD`). The default environment retains I2C.
Read `docs/tilt-pwm-setup.md` before wiring/uploading. Temporary CONF setup
still requires reliable SDA21/SCL22 at boot/after sensor power cycling;
there is no OTP/BURN command. PWM POS has fresh angle/validity fields and
`AGC_TILT_AVAILABLE:0`; the AGC=255 placeholder is not a magnetic measurement.
Native timing/configuration/hold tests and MATLAB compatibility tests passed,
and this environment has been uploaded to COM5. The no-motion loaded probe
confirmed `FW:V4.1_PWM_HOLD`, `PWM_CONFIG:1`, driver HOLD:0 and GPIO23.
The first probe had no OUT edges. After the user wired OUT and retained
SDA/SCL, a nondefault sensor range was observed (ZPOS0A48/MPOS0A47). The trial
now normalizes only VOLATILE range registers before CONF, preserving reserved
bits, OTP and mechanical ZERO. Actual stationary acceptance passed 30/30
released +100/100 held +30/30 released, and a subsequent COM5 reopen still
read valid PWM. Pulse period4274..4276 us; within-phase motor-angle span
0.26/0.27/0.35 degrees. No STEP commands. Physical Tilt travel/accuracy and
full3D scans remain unverified. See `docs/tilt-pwm-validation-2026-10-14.md`.
Build/upload/probe evidence:
`data/validation/tilt_pwm_build_20261014_134043/`.

```powershell
python -X utf8 firmware/positioner_v3_hold/test/hardware_pwm.py --port COM5 --configure
```

This is hardware-capable: holds/releases drivers, reads 30/100/30 samples,
but never issues STEP/GOTO/ZERO or accesses the VNA.

## Ver2 Pan × Tilt 3D — 2026-10-13

Implementation is on `codex/ver2-pan-tilt-3d`; `ver1/` remains the frozen baseline.
See `docs/ver2-pan-tilt-3d.md` for independent axis grids, geometric ZERO offsets,
declared travel, sequential/alternating rows, slice selection and dataset export.
Firmware V4.0_HOLD has now been uploaded to COM5 and tested with the real
SAA-2N on COM6. Pan 0..360 / 10 completed 37/37 valid-encoder RF points;
the user observed return to the physical mark. Idle STOP/restart was reproduced
and repaired. The original Tilt check failed; subsequent sensor and wiring
changes are recorded below. See `docs/ver2-hardware-validation-2026-10-14.md`.

Later on 2026-10-14, the user replaced the Tilt AS5600. It now responds:
40/40 released POS reads and 98/100 holding POS reads in the final check, with
earlier failures and raw I2C NACKs under driver hold. It is still intermittent,
so real 3D remains unqualified. Diagnostic firmware was temporary; production
V4.0_HOLD is restored. See `docs/as5600-tilt-new-sensor-2026-10-14.md`.

After separating motor and sensor cables, the user added a 2.5 kΩ pull-up to
Tilt SDA. A no-motion COM5 retest read Tilt 30/30 with drivers released,
218/300 while holding, and 30/30 after release (Pan 360/360). Tilt AGC
remained at 128 for valid samples. Real 3D is still unqualified; investigate
magnet alignment and sensor-side 3.3 V/GND under hold. Raw log and summary:
`data/validation/tilt_pullup_20261014/`.

After the user further separated cable bundles and reconnected COM5 (without
changing J3 electrical connections), a final no-motion
retest returned Tilt 0/30 released, 95/300 holding, 0/30 released; Pan stayed
360/360. Raw Tilt values during hold also spanned almost the full 0..360°.
Real Tilt/3D remains unqualified until J3 wiring and sensor-side power are
verified. See `data/validation/tilt_extra_wires_removed_20261014/`.

Software-only regression (both new and selected legacy tests; no serial ports):

```powershell
matlab -batch "addpath('matlab/classes','matlab/app','matlab/tests/fixtures'); set(groot,'DefaultFigureVisible','off'); r=runtests({'matlab/tests/TestScanGeometry.m','matlab/tests/TestPositionerLimits.m','matlab/tests/TestScan3D.m','matlab/tests/TestScan3DData.m','matlab/tests/TestScan3DGUI.m','matlab/tests/TestPositionerResponse.m','matlab/tests/TestManualHoming.m','matlab/tests/TestScanStopGUI.m'}); assertSuccess(r)"
python -X utf8 -m unittest discover -s python/tests -p 'test_*.py'
```

Mock preview with a coarse 91-point spherical grid (no COM access):

```matlab
addpath('matlab/tests');
create_ver2_mock_demo(fullfile(tempdir,'antenna-ver2-demo'));
```

The GUI defaults to Mock for both instruments. Geometric offsets are saved without
motion and never automatically recalibrate the physical ZERO. Real 3D scanning
requires both valid encoders and travel confirmed for the current ZERO.

Explicit hardware regression (captures a test ZERO at the current pose, moves
Pan 0..10 and returns; no Tilt movement):

```matlab
addpath('matlab/tests');
test_real_idle_stop_restart('COM5',fullfile(tempdir,'idle-stop-real'),'Real');
```

This uses COM6 for real RF. Omit the third argument for Mock RF + real Pan.
`test_real_3d_encoder_gate` is an explicit hardware negative test: its fixture
prohibits all motion even if a previously missing encoder recovers. Neither
hardware test is included in the ordinary mock suite.

## Historical v3.2 firmware and AS5600 validation — 2026-10-13

COM5 ran **v3.2** from `firmware/positioner_v3_hold/` during these historical tests; it now runs V4.0_HOLD. See `docs/as5600-fix-2026-10-13.md`. Pan passed 100/100 stationary feedback reads and the real 0–360° / 10° scan with valid encoder feedback at all 37 points, continuous hold, and a second scan using the same ZERO. Tilt remained intermittent with its driver enabled; the later 2.5 kΩ pull-up test is recorded above. Verify the electrical link before claiming Tilt is repaired.

Firmware uses bounded GPIO I2C transactions on dedicated AS5600 buses, three fresh agreeing samples, packet/magnet checks and bus recovery. SDA stays open drain; driven SCL is specific to AS5600's input-only, non-stretching clock. Readings never reuse a previous POS cache. MATLAB now blocks a scan without valid feedback from the selected axis and stops on feedback loss, preserving completed points and holding torque. It does not continue a successful scan on step counts alone. The v3.1 worker described below is superseded.

The ordinary selected MATLAB regression suite is `TestPositionerResponse`, `TestManualHoming`, and `TestScanStopGUI` (24 tests as of this update). The stationary **hardware-capable** check is `python -X utf8 firmware/positioner_v3_hold/test/hardware_encoder.py`; it enables/releases both drivers and requires both encoders valid 100/100 times. `--axis pan` only checks Pan. The **hardware-capable** `test_real_continuous_hold('COM5')` moves Pan through a full turn and back and requires valid Pan feedback at every measured point. Neither test measures the antenna table's physical zero independently.

## Historical v3.1 hold and manual homing — 2026-10-11 (superseded)

The current COM5 ESP32 has v3.1 from `firmware/positioner_v3_hold/` loaded. Both drivers stay enabled throughout movements, settling, STOP and sensor queries. It releases both on disconnect or **Nhả motor**, or after 30 seconds without a host signal. The previous flash is backed up at `C:\Users\Spooky Laptop\Documents\ChatGPT\esp32-pre-hold-20261011.bin`. See `docs/continuous-hold-fix-2026-10-11.md` for the latest validation; the earlier hold report describes a superseded implementation.

To establish a physical reference: select **ESP32 (thật)** / COM5 → **Connect** → **Nhả motor** → align both axes by hand → **Khóa + ZERO**. Scans now preserve that reference and move to Start relative to it; they never automatically send ZERO. An interrupted movement requires manual calibration again. Disconnect/closing the GUI releases both drivers. Repeat calibration after reset or release. AS5600 readings are fresh or explicitly unavailable (NaN), never stale held snapshots. With missing feedback the scan uses step-count angles and reports that physical position is unverified. I2C runs on a separate worker; each POS waits at most 200 ms for a matching snapshot, so a stuck sensor cannot block the command loop. This does not repair physical I2C interference.

Build/upload with PlatformIO from the repository root:

```powershell
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner_v3_hold
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner_v3_hold -t upload
```

Close MATLAB, the GUI, and Serial Monitor before uploading. Upload resets the ESP32 and releases the motors. The no-motion hardware probe is `python -X utf8 firmware/positioner_v3_hold/test/hardware_smoke.py`; it deliberately checks the 30-second lease expiry. The original handover v3 sketch remains in `CODEX_HANDOVER/contex ver2/firmware/firmware_positioner_v3.ino` for comparison.

## Latest positioner integration — 2026-10-11, about 14:12

The new `CODEX_HANDOVER/contex ver2` package contains the later v2/v3 hardware reports. The connected CH340 positioner is now COM5. MATLAB now accepts the handover v3 POS format (RAW is already in motor degrees) and the legacy degree-valued text format. The GUI defaults to COM5 and permits Tilt after identifying v3 with an available Tilt encoder. MATLAB rejects Tilt requests outside the v3 firmware range -5° to 95° before sending motion. Direct controller users retain the explicit `TiltDisabled` constructor option. Real MATLAB Pan 10° / Tilt 5° moves and return-to-zero, plus GUI connection callbacks, passed on COM5. The user's accepted measurement model is a motor-tail encoder with the 90:16 transmission; motor-side angle errors are divided by 5.625 when expressed at the antenna shaft. This does not change the existing encoder loss/mismatch checks. The workspace firmware is a different implementation that holds tilt energized; the repaired MATLAB connection uses the existing device v3 without flashing it. See `docs/positioner-v3-recheck-2026-10-11.md` for evidence and limits. The COM9 conventions below describe the earlier setup.

## Local environment verified on 2026-10-11

- Workspace: `C:\Users\Spooky Laptop\Documents\ChatGPT\antennamatlab` (Git `main`, imported from the Antigravity `antenna-v3` checkout).
- MATLAB R2025b is available through `matlab.exe` on `PATH`.
- Python 3.13.13 with `pyserial` 3.5 is available. MATLAB `pyenv` resolves to the same Python installation in `OutOfProcess` mode.
- The existing MATLAB MCP executable is registered as the global Codex server `matlab`, and the installed serial MCP command is registered as `serial`. Confirm with `codex mcp get matlab` and `codex mcp get serial`. A new Codex session may be needed before their tools appear in the active tool list. MATLAB CLI commands below work independently of MCP.
- The local `matlab-control` skill from the Antigravity project was copied into Codex's user skills directory. A new session may be needed for skill discovery.

## Run the application

On Windows, double-click **Open Antenna App.vbs** in the repository root.
It opens the antenna GUI without the MATLAB desktop or a command window,
using installed MATLAB R2025b (or `matlab.exe` on `PATH`). Closing the GUI
exits that MATLAB session. Both instruments start in Mock mode; use the GUI
to select and connect real hardware. MATLAB must remain installed and licensed.
You can create a Windows shortcut to this file for access from the Desktop.

From the repository root in MATLAB:

```matlab
addpath('matlab/classes', 'matlab/app');
app = AntennaMeasurementApp();
```

Load both paths before constructing the app: its typed controller properties require the classes to be resolvable before the constructor runs. Select mock modes in the app when developing without physical devices. For real motor control on the current v3 device, select Positioner Hardware and COM5, then Connect. VNA can remain Mock for a motor-only scan; select Real and COM6 for physical RF acquisition.

The Positioner dropdown defaults to **Mock (2 trục)**. Its connected lamp now says **MÔ PHỎNG**, and ZERO/release logs explicitly say no physical motor is controlled. A COM5 value in the port edit box does not imply a hardware connection. Select **ESP32 (thật)** before connecting to control the real drivers.

## Verify software without a hardware test

From the repository root in PowerShell:

```powershell
matlab -batch "addpath('matlab/classes'); results=runtests({'matlab/tests/TestPositionerResponse.m','matlab/tests/TestScanStopGUI.m'}); assertSuccess(results); run('matlab/tests/test_pattern_analyzer.m'); run('matlab/tests/test_orchestrator_mock.m'); run('matlab/tests/test_scan_direction_and_abort.m')"
python -X utf8 -m unittest discover -s python/tests -p 'test_*.py'
```

These MATLAB tests passed during setup. The GUI test `matlab/tests/test_app_gui.m` also passed locally, but it attempted to connect to COM9 before proceeding. The Python empirical challenge suite should be run separately from hardware scripts.

`matlab/run_all_matlab_tests.m` auto includes an ESP32 hardware test when COM9 is available, and includes a semi hardware VNA test. `python/test_saa2n.py` directly opens a serial port. Run those only when the hardware procedure calls for them. The handover plan's claim that `python/test_saa2n.py` is a mock test is incorrect.

For an intentional small v3 hardware test on COM5 (both axes move), use `matlab -batch "addpath('matlab/tests'); test_real_positioner_v3('COM5');"`. It checks Pan 10° / Tilt 5°, returns to the local zero, and checks the actual GUI connect callbacks. It is separate from the automatic master runner.

## Current test baseline

The Python suite passes 39 tests with `python -X utf8 -m unittest discover -s python/tests -p 'test_*.py'`. The UTF-8 flag avoids PowerShell's legacy `cp1252` output encoding on Unicode test logs. After the v3 MATLAB repair, all eight protocol tests and all five master-runner groups pass, including GUI and real VNA with mock motor. The explicit COM5 v3 small hardware test also passes on both axes and checks the GUI connection. Earlier real pan and three-point COM6 + COM9 tests are recorded in `docs/hardware-validation-2026-10-11.md`; later v3 results are in `docs/positioner-v3-recheck-2026-10-11.md`.

## Hardware conventions from the handover

- NanoVNA SAA-2N: nominal COM6.
- ESP32 positioner: currently COM5 at 115200 baud (earlier COM9).
- Earlier device v3 source: `CODEX_HANDOVER/contex ver2/firmware/firmware_positioner_v3.ino`. The active hold-capable derivative is `firmware/positioner_v3_hold/`.
- Earlier workspace firmware: `firmware/positioner/` (PlatformIO), a different implementation with encoder guards and energized Tilt hold. Its upload command is `C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe run -d firmware/positioner -t upload`; uploading it replaces the v3 behavior. Its configuration still names the earlier COM9.
- The original 4 MB ESP32 flash is backed up at `C:\Users\Spooky Laptop\Documents\ChatGPT\esp32-original-20261011.bin`.
- Positive pan is counterclockwise viewed from above. Both axes have 360° mechanical travel according to the user; firmware accepts 0–360° relative to `ZERO`.
- The GUI enables Tilt for the verified handover v3 with an available encoder. Keep `TiltDisabled=true` when using the earlier energized-hold workspace firmware: that mode caused both I²C buses to time out. Do not transfer the hold-mode fault conclusion to v3, which reads encoders with EN released.
- Confirm the actual port and calibration state before physical measurement. The ports are project defaults, not proof that hardware is connected.

## Handover references

- `INSTRUCTIONS_FOR_CODEX.md` — code map and original handover notes.
- `plans/2026-10-11-codex-handover-plan.md` — Antigravity's proposed phases and roadmap.
- `docs/automatic-antenna-measurement-system-master-v4.md` — system requirements and measurement background.
- `matlab/README.md` — MATLAB subsystem usage.
