# Driver holding diagnosis — 2026-10-14

## Follow-up after physical wire repair

At approximately23:05 local time, the user reported finding a broken Pan
motor wire in the pair connected to A1/A2 and replacing/repairing it.
Pan validation is being repeated using the existing slow profile and
unchanged encoder guards. This is a user-reported physical repair;
no software pulse compensation or current adjustment was made.
The post-repair stationary30/100/30 test passed160/160 samples for each
encoder, with maximum Pan span0.08 motor degrees and Tilt span0.00.
Pan motion then passed 21/21 positions through 0..+90..0 with 210/210 paired
snapshots, no hold loss, maximum output-angle estimate error0.218667 degrees
and motor closure−0.09 degrees. The user confirmed smooth movement and return
to the physical mark. This supports the broken A1/A2 motor wire as the cause
of the reproduced Pan failure. Drivers released; COM5 closed. See
`pan-wire-repair-validation-2026-10-14.md` and
`data/validation/pan_wire_repair_20261014_230557/` for the completed results.

## Earlier diagnostic record

Status: root cause of inaccurate motion not yet established; enable voltages
and physical holding now confirmed, encoder stability being rechecked.
User requested continuation after Pan failed both the normal and slow profiles.

## Confirmed observations

- Active firmware and the AP reference agree on Pan STEP25/DIR26/EN27,
  Tilt STEP32/DIR33/EN14 and active-low enable, with25 pulses/output degree.
- The complete command handler refreshes the hold lease after HOLD ON and
  LOCK ZERO. There is no missing initial renewal in these command paths.
- A bounded stationary test sent HOLD ON, then POS every5 seconds, without
  ZERO or movement commands. All24 samples across approximately116.6 seconds
  reported HOLD1, both encoders valid and RELEASES0.
- The user reported both motors still soft during this observation and
  confirmed MS1/MS2 have no wires attached.
- The test then sent HOLD OFF. Final POS reported HOLD0 and RELEASES1,
  and the serial connection was closed.

HOLD telemetry describes firmware intent. It does not measure voltage at
the driver, winding current or physical holding torque. Native pulse tests
likewise do not measure the actual electrical waveform at the driver input.

## What remains to distinguish

| Check | Intended setup | Result |
|---|---|---|
| Pan VM to driver GND | Approximately20 V supply | User measured20 V while released |
| Pan VIO to driver GND | Approximately3.3 V logic | User measured3.2 V while released |
| Tilt VM to driver GND | Approximately20 V supply | User measured20 V while released |
| Tilt VIO to driver GND | Approximately3.3 V logic | User measured3.2 V while released |
| EN at each driver, released | High while released | User measured3.2 V on both |
| EN at each driver, held | Low while held | User measured0 V on both and confirmed both motors stiff |
| Actual MS pin levels/module pull resistors | Low/low for standalone1/8 | User reports unconnected pins; electrical level unmeasured |
| Winding connection and driver current setting | Matches actual motor/module | Not yet established |

The user measured VM20 V and VIO3.2 V at both drivers while released.
This shows the rails are present at the measurement time; it does not measure
their behavior under load. The user next measured EN3.2 V on both released
drivers. A separately announced hold-only phase (maximum180 seconds) is now
collected the held EN readings and physical holding observation: both EN0 V
and both motors stiff. This confirms an active electrical enable path and
some physical holding torque at that time. It does not prove correct phase
current, both windings healthy, or accurate motion. The earlier report of
both soft must not be treated as a permanent no-hold fault.

The enable-measurement run had30 snapshots: Pan25/30 valid, Tilt28/30 valid.
Both angles also changed substantially without computer motion commands.
Whether the operator moved the mechanism/wiring during probing is pending.
Final HOLD0/RELEASES2 confirmed; COM5 closed. A fresh hands-off stationary
30/100/30 run was started before permitting another motion test.

The fresh stationary run completed: Pan160/160 and Tilt160/160 valid,
within-state spans at most0.09 motor degrees, with commanded hold matching
all three states. Final HOLD OFF confirmed and COM5 closed. This supports
stable stationary feedback under those conditions, not validated feedback
during movement or independently measured output angle.

## Interpretation

The no-motion holding observation makes the electrical drive path the next
diagnostic priority. It does not prove either motor or driver is damaged.
Unconnected MS pins agree with the handover description; on the TMC2209 IC,
internal pull-downs select1/8, but board-level wiring and resistors have not
been inspected. The former near-eightfold angle discrepancy is therefore
a hypothesis, not an established microstep configuration error.

No production code was changed in this diagnostic step because no new
software defect was established. No extra compensation pulses, current
increase or encoder-guard bypass was applied.

Evidence: `data/validation/driver_diagnosis_20261014_2224/hold.log`,
`hold.json`, `hold_summary.json`, `hold_observation.py` and `progress.md`.
Reference: [TMC2209 datasheet rev1.09, signal descriptions and standalone
operation](https://www.analog.com/media/en/technical-documentation/data-sheets/TMC2209_datasheet_rev1.09.pdf).
