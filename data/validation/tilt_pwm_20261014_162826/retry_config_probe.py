import pathlib
import time
import serial

folder=pathlib.Path(__file__).resolve().parent
with (folder/'config_retries.log').open('w',encoding='utf-8') as log, serial.Serial('COM5',115200,timeout=5) as port:
    time.sleep(1.8); port.reset_input_buffer()
    def send(name):
        port.write((name+'\n').encode())
        text=port.read_until(b'ESP32-ANTENNA> ').decode('utf-8','replace')
        log.write(name+'\n'+text+'\n'); log.flush()
        assert 'ESP32-ANTENNA>' in text,text
        return text
    try:
        assert 'HOLD OFF OK' in send('HOLD OFF')
        for index in range(3):
            result=send('TILT PWM CONFIG')
            print('Attempt '+str(index+1)+': '+result.strip(),flush=True)
            time.sleep(.1)
            snapshot=send('TILT PWM CHECK')
            print(snapshot.strip(),flush=True)
            if 'TILT PWM CONFIG OK' in result: break
    finally:
        assert 'HOLD OFF OK' in send('HOLD OFF')
