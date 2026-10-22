import struct
import unittest
from unittest.mock import MagicMock, patch
from python import nanovna_bridge as bridge
from python.nanovna_v2 import NanoVNA_V2, FIFORecord, SweepResult, FIFOError, TransportError


class FIFOTransport:
    def __init__(self):
        self.is_open=True; self.timeout=2.; self.commands=[]; self.buffer=bytearray(); self.index=0
    def close(self): self.is_open=False
    def write(self,data):
        self.commands.append(data)
        count=data[2]
        for _ in range(count):
            self.buffer.extend(struct.pack('<iiiiiiH6x',100,0,self.index,0,20,0,self.index))
            self.index+=1
    def read(self,count):
        result=bytes(self.buffer[:count]); del self.buffer[:count]; return result


class TestVNATransport(unittest.TestCase):
    def test_connect_rolls_back_when_identity_read_fails(self):
        class IdentityFailingVNA:
            def __init__(self):
                self.disconnected=False
            def connect(self, port): self.port=port
            def identify(self): raise RuntimeError('identity read failed')
            def indicate(self): return True
            def disconnect(self): self.disconnected=True

        fake=IdentityFailingVNA()
        with patch.object(bridge,'NanoVNA_V2',return_value=fake):
            with self.assertRaises(RuntimeError): bridge.connect('COM_TEST')
        self.assertTrue(fake.disconnected)
        self.assertIsNone(bridge._vna)

    def test_fifo_timeout_closes_pending_reply_before_next_command(self):
        v=NanoVNA_V2(); transport=FIFOTransport(); v._ser=transport
        with patch('python.nanovna_v2.time.monotonic',side_effect=[0.,11.]):
            with self.assertRaises(FIFOError): v._read_fifo(1)
        self.assertFalse(transport.is_open); self.assertFalse(v.connected)

    def test_slow_invalid_sweep_is_not_retried(self):
        invalid=SweepResult(points=4,records=[FIFORecord(freq_index=i) for i in (0,1,0,1)])
        v=MagicMock(connected=True,_sweep_start=1000000,_sweep_step=100,_sweep_points=4)
        v.acquire_single.return_value=invalid
        with patch.object(bridge,'_vna',v), patch.object(bridge.time,'monotonic',side_effect=[0.,12.1]):
            result=bridge.acquire_single()
        self.assertFalse(result['complete']); self.assertEqual(v.acquire_single.call_count,1)

    def test_bridge_preserves_transport_error_code(self):
        v=MagicMock(connected=True,_sweep_start=1000000,_sweep_step=100,_sweep_points=4)
        v.acquire_single.side_effect=TransportError('FIFO timeout')
        with patch.object(bridge,'_vna',v):
            result=bridge.acquire_single()
        self.assertTrue(result['status'].startswith('ERROR:TRANSPORT:'))
        self.assertFalse(result['complete'])

    def test_configure_preserves_transport_error_code(self):
        v=MagicMock(connected=True)
        v.configure_sweep.side_effect=TransportError('serial closed')
        with patch.object(bridge,'_vna',v):
            status=bridge.configure_sweep(2395e6,2405e6,11)
        self.assertTrue(status.startswith('ERROR:TRANSPORT:'))
        v.disconnect.assert_called_once()

    def test_fifo_uses_one_byte_count_and_chunks_above_255(self):
        v=NanoVNA_V2(); v._ser=FIFOTransport()
        records=v._read_fifo(401)
        self.assertEqual(v._ser.commands,[bytes([0x18,0x30,255]),bytes([0x18,0x30,146])])
        self.assertEqual([r.freq_index for r in records],list(range(401)))

    def test_transitional_fifo_is_reacquired_as_a_whole_sweep(self):
        old=SweepResult(start_hz=1000000,step_hz=100,points=4,
            records=[FIFORecord(fwd0_re=100,rev0_re=1,freq_index=i) for i in (0,1,0,1)])
        fresh=SweepResult(start_hz=1000000,step_hz=100,points=4,
            records=[FIFORecord(fwd0_re=100,rev0_re=10+i,freq_index=i) for i in (2,3,0,1)])
        v=MagicMock(connected=True,_sweep_start=1000000,_sweep_step=100,_sweep_points=4)
        v.acquire_single.side_effect=[old,fresh]
        with patch.object(bridge,'_vna',v): result=bridge.acquire_single()
        self.assertEqual(result['status'],'OK')
        self.assertEqual(result['s11_real'],[.10,.11,.12,.13])
        self.assertEqual(v.acquire_single.call_count,2)

    def test_persistent_duplicate_indices_still_reject_after_bounded_retry(self):
        invalid=SweepResult(points=4,records=[FIFORecord(freq_index=i) for i in (0,1,0,1)])
        v=MagicMock(connected=True,_sweep_start=1000000,_sweep_step=100,_sweep_points=4)
        v.acquire_single.return_value=invalid
        with patch.object(bridge,'_vna',v): result=bridge.acquire_single()
        self.assertTrue(result['status'].startswith('ERROR:'))
        self.assertFalse(result['complete']); self.assertEqual(result['frequency_hz'],[])
        self.assertEqual(v.acquire_single.call_count,2)
