# Full180-degree Tilt configuration —2026-10-17

## Report and cause

The screenshot requests motor Tilt+90 to−90 degrees in5-degree steps, travel−90..+90, Pan0..360 in5-degree steps, but declares the ZERO orientation as polar theta0 with positive Tilt direction. The geometry is `theta = TiltAtZeroDeg + TiltSign * TiltMotorDeg`; that declaration produces theta+90..−90, outside the spherical grid0..180. The reported rejection is a spherical-frame mismatch, not a firmware90-degree cap.

Current firmware source advertises Tilt−180..+180. The declared motor travel and the firmware capability are separate from polar theta. This change does not increase firmware limits, automatically confirm mechanical clearance, move motors, send ZERO, or flash firmware.

## Correct configurations

If the antenna is horizontal at mechanical ZERO, declare polar theta90. The requested motor+90..−90 then maps to theta180..0 for positive TiltSign. There are37Tilt rows and73Pan samples,2701 points including the Pan360 endpoint. Negative TiltSign reverses the theta ordering. Motor targets stay within−90..+90.

If the antenna points up at ZERO, keep theta0 and select motor0..180 with positive TiltSign, provided the actual mechanism and declared travel permit it. Do not declare a horizontal ZERO solely to dismiss a validation error. The operator was asked which physical orientation applies; no saved user configuration was rewritten automatically.

## App changes

- Rename the ambiguous `Góc Tilt tại ZERO` field to `Góc cực θ tại ZERO`.
- Add `ZERO nằm ngang (θ =90°)`, explicitly described as appropriate only when the antenna is horizontal at mechanical ZERO. It changes the pending form field and preview only; saving and travel confirmation remain explicit actions.
- Explain theta rejection in Vietnamese, showing the ZERO values compatible with the requested motor endpoints and the motor interval compatible with the existing ZERO. Ranges spanning more than180 degrees receive a specific explanation.
- Reset preview text from error red to black after a valid edit.

## Verification

All checks used Mock or a fixture that forbids hardware motion. No instrument COM port was opened.

- Before implementation, two focused regressions failed: no horizontal-ZERO button and no actionable ZERO-field diagnosis.
- The selected geometry/GUI/positioner-limit/3D scan run exercised29 tests:28 passed; the new GUI assertion errored because a multiline uicontrol String is a character matrix and `contains` needs conversion. Its assertion was corrected to use `string` and the focused GUI test then passed in a fresh process, exit0. No production validator or check was weakened to pass it.
- Geometry verified the complete requested2701-point grid and both poles; mismatched ZERO remains rejected. Existing firmware/travel-limit and scan-preservation tests passed.
- The final GUI regression verified error recovery, unchanged endpoints/travel, saving the configuration, and no connection, homing or travel confirmation caused by the preset.
- Rendered both invalid and valid forms; inspected the PNGs for text clipping and overlap.
- `git diff --check` passed. User logs and raw measurement data were preserved.

Evidence: `docs/verification/tilt-180-2026-10-17/`. Diagnostic scripts remain in ignored `.superpowers/sdd/tilt-180-2026-10-17/`. Physical full-range Tilt motion has not been qualified by these software tests.
