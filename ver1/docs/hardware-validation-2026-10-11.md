# Hardware validation — 2026-10-11

> Later evidence: the handover v3 on COM5 completed three small Pan 10° / Tilt 5° cycles at about 14:02 with both encoders responding and no reported I²C timeouts. At about 14:12, MATLAB POS parsing was repaired and real MATLAB moves on both axes plus GUI connection passed. V3 releases both drivers before sensor reads, unlike the workspace firmware used below. The earlier enable-related fault does not imply tilt cannot run with v3. See `positioner-v3-recheck-2026-10-11.md` for evidence and limits; retain the measurements below as historical evidence.

## Connected hardware and tested results

| Subsystem | Result | Evidence |
| --- | --- | --- |
| NanoVNA SAA-2N, COM6 | RF checks passed with qualification | THRU S21 about -3.01 dB; 100-sweep mean -3.0152 dB, standard deviation 0.0049 dB; FIFO open→THRU→open transitions were fresh. The 50 Ω LOAD S11 was -14.54 dB, slightly above the absolute -15 dB target while clearly below OPEN/SHORT. |
| ESP32 pan, COM9 | Passed at small angles | MATLAB commanded 0→5→10→15→0°. AS5600 J4 moved at each point. A human observer confirmed positive pan moves counterclockwise when viewed from above. |
| Full COM6 + COM9 chain | Passed with 50 Ω LOAD on VNA | Three real VNA sweeps synchronized with pan 0→5→10°. J4 moved 58.54° motor angle over the 10° pan sweep; raw complex sweeps saved in `data/scans/real_vna_real_pan_smoke_20261011_123346/`. Pan was returned to its local zero. This is an integration check, not an antenna radiation pattern. |
| ESP32 tilt, COM9 | **Do not use for automatic scans yet** | A ramp toward 90° stopped at the 30° command because AS5600 J3 advanced only 63.1° motor angle for an expected 84.4° on the 15→30° segment. J3 later fell from raw 2151 to 2013 at rest. |
| Tilt electrical diagnostic | Fault isolated to driver enable | With no STEP pulses, asserting tilt EN caused both AS5600 I²C buses to fail. Releasing EN restored both bus readings. This suggests a shared supply, ground, or interference issue; it does not yet identify the exact component. |
| Pan-versus-tilt enable comparison | Both drivers trigger the same fault | With normal 20 V and 3.3 V regulator power, stationary `HOLD PAN` made J3 and J4 unavailable (`RAW=-1`, `MAG=0`) just like stationary `HOLD TILT`. Both EN pins were then released. J3 recovered on subsequent reads; eight consecutive `POS` samples were valid and stable (J4 raw 4082, J3 raw 607). The problem is shared rather than unique to the tilt sensor or tilt driver. |
| J1-disconnected trial | Inconclusive until connector identity is checked | After the user reported unplugging J1 with all power off, J4 was unavailable even before EN was asserted (five later idle samples also had `MAG_PAN=0`), while J3 remained readable. `HOLD PAN` then made J3 unavailable; releasing EN restored J3. Since J1 and J4 are both four-pin jacks, verify the disconnected plug is truly motor J1 and that sensor J4 remains connected before interpreting the coil-isolation result. Both EN pins were verified off after the trial. |

The user confirmed both axes have 360° mechanical travel and that cables have
been checked for clearance. The tilt axis was returned close to its original
encoder reading (raw 572 versus raw 563 before the last ramp). ESP32 3V3 was
about 3.3 V with tilt EN off and 3.23 V with EN on; J3 VCC-to-GND remained
about 3.2–3.3 V under the same load. A DC meter cannot rule out fast ripple.
All four I²C pins read high when idle under both EN states. Transactions on
both buses still timed out when tilt EN was on, at both 100 kHz and 25 kHz.
The user clarified the actual power topology: the 20 V source also feeds a
3.3 V step-down regulator, whose output powers both AS5600 sensors and both
TMC2209 VIO inputs; ESP32 is powered separately over USB, with common GND and
GPIO connections. This supersedes the older handover diagram that showed the
ESP32 3V3 pin as the source for those loads. J3 GND measures near 0 V relative
to ESP32 GND. Removing the 20 V source would remove sensor logic power too,
so it is not a valid way to isolate motor current from the I²C fault.
The regulator is identified by the user as a Mini 560 Pro 3.3 V module. With
pan EN asserted and no STEP pulses, a DC meter at its OUT+/OUT− stayed at
3.3 V. This excludes a sustained DC collapse at the regulator output but
does not exclude fast ripple or ground bounce.
In a later stationary `POS` check with tilt EN off, both sensors responded
(`MAG_PAN=1`, `MAG_TILT=1`; J4 raw 313, J3 raw 589). Thus the available
evidence does not show a permanently failed AS5600. The changed J4 raw angle
relative to an earlier session has not been explained; establish a fresh local
`ZERO` before another motion test.

## Current safeguards

- The MATLAB GUI keeps `TiltDisabled=true` until the electrical fault is fixed
  and a full motion test succeeds.
- The ESP32 firmware rejects encoder loss, cumulative angle drift, and
  per-chunk mismatch. It releases the affected driver on an encoder fault.
- `HOLD PAN` and `HOLD TILT` enable each stationary driver for at most 90
  seconds to support voltage measurement. `RELEASE PAN` and `RELEASE` end the
  respective tests immediately. Neither diagnostic command sends STEP pulses.
- `JOG TILT ±5` can recover a small angle after a fault. A subsequent `ZERO`
  is required before absolute moves.

## Next hardware checks

1. Verify the identity of the disconnected four-pin jack and restore the J4
   AS5600 connection while all power is off. Repeat the J1 coil-isolation
   test only after both sensors respond at baseline. If I²C recovers without
   the motor coil load, investigate motor current, supply coupling, and wiring
   proximity. If it still fails, investigate driver enable, regulator output
   impedance, and I²C pull-ups.
2. Measure the 20 V input of the 3.3 V regulator with driver EN active, using
   the regulator GND as reference. A DC meter can identify sustained sag but
   cannot rule out switching ripple. Check its ground connection to ESP32 GND.
3. Inspect the external SDA/SCL pull-up resistors on both I²C buses and the
   routing of motor power/coil wires beside the sensor cables. Espressif's
   I²C guide recommends external pull-ups, typically 2–5 kΩ, and notes that
   transaction timeouts can indicate inadequate pull-ups.
4. Inspect the common ground and tilt TMC2209 VIO/VM wiring. A scope or logic
   analyzer would distinguish supply ripple and I²C edge corruption that a
   DC meter cannot show.
5. After repair, run the staged 5→15→30→45→60→75→90° check and return to
   the local zero while watching AS5600 J3 at every stage.

Official reference: https://docs.espressif.com/projects/esp-idf/en/latest/esp32/api-reference/peripherals/i2c.html

The original 4 MB ESP32 flash image was saved outside the repository at
`C:\Users\Spooky Laptop\Documents\ChatGPT\esp32-original-20261011.bin`
before the first firmware upload (SHA-256
`C1544C71E646F59B4239FDE1DE87BDB5FC555F6D0371F30ECE6F5373E16A255D`).
