"""Explicit stationary COM9 diagnosis: release/hold/release, no ZERO or motion."""
from pathlib import Path
from datetime import datetime
import json,re,time,serial
root=Path(__file__).resolve().parents[2]
folder=root/'data'/'validation'/('acceptance_encoder_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir(parents=True)
records=[]
with (folder/'raw.jsonl').open('w',encoding='utf-8') as log, serial.Serial('COM9',115200,timeout=.02) as port:
    time.sleep(1.5); port.reset_input_buffer()
    def send(command,phase):
        started=time.monotonic(); port.write((command+'\n').encode()); data=b''
        while time.monotonic()-started<3:
            data+=port.read(port.in_waiting or 1)
            if b'ESP32-ANTENNA> ' in data: break
        record=dict(phase=phase,command=command,elapsed=time.monotonic()-started,
                    response=data.decode('utf-8','replace'))
        records.append(record); log.write(json.dumps(record)+'\n'); log.flush()
        assert b'ESP32-ANTENNA> ' in data,'Missing command prompt'
        return record['response']
    try:
        send('HOLD OFF','setup')
        for phase,count in [('released_before',30),('held',100),('released_after',30)]:
            if phase=='held': assert 'HOLD ON OK' in send('HOLD ON',phase)
            if phase=='released_after': send('HOLD OFF',phase)
            for _ in range(count): send('POS',phase)
    finally:
        send('HOLD OFF','cleanup')
summary={}
for phase in ('released_before','held','released_after'):
    samples=[r['response'] for r in records if r['phase']==phase and r['command']=='POS']
    summary[phase]=dict(total=len(samples),
        pan_valid=sum('ENC_PAN_VALID:1' in r for r in samples),
        tilt_valid=sum('ENC_TILT_VALID:1' in r for r in samples))
(folder/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf-8')
print(folder,flush=True); print(json.dumps(summary),flush=True)
raise SystemExit(0 if all(s['pan_valid']==s['tilt_valid']==s['total'] for s in summary.values()) else 1)
