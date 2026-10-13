"""Compare stationary pan and tilt driver-enable effects on both AS5600 buses.

Requires the normal 20 V supply, which also feeds the 3.3 V sensor regulator.
No STEP command is sent. Each hold is released in a finally block; firmware
also auto-releases diagnostic holds after 90 seconds.
"""

import re
import time

import serial


PROMPT = b"ESP32-ANTENNA> "


def command(port: serial.Serial, name: str) -> str:
    port.write((name + "\n").encode("ascii"))
    response = port.read_until(PROMPT).decode("utf-8", "replace")
    if "ESP32-ANTENNA>" not in response:
        raise RuntimeError(f"No firmware prompt after {name}: {response!r}")
    return response.strip()


def position(port: serial.Serial, label: str) -> tuple[int, int]:
    response = command(port, "POS")
    match = re.search(r"RAW_PAN:(-?\d+) RAW_TILT:(-?\d+) MAG_PAN:(\d+) MAG_TILT:(\d+)", response)
    if match is None:
        raise RuntimeError(f"Invalid POS at {label}: {response}")
    print(f"{label}: {match.group(0)}", flush=True)
    return int(match.group(3)), int(match.group(4))


def probe(port: serial.Serial, axis: str) -> None:
    hold = f"HOLD {axis}"
    release = f"RELEASE {axis}" if axis == "PAN" else "RELEASE"
    try:
        response = command(port, hold)
        if f"DIAGNOSTIC {axis} HOLD ACTIVE" not in response:
            raise RuntimeError(f"{hold} unsupported or rejected: {response}")
        print(f"{axis} EN on: {command(port, 'LINES')}", flush=True)
        position(port, f"{axis} EN on")
    finally:
        print(f"{axis} release: {command(port, release)}", flush=True)
        position(port, f"{axis} EN off")


def main() -> None:
    with serial.Serial("COM9", 115200, timeout=5) as port:
        time.sleep(1.8)
        port.reset_input_buffer()
        position(port, "Baseline")
        probe(port, "PAN")
        probe(port, "TILT")


if __name__ == "__main__":
    main()
