# ESP32 antenna positioner firmware

This PlatformIO project targets the ESP32 DevKit V1 on COM9. The pin map,
1/8 microstepping and 16:90 pulley ratio come from `CODEX_HANDOVER/AGENTS.md`.
It supersedes the diagnostic-only `CODEX_HANDOVER/firmware/test_as5600.ino`
for motion control.

## Build and upload

```powershell
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner
& 'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe' run -d firmware/positioner -t upload
```

Serial runs at 115200 baud with newline-terminated commands. `ZERO` makes the
current mechanical position the 0° reference. `POS` reports commanded antenna
angles, raw AS5600 values, magnet detection, and encoder angles. `PAN <deg>`,
`TILT <deg>`, and `GOTO <pan> <tilt>` move to absolute angles; `STOP` aborts
between motion chunks. Both axes are limited to 0–360° from the local `ZERO`.
Positive pan is counterclockwise when viewed from above on the installed wiring.

Tilt stays energized after a move to hold the load. `STOP` stops motion but
keeps tilt holding; `RELEASE` deenergizes tilt after it has returned to a safe
position. Encoder motion is checked both per chunk and cumulatively from `ZERO`.
On an encoder fault, the affected driver is released. `JOG TILT -5` or
`JOG PAN -5` is a recovery command limited to 5° per call; it invalidates the
absolute reference, so use `ZERO` afterward.
`HOLD PAN` and `HOLD TILT` energize one driver for a 90-second stationary
electrical diagnostic without STEP pulses. They release automatically or
immediately with `RELEASE PAN` and `RELEASE`, respectively. `LINES` reports
the idle logic levels of pan/tilt SDA and SCL and both EN states without
making an I²C transaction.

As of 2026-10-11, enabling either driver makes both AS5600 buses stop
responding. The actual hardware uses a 20 V-fed 3.3 V regulator to power
both AS5600s and both TMC2209 VIO inputs; ESP32 has separate USB power and
shares GND. Keep MATLAB tilt scans locked until the electrical fault in
`docs/hardware-validation-2026-10-11.md` is corrected and the staged test
passes. The 90° probe script is for validation after that repair.

Each axis uses at most 125 microsteps (5° antenna angle) before stopping STEP
pulses and checking its AS5600. A missing magnet, I2C failure or encoder
mismatch disables that driver, reports `ERR:`, and requires another `ZERO`
before motion. Both drivers are disabled at startup. Pan is disabled between
chunks; tilt stays enabled during a move to hold the load.

`GOTO` moves pan then tilt. Check physical direction and cable clearance before
a large scan. `ZERO` is a reference setting, not a limit-switch homing routine.
The controller cannot measure the 20 V motor supply; verify VM and common GND
on the hardware before commanding motion.
