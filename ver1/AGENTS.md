# Antenna measurement project

## Working context

- This repository contains the MATLAB R2025b GUI and scan pipeline, the Python NanoVNA bridge, and measurement data.
- Read `INSTRUCTIONS_FOR_CODEX.md` for the handover map and `CODEX_GUIDE.md` for verified local setup and commands. Consult `docs/automatic-antenna-measurement-system-master-v4.md` for measurement requirements before substantial changes.
- MATLAB entry points: `matlab/app/AntennaMeasurementApp.m`, `matlab/classes/MeasurementOrchestrator.m`, `matlab/classes/PatternAnalyzer.m`, `matlab/classes/VNAController.m`, `matlab/classes/PositionerController.m`, and `matlab/classes/DataManager.m`.
- Python bridge: `python/nanovna_bridge.py` and `python/nanovna_v2.py`.

## Development workflow

- Keep mock and hardware paths explicit. For ordinary development, run the selected mock MATLAB tests in `CODEX_GUIDE.md` and relevant Python unit tests.
- Treat `python/test_saa2n.py`, `matlab/test_python_bridge.m`, `matlab/tests/test_real_esp32_pan_as5600.m`, and the MATLAB master runner as hardware capable. Check their behavior before running them against connected equipment.
- Preserve raw scan and validation data. Tests may write into `data/`; inspect `git status` afterward and keep generated artifacts out of code changes unless needed.
- Use the installed `matlab-control` skill for MATLAB measurement and instrument communication work when its guidance applies. Prefer this repository's actual APIs and tests over generic examples in that skill.
