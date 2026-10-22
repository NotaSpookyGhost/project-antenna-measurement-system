"""Calibration kit numerical models. No device I/O."""
import numpy as np
import hashlib
from pathlib import Path
import skrf as rf
from python.vna_contracts import VNAError


def split(z):
    z=np.asarray(z,dtype=complex)
    return {'real':z.real.tolist(),'imag':z.imag.tolist()}


def ideal_kit(frequency_hz):
    one=np.ones(len(frequency_hz),complex); zero=np.zeros_like(one)
    return dict(kind='IDEAL_50OHM',name='Ideal 50 ohm',
        assumption_note='Ideal standards assumed; not independently characterized',source_files=[],
        models=dict(open=split(one),short=split(-one),load=split(zero),
                    thru=dict(s11=split(zero),s21=split(one),s12=split(one),s22=split(zero))))


def load_kit(paths,frequency_hz,algorithm,name):
    if algorithm not in ('SOL_1PORT','TR_ENHANCED_RESPONSE'):
        raise VNAError('INVALID_PROFILE','Unsupported calibration algorithm')
    models={}; sources=[]
    names=['open','short','load']+(['thru'] if algorithm=='TR_ENHANCED_RESPONSE' else [])
    for standard in names:
        try:
            path=Path(paths[standard]); contents=path.read_bytes()
            network=rf.Network(str(path))
        except (OSError,KeyError,ValueError) as exc:
            raise VNAError('INVALID_PROFILE',f'Cannot read {standard} kit file: {exc}') from exc
        ports=2 if standard=='thru' else 1
        if network.nports!=ports or not np.array_equal(network.frequency.f,frequency_hz):
            raise VNAError('GRID_MISMATCH',f'{standard} ports/grid do not match')
        if not np.all(network.z0==50) or not np.all(np.isfinite(network.s)):
            raise VNAError('INVALID_PROFILE',f'{standard} requires finite S parameters and real 50 ohm z0')
        if ports==1: models[standard]=split(network.s[:,0,0])
        else:
            models['thru']={key:split(network.s[:,a,b]) for key,a,b in
                            [('s11',0,0),('s21',1,0),('s12',0,1),('s22',1,1)]}
        sources.append(dict(basename=path.name,sha256=hashlib.sha256(contents).hexdigest()))
    return dict(kind='CHARACTERIZED',name=name,assumption_note='Imported characterized models',
                source_files=sources,models=models)
