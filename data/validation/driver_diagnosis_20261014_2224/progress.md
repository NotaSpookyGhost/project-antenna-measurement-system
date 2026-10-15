# Driver investigation — 2026-10-14

User request: repair the system after persistent Pan encoder mismatch, using
the using-superpowers workflow. Follow systematic debugging; do not compensate
with extra pulses or remove encoder guards without establishing the cause.

- [x] Review failures and the Pan slow trial.
- [x] Compare active firmware to AP and handover pin/step configuration.
- [x] Check physical holding during a bounded, no-motion HOLD test: user reports both motors soft.
- [ ] Confirm actual driver wiring/configuration and relevant voltages.
- [ ] Repair the established cause, verify with focused software/hardware tests.
- [ ] Qualify Pan and Tilt motion before claiming 3D readiness.

Verified source facts: active and AP firmware use Pan STEP25/DIR26/EN27,
Tilt STEP32/DIR33/EN14, EN active low, 25 pulses per output degree.
Current firmware remains enabled during moves/settling/POS; HOLD telemetry
represents commanded state, not measured motor current or torque.
No TMC UART communication is implemented or identified as wired.
Handover specifies standalone MS1/MS2 floating (internal pull-downs expected),
but actual current board wiring is unverified. Software cannot infer the
driver's actual microstep selection from its own constant.

TMC2209 datasheet rev1.09, pages9 and14: MS2/MS1=00 selects1/8,
01 selects1/32,10 selects1/64,11 selects1/16; ENN high disables outputs.
Source: https://www.analog.com/media/en/technical-documentation/data-sheets/TMC2209_datasheet_rev1.09.pdf

Hardware script hold_observation.py has a120-second hold limit, queries POS
every5 seconds to maintain the lease, and releases/closes in finally.
It sends no movement or ZERO commands. User asked to compare physical hold
while it is active and report multimeter availability and MS pin wiring.

User confirms MS1/MS2 are unconnected. That matches the intended standalone
configuration at the wiring-description level; actual pin voltages/module
pull resistors remain unmeasured. User reports both motors soft during HOLD.
24 fresh paired snapshots over about116.6 seconds reported HOLD1, both
encoders valid and RELEASES0. Final release confirmed HOLD0, RELEASES1;
the script exited and closed COM5. No ZERO or motion command was sent.

Reviewed the complete firmware command handler: it refreshes the lease at
the end when holdRequested is true, including the first HOLD ON and LOCK
ZERO. No missing-first-lease-refresh defect was found. Pin initialization,
enable polarity and pulse scaling agree with AP. No new production change
is justified by the present evidence. Next discriminator: actual VM/VIO at
the driver, followed by EN during held/released phases. Multimeter
availability requested; it cannot be inferred from serial telemetry.
User measured VM20 V and VIO3.2 V on both drivers while released. Requested EN-to-GND readings at both driver modules while still released; will compare with an explicitly announced held phase. Supply sag under load is not yet measured.
User measured released EN3.2 V on both driver modules. Started separately announced enable_measurement/hold_observation.py: maximum180-second HOLD with POS heartbeat, no motion. Awaiting held EN voltages and physical holding observation.
User measured EN0 V on BOTH drivers while held and confirmed BOTH motors stiff. Prior released EN was3.2 V on both. Electrical enable switching and some holding torque are now physically confirmed; earlier soft observation is not proof of permanent driver failure. Held-phase log had30 samples, Pan25 valid/Tilt28 valid and substantial angle changes. Asked whether operator moved axes/wiring. Released explicitly, final HOLD0/RELEASES2, COM5 closed. Running hands-off30/100/30 stationary recheck before any motion.
Resolved follow-up: user found and repaired broken Pan conductor in the A1/A2 pair. Retest in data/validation/pan_wire_repair_20261014_230557 passed stationary160/160 per sensor and Pan0..90..0 at21 positions/210 paired snapshots. Max Pan output estimate error0.218667 deg; motor closure−0.09 deg. User confirms smooth motion and physical return to mark. Same firmware/guards, no pulse compensation. Final HOLD0 verified, COM5 closed. See docs/pan-wire-repair-validation-2026-10-14.md. Tilt motion and full3D not part of this retest.
