"""One short Pan motion to verify real mid-move STOP on COM5."""

import time
import serial


def read_prompt(port, timeout=5):
    deadline = time.monotonic() + timeout
    data = b""
    while time.monotonic() < deadline:
        data += port.read(port.in_waiting or 1)
        if b"ESP32-ANTENNA> " in data:
            break
    return data.decode("utf-8", errors="replace")


with serial.Serial("COM5", 115200, timeout=0.05) as port:
    time.sleep(1.8)
    port.reset_input_buffer()
    try:
        port.write(b"LOCK ZERO\n")
        response = read_prompt(port)
        assert "LOCK ZERO OK" in response, response
        port.write(b"PAN 5\n")
        time.sleep(0.08)
        port.write(b"STOP\n")
        response = read_prompt(port)
        print(response.strip())
        assert "ABORTED PAN:" in response, response
        port.write(b"POS\n")
        response = read_prompt(port)
        print(response.strip())
        assert "HOLD:1 CAL_REQUIRED:1" in response, response
        print("Hardware mid-move STOP PASS")
    finally:
        port.write(b"HOLD OFF\n")
        print(read_prompt(port).strip())
