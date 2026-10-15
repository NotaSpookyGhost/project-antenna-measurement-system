# Tilt: 1 m cable, I2C versus PWM — 2026-10-14

User confirmed the Tilt cable is now approximately 1 m (previously approximately
2 m), with the external 2.5 kohm SDA pull-up still connected. OUT remains wired
to GPIO23; SDA21/SCL22 remain connected. No physical wiring was changed between
the two trials below. Only the ESP32 firmware environment was changed.

## Actual stationary results on COM5

| Transport / firmware | Released before | Held | Released after | Held motor-angle span |
| --- | --- | --- | --- | --- |
| I2C / V4.0_HOLD | 30/30 | 100/100 | 30/30 | 0.09 degrees |
| PWM / V4.1_PWM_HOLD, restored | 30/30 | 100/100 | 30/30 | 0.27 degrees |

Both have 160/160 valid Tilt readings. Within each phase the release counter
remained constant. I2C AGC was 128 throughout. PWM period was 4274..4276 us;
PWM AGC is unavailable and its 255 placeholder is not a magnetic reading.

The experiment issued no STEP/GOTO/ZERO commands and accessed no VNA. HOLD
commands enable/release both drivers; acceptance was based on Tilt. These are
stationary motor-tail sensor spans, not independent antenna-table accuracy
measurements. No moving Tilt or 3D scan was tested.

## Interpretation

I2C works in this stationary trial with the current 1 m cable plus 2.5 kohm
pull-up. PWM is therefore not required to obtain 160/160 in this condition.
This does not prove shortening alone was sufficient: the resistor remained,
OUT wiring remained, and the prior PWM setup normalized the sensor's volatile
range registers. I2C reads RAW_ANGLE, independent of the PWM output range.
An additional matched I2C trial after the user powers off and removes only the
external resistor is needed to evaluate the cable-only hypothesis.

## Final state and evidence

The current-source `tilt-pwm` build was restored successfully, then its
30/100/30 acceptance passed. Drivers were released and COM5 was closed.
Reset/release means manual calibration is required before scanning again.
No production source files were changed during this comparison.

- `comparison.json`: complete result, exact firmware upload return codes.
- `stationary.log`, `summary.json`, `i2c_stationary.log`: I2C raw responses/counts.
- `i2c_upload.log`, `pwm_restore_upload.log`: PlatformIO build/upload verification.
- `../tilt_pwm_20261014_165345/raw.log` and `summary.json`: restored PWM trial.
- `run_comparison.py`: orchestrator with PWM restoration in `finally`.
- `stationary_check.py`: unchanged copy of the earlier 30/100/30 I2C trial.
