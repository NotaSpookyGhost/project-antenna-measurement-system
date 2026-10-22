import json
import unittest
from python import vna_calibration_api as api
from python.tests.vna_fixtures import fixture


class TestCalibrationAPI(unittest.TestCase):
    def test_solve_apply_and_stable_error_envelopes(self):
        d,raw,*_=fixture(); response=json.loads(api.solve_json(json.dumps(d)))
        self.assertEqual(response['status'],'OK')
        text=response['payload']['profile_json']
        result=json.loads(api.apply_json(text,json.dumps(raw)))
        self.assertEqual(result['status'],'OK')
        self.assertIsNone(result['payload']['corrected_s21'])
        raw['frequency_hz'][0]+=1
        bad=json.loads(api.apply_json(text,json.dumps(raw)))
        self.assertEqual(bad['code'],'GRID_MISMATCH')
        self.assertEqual(json.loads(api.load_json('missing-file.vnacal.json'))['status'],'ERROR')
        self.assertEqual(json.loads(api.solve_json('{bad'))['status'],'ERROR')
        self.assertEqual(json.loads(api.backend_info_json())['payload']['version'],'2.1.0')


if __name__=='__main__': unittest.main()
