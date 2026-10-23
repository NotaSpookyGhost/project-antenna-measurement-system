"""Transport failures through the real driver, with no serial port access."""
import threading
import time
import unittest
from unittest.mock import patch

from serial import SerialException
from python import nanovna_bridge as bridge
from python.nanovna_v2 import NanoVNA_V2
from python.vna_contracts import VNAError
from python.vna_jobs import JobManager


REQUEST = dict(start_hz=2395000000, stop_hz=2405000000, points=11, averages=1)


class FailingSerial:
    def __init__(self, stage='write', clear_number=1, gated=False):
        self.is_open = True
        self.timeout = 2.0
        self.stage = stage
        self.clear_number = clear_number
        self.clears = 0
        self.gated = gated
        self.entered = threading.Event()
        self.release = threading.Event()

    def fail(self):
        if self.gated:
            self.entered.set()
            if not self.release.wait(2):
                raise AssertionError('test coordinator did not release serial failure')
        raise SerialException('injected transport loss')

    def write(self, data):
        if data == bytes([0x20, 0x30, 0]):
            self.clears += 1
            if self.stage == 'write' and self.clears == self.clear_number:
                self.fail()

    def reset_input_buffer(self):
        if self.stage == 'reset' and self.clears == self.clear_number:
            self.fail()

    def read(self, count):
        self.fail()

    def close(self):
        self.is_open = False


def configured_driver(transport):
    vna = NanoVNA_V2()
    vna._ser = transport
    vna._sweep_start = REQUEST['start_hz']
    vna._sweep_step = 1000000
    vna._sweep_points = REQUEST['points']
    vna._sweep_values_per_freq = 1
    return vna


class TestTransportRegressions(unittest.TestCase):
    def terminal(self, manager, job):
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            result = manager.poll(job['job_id'])
            if result['state'] != 'RUNNING':
                return result
            threading.Event().wait(.001)
        self.fail('worker did not terminate')

    def test_configuration_failure_keeps_transport_code(self):
        vna = configured_driver(FailingSerial())
        vna._sweep_start = 0  # The worker must configure a different actual grid.
        manager = JobManager(bridge.acquire_single, bridge._configure_job, threading.RLock())
        with patch.object(bridge, '_vna', vna), patch.object(bridge, '_jobs', manager):
            result = self.terminal(manager, manager.start(REQUEST, 1))
        self.assertEqual(result['state'], 'FAILED')
        self.assertEqual(result['error']['code'], 'TRANSPORT')
        self.assertFalse(vna.connected)
        self.assertNotIn('raw', result)

    def test_fifo_clear_failure_disconnects_entire_acquisition(self):
        for operation in ('acquire_single', 'acquire_sweep'):
            for stage in ('write', 'reset'):
                with self.subTest(operation=operation, stage=stage):
                    # acquire_sweep configures first, then clears for acquisition.
                    transport = FailingSerial(stage, 2 if operation == 'acquire_sweep' else 1)
                    vna = configured_driver(transport)
                    with patch.object(bridge, '_vna', vna):
                        if operation == 'acquire_single':
                            result = bridge.acquire_single()
                        else:
                            result = bridge.acquire_sweep(2395e6, 2405e6, 11)
                    self.assertTrue(result['status'].startswith('ERROR:TRANSPORT:'), result)
                    self.assertFalse(vna.connected)
                    self.assertFalse(result['complete'])
                    self.assertEqual(result['frequency_hz'], [])

    def test_cancel_retains_transport_failure_during_configuration_or_read(self):
        for phase in ('configuration', 'acquisition'):
            with self.subTest(phase=phase):
                transport = FailingSerial('write' if phase == 'configuration' else 'read', gated=True)
                vna = configured_driver(transport)
                if phase == 'configuration':
                    vna._sweep_start = 0
                manager = JobManager(bridge.acquire_single, bridge._configure_job, threading.RLock())
                with patch.object(bridge, '_vna', vna), patch.object(bridge, '_jobs', manager):
                    job = manager.start(REQUEST, 1)
                    try:
                        self.assertTrue(transport.entered.wait(2), 'serial failure was not reached')
                        manager.cancel(job['job_id'])
                    finally:
                        transport.release.set()
                    result = self.terminal(manager, job)
                self.assertEqual(result['state'], 'CANCELLED')
                self.assertEqual(result.get('error', {}).get('code'), 'TRANSPORT')
                self.assertFalse(vna.connected)
                self.assertNotIn('raw', result)
                self.assertEqual(result, manager.poll(job['job_id']))

    def test_cancel_retains_nontransport_configuration_error(self):
        entered = threading.Event()
        release = threading.Event()

        def configure(request):
            entered.set()
            if not release.wait(2):
                raise AssertionError('test coordinator did not release configuration')
            raise VNAError('INVALID_REQUEST', 'invalid sweep setting')

        manager = JobManager(lambda: self.fail('acquisition after failed configuration'),
                             configure, threading.RLock())
        job = manager.start(REQUEST, 1)
        try:
            self.assertTrue(entered.wait(2))
            manager.cancel(job['job_id'])
        finally:
            release.set()
        result = self.terminal(manager, job)
        self.assertEqual(result['state'], 'CANCELLED')
        self.assertEqual(result.get('error', {}).get('code'), 'INVALID_REQUEST')
        self.assertNotIn('raw', result)
