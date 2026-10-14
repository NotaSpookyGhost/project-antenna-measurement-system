"""Explicit Tilt PWM acceptance on COM5. No STEP, GOTO or ZERO commands.

Use --configure for temporary AS5600 CONF setup via SDA21/SCL22. OUT must
already be wired to GPIO23. This never sends any OTP/BURN command.
"""
import argparse
import datetime
import json
import pathlib
import re
import time
import serial


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',default='COM5')
    parser.add_argument('--configure',action='store_true')
    args=parser.parse_args()
    root=pathlib.Path(__file__).resolve().parents[3]
    folder=root/'data'/'validation'/('tilt_pwm_'+datetime.datetime.now().strftime('%Y%m%d_%H%M%S'))
    folder.mkdir(parents=True)
    report={'port':args.port,'phases':[],'release_confirmed':False,'passed':False}
    try:
        with (folder/'raw.log').open('w',encoding='utf-8') as log, serial.Serial(args.port,115200,timeout=5) as port:
            def send(name):
                port.write((name+'\n').encode('ascii'))
                text=port.read_until(b'ESP32-ANTENNA> ').decode('utf-8','replace')
                log.write(name+'\n'+text+'\n'); log.flush()
                if 'ESP32-ANTENNA>' not in text: raise RuntimeError('Missing firmware prompt: '+name)
                return text
            def field(text,key):
                found=re.search(r'\b'+key+r':\s*([^\s]+)',text)
                if not found: raise RuntimeError('Missing field '+key)
                return found[1]
            def phase(name,n,holding):
                angles=[]; period=[]; releases=[]
                for i in range(n):
                    if holding and i%20==0 and 'PONG' not in send('PING'):
                        raise RuntimeError('HOLD lease renewal failed')
                    text=send('TILT PWM CHECK')
                    if field(text,'FW')!='V4.1_PWM_HOLD' or field(text,'ENC_TILT_SOURCE')!='PWM':
                        raise RuntimeError('Wrong firmware; upload the tilt-pwm environment')
                    if field(text,'PWM_CONFIG')!='1': raise RuntimeError('PWM is not configured; use --configure with reliable I2C wiring')
                    if field(text,'HOLD')!=str(int(holding)): raise RuntimeError('Unexpected HOLD state')
                    releases.append(int(field(text,'RELEASES')))
                    if field(text,'ENC_TILT_VALID')=='1':
                        angle=float(field(text,'RAW_TILT'))
                        if not 0<=angle<360: raise RuntimeError('Invalid decoded PWM angle')
                        angles.append(angle); period.append(int(field(text,'PWM_PERIOD_US')))
                span=None
                if angles:
                    relative=[(angle-angles[0]+180)%360-180 for angle in angles]
                    span=max(relative)-min(relative)
                row={'state':name,'reads':n,'tilt_valid':len(angles),'circular_span_deg':span,
                     'release_count_start':releases[0],'release_count_end':releases[-1],
                     'period_us_range':[min(period,default=None),max(period,default=None)]}
                report['phases'].append(row); print(json.dumps(row),flush=True)
                return len(angles)==n and span is not None and span<=2 and releases[0]==releases[-1]
            time.sleep(1.8); port.reset_input_buffer()
            try:
                if 'HOLD OFF OK' not in send('HOLD OFF'): raise RuntimeError('Could not release drivers before configuration')
                if args.configure and 'TILT PWM CONFIG OK' not in send('TILT PWM CONFIG'):
                    raise RuntimeError('Configuration failed; check sensor-side 3.3 V and use short SDA/SCL wires')
                first=phase('released before',30,False)
                if 'HOLD ON OK' not in send('HOLD ON'): raise RuntimeError('HOLD ON rejected')
                held=phase('held',100,True)
                if 'HOLD OFF OK' not in send('HOLD OFF'): raise RuntimeError('HOLD OFF rejected')
                final=phase('released after',30,False)
                report['passed']=first and held and final
            finally:
                try: report['release_confirmed']='HOLD OFF OK' in send('HOLD OFF')
                except Exception as exc: report['cleanup_error']=str(exc)
    except Exception as exc:
        report['error']=str(exc); print('FAIL: '+str(exc),flush=True)
    report['passed']=report['passed'] and report['release_confirmed']
    (folder/'summary.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(('PASS' if report['passed'] else 'FAIL')+' Tilt PWM stationary acceptance; '+str(folder))
    return 0 if report['passed'] else 1


if __name__=='__main__':
    raise SystemExit(main())
