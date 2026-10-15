"""Explicit hardware test: released/held/released; no STEP, GOTO or ZERO."""
import json
import math
from pathlib import Path
import re
import time
import serial

folder = Path(__file__).resolve().parent
report = {}
with (folder / 'stationary.log').open('w', encoding='utf-8') as log, serial.Serial('COM5', 115200, timeout=.05) as port:
    def send(command):
        port.write((command + '\n').encode())
        deadline = time.monotonic() + 4
        raw = b''
        while time.monotonic() < deadline and b'ESP32-ANTENNA>' not in raw:
            raw += port.read(port.in_waiting or 1)
        response = raw.decode('utf-8', errors='replace')
        log.write(f'{time.monotonic():.4f} > {command}\n{response}\n')
        log.flush()
        if b'ESP32-ANTENNA>' not in raw:
            raise RuntimeError('Missing prompt: ' + response)
        return response

    time.sleep(2)
    port.reset_input_buffer()
    try:
        for name, command, count, hold in [('released_before','HOLD OFF',30,0), ('held','HOLD ON',100,1), ('released_after','HOLD OFF',30,0)]:
            send(command)
            time.sleep(.3)
            samples = []
            for i in range(count):
                response = send('POS')
                values = {}
                for key in ('PAN','TILT','RAW_PAN','RAW_TILT','HOLD','RELEASES','ENC_PAN_VALID','ENC_TILT_VALID'):
                    found = re.search(r'\b' + key + r':\s*(-?[\d.]+)', response)
                    values[key] = float(found[1]) if found else None
                samples.append(values)
                time.sleep(.05)
            result = {'count':count,'samples':samples,'hold_matches':all(s['HOLD']==hold for s in samples)}
            for axis in ('PAN','TILT'):
                vals = [s['RAW_'+axis] for s in samples if s['ENC_'+axis+'_VALID']==1 and s['RAW_'+axis] is not None and 0<=s['RAW_'+axis]<360]
                relative = [(v-vals[0]+180)%360-180 for v in vals] if vals else []
                result[axis] = {'valid':len(vals),'raw_min':min(vals,default=None),'raw_max':max(vals,default=None), 'span_deg':max(relative)-min(relative) if relative else None}
            report[name] = result
            (folder / 'stationary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
            print(name, {k:v for k,v in result.items() if k!='samples'},flush=True)
    finally:
        send('HOLD OFF')
print('COM5 closed; no motion commands sent.')
