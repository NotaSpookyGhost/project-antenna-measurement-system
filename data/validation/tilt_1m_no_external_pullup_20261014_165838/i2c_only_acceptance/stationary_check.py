"""Read-only AS5600 acceptance check after the Tilt SDA pull-up change.

The script sends no motor STEP/GOTO/ZERO commands. It restores HOLD OFF and
closes COM5 even when a serial transaction fails.
"""

import json
import re
import time
from pathlib import Path

import serial


HERE = Path(__file__).resolve().parent
PROMPT = b"ESP32-ANTENNA> "


def command(port, name, raw_log):
    port.write((name + "\n").encode("ascii"))
    response = port.read_until(PROMPT).decode("utf-8", "replace")
    raw_log.write(name + "\n" + response + "\n")
    raw_log.flush()
    if "ESP32-ANTENNA>" not in response:
        raise RuntimeError(f"No prompt after {name}: {response!r}")
    return response


def sample(port, raw_log):
    response = command(port, "POS", raw_log)
    fields = {}
    for key in ("RAW_PAN", "RAW_TILT", "HOLD", "ENC_PAN_VALID", "ENC_TILT_VALID", "RELEASES", "FW"):
        m = re.search(rf"\b{key}:\s*([^\s]+)", response)
        if m is None:
            raise RuntimeError(f"Missing {key} from POS: {response!r}")
        fields[key] = m.group(1)
    agc = re.findall(r"\(AGC:\s*(\d+)\)", response)
    if len(agc) != 2:
        raise RuntimeError(f"Missing AGC readings: {response!r}")
    fields["AGC_PAN"], fields["AGC_TILT"] = map(int, agc)
    return fields


def run_phase(port, raw_log, name, count, expected_hold):
    rows = []
    for index in range(count):
        if expected_hold and index % 20 == 0:
            if "PONG" not in command(port, "PING", raw_log):
                raise RuntimeError("HOLD lease could not be renewed")
        row = sample(port, raw_log)
        if row["FW"] != "V4.0_HOLD":
            raise RuntimeError(f"Unexpected firmware: {row['FW']}")
        if row["HOLD"] != str(expected_hold):
            raise RuntimeError(f"HOLD changed during {name}: {row}")
        rows.append(row)
        if (index + 1) % 25 == 0:
            print(f"{name}: {index + 1}/{count}", flush=True)
    result = {
        "state": name,
        "reads": count,
        "pan_valid": sum(row["ENC_PAN_VALID"] == "1" for row in rows),
        "tilt_valid": sum(row["ENC_TILT_VALID"] == "1" for row in rows),
        "tilt_agc_unique": sorted({row["AGC_TILT"] for row in rows}),
        "tilt_raw_valid_range": [
            min((float(row["RAW_TILT"]) for row in rows if row["ENC_TILT_VALID"] == "1"), default=None),
            max((float(row["RAW_TILT"]) for row in rows if row["ENC_TILT_VALID"] == "1"), default=None),
        ],
        "release_counter_start": int(rows[0]["RELEASES"]),
        "release_counter_end": int(rows[-1]["RELEASES"]),
    }
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    results = []
    with (HERE / "stationary.log").open("w", encoding="utf-8") as raw_log:
        with serial.Serial("COM5", 115200, timeout=5) as port:
            time.sleep(1.8)
            port.reset_input_buffer()
            try:
                command(port, "HOLD OFF", raw_log)
                results.append(run_phase(port, raw_log, "HOLD OFF before", 30, 0))
                if "HOLD ON OK" not in command(port, "HOLD ON", raw_log):
                    raise RuntimeError("HOLD ON was rejected")
                results.append(run_phase(port, raw_log, "HOLD ON", 100, 1))
            finally:
                try:
                    released = command(port, "HOLD OFF", raw_log)
                    if "HOLD OFF OK" not in released:
                        raise RuntimeError(f"Could not release drivers: {released!r}")
                    results.append(run_phase(port, raw_log, "HOLD OFF after", 30, 0))
                finally:
                    (HERE / "summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()

