"""Stationary COM5 test: diagnostic firmware only; enables both drivers, no motion."""
import datetime
import pathlib
import re
import serial
import time

root = pathlib.Path(__file__).resolve().parents[2]
folder = root / 'data' / 'validation' / ('as5600_qualified_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir(parents=True)
with (folder / 'serial.log').open('w', encoding='utf-8') as log, serial.Serial('COM5', 115200, timeout=.05) as port:
    def command(cmd):
        port.write((cmd + '\n').encode())
        deadline = time.monotonic() + 15
        data = b''
        while time.monotonic() < deadline:
            data += port.read(port.in_waiting or 1)
            if b'DIAG> ' in data:
                break
        text = data.decode('utf-8', 'replace')
        log.write(cmd + '\n' + text + '\n'); log.flush()
        assert 'DIAG> ' in text, text
        return text
    time.sleep(2); port.reset_input_buffer()
    assert 'ERR' in command('POS'), 'Expected diagnostic firmware'
    results = {}
    try:
        for mask in (0, 3):
            command(f'H {mask}')
            samples = []
            for _ in range(10):
                reply = command('D 6 10000')
                for line in reply.splitlines():
                    if line.startswith('SAMPLE'):
                        samples.append(dict(re.findall(r'(\w+)=([^ ]+)', line)))
            results[mask] = samples
    finally:
        command('H 0')
for mask, samples in results.items():
    for axis in (0, 1):
        subset = [s for s in samples if int(s['axis']) == axis]
        good = [s for s in subset if s['err'] == '0']
        raw = [int(s['raw']) for s in good]
        print(f'mask={mask} axis={axis} valid={len(good)}/{len(subset)} range={min(raw,default=None)}..{max(raw,default=None)} max_us={max(int(s["us"]) for s in subset)}')
print(folder)
