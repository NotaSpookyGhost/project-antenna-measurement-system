"""Explicit stationary hardware comparison; requires diagnostic firmware on COM5."""
import datetime
import pathlib
import serial
import time

root = pathlib.Path(__file__).resolve().parents[2]
folder = root / 'data' / 'validation' / ('as5600_profiles_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir(parents=True)
with (folder / 'serial.log').open('w', encoding='utf-8') as log, serial.Serial('COM5', 115200, timeout=.05) as port:
    def command(cmd, timeout=25):
        port.write((cmd+'\n').encode())
        deadline = time.monotonic() + timeout
        data = b''
        while time.monotonic() < deadline:
            data += port.read(port.in_waiting or 1)
            if b'DIAG> ' in data:
                break
        text = data.decode('utf-8', 'replace')
        log.write(cmd+'\n'+text+'\n'); log.flush()
        assert 'DIAG> ' in text, text
        for line in text.splitlines():
            if line.startswith(('SUMMARY', 'HOLD', 'SAMPLE')):
                print(line, flush=True)
        return text
    time.sleep(1.8); port.reset_input_buffer()
    assert 'ERR' in command('POS'), 'Expected diagnostic firmware'
    try:
        for mask in (0, 3, 1, 2):
            command(f'H {mask}')
            for mode, hz in ((0,100000),(1,100000),(2,100000),(0,50000),(0,10000),(3,10000)):
                command(f'D {mode} {hz}')
    finally:
        command('H 0')
print(folder)
