"""Bounded physical hold observation: no ZERO, PAN, TILT or GOTO commands."""
from pathlib import Path
import json
import re
import time
import serial

folder = Path(__file__).resolve().parent
samples = []
report = {'motionCommandsSent': False, 'holdLimitSeconds': 120}
with (folder / 'hold.log').open('w', encoding='utf-8') as log, serial.Serial('COM5',115200,timeout=.1) as port:
    def send(command):
        port.write((command+'\n').encode())
        result=b''
        deadline=time.monotonic()+4
        while time.monotonic()<deadline and b'ESP32-ANTENNA>' not in result:
            result+=port.read(port.in_waiting or 1)
        text=result.decode(errors='replace')
        log.write(f'{time.time():.3f} > {command}\n{text}\n'); log.flush()
        if b'ESP32-ANTENNA>' not in result or b'ERR:' in result:
            raise RuntimeError(text)
        return text
    time.sleep(2)
    port.reset_input_buffer()
    try:
        baseline=send('POS')
        if 'FW:V4.0_HOLD' not in baseline or 'HOLD_CAP:1' not in baseline:
            raise RuntimeError('Unexpected firmware: '+baseline)
        report['before']=baseline
        send('HOLD ON')
        started=time.monotonic()
        print('HOLD ON active for observation, up to 120 seconds. No rotation.',flush=True)
        while time.monotonic()-started < 120 and not (folder/'stop_hold').exists():
            response=send('POS')
            sample={'elapsed':time.monotonic()-started,'response':response}
            samples.append(sample)
            if not re.search(r'\bHOLD:1\b',response):
                raise RuntimeError('Firmware lost hold: '+response)
            report['samples']=samples
            (folder/'hold.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
            if len(samples)%4==1: print(response.strip(),flush=True)
            time.sleep(5)
    except Exception as exc:
        report['error']=str(exc)
        raise
    finally:
        try:
            send('HOLD OFF')
            report['final']=send('POS')
            report['releaseConfirmed']=bool(re.search(r'\bHOLD:0\b',report['final']))
        finally:
            report['samples']=samples
            (folder/'hold.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('HOLD OFF; COM5 closed.',flush=True)
