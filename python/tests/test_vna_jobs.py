import threading
import time
import unittest
from unittest.mock import patch
from python.vna_jobs import JobManager
from python.vna_contracts import VNAError
from python.tests.vna_fixtures import fixture


class TestVNAJobs(unittest.TestCase):
    def test_poll_and_cancel_do_not_wait_for_worker_configuration(self):
        entered=threading.Event(); release=threading.Event(); _,raw,*_=fixture()
        def configure(request): entered.set(); release.wait(2)
        m=JobManager(lambda:raw,configure,threading.RLock())
        job=m.start(self.request(),1)
        try:
            self.assertTrue(entered.wait(1))
            start=time.monotonic()
            self.assertEqual(m.poll(job['job_id'])['state'],'RUNNING')
            m.cancel(job['job_id'])
            self.assertLess(time.monotonic()-start,.5)
            self.assertFalse(release.is_set())
        finally: release.set()
        self.assertEqual(self.terminal(m,job)['state'],'CANCELLED')

    def test_bridge_hardware_calls_are_busy_before_worker_acquires_io(self):
        from python import nanovna_bridge as bridge
        gate=threading.Event(); waiting=threading.Event(); main=threading.get_ident()
        class GatedLock:
            def __init__(self): self.lock=threading.RLock()
            def acquire(self,blocking=True): return self.lock.acquire(blocking=blocking)
            def release(self): self.lock.release()
            def __enter__(self):
                if threading.get_ident()!=main: waiting.set(); gate.wait(2)
                self.lock.acquire(); return self
            def __exit__(self,*args): self.lock.release()
        _,raw,*_=fixture(); m=JobManager(lambda:raw,lambda r:None,GatedLock())
        job=m.start(self.request(),1)
        try:
            self.assertTrue(waiting.wait(1))
            with patch.object(bridge,'_jobs',m):
                for name,args in [('connect',('COM_FAKE',)),('disconnect',()),('identify',()),
                                  ('configure_sweep',(2300000000,2500000000,11)),
                                  ('acquire_single',()),('auto_detect_port',())]:
                    with self.subTest(name=name), self.assertRaises(VNAError) as e:
                        getattr(bridge,name)(*args)
                    self.assertEqual(e.exception.code,'BUSY')
        finally: gate.set()
        self.assertEqual(self.terminal(m,job)['state'],'SUCCEEDED')

    def test_cancel_returns_after_bounded_read_timeout(self):
        entered=threading.Event(); _,raw,*_=fixture()
        def acquire(): entered.set(); threading.Event().wait(.05); return raw
        m=JobManager(acquire,lambda r:None,threading.RLock()); job=m.start(self.request(),1)
        self.assertTrue(entered.wait(1)); start=time.monotonic(); m.cancel(job['job_id'])
        result=self.terminal(m,job)
        self.assertEqual(result['state'],'CANCELLED'); self.assertNotIn('raw',result)
        self.assertLess(time.monotonic()-start,1)

    def request(self): return dict(start_hz=2300000000,stop_hz=2500000000,points=11,averages=2)
    def terminal(self,manager,job):
        deadline=time.monotonic()+2
        while time.monotonic()<deadline:
            result=manager.poll(job['job_id'])
            if result['state']!='RUNNING': return result
            time.sleep(.001)
        self.fail('worker did not terminate')

    def test_complex_average_and_repeated_terminal_poll(self):
        _,raw,*_=fixture(); count=[0]
        def acquire():
            count[0]+=1
            r=dict(raw); r['s11_real']=[1 if count[0]==1 else -1]*11
            r['s11_imag']=[1 if count[0]==1 else -1]*11
            return r
        m=JobManager(acquire,lambda r:None,threading.RLock())
        job=m.start(self.request(),7); result=self.terminal(m,job)
        self.assertEqual(result['state'],'SUCCEEDED')
        self.assertEqual(result['raw']['s11_real'],[0.0]*11)
        self.assertEqual(result['raw']['s11_imag'],[0.0]*11)
        self.assertEqual(result['raw']['averages'],2)
        self.assertEqual(result,m.poll(job['job_id']))

    def test_cancel_busy_legacy_guard_and_no_late_publish(self):
        entered=threading.Event(); release=threading.Event(); _,raw,*_=fixture()
        def acquire(): entered.set(); release.wait(2); return raw
        m=JobManager(acquire,lambda r:None,threading.RLock())
        job=m.start(self.request(),1)
        try:
            self.assertTrue(entered.wait(1))
            with self.assertRaises(VNAError): m.start(self.request(),1)
            with self.assertRaises(VNAError):
                with m.hardware_guard(): self.fail('guard allowed legacy call')
            m.cancel(job['job_id'])
        finally: release.set()
        result=self.terminal(m,job)
        self.assertEqual(result['state'],'CANCELLED'); self.assertNotIn('raw',result)
        with m.hardware_guard(): pass

    def test_wrong_grid_and_worker_failure_release_ownership(self):
        _,raw,*_=fixture(); count=[0]
        def acquire():
            count[0]+=1; r=dict(raw)
            r['frequency_hz']=raw['frequency_hz'].copy()
            if count[0]==2: r['frequency_hz'][0]+=1
            return r
        m=JobManager(acquire,lambda r:None,threading.RLock())
        result=self.terminal(m,m.start(self.request(),2))
        self.assertEqual(result['state'],'FAILED')
        self.assertEqual(result['error']['code'],'GRID_MISMATCH')
        with m.hardware_guard(): pass
        def fail(): raise RuntimeError('injected transport failure')
        m=JobManager(fail,lambda r:None,threading.RLock())
        self.assertEqual(self.terminal(m,m.start(self.request(),3))['state'],'FAILED')
        with m.hardware_guard(): pass

    def test_transport_error_gets_stable_job_code(self):
        def fail():
            return {
                'status':'ERROR:TRANSPORT:FIFO timeout',
                'complete':False,
                'points_received':0,
            }
        m=JobManager(fail,lambda r:None,threading.RLock())
        result=self.terminal(m,m.start(self.request(),4))
        self.assertEqual(result['state'],'FAILED')
        self.assertEqual(result['error']['code'],'TRANSPORT')

    def test_legacy_lock_prevents_start_and_unknown_job_rejects(self):
        lock=threading.RLock(); entered=threading.Event(); release=threading.Event()
        def hold():
            with lock: entered.set(); release.wait(2)
        t=threading.Thread(target=hold); t.start(); entered.wait(1)
        m=JobManager(lambda:None,lambda r:None,lock)
        try:
            with self.assertRaises(VNAError): m.start(self.request(),1)
            with self.assertRaises(VNAError): m.poll('unknown')
        finally: release.set(); t.join()


if __name__=='__main__': unittest.main()
