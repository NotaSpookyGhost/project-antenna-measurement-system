"""Interactive, encoder-checked tilt check for the ESP32 positioner.

Keep this process open while an observer checks the physical direction.
Press Enter to return to the local ZERO position after the observation.
"""

import argparse
import re
import sys
import time

import serial


PROMPT = b"ESP32-ANTENNA> "


def command(port: serial.Serial, text: str) -> str:
    port.write((text + "\n").encode("ascii"))
    response = port.read_until(PROMPT).decode("utf-8", "replace")
    if "ESP32-ANTENNA>" not in response or "ERR:" in response:
        raise RuntimeError(f"{text}: {response.strip()}")
    return response.strip()


def raw_tilt(port: serial.Serial) -> int:
    response = command(port, "POS")
    match = re.search(r"RAW_TILT:(\d+)\s+MAG_PAN:(\d+)\s+MAG_TILT:(\d+)", response)
    if match is None or match.group(3) != "1":
        raise RuntimeError(f"Tilt AS5600 is unavailable: {response}")
    print("POS:", response, flush=True)
    return int(match.group(1))


def checked_move(port: serial.Serial, current: int, target: int, before: int) -> int:
    print(f"TILT {target}:", command(port, f"TILT {target}"), flush=True)
    after = raw_tilt(port)
    motor_delta = ((after - before + 2048) % 4096 - 2048) * 360.0 / 4096.0
    expected = (target - current) * 90.0 / 16.0
    if abs(motor_delta - expected) > max(12.0, 0.2 * abs(expected)):
        raise RuntimeError(
            f"Tilt encoder mismatch at {target} degrees: "
            f"measured {motor_delta:.1f} motor degrees, expected {expected:.1f}; stopped"
        )
    time.sleep(0.8)
    return after


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--target", type=int, choices=(5, 90), default=5)
    args = parser.parse_args()
    with serial.Serial("COM9", 115200, timeout=8) as port:
        time.sleep(1.8)
        port.reset_input_buffer()
        print("ZERO:", command(port, "ZERO"), flush=True)
        previous_raw = raw_tilt(port)
        stages = [5] if args.target == 5 else [5, 15, 30, 45, 60, 75, 90]
        previous_target = 0
        for target in stages:
            previous_raw = checked_move(port, previous_target, target, previous_raw)
            previous_target = target
        print(f"Tilt at +{args.target} degrees. Press Enter to return to local zero.", flush=True)
        sys.stdin.readline()
        for target in list(reversed(stages[:-1])) + [0]:
            previous_raw = checked_move(port, previous_target, target, previous_raw)
            previous_target = target
        print("RELEASE:", command(port, "RELEASE"), flush=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
