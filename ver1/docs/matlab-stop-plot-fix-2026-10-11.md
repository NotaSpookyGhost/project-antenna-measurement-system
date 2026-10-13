# MATLAB STOP and plot visibility

The user's screenshots show the log tab occupying the plot area after an error and on the next scan. The plot axes were not deleted by STOP. The scan error handler selected the log tab; starting another scan never selected a plotting tab. The fixed 1200 x 780 window also extended beyond the locally scaled 1280 x 720 screen, hiding the tab strip. A regression test measured the original window top at 830 versus a screen-safe maximum of 691.

STOP during a hardware positioner command wait raises `PositionerController:Aborted`. The orchestrator previously propagated that exception instead of processing completed measurement rows. The GUI consequently displayed a scan error and switched to logs.

The repair:

- Treats a positioner wait interruption as a user abort only when cancellation was requested; other hardware errors still surface.
- Retains completed rows for analysis/export when at least two points were acquired, including a STOP during the next move or position query.
- Handles STOP during homing without an error dialog. It leaves the previous graph visible until the first new point replaces it.
- Returns from the log/3D tab to the polar tab on a new scan, preserving an already selected Cartesian or RF tab. Scan errors retain the selected plot and recorded live curves.
- Fits the initial window to the scaled screen and uses normalized control positions so resizing keeps tabs and controls inside the window.
- Clears an earlier abort flag when a new home command starts, and displays rounded progress percentages instead of scientific notation.

`matlab/tests/TestScanStopGUI.m` uses mock VNA/positioner objects and a positioner fixture that raises the actual hardware exception identifiers. It covers restart from logs, STOP during motion followed by a successful restart, STOP during homing, encoder errors retaining live graphs, Cartesian tab selection, and screen bounds. These checks use no serial ports and make no claim about immediate physical stopping by the device firmware. The existing v3 firmware's STOP behavior and encoder mismatch thresholds are unchanged.

Validation passed: all six new GUI tests, all eight positioner protocol tests, the existing direction/abort suite, and the existing forward/reverse GUI scan test. A separate timed invocation of the actual STOP button callback retained two measured points, followed by a successful three-point restart from the log tab. Its dataset and screenshots are in `data/validation/gui_stop_plot_20261011_143656/`. Both screenshot sets were inspected; the plots and full tab strip are visible. No hardware ports were opened for these checks.
