import copy
import hashlib
import json
import subprocess
import sys
import tempfile
from pathlib import Path
from unittest.mock import patch
import unittest
import numpy as np
from python.vna_profile import create_profile,validate_profile,save_profile,load_profile,canonical_json
from python.vna_calibration import apply_engine,build_engine
from python.vna_contracts import VNAError
from python.tests.vna_fixtures import fixture


class TestCalibrationProfile(unittest.TestCase):
    def test_cross_process_roundtrip_and_correction(self):
        d,raw,*_=fixture('TR_ENHANCED_RESPONSE'); p=create_profile(d)
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'hiệu chuẩn.vnacal.json'; save_profile(str(path),p)
            code='from python.vna_profile import load_profile,canonical_json; import sys; print(canonical_json(load_profile(sys.argv[1])))'
            result=subprocess.run([sys.executable,'-X','utf8','-c',code,str(path)],capture_output=True,text=True,encoding='utf-8',check=True)
            restored=json.loads(result.stdout)
            self.assertEqual(restored,p)
            a=apply_engine(build_engine(p),raw,p['algorithm'])
            b=apply_engine(build_engine(restored),raw,p['algorithm'])
            for channel in ('corrected_s11','corrected_s21'):
                self.assertLessEqual(np.max(np.abs(np.array(a[channel]['real'])-b[channel]['real'])),1e-12)

    def test_hash_does_not_replace_recompute_verification(self):
        p=create_profile(fixture()[0]); key=next(iter(p['coefficients']))
        p['coefficients'][key]['real'][0]+=.1
        p['content_sha256']=hashlib.sha256(canonical_json({k:v for k,v in p.items() if k!='content_sha256'}).encode()).hexdigest()
        with self.assertRaises(VNAError): validate_profile(p)

    def test_strict_schema_engine_and_finite_data(self):
        for mutate in [lambda p:p.update(schema_version=2),lambda p:p.update(extra=True),
                       lambda p:p['engine'].update(version='0.0'),
                       lambda p:p['standards']['open']['s11_real'].__setitem__(0,float('nan'))]:
            p=create_profile(fixture()[0]); mutate(p)
            with self.assertRaises(VNAError): validate_profile(p)

    def test_failed_replace_preserves_old_file_and_cleans_temp(self):
        p=create_profile(fixture()[0])
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'cal.json'; path.write_text('old',encoding='utf-8')
            with patch('python.vna_profile.os.replace',side_effect=OSError('injected')):
                with self.assertRaises(OSError): save_profile(str(path),p)
            self.assertEqual(path.read_text(),'old')
            self.assertEqual(list(Path(td).iterdir()),[path])

    def test_oversize_and_nonstandard_json_reject(self):
        with tempfile.TemporaryDirectory() as td:
            path=Path(td)/'cal.json'
            for data in [' '* (10*1024*1024+1),'{"x":NaN}','{"x":1,"x":2}']:
                path.write_text(data)
                with self.assertRaises(VNAError): load_profile(str(path))


if __name__=='__main__': unittest.main()
