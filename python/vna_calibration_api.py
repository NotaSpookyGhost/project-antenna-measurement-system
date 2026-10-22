"""Plain JSON calibration boundary for MATLAB. Never opens instruments."""
import logging
import threading
import skrf
from python.vna_contracts import VNAError,validate_raw
from python.vna_profile import (ENGINE,canonical_json,parse_json,create_profile,
    validate_profile,save_profile,load_profile)
from python.vna_calibration import build_engine,apply_engine
from python.vna_kit import load_kit

_lock=threading.RLock()
_cached_text=None
_cached_profile=None
_cached_engine=None


def _envelope(operation):
    try:
        return canonical_json(dict(status='OK',payload=operation()))
    except VNAError as exc:
        return canonical_json(dict(status='ERROR',code=exc.code,message=str(exc)))
    except ImportError as exc:
        return canonical_json(dict(status='ERROR',code='BACKEND_UNAVAILABLE',message=str(exc)))
    except (OSError,ValueError,TypeError,KeyError) as exc:
        return canonical_json(dict(status='ERROR',code='INVALID_PROFILE',message=str(exc)))
    except Exception as exc:
        logging.exception('Unexpected calibration adapter failure')
        return canonical_json(dict(status='ERROR',code='INVALID_PROFILE',message=str(exc)))


def backend_info_json():
    return _envelope(lambda:dict(ENGINE,version=skrf.__version__))


def kit_json(paths_json,frequency_json,algorithm,name):
    return _envelope(lambda:load_kit(parse_json(paths_json),parse_json(frequency_json),algorithm,name))


def solve_json(draft_json):
    return _envelope(lambda:dict(profile_json=canonical_json(create_profile(parse_json(draft_json)))))


def apply_json(profile_json,raw_json):
    def operation():
        global _cached_text,_cached_profile,_cached_engine
        raw=validate_raw(parse_json(raw_json))
        with _lock:
            if profile_json!=_cached_text:
                p=validate_profile(parse_json(profile_json)); engine=build_engine(p)
                _cached_text=profile_json; _cached_profile=p; _cached_engine=engine
            if raw['mode']!=_cached_profile['context']['mode']:
                raise VNAError('CONTEXT_MISMATCH','Raw and profile modes differ')
            return apply_engine(_cached_engine,raw,_cached_profile['algorithm'])
    return _envelope(operation)


def save_json(path,profile_json):
    def operation():
        p=parse_json(profile_json); save_profile(path,p)
        return dict(path=path,profile_id=p['profile_id'])
    return _envelope(operation)


def load_json(path):
    return _envelope(lambda:dict(profile_json=canonical_json(load_profile(path))))
