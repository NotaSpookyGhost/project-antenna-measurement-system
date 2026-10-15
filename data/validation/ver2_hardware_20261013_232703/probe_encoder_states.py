"""No STEP commands: compare encoder telemetry with both drivers released/held."""
import json,pathlib,re,time,serial
folder=pathlib.Path(__file__).resolve().parent
summaries=[]
with serial.Serial('COM5',115200,timeout=.02) as p, (folder/'encoder_states.log').open('w',encoding='utf-8') as log:
    time.sleep(2); p.reset_input_buffer()
    def send(cmd):
        p.write((cmd+'\n').encode()); end=time.monotonic()+4; data=b''
        while time.monotonic()<end:
            data+=p.read(p.in_waiting or 1)
            if b'ESP32-ANTENNA>' in data: break
        text=data.decode('utf-8','replace'); log.write(cmd+'\n'+text+'\n'); log.flush()
        assert b'ESP32-ANTENNA>' in data,text
        return text
    try:
        for command,count in [('HOLD OFF',25),('HOLD ON',100),('HOLD OFF',25)]:
            send(command); pan=tilt=0
            for i in range(count):
                text=send('POS'); pan+='ENC_PAN_VALID:1' in text; tilt+='ENC_TILT_VALID:1' in text
            result=dict(command=command,reads=count,pan_valid=pan,tilt_valid=tilt)
            summaries.append(result); print(result,flush=True)
    finally: send('HOLD OFF')
(folder/'encoder_states.json').write_text(json.dumps(summaries,indent=2),encoding='utf-8')
