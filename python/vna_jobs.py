"""One cooperative sweep worker; polling never waits for instrument I/O."""
from contextlib import contextmanager
import copy
from datetime import datetime,timezone
import threading
from uuid import uuid4
from python.vna_contracts import VNAError,actual_grid,validate_raw,validate_request


class JobManager:
    def __init__(self,acquire_once,configure,io_lock):
        self._acquire=acquire_once; self._configure=configure; self._io=io_lock
        self._mutex=threading.RLock(); self._job=None
        self._cancel=threading.Event(); self._worker_ident=None

    @contextmanager
    def hardware_guard(self):
        with self._mutex:
            if (self._job and self._job['state']=='RUNNING'
                    and threading.get_ident()!=self._worker_ident):
                raise VNAError('BUSY','A VNA sweep job owns the instrument')
            if not self._io.acquire(blocking=False):
                raise VNAError('BUSY','VNA hardware operation is in progress')
        try:
            yield
        finally:
            self._io.release()

    def start(self,request,generation):
        request=validate_request(request)
        with self._mutex:
            if self._job and self._job['state']=='RUNNING':
                raise VNAError('BUSY','A sweep job is already running')
            if not self._io.acquire(blocking=False):
                raise VNAError('BUSY','VNA I/O is in use')
            self._io.release()
            self._cancel=threading.Event()
            self._job=dict(job_id=str(uuid4()),generation=int(generation),state='RUNNING')
            result=copy.deepcopy(self._job)
            threading.Thread(target=self._run,args=(copy.deepcopy(request),),daemon=True).start()
            return result

    def poll(self,job_id):
        with self._mutex:
            if not self._job or self._job['job_id']!=job_id:
                raise VNAError('INVALID_REQUEST','Unknown VNA job')
            return copy.deepcopy(self._job)

    def cancel(self,job_id):
        with self._mutex:
            self.poll(job_id)
            if self._job['state']=='RUNNING': self._cancel.set()
            return copy.deepcopy(self._job)

    def _check_cancel(self):
        if self._cancel.is_set(): raise VNAError('CANCELLED','Sweep cancelled')

    def _run(self,request):
        state='FAILED'; result={}
        try:
            with self._io:
                with self._mutex: self._worker_ident=threading.get_ident()
                self._check_cancel(); self._configure(request)
                expected=actual_grid(request); total=None; first=None
                fields=('s11_real','s11_imag','s21_real','s21_imag')
                for _ in range(request['averages']):
                    self._check_cancel(); incoming=self._acquire(); self._check_cancel()
                    if str(incoming.get('status','OK')).startswith('ERROR'):
                        status=str(incoming['status'])
                        if 'TRANSPORT:' in status:
                            code='TRANSPORT'
                        elif 'ZERO_REFERENCE' in status:
                            code='ZERO_REFERENCE'
                        else:
                            code='INVALID_SWEEP'
                        raise VNAError(code,incoming['status'])
                    raw=validate_raw(incoming)
                    if raw['frequency_hz']!=expected or (first and raw['mode']!=first['mode']):
                        raise VNAError('GRID_MISMATCH','Sweep grid/mode changed inside averaging group')
                    if first is None:
                        first=raw; total={k:[0.0]*len(expected) for k in fields}
                    for key in fields:
                        total[key]=[a+b/request['averages'] for a,b in zip(total[key],raw[key])]
                first.update(total,averages=request['averages'],acquisition_id=str(uuid4()),
                             captured_at_utc=datetime.now(timezone.utc).isoformat())
                result={'raw':validate_raw(first)}; state='SUCCEEDED'
        except VNAError as exc:
            state='CANCELLED' if exc.code=='CANCELLED' else 'FAILED'
            result={} if state=='CANCELLED' else {'error':dict(code=exc.code,message=str(exc))}
        except Exception as exc:
            result={'error':dict(code='INVALID_SWEEP',message=str(exc))}
        finally:
            with self._mutex:
                if self._cancel.is_set(): state='CANCELLED'; result={}
                self._job.update(state=state,**result); self._worker_ident=None
