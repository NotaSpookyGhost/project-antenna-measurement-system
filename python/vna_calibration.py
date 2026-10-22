"""scikit-rf adapter for SOL and forward T/R enhanced response only."""
import numpy as np
import skrf as rf
from skrf.calibration import OnePort,TwoPortOnePath
from python.vna_contracts import VNAError,finite_vector,validate_raw
from python.vna_kit import split


def unsplit(value,n):
    try:
        return np.asarray(finite_vector(value['real'],'real',n))+1j*np.asarray(finite_vector(value['imag'],'imag',n))
    except (KeyError,TypeError) as exc:
        raise VNAError('INVALID_PROFILE','Invalid complex model') from exc


def _network(f,s):
    return rf.Network(frequency=rf.Frequency.from_f(f,unit='Hz'),s=s,z0=50)


def _require_version():
    if rf.__version__!='2.1.0':
        raise VNAError('ENGINE_VERSION_MISMATCH','This adapter requires scikit-rf 2.1.0 at runtime')


def build_engine(draft):
    _require_version()
    algorithm=draft.get('algorithm')
    if algorithm not in ('SOL_1PORT','TR_ENHANCED_RESPONSE') or draft.get('z0_ohm')!=50:
        raise VNAError('INVALID_PROFILE','Unsupported algorithm or reference impedance')
    f=draft['frequency_hz']; n=len(f)
    names=['short','open','load']+(['thru'] if algorithm=='TR_ENHANCED_RESPONSE' else [])
    try:
        raws=[validate_raw(draft['standards'][name]) for name in names]
    except KeyError as exc:
        raise VNAError('MISSING_STANDARD',f'Missing standard {exc}') from exc
    if any(r['frequency_hz']!=f for r in raws):
        raise VNAError('GRID_MISMATCH','Standards must share exact actual Hz grid')
    models=draft['kit']['models']
    gamma=np.asarray([unsplit(models[name],n) for name in names[:3]])
    measured=np.asarray([np.array(r['s11_real'])+1j*np.array(r['s11_imag']) for r in raws[:3]])
    for k in range(n):
        if min(abs(gamma[a,k]-gamma[b,k]) for a,b in [(0,1),(0,2),(1,2)])<=1e-6:
            raise VNAError('DEGENERATE_STANDARDS','Ideal OSL models are indistinguishable')
        matrix=np.column_stack((np.ones(3),gamma[:,k],gamma[:,k]*measured[:,k]))
        if np.linalg.cond(matrix)>1e12:
            raise VNAError('DEGENERATE_STANDARDS','OSL fit is ill-conditioned')
    measured_networks=[]; ideal_networks=[]
    for i,name in enumerate(names):
        r=raws[i]; m=np.array(r['s11_real'])+1j*np.array(r['s11_imag'])
        if algorithm=='SOL_1PORT':
            measured_networks.append(_network(f,m[:,None,None]))
            ideal_networks.append(_network(f,gamma[i,:,None,None]))
        else:
            s=np.zeros((n,2,2),complex); s[:,0,0]=m
            s[:,1,0]=np.array(r['s21_real'])+1j*np.array(r['s21_imag'])
            ideal=np.zeros_like(s)
            if name=='thru':
                if np.any(np.abs(s[:,1,0])<1e-8):
                    raise VNAError('DEGENERATE_STANDARDS','Thru transmission is too small')
                for key,a,b in [('s11',0,0),('s21',1,0),('s12',0,1),('s22',1,1)]:
                    ideal[:,a,b]=unsplit(models['thru'][key],n)
            else:
                # Numerical mirror required by TwoPortOnePath's reverse fit.
                # These are ideal-model entries, never measured reverse channels.
                ideal[:,0,0]=gamma[i]; ideal[:,1,1]=gamma[i]
            measured_networks.append(_network(f,s)); ideal_networks.append(_network(f,ideal))
    try:
        if algorithm=='SOL_1PORT':
            engine=OnePort(measured=measured_networks,ideals=ideal_networks)
        else:
            engine=TwoPortOnePath(measured=measured_networks,ideals=ideal_networks,source_port=1,n_thrus=1)
        engine.run()
        if any(not np.all(np.isfinite(c)) for c in engine.coefs.values()):
            raise VNAError('DEGENERATE_STANDARDS','Nonfinite calibration coefficients')
        return engine
    except (np.linalg.LinAlgError,ZeroDivisionError) as exc:
        raise VNAError('DEGENERATE_STANDARDS',str(exc)) from exc


def coefficients_to_wire(engine):
    return {name:split(value) for name,value in engine.coefs.items()}


def apply_engine(engine,raw,algorithm):
    _require_version()
    raw=validate_raw(raw); f=raw['frequency_hz']; n=len(f)
    if not np.array_equal(engine.frequency.f,np.asarray(f)):
        raise VNAError('GRID_MISMATCH','Profile and raw frequency grid differ')
    a=np.array(raw['s11_real'])+1j*np.array(raw['s11_imag'])
    b=np.array(raw['s21_real'])+1j*np.array(raw['s21_imag'])
    if algorithm=='SOL_1PORT':
        result=engine.apply_cal(_network(f,a[:,None,None])).s
        s11=result[:,0,0]; s21=None; state={'s11':'SOL','s21':'RAW'}
    elif algorithm=='TR_ENHANCED_RESPONSE':
        s=np.zeros((n,2,2),complex); s[:,0,0]=a; s[:,1,0]=b
        result=engine.apply_cal(_network(f,s)).s
        s11=result[:,0,0]; s21=result[:,1,0]
        state={'s11':'TR_ENHANCED_RESPONSE','s21':'TR_ENHANCED_RESPONSE'}
    else:
        raise VNAError('INVALID_PROFILE','Unsupported calibration algorithm')
    if not np.all(np.isfinite(s11)) or (s21 is not None and not np.all(np.isfinite(s21))):
        raise VNAError('INVALID_SWEEP','Correction produced nonfinite samples')
    return dict(corrected_s11=split(s11),corrected_s21=None if s21 is None else split(s21),channel_state=state)
