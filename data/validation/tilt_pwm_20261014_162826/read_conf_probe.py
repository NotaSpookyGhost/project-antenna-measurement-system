import pathlib
import time
import serial

folder=pathlib.Path(__file__).resolve().parent
with (folder/'configuration_details.log').open('w',encoding='utf-8') as log, serial.Serial('COM5',115200,timeout=5) as port:
    time.sleep(1.8); port.reset_input_buffer()
    def send(name):
        port.write((name+'\n').encode())
        text=port.read_until(b'ESP32-ANTENNA> ').decode('utf-8','replace')
        log.write(name+'\n'+text+'\n'); log.flush()
        assert 'ESP32-ANTENNA>' in text,text
        print(name+': '+text.strip(),flush=True)
        return text
    try:
        assert 'HOLD OFF OK' in send('HOLD OFF')
        for _ in range(3): send('TILT PWM REG')
        send('TILT PWM CONFIG')
        for _ in range(3): send('TILT PWM REG')
        send('TILT PWM CHECK')
    finally:
        assert 'HOLD OFF OK' in send('HOLD OFF')
