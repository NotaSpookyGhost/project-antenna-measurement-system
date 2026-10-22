import tempfile
from pathlib import Path
import unittest
import numpy as np
import skrf as rf
from python.vna_kit import load_kit
from python.vna_contracts import VNAError
from python.vna_calibration import build_engine
from python.tests.vna_fixtures import fixture


class TestVNAKit(unittest.TestCase):
    def files(self,root,z0=50):
        d,*_=fixture('TR_ENHANCED_RESPONSE'); f=d['frequency_hz']; paths={}
        for name,g in [('open',1),('short',-1),('load',0)]:
            network=rf.Network(frequency=rf.Frequency.from_f(f,unit='Hz'),
                               s=np.full((len(f),1,1),g,complex),z0=z0)
            p=root/(name+' chuẩn.s1p'); network.write_touchstone(str(p)); paths[name]=str(p)
        s=np.zeros((len(f),2,2),complex); s[:,1,0]=1; s[:,0,1]=1
        p=root/'thru chuẩn.s2p'
        rf.Network(frequency=rf.Frequency.from_f(f,unit='Hz'),s=s,z0=z0).write_touchstone(str(p))
        paths['thru']=str(p)
        return d,paths

    def test_characterized_kit_embeds_models_and_survives_source_removal(self):
        with tempfile.TemporaryDirectory() as td:
            d,paths=self.files(Path(td)); d['kit']=load_kit(paths,d['frequency_hz'],d['algorithm'],'Kit chuẩn')
            for p in paths.values(): Path(p).unlink()
            self.assertEqual(d['kit']['kind'],'CHARACTERIZED')
            self.assertEqual(len(d['kit']['source_files']),4)
            self.assertTrue(all('/' not in x['basename'] and '\\' not in x['basename'] for x in d['kit']['source_files']))
            build_engine(d)

    def test_grid_impedance_and_missing_file_reject_without_fallback(self):
        with tempfile.TemporaryDirectory() as td:
            d,paths=self.files(Path(td),75)
            with self.assertRaises(VNAError): load_kit(paths,d['frequency_hz'],d['algorithm'],'bad')
            d,paths=self.files(Path(td),50)
            f=d['frequency_hz'].copy(); f[0]+=1
            with self.assertRaises(VNAError): load_kit(paths,f,d['algorithm'],'bad')
            Path(paths['open']).unlink()
            with self.assertRaises(VNAError): load_kit(paths,d['frequency_hz'],d['algorithm'],'bad')


if __name__=='__main__': unittest.main()
