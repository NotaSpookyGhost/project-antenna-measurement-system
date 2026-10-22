"""Contracts reject corrupt data without converting valid zero responses."""
import copy
import unittest

from python.vna_contracts import VNAError, actual_grid, validate_raw, validate_request
from python.nanovna_bridge import _result_to_dict
from python.nanovna_v2 import FIFORecord, SweepResult


class TestVNAContracts(unittest.TestCase):
    def request(self, **kw):
        return dict(start_hz=100000, stop_hz=100010, points=4, averages=1, **kw)

    def raw(self):
        return dict(frequency_hz=[100000,100003,100006,100009],
                    s11_real=[0.0]*4, s11_imag=[0.0]*4,
                    s21_real=[0.0]*4, s21_imag=[0.0]*4,
                    points_received=4, complete=True, mode='Mock', averages=1,
                    captured_at_utc='2026-10-15T00:00:00Z', acquisition_id='fixture')

    def test_actual_integer_grid(self):
        self.assertEqual(actual_grid(self.request()), [100000,100003,100006,100009])

    def test_rejects_fraction_bool_nonfinite_and_out_of_range(self):
        for key, value in [('points',2.5),('points',True),('averages',17),
                           ('start_hz',float('nan')),('stop_hz',3e9+1),
                           ('points',401),('start_hz',100000.1)]:
            request=self.request(); request[key]=value
            with self.subTest(key=key,value=value), self.assertRaises(VNAError):
                validate_request(request)

    def test_zero_complex_is_valid_and_derived_fields_are_omitted(self):
        raw=self.raw(); raw['s11_db']=[float('-inf')]*4
        before=copy.deepcopy(raw)
        wire=validate_raw(raw)
        self.assertNotIn('s11_db',wire)
        self.assertEqual(wire['s11_real'],[0.0]*4)
        self.assertEqual(raw,before)

    def test_invalid_raw_fails(self):
        for change in [dict(complete=False),dict(s11_real=[1]),
                       dict(frequency_hz=[1,2,2,4]),dict(s21_imag=[float('nan')]*4)]:
            raw=self.raw(); raw.update(change)
            with self.subTest(change=change), self.assertRaises(VNAError):
                validate_raw(raw)

    def test_zero_forward_reference_is_error_but_zero_response_is_valid(self):
        bad=SweepResult(start_hz=100000,step_hz=1,points=2,
                        records=[FIFORecord(freq_index=i) for i in range(2)])
        result=_result_to_dict(bad,2)
        self.assertFalse(result['complete'])
        self.assertIn('ZERO_REFERENCE',result['status'])
        for record in bad.records: record.fwd0_re=10
        good=_result_to_dict(bad,2)
        self.assertTrue(good['complete'])
        self.assertEqual(good['s11_real'],[0,0])

    def test_bridge_never_marks_nonfinite_response_complete(self):
        result=SweepResult(start_hz=100000,step_hz=1,points=2,
            records=[FIFORecord(fwd0_re=1,rev0_re=float('nan'),freq_index=i) for i in range(2)])
        response=_result_to_dict(result,2)
        self.assertFalse(response['complete']); self.assertIn('INVALID_SWEEP',response['status'])


if __name__=='__main__': unittest.main()
