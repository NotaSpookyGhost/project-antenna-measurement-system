"""Lower tilt in small steps, stopping at the measured starting encoder angle.

For the 2026-10-11 test, the baseline AS5600 J3 raw value was 581.
The ESP32 command counter can differ from physical tilt after motor slip.
"""

import re
import time

import serial


PROMPT = b"ESP32-ANTENNA> "
BASELINE_RAW = 581


def ask(port: serial.Serial, cmd: str) -> str:
    port.write((cmd + "\n").encode("ascii"))
    answer = port.read_until(PROMPT).decode("utf-8", "replace")
    if "ESP32-ANTENNA>" not in answer or "ERR:" in answer:
        raise RuntimeError(f"{cmd}: {answer.strip()}")
    return answer


def position(port: serial.Serial) -> tuple[float, int]:
    answer = ask(port, "POS")
    match = re.search(r"TILT:(-?[\d.]+)\s+RAW_PAN:\d+\s+RAW_TILT:(\d+)", answer)
    if match is None:
        raise RuntimeError(f"Invalid POS response: {answer.strip()}")
    angle, raw = float(match.group(1)), int(match.group(2))
    print(f"Commanded tilt={angle:.1f}, J3 raw={raw}", flush=True)
    return angle, raw


def main() -> None:
    with serial.Serial("COM9", 115200, timeout=8) as port:
        time.sleep(1.8)
        port.reset_input_buffer()
        commanded, raw = position(port)
        if abs(commanded - 30.0) > 0.1:
            raise RuntimeError("Expected tilt command counter 30 degrees; no motion attempted")
        for target in (25, 20, 15, 10, 5, 0):
            if raw <= BASELINE_RAW + 80:
                print("Reached the starting encoder neighborhood; stopping.", flush=True)
                break
            print(ask(port, f"TILT {target}").strip(), flush=True)
            commanded, raw = position(port)
            time.sleep(0.8)
        print(f"Final raw={raw}; baseline raw={BASELINE_RAW}", flush=True)


if __name__ == "__main__":
    main()
