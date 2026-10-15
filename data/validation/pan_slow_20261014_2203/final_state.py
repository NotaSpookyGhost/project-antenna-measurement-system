"""Read-only final POS after the motion script released and closed COM5."""
from pathlib import Path
import time
import serial

with serial.Serial('COM5', 115200, timeout=.1) as port:
    time.sleep(2)
    port.reset_input_buffer()
    port.write(b'POS\n')
    response = b''
    deadline = time.monotonic() + 4
    while time.monotonic() < deadline and b'ESP32-ANTENNA>' not in response:
        response += port.read(port.in_waiting or 1)
    text = response.decode(errors='replace')
    Path(__file__).with_suffix('.log').write_text(text, encoding='utf-8')
    print(text)
    assert b'HOLD:0' in response and b'ESP32-ANTENNA>' in response
print('Final HOLD:0 verified; COM5 closed.')
