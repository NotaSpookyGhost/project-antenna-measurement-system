import pathlib
import re
import time
import serial

folder=pathlib.Path(__file__).resolve().parent
with (folder/'final_probe.log').open('w',encoding='utf-8') as log, serial.Serial('COM5',115200,timeout=5) as port:
    time.sleep(1.8); port.reset_input_buffer()
    def send(command):
        port.write((command+'\n').encode())
        text=port.read_until(b'ESP32-ANTENNA> ').decode('utf-8','replace')
        log.write(command+'\n'+text+'\n'); log.flush()
        assert 'ESP32-ANTENNA>' in text
        return text
    try:
        assert 'HOLD OFF OK' in send('HOLD OFF')
        first=send('POS')
        assert 'FW:V4.0_HOLD' in first and 'ENC_TILT_VALID:1' in first
        assert 'ENC_TILT_SOURCE:PWM' not in first and 'PWM_CONFIG:' not in first
        assert 'HOLD:0' in first and 'CAL_REQUIRED:1' in first
        for name in ('TILT PWM CHECK','TILT PWM CONFIG','TILT PWM REG'):
            assert 'ERR: UNSUPPORTED_COMMAND; TILT USES I2C' in send(name)
        last=send('POS')
        for key in ('PAN','TILT','HOLD','RELEASES'):
            pattern=r'(?<![A-Z_])'+key+r':\s*([^\s]+)'
            assert re.search(pattern,first)[1]==re.search(pattern,last)[1]
        print(last)
        print('PASS: loaded I2C-only firmware, valid Tilt, retired commands rejected, released.')
    finally:
        assert 'HOLD OFF OK' in send('HOLD OFF')
