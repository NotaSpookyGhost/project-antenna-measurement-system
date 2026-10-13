"""No-motion COM5 smoke test for the hold/manual-zero firmware."""

import time
import serial


def send(port, command, token, timeout=6):
    port.write((command + "\n").encode("ascii"))
    deadline = time.monotonic() + timeout
    response = b""
    while time.monotonic() < deadline:
        response += port.read(port.in_waiting or 1)
        if b"ESP32-ANTENNA> " in response:
            break
    text = response.decode("utf-8", errors="replace")
    print(f"{command}: {text.strip()}")
    assert token in text, f"{command}: missing {token!r}"
    return text


with serial.Serial("COM5", 115200, timeout=0.1) as port:
    time.sleep(1.8)
    port.reset_input_buffer()
    try:
        send(port, "POS", "HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1")
        send(port, "HOLD ON", "HOLD ON OK CAL_REQUIRED:1")
        send(port, "POS", "HOLD_CAP:1 HOLD:1 CAL_REQUIRED:1 SENSOR_CACHED:0")
        send(port, "PING", "PONG")
        send(port, "CAL RELEASE", "CAL RELEASE OK")
        send(port, "POS", "HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1")
        send(port, "LOCK ZERO", "LOCK ZERO OK")
        send(port, "POS", "HOLD_CAP:1 HOLD:1 CAL_REQUIRED:0 SENSOR_CACHED:0")
        send(port, "HOLD OFF", "HOLD OFF OK")
        send(port, "POS", "HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1")
        send(port, "HOLD ON", "HOLD ON OK CAL_REQUIRED:1")
        time.sleep(31)
        send(port, "POS", "HOLD_CAP:1 HOLD:0 CAL_REQUIRED:1")
        print("Hardware hold/release/manual ZERO protocol PASS")
    finally:
        # The device also self-releases after 30 s if this command cannot run.
        try:
            send(port, "HOLD OFF", "HOLD OFF OK")
        except Exception as exc:
            print(f"Cleanup release unconfirmed: {exc}")
