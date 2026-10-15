import pathlib,serial,time,collections,re,subprocess,json
folder=pathlib.Path(__file__).resolve().parent
results=[]
try:
    with serial.Serial('COM5',115200,timeout=.05) as p,(folder/'diagnostic.log').open('w',encoding='utf-8') as log:
        time.sleep(2); p.reset_input_buffer()
        def send(cmd):
            p.write((cmd+'\n').encode()); end=time.monotonic()+5; b=b''
            while time.monotonic()<end:
                b+=p.read(p.in_waiting or 1)
                if b'ESP32-ANTENNA>' in b: break
            s=b.decode('utf-8','replace'); log.write(cmd+'\n'+s+'\n'); log.flush()
            assert b'ESP32-ANTENNA>' in b,s
            return s
        assert 'FW:V4.0_DIAG_NO_MOTION' in send('POS')
        try:
            for state in ['HOLD OFF','HOLD ON']:
                send(state); raw=send('SENSOR DIAG')
                for axis in ['PAN','TILT']:
                    rows=[x for x in raw.splitlines() if x.startswith('DIAG AXIS:'+axis+' ')]
                    assert len(rows)==20,(axis,len(rows),raw)
                    summary=dict(state=state,axis=axis,reads=len(rows),transferred=sum('XFER:1 ' in x for x in rows),magnet_detected=sum('MD:1 ' in x for x in rows),stages=dict(collections.Counter(re.search(r'STAGE:(\S+)',x)[1] for x in rows)))
                    results.append(summary); print(summary,flush=True); print(rows[0],flush=True)
        finally: send('HOLD OFF')
    (folder/'diagnostic_summary.json').write_text(json.dumps(results,indent=2),encoding='utf-8')
finally:
    # Restore the unmodified production build even if diagnostic acquisition fails.
    print('Restoring production V4.0_HOLD firmware...',flush=True)
    with (folder/'restore.log').open('w',encoding='utf-8') as restorelog:
        r=subprocess.run([r'C:\Users\Spooky Laptop\.platformio\penv\Scripts\platformio.exe','run','-d','firmware/positioner_v3_hold','-t','upload','--upload-port','COM5'],stdout=restorelog,stderr=subprocess.STDOUT)
    print('RESTORE_EXIT',r.returncode,flush=True)
    if r.returncode: raise RuntimeError('Production firmware restore failed; see restore.log')
    with serial.Serial('COM5',115200,timeout=.05) as p:
        time.sleep(2); p.reset_input_buffer(); p.write(b'POS\n'); end=time.monotonic()+4; data=b''
        while time.monotonic()<end:
            data+=p.read(p.in_waiting or 1)
            if b'ESP32-ANTENNA>' in data: break
        text=data.decode('utf-8','replace'); print(text,flush=True)
        (folder/'restored_pos.log').write_text(text,encoding='utf-8')
        assert 'FW:V4.0_HOLD ' in text and 'FW:V4.0_DIAG' not in text
