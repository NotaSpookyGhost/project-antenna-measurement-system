"""No-motion COM5 check of the adjustable ramp firmware."""

import time

import serial


def exchange(port, command):
    port.reset_input_buffer()
    port.write((command + "\n").encode("ascii"))
    deadline = time.monotonic() + 5
    reply = bytearray()
    while time.monotonic() < deadline:
        reply.extend(port.read(port.in_waiting or 1))
        if b"ESP32-ANTENNA>" in reply:
            return reply.decode("utf-8", "replace")
    raise TimeoutError(f"No prompt after {command}: {reply!r}")


with serial.Serial("COM5", 115200, timeout=0.1) as port:
    time.sleep(2)
    initial = exchange(port, "POS")
    assert "RAMP_CAP:1 RAMP_PAN:150 RAMP_TILT:100" in initial, initial
    rejected = exchange(port, "RAMP 99 75")
    assert "ERR: RAMP_RANGE" in rejected, rejected
    assert "RAMP_PAN:150 RAMP_TILT:100" in exchange(port, "POS")
    try:
        faster = exchange(port, "RAMP 100 75")
        assert "RAMP OK PAN:100 TILT:75" in faster, faster
        assert "RAMP_PAN:100 RAMP_TILT:75" in exchange(port, "POS")
    finally:
        restored = exchange(port, "RAMP 150 100")
        assert "RAMP OK PAN:150 TILT:100" in restored, restored
    assert "RAMP_PAN:150 RAMP_TILT:100" in exchange(port, "POS")

print("PASS: ramp capability, bounds, faster setting, and restored defaults; no movement command sent")
