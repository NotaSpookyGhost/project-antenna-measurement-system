"""Independent forward error equations; never call calibration embed as oracle."""
import numpy as np


def wire(z):
    z=np.asarray(z,dtype=complex)
    return dict(real=z.real.tolist(),imag=z.imag.tolist())


def raw(f,g,t):
    ed,es,er,et=.02+.01j,.05-.02j,.9+.05j,.8-.1j
    m=ed+er*g/(1-es*g); q=et*t/(1-es*g)
    return dict(frequency_hz=list(f),s11_real=m.real.tolist(),s11_imag=m.imag.tolist(),
                s21_real=q.real.tolist(),s21_imag=q.imag.tolist(),complete=True,
                points_received=len(f),averages=4,mode='Mock',
                captured_at_utc='2026-10-15T00:00:00Z',acquisition_id='fixture')


def fixture(algorithm='SOL_1PORT'):
    f=list(range(2300000000,2500000001,20000000)); n=len(f)
    ones=np.ones(n,dtype=complex); zeros=np.zeros(n,dtype=complex)
    context=dict(mode='Mock',instrument_label='Synthetic VNA',device_variant=2,
        protocol_version=1,hardware_revision=2,firmware_major=1,firmware_minor=2,
        port_at_capture='MOCK_COM',rf_path_id='fixture',reference_plane='cable ends',
        mock_model='three-term-v1')
    models=dict(open=wire(ones),short=wire(-ones),load=wire(zeros),
                thru=dict(s11=wire(zeros),s21=wire(ones),s12=wire(ones),s22=wire(zeros)))
    standards={name:raw(f,g,zeros) for name,g in [('open',ones),('short',-ones),('load',zeros)]}
    if algorithm=='TR_ENHANCED_RESPONSE': standards['thru']=raw(f,zeros,ones)
    draft=dict(name='Synthetic calibration',algorithm=algorithm,frequency_hz=f,z0_ohm=50.,
        context=context,kit=dict(kind='IDEAL_50OHM',name='Ideal 50 ohm',
        assumption_note='Ideal standards assumed',source_files=[],models=models),standards=standards)
    gamma=.2+.1j+.04*np.sin(np.arange(n)); transmission=.4*np.exp(-.3j*np.arange(n))
    return draft,raw(f,gamma,transmission),gamma,transmission
