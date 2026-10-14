# Tilt AS5600 PWM trial

The user approved a reversible Tilt-only PWM trial after intermittent encoder
feedback on a mandatory 2 m I2C cable. Pan continues using its existing bus.
The trial must preserve continuous hold, STOP, manual ZERO and the 30 s lease,
and expose missing feedback through the existing POS validity fields.

Use an explicit PlatformIO `tilt-pwm` environment. OUT connects to GPIO23,
with sensor VCC still 3.3 V and a common GND. Retain Tilt SDA21/SCL22 for
temporary configuration at 230 Hz. No BURN/OTP command is exposed or sent.
Sensor power cycling resets temporary settings, so configure again afterward.

GPIO edge capture measures both high time and actual frame period. Decode
the AS5600 128/4095/128 timing frame, validate frequency/duty, reject noise,
and require three fresh agreeing frames obtained after each POS request.
Missing edges/timeouts produce RAW_TILT=-1 and ENC_TILT_VALID=0. PWM cannot
report AGC/ML/MH, so availability is explicitly labelled; never claim a healthy
magnetic field from a PWM angle alone.

`TILT PWM CONFIG` must run only with drivers released, check full-turn sensor
range and read/modify/write/read-back CONF. `TILT PWM CHECK` reports capture
health without motion. Default I2C firmware behavior remains supported.

Acceptance: native tests cover timing endpoints, noisy/stale frames, wrap,
configuration failure/readback, no OTP writes and no STEP pulses. Both firmware
environments build. MATLAB decodes PWM POS and rejects invalid frames. Actual
PWM acceptance requires the user to wire OUT, then released/held stationary
checks before any Tilt movement.

Source: https://www.mouser.com/datasheet/2/588/AS5600_DS000365_5_00-1877365.pdf
