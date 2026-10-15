import pathlib
import time
import serial

folder=pathlib.Path(__file__).resolve().parent
with (folder/'loaded_probe.log').open('w',encoding='utf-8') as log, serial.Serial('COM5',115200,timeout=5) as port:
    time.sleep(1.8)
    boot=port.read(port.in_waiting).decode('utf-8','replace')
    log.write('BOOT\n'+boot+'\n')
    port.reset_input_buffer()
    def send(command):
        port.write((command+'\n').encode())
        text=port.read_until(b'ESP32-ANTENNA> ').decode('utf-8','replace')
        log.write(command+'\n'+text+'\n'); log.flush()
        assert 'ESP32-ANTENNA>' in text,text
        return text
    try:
        assert 'HOLD OFF OK' in send('HOLD OFF')
        text=send('TILT PWM CHECK')
        assert 'FW:V4.1_PWM_HOLD' in text and 'ENC_TILT_SOURCE:PWM' in text and 'PWM_PIN:23' in text,text
        assert 'HOLD:0' in text and 'AGC_TILT_AVAILABLE:0' in text,text
        print(text)
        print('PASS: loaded PWM firmware identified; diagnostic did not command motion.')
    finally:
        assert 'HOLD OFF OK' in send('HOLD OFF')
