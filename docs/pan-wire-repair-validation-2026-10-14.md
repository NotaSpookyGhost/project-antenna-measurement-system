# Pan validation after A1/A2 wire repair — 2026-10-14

**Pan passed the 0° → +90° → 0° hardware test after the user repaired a
broken conductor in the motor pair connected to A1/A2.** The user also
confirmed smooth movement and return to the original physical mark.

The same slow-Pan firmware and MATLAB encoder guards were used. No pulse
compensation, gear-ratio change, current adjustment or firmware reflash
was performed for this retest. This before/after result strongly supports
the broken motor wire as the cause of the Pan failure reproduced earlier.
The earlier suspected microstep mismatch was not confirmed.

## Results

| Check | Result |
|---|---|
| Stationary released/held/released | 30/100/30 samples; both encoders 160/160 valid |
| Maximum stationary span | Pan 0.08°, Tilt 0.00°, motor-side angles |
| Pan route | 0, 5, 10, 20, …, 90, 80, …, 10, 5, 0° |
| Validated positions | 21/21, including initial ZERO |
| Paired encoder snapshots | 210/210 valid, 10 per position |
| First Pan 5° encoder change | Magnitude 28.31° motor, expected 28.125° |
| Maximum absolute Pan tracking error | 0.218667° estimated output angle |
| Pan return-to-zero error | −0.09° motor, +0.016° estimated output |
| Tilt drift while Pan moved | At most 0.016° estimated output |
| Driver hold during all snapshots | HOLD1 throughout; release counter unchanged |
| User observation | Quay đều và về đúng mốc — smooth and returned to physical mark |
| Final state | PAN0, TILT0, HOLD0, CAL_REQUIRED1; COM5 closed |

Output-angle estimates use the motor-tail encoders divided by 5.625, with
encoder direction established from the first move and circular increments
unwrapped between the small motion steps. They are not independent angular
metrology of the antenna table. The user separately confirmed the visible
return to the starting mark.

All existing controller mismatch checks remained enabled. The test also
required valid paired encoders, continuous commanded hold, no release-count
increase, stationary span ≤2 motor degrees, accumulated output-angle error
≤2 degrees, and return closure ≤2 motor degrees. It would stop on failure
without automatically returning or adding compensation pulses.

## Scope

This run moved Pan only. Tilt feedback was monitored while Tilt stayed at
its initial commanded position. It did not repeat Tilt motion or a complete
3D RF scan. The earlier slow-Pan profile remains installed: 5000/9000 µs,
maximum ramp 150, with unchanged standalone Tilt timing.

After the successful test, the controller released both motors and closed
COM5. A separate read-only POS probe confirmed HOLD0 and closed the port.
Establish a new mechanical ZERO before the next measurement because release
invalidates calibration.

## Evidence

Directory: `data/validation/pan_wire_repair_20261014_230557/`.

- `stationary.py`, `stationary.log`, `stationary.json`: stationary test.
- `test_pan_wire_repair.m`, `motion_console.log`: guarded MATLAB hardware run.
- `motion.mat`, `motion.csv`, `motion.json`: paired raw samples and stage metrics.
- `final_state.py`, `final_state.log`: final released-state verification.
- `summary.json`: result summary and user observation.

Previous diagnostic records: `driver-diagnosis-2026-10-14.md` and
`pan-slow-validation-2026-10-14.md`. Their failed results describe the
pre-repair state and should not be mistaken for the current Pan result.
