"""Finite, hardware-independent contracts shared by VNA adapters."""
import math
from numbers import Real


class VNAError(ValueError):
    def __init__(self, code, message):
        self.code = code
        super().__init__(message)


def _integer(value, name, low, high, code='INVALID_REQUEST'):
    if (isinstance(value, bool) or not isinstance(value, Real)
            or not math.isfinite(value) or int(value) != value
            or not low <= value <= high):
        raise VNAError(code, f'{name} must be an integer in {low}..{high}')
    return int(value)


def validate_request(request):
    try:
        r = dict(start_hz=_integer(request['start_hz'],'start_hz',50000,3000000000),
                 stop_hz=_integer(request['stop_hz'],'stop_hz',50000,3000000000),
                 points=_integer(request['points'],'points',2,401),
                 averages=_integer(request.get('averages',1),'averages',1,16),
                 mock_standard=request.get('mock_standard','DUT'))
        if r['stop_hz']-r['start_hz'] < r['points']-1:
            raise VNAError('INVALID_REQUEST','Sweep requires positive integer Hz step')
        if r['mock_standard'] not in ('DUT','OPEN','SHORT','LOAD','THRU'):
            raise VNAError('INVALID_REQUEST','Unknown mock standard')
        return r
    except (KeyError,TypeError) as exc:
        raise VNAError('INVALID_REQUEST','Invalid sweep request') from exc


def actual_grid(request):
    r=validate_request(request)
    step=(r['stop_hz']-r['start_hz'])//(r['points']-1)
    return [r['start_hz']+i*step for i in range(r['points'])]


def finite_vector(value, name, n=None):
    if not isinstance(value,(list,tuple)) or (n is not None and len(value)!=n):
        raise VNAError('INVALID_SWEEP',f'Invalid length for {name}')
    if any(isinstance(v,bool) or not isinstance(v,Real) or not math.isfinite(v) for v in value):
        raise VNAError('INVALID_SWEEP',f'{name} must contain finite numbers')
    return [float(v) for v in value]


def validate_raw(raw):
    try:
        freq=finite_vector(raw['frequency_hz'],'frequency_hz')
        n=len(freq)
        if not 2<=n<=401 or any(int(f)!=f or not 50000<=f<=3000000000 for f in freq):
            raise VNAError('INVALID_SWEEP','Invalid frequency grid')
        if any(b<=a for a,b in zip(freq,freq[1:])):
            raise VNAError('INVALID_SWEEP','Frequency grid must increase strictly')
        if raw['complete'] is not True or raw['points_received']!=n:
            raise VNAError('INVALID_SWEEP','Incomplete sweep')
        out={'frequency_hz':[int(f) for f in freq], 'points_received':n,'complete':True}
        for key in ('s11_real','s11_imag','s21_real','s21_imag'):
            out[key]=finite_vector(raw[key],key,n)
        out['averages']=_integer(raw['averages'],'averages',1,16,'INVALID_SWEEP')
        for key in ('captured_at_utc','acquisition_id','mode'):
            if not isinstance(raw[key],str) or not raw[key]:
                raise VNAError('INVALID_SWEEP',f'Missing {key}')
            out[key]=raw[key]
        if out['mode'] not in ('Real','Mock'):
            raise VNAError('INVALID_SWEEP','Invalid mode')
        return out
    except (KeyError,TypeError) as exc:
        raise VNAError('INVALID_SWEEP','Missing raw sweep fields') from exc


CONTEXT_FIELDS=('mode','instrument_label','device_variant','protocol_version',
                'hardware_revision','firmware_major','firmware_minor',
                'port_at_capture','rf_path_id','reference_plane','mock_model')


def validate_context(context):
    if not isinstance(context,dict) or set(context)!=set(CONTEXT_FIELDS):
        raise VNAError('CONTEXT_MISMATCH','Incomplete RF context')
    if context['mode'] not in ('Real','Mock'):
        raise VNAError('CONTEXT_MISMATCH','Invalid mode')
    for key in ('instrument_label','rf_path_id','reference_plane'):
        if not isinstance(context[key],str) or not context[key].strip():
            raise VNAError('CONTEXT_MISMATCH',f'Required RF context: {key}')
    for key in ('device_variant','protocol_version','hardware_revision','firmware_major','firmware_minor'):
        if context[key] is not None:
            _integer(context[key],key,0,255,'CONTEXT_MISMATCH')
    for key in ('port_at_capture','mock_model'):
        if not isinstance(context[key],str):
            raise VNAError('CONTEXT_MISMATCH',f'Invalid {key}')
    return dict(context)
