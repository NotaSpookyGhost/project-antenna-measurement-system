"""Explicit real COM6 stationary I/O acceptance; does not access positioner."""
from pathlib import Path
import sys,json,time
from datetime import datetime
root=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(root))
from python import nanovna_bridge as bridge
folder=root/'data'/'validation'/('acceptance_rf_'+datetime.now().strftime('%Y%m%d_%H%M%S'))
folder.mkdir(parents=True)
result={'port':'COM6','sweeps':[],'state':'RUNNING'}
def persist():
    (folder/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
try:
    result['connection']=bridge.connect('COM6')
    assert result['connection'].startswith('CONNECTED'),result['connection']
    result['identity']=bridge.identify()
    assert result['identity']['status']=='OK',result['identity']
    for points in (11,101,401):
        status=bridge.configure_sweep(2395e6,2405e6,points)
        assert status=='OK',status
        for repeat in range(3):
            start=time.monotonic(); raw=bridge.acquire_single()
            result['sweeps'].append(dict(points=points,repeat=repeat,elapsed=time.monotonic()-start,raw=raw))
            persist()
            assert raw['status']=='OK' and raw['complete'],raw['status']
            assert raw['points_received']==points
    result['state']='PASS'
finally:
    result['disconnect']=bridge.disconnect()
    persist()
    print(folder,flush=True)
    print(result['state'],len(result['sweeps']),'real sweeps',flush=True)
