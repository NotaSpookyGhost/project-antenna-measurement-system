# Pan/Tilt hold and manual homing — 2026-10-11

**Historical report, superseded by v3.1.** The temporary release described below was a defect, not continuous hold. See `continuous-hold-fix-2026-10-11.md` for the replacement and current evidence. Do not use the cached-encoder procedure below for new measurements.

The handover v3 firmware disabled the TMC2209 drivers after each move. The new PlatformIO derivative at `firmware/positioner_v3_hold/` holds both drivers enabled while MATLAB has an active connection. The **Nhả motor** GUI action disables both so the operator can align by hand. **Khóa + ZERO** reads both AS5600 encoders while the drivers are disabled, zeros both logical axes, and then enables both drivers. `HOLD OFF` on disconnect releases them. On boot/reset the drivers are disabled. A 30-second host-command lease releases both and marks calibration required if MATLAB disappears without disconnecting.

The earlier energized-driver experiment caused both AS5600 I²C buses to time out. This derivative samples the sensors only while the drivers are disabled, then re-enables the hold. `POS` reports `SENSOR_CACHED:1` when held; the encoder values in that state are last sampled values, not live feedback. Movement temporarily disables the drivers after pulses for the sensor read, then restores holding. An interrupted move sets `CAL_REQUIRED:1`, so a new manual ZERO is needed. STOP is checked every ten pulses. The real COM5 short-motion test confirmed interruption at 0.8° during a 5° Pan command; exact stop latency was not measured.

Validation:

- `g++` native simulation: hold/release, manual ZERO, move, STOP, I²C while held, and 30-second lease passed.
- PlatformIO ESP32 build and COM5 upload passed, including esptool hash verification.
- A 4,194,304-byte flash backup was captured before upload at `C:\Users\Spooky Laptop\Documents\ChatGPT\esp32-pre-hold-20261011.bin`.
- Real COM5 serial smoke test passed: `POS`, `HOLD ON`, `PING`, `CAL RELEASE`, `LOCK ZERO`, `HOLD OFF`; after 31 seconds without a host command, `POS` reported `HOLD:0 CAL_REQUIRED:1` and the lease-expired warning.
- Real MATLAB COM5 integration passed for connect, release, lock/zero, disconnect, and a 1° Pan move out and back with holding active after both moves. Mock MATLAB manual-homing/scan/STOP and parser tests passed.
- Real COM5 mid-move STOP passed: `PAN 5`, then STOP after 80 ms, reported `ABORTED PAN:0.80`, kept holding active, and required recalibration. The test then sent `HOLD OFF`.

The serial tests confirm firmware state and logical behavior, but do not measure torque or temperature. Check actual holding force and driver heating at the intended load before unattended long scans. The motor-tail encoder cannot report movement while holding is active because its last reading is cached during that state.
