import copy
import unittest
from unittest.mock import patch
import numpy as np
from python.vna_calibration import build_engine,apply_engine
from python.vna_contracts import VNAError
from python.tests.vna_fixtures import fixture
from python.tests.vna_fixtures import raw as independent_raw,wire


def complex_wire(w): return np.array(w['real'])+1j*np.array(w['imag'])


class TestCalibrationEngine(unittest.TestCase):
    def test_runtime_engine_version_must_match_profile_adapter(self):
        with patch('python.vna_calibration.rf.__version__','99.0'):
            with self.assertRaises(VNAError) as e: build_engine(fixture()[0])
        self.assertEqual(e.exception.code,'ENGINE_VERSION_MISMATCH')

    def test_nonideal_characterized_osl_uses_known_models(self):
        d,measured,g,t=fixture(); n=len(g); f=d['frequency_hz']
        models={'open':.97*np.exp(-.04j*np.arange(n)),
                'short':-.96*np.exp(-.03j*np.arange(n)),
                'load':np.full(n,.02+.01j)}
        d['kit']['kind']='CHARACTERIZED'
        for name,value in models.items():
            d['kit']['models'][name]=wire(value)
            d['standards'][name]=independent_raw(f,value,np.zeros(n,complex))
        result=apply_engine(build_engine(d),measured,d['algorithm'])
        self.assertLessEqual(np.max(np.abs(complex_wire(result['corrected_s11'])-g)),1e-10)

    def test_sol_recovers_independent_truth_without_mutating_raw(self):
        draft,raw,g,t=fixture(); before=copy.deepcopy(raw)
        result=apply_engine(build_engine(draft),raw,draft['algorithm'])
        self.assertLessEqual(np.max(np.abs(complex_wire(result['corrected_s11'])-g)),1e-10)
        self.assertIsNone(result['corrected_s21'])
        self.assertEqual(result['channel_state']['s21'],'RAW')
        self.assertEqual(before,raw)

    def test_rejects_missing_degenerate_nonfinite_and_wrong_grid(self):
        for change,code in [('missing','MISSING_STANDARD'),('duplicate','DEGENERATE_STANDARDS'),
                            ('nan','INVALID_SWEEP'),('grid','GRID_MISMATCH')]:
            d,*_=fixture()
            if change=='missing': del d['standards']['load']
            if change=='duplicate': d['standards']['open']=copy.deepcopy(d['standards']['short'])
            if change=='nan': d['standards']['open']['s11_real'][0]=float('nan')
            if change=='grid': d['standards']['open']['frequency_hz'][0]+=1
            with self.subTest(change=change), self.assertRaises(VNAError) as e:
                build_engine(d)
            self.assertEqual(e.exception.code,code)


if __name__=='__main__': unittest.main()
