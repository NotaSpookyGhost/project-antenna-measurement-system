"""Self-contained versioned calibration records with verified atomic persistence."""
import copy
from datetime import datetime,timezone
import hashlib
import json
import os
from pathlib import Path
import re
import tempfile
from uuid import UUID,uuid4
import numpy as np
from python.vna_contracts import VNAError,validate_context,validate_raw
from python.vna_calibration import build_engine,coefficients_to_wire,unsplit

MAX_BYTES=10*1024*1024
ENGINE=dict(name='scikit-rf',version='2.1.0',adapter_version=1)
FIELDS={'schema_version','profile_id','name','created_at_utc','algorithm','engine',
        'frequency_hz','z0_ohm','context','kit','standards','coefficients','validation','content_sha256'}


def canonical_json(value):
    try:
        return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False,allow_nan=False)
    except (TypeError,ValueError) as exc:
        raise VNAError('INVALID_PROFILE','Profile must contain finite JSON values') from exc


def _pairs(pairs):
    result={}
    for key,value in pairs:
        if key in result: raise VNAError('INVALID_PROFILE','Duplicate JSON key')
        result[key]=value
    return result


def parse_json(text):
    if not isinstance(text,str) or len(text.encode('utf-8'))>MAX_BYTES:
        raise VNAError('INVALID_PROFILE','JSON exceeds 10 MiB or is not text')
    def reject(value): raise VNAError('INVALID_PROFILE',f'Nonstandard JSON number {value}')
    try:
        return json.loads(text,parse_constant=reject,object_pairs_hook=_pairs)
    except (ValueError,TypeError) as exc:
        raise VNAError('INVALID_PROFILE','Malformed JSON') from exc


def _digest(profile):
    return hashlib.sha256(canonical_json({k:v for k,v in profile.items() if k!='content_sha256'}).encode('utf-8')).hexdigest()


def _check_inputs(p):
    validate_context(p['context'])
    names={'open','short','load'}|({'thru'} if p['algorithm']=='TR_ENHANCED_RESPONSE' else set())
    if set(p['standards'])!=names:
        raise VNAError('MISSING_STANDARD','Incorrect standard set')
    for raw in p['standards'].values():
        if validate_raw(raw)!=raw or raw['mode']!=p['context']['mode']:
            raise VNAError('INVALID_PROFILE','Standards require finite raw projection in the profile mode')
    kit=p['kit']
    if set(kit)!={'kind','name','assumption_note','source_files','models'} or kit['kind'] not in ('IDEAL_50OHM','CHARACTERIZED'):
        raise VNAError('INVALID_PROFILE','Invalid kit schema')
    if not isinstance(kit['name'],str) or not kit['name'].strip() or not isinstance(kit['assumption_note'],str):
        raise VNAError('INVALID_PROFILE','Invalid kit name/assumptions')
    if not names.issubset(kit['models']) or set(kit['models'])-{'open','short','load','thru'}:
        raise VNAError('INVALID_PROFILE','Missing or unknown kit models')
    for source in kit['source_files']:
        if (set(source)!={'basename','sha256'} or not isinstance(source['basename'],str)
                or '/' in source['basename'] or '\\' in source['basename']
                or not re.fullmatch('[0-9a-f]{64}',source['sha256'])):
            raise VNAError('INVALID_PROFILE','Invalid kit provenance')


def create_profile(draft):
    p=copy.deepcopy(draft)
    p['standards']={name:validate_raw(raw) for name,raw in p['standards'].items()}
    _check_inputs(p)
    engine=build_engine(p)
    p.update(schema_version=1,profile_id=str(uuid4()),created_at_utc=datetime.now(timezone.utc).isoformat(),
             engine=dict(ENGINE),coefficients=coefficients_to_wire(engine),
             validation=dict(status='NOT_CHECKED',evidence_ids=[],note=''))
    p['content_sha256']=_digest(p)
    return validate_profile(p)


def validate_profile(profile):
    try:
        p=parse_json(canonical_json(profile))
        if set(p)!=FIELDS or type(p['schema_version']) is not int or p['schema_version']!=1:
            raise VNAError('INVALID_PROFILE','Unknown profile schema/fields')
        if p['engine']!=ENGINE:
            raise VNAError('ENGINE_VERSION_MISMATCH','Profile requires scikit-rf 2.1.0 adapter 1')
        if UUID(p['profile_id']).version!=4 or not p['name'].strip():
            raise VNAError('INVALID_PROFILE','Invalid profile identity')
        if datetime.fromisoformat(p['created_at_utc'].replace('Z','+00:00')).tzinfo is None:
            raise VNAError('INVALID_PROFILE','Timestamp must include UTC offset')
        if p['content_sha256']!=_digest(p):
            raise VNAError('INVALID_PROFILE','Profile content hash mismatch')
        validation=p['validation']
        if (set(validation)!={'status','evidence_ids','note'} or validation['status'] not in ('NOT_CHECKED','CHECKED')
                or not isinstance(validation['evidence_ids'],list) or not isinstance(validation['note'],str)):
            raise VNAError('INVALID_PROFILE','Invalid validation evidence')
        if validation['status']=='CHECKED' and not validation['evidence_ids']:
            raise VNAError('INVALID_PROFILE','Checked profiles require independent evidence IDs')
        _check_inputs(p)
        actual=coefficients_to_wire(build_engine(p)); stored=p['coefficients']; n=len(p['frequency_hz'])
        if set(actual)!=set(stored): raise VNAError('INVALID_PROFILE','Coefficient names differ from solver')
        for key in actual:
            if not np.allclose(unsplit(actual[key],n),unsplit(stored[key],n),rtol=1e-10,atol=1e-12):
                raise VNAError('INVALID_PROFILE','Stored coefficients do not reproduce standards/models')
        return p
    except VNAError:
        raise
    except (ValueError,TypeError,KeyError,AttributeError) as exc:
        raise VNAError('INVALID_PROFILE',f'Invalid profile: {exc}') from exc


def save_profile(path,profile):
    payload=canonical_json(validate_profile(profile)).encode('utf-8')
    target=Path(path); temporary=None
    try:
        with tempfile.NamedTemporaryFile(dir=target.parent,prefix='.'+target.name+'.',suffix='.tmp',delete=False) as stream:
            temporary=Path(stream.name); stream.write(payload); stream.flush(); os.fsync(stream.fileno())
        os.replace(temporary,target)
    finally:
        if temporary is not None and temporary.exists(): temporary.unlink()


def load_profile(path):
    target=Path(path)
    if target.stat().st_size>MAX_BYTES: raise VNAError('INVALID_PROFILE','Profile exceeds 10 MiB')
    return validate_profile(parse_json(target.read_text(encoding='utf-8')))
