import unittest
import numpy as np
from python.vna_calibration import build_engine,apply_engine
from python.vna_contracts import VNAError
from python.tests.vna_fixtures import fixture


class TestCalibrationTR(unittest.TestCase):
    def test_forward_tr_recovers_independent_matched_receive_truth(self):
        d,raw,g,t=fixture('TR_ENHANCED_RESPONSE')
        result=apply_engine(build_engine(d),raw,d['algorithm'])
        for name,want in [('corrected_s11',g),('corrected_s21',t)]:
            got=np.array(result[name]['real'])+1j*np.array(result[name]['imag'])
            self.assertLessEqual(np.max(np.abs(got-want)),1e-10)
        self.assertEqual(set(result),{'corrected_s11','corrected_s21','channel_state'})
        self.assertEqual(result['channel_state']['s21'],'TR_ENHANCED_RESPONSE')

    def test_missing_and_zero_thru_reject(self):
        for missing in (True,False):
            d,*_=fixture('TR_ENHANCED_RESPONSE')
            if missing: del d['standards']['thru']
            else:
                d['standards']['thru']['s21_real']=[0]*11
                d['standards']['thru']['s21_imag']=[0]*11
            with self.assertRaises(VNAError) as e: build_engine(d)
            self.assertEqual(e.exception.code,'MISSING_STANDARD' if missing else 'DEGENERATE_STANDARDS')


if __name__=='__main__': unittest.main()
