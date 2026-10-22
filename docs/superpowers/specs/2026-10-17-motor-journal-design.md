# Motor encoder journal and Pan return monitoring

Implement the approved diagnostic change: persist encoder feedback for each scan movement and compare every completed return to commanded Pan0 against the unchanged manually established ZERO. Preserve existing motion commands, encoder-mismatch guards, travel limits, hold behavior and scan data provenance. No automatic ZERO, correction move, firmware upload or real motion test.

Use a JSONL journal independent of RF export; VNA Mock with ESP32 hardware must still record real motor feedback. Record move attempts, completed/failed moves, both axes' cached command/encoder values, HOLD, calibration state, release counter, fixed ZERO reference/id and explicit VNA/positioner modes. Close each append so records survive app closure without Export Dataset. Unique paths under data/logs/motor; no RF arrays are required.

Capture the Pan encoder reference only at explicit successful Pan/all home or Lock+ZERO (and the existing implicit virtual ZERO on Mock connect). Invalidate it on connection/release. Never adopt a new reference at each scan or return. A previously homed board with no reference captured by this app logs unavailable reference rather than inventing one.

At completed Pan0 targets, compare shortest signed shaft-encoder difference with the fixed reference. Hardware uses5.625 shaft degrees per antenna degree. Legacy Mock encoder behavior uses1 and is labelled explicitly. Warn above1 estimated antenna degree; this is a diagnostic choice, not a qualified accuracy specification or a replacement for existing stop checks. Modulo motor encoders cannot distinguish lost whole shaft turns or downstream belt slip. Do not compare raw encoder0 and360 antenna endpoints as if they were the same shaft angle.

Journal startup/write failure must not silently permit unlogged movement. Preserve the primary motion exception if writing its failure record also fails. Final cleanup is best effort. Mock tests write only into temporary directories. Existing user logs/data and the current dirty feature checkout are preserved.
