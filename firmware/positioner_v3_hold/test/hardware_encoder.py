"""Explicit COM5 stationary encoder acceptance. No STEP commands; holds both motors."""
import datetime
import argparse
import pathlib
import re
import serial
import time

root = pathlib.Path(__file__).resolve().parents[3]
parser = argparse.ArgumentParser()
parser.add_argument('--axis', choices=('both','pan','tilt'), default='both')
selected_axis = parser.parse_args().axis
folder = root / 'data' / 'validation' / ('as5600_v32_' + datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir(parents=True)
with (folder / 'stationary.log').open('w', encoding='utf-8') as log, serial.Serial('COM5', 115200, timeout=.02) as port:
    def send(cmd):
        start = time.monotonic()
        port.write((cmd+'\n').encode())
        data = b''
        while time.monotonic()-start < 3:
            data += port.read(port.in_waiting or 1)
            if b'ESP32-ANTENNA> ' in data:
                break
        text = data.decode('utf-8','replace')
        elapsed = time.monotonic()-start
        log.write(f'{cmd} elapsed={elapsed:.4f}\n{text}\n'); log.flush()
        assert 'ESP32-ANTENNA> ' in text, text
        return text, elapsed
    time.sleep(2); port.reset_input_buffer()
    initial = send('POS')[0]
    assert any(version in initial for version in ('FW:V3.2_HOLD', 'FW:V4.0_HOLD'))
    baseline_releases = int(re.search(r'RELEASES:(\d+)', initial)[1])
    try:
        send('HOLD ON')
        valid = 0; maximum = 0; angles = [[], []]
        for _ in range(100):
            text, elapsed = send('POS')
            maximum = max(maximum, elapsed)
            assert 'HOLD:1' in text and int(re.search(r'RELEASES:(\d+)', text)[1]) == baseline_releases, text
            pan_ok = 'ENC_PAN_VALID:1' in text
            tilt_ok = 'ENC_TILT_VALID:1' in text
            ok = pan_ok and tilt_ok if selected_axis == 'both' else (pan_ok if selected_axis == 'pan' else tilt_ok)
            valid += ok
            if ok:
                for sensor_index,key in enumerate(('RAW_PAN','RAW_TILT')):
                    if (pan_ok,tilt_ok)[sensor_index]:
                        angles[sensor_index].append(float(re.search(key+r':\s*([\d.-]+)',text)[1]))
        summary=f'{selected_axis} feedback valid {valid}/100; max POS latency {maximum:.4f}s; ranges={[(min(a,default=None),max(a,default=None)) for a in angles]}'
        print(summary); log.write(summary+'\n')
        assert valid == 100, 'Encoder feedback acceptance failed; see raw log'
    finally:
        send('HOLD OFF')
print(folder)
