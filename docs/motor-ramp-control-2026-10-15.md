# Adjustable motor acceleration — 2026-10-15

The MATLAB GUI now has a **Gia tốc...** control beside Settle Time. It sets
the Pan and Tilt ramp lengths together through the ESP32 `RAMP <pan> <tilt>`
command. Fewer ramp steps mean faster acceleration. The setting is allowed
only while the scan and motor are idle; firmware bounds are Pan 100..600 and
Tilt 75..300 steps. The firmware rejects a bad command without changing
either axis, and its `POS` reply advertises `RAMP_CAP:1` and both current
values. MATLAB reports an unsupported-firmware error if the connected ESP32
does not advertise the capability.

The previous defaults are retained: Pan 150 steps from 9000 to 5000 us per
pulse; standalone Tilt 100 steps from 5000 to 2200 us per pulse. At 25
pulses per output degree these correspond to approximate average full-ramp
accelerations of 3.39 and 28.28 output deg/s². The fastest allowed choices
are Pan 100 steps (about 5.08 deg/s²) and Tilt 75 steps (about 37.70
deg/s²). These are calculated from commanded pulse timing, not measured
mechanical acceleration. Cruise speeds remain 8 and 18.18 deg/s. Dual-axis
moves with Pan pulses use Pan's slower shared pulse clock.

Short moves now follow the selected ramp slope up to their midpoint and
decelerate symmetrically, so they never compress the ramp into a sharper
acceleration than selected. Settings are held in ESP32 RAM and return to
150/100 after a reset; reconnecting the GUI reads the live values.

Verification: five native C++ suites passed, the PlatformIO release build
passed, and 39 selected MATLAB mock tests passed. The GUI layout was
visually inspected. A 4 MB pre-upload flash backup was saved at
`data/validation/motor_ramp_20261015/pre_ramp_full_flash.bin` (SHA256
`47b4957057ac09fea6a951b84e1e1774170629c0d223a7adbb86e89b13b8920c`).
PlatformIO uploaded the new firmware to COM5 and esptool verified all
written hashes. The application binary SHA256 is
`cc5cfc990ee52699017daf516b8a56245bf77c7f6a878efa6a11dd0af7e0d864`.
The no-motion serial probe in the same validation folder confirmed
`RAMP_CAP:1`, rejected an out-of-range command without changing settings,
accepted Pan 100/Tilt 75, and restored Pan 150/Tilt 100. No physical motor
motion was commanded. The GUI was reopened in Mock mode. Upload reset the
ESP32 and released the drivers; reconnect COM5 and establish a fresh manual
mechanical ZERO before scanning.
