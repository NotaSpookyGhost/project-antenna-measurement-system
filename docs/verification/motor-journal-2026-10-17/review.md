# Scoped independent review

The fresh reviewer inspected the motor-journal feature against its spec/plan, read-only, without tests or hardware operations. Earlier unrelated uncommitted VNA work was excluded.

Two P2 defects were found and fixed:

1. Success followed by invalid new configuration could inherit the previous COMPLETED journal state. Per-run terminal state now starts empty and is set only by current-run terminal transitions; otherwise the journal ends ERROR.
2. Observed release/calibration loss or a release-count discontinuity could leave the old reference usable. POS handling and keepalive loss now invalidate it without capturing a replacement. The protected status seam is tested without serial I/O.

A separate regression demonstrated that warning-as-error configuration could replace the primary motor fault when logging failed. Secondary diagnostic warnings are now guarded; original movement errors remain primary.

All three regressions were observed failing before the fixes and passed afterward. The same reviewer rechecked the fix pass and approved within scope, pending the parent's final gate. Hardware accuracy, real serial timing, endurance, downstream belt slip and power-loss durability were not qualified by this review.
