import unittest
from unittest.mock import patch
from python import nanovna_bridge as bridge
from python.nanovna_v2 import NanoVNA_V2
from python.tests.test_vna_transport import FIFOTransport


class ConfiguredVNA:
    connected=True
    def __init__(self):
        self._sweep_start=0; self._sweep_step=0; self._sweep_points=0; self._sweep_values_per_freq=0; self.configurations=[]
    def configure_sweep(self,start,stop,points):
        self.configurations.append((start,stop,points))
        self._sweep_start=start; self._sweep_step=(stop-start)//(points-1); self._sweep_points=points
        self._sweep_values_per_freq=1


class TestVNAPerformance(unittest.TestCase):
    def test_live_sweep_discards_stale_bytes_without_fixed_cycle_waits(self):
        class Transport(FIFOTransport):
            def write(self,data):
                if data[:2]==bytes([0x20,0x30]):
                    self.commands.append(data); self.buffer.clear()
                else: super().write(data)
            def reset_input_buffer(self): self.buffer.clear()
        v=NanoVNA_V2(); transport=Transport(); v._ser=transport
        v._sweep_start=1000000; v._sweep_step=100; v._sweep_points=4
        transport.buffer.extend(b'old invalid bytes')
        with patch('python.nanovna_v2.time.sleep') as sleep:
            result=v.acquire_single(1000000,1000300,4)
        self.assertTrue(result.complete)
        self.assertEqual([r.freq_index for r in result.records],[0,1,2,3])
        self.assertLessEqual(sum(call.args[0] for call in sleep.call_args_list),.21)

    def test_repeated_actual_grid_does_not_restart_device_sweep(self):
        request=dict(start_hz=2395000000,stop_hz=2405000000,points=101,averages=1)
        v=ConfiguredVNA()
        with patch.object(bridge,'_vna',v):
            bridge._configure_job(request)
            bridge._configure_job(dict(request,averages=4))
            bridge._configure_job(dict(request,stop_hz=request['stop_hz']+1))
            self.assertEqual(len(v.configurations),1)
            bridge._configure_job(dict(request,points=11))
            self.assertEqual(len(v.configurations),2)

    def test_replacement_connection_always_configures_its_device(self):
        request=dict(start_hz=2395000000,stop_hz=2405000000,points=101,averages=1)
        for v in (ConfiguredVNA(),ConfiguredVNA()):
            with patch.object(bridge,'_vna',v): bridge._configure_job(request)
            self.assertEqual(len(v.configurations),1)
