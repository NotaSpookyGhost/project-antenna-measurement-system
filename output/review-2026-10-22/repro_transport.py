"""Software-only transport regression probes for commit aeb1b9f.

Expected contract assertions fail on the reviewed commit. No real serial port
is created: every driver receives an in-memory serial double.
Run from any directory with the repository .venv-vna Python interpreter.
"""
from pathlib import Path
import subprocess
import sys
import threading
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from serial import SerialException
from python import nanovna_bridge as bridge
from python.nanovna_v2 import NanoVNA_V2
from python.vna_jobs import JobManager

TARGET = "aeb1b9f67805d2004c694f63e8a835b0003a8112"
REQUEST = dict(start_hz=2395000000, stop_hz=2405000000, points=11, averages=1)


class WriteFailureSerial:
    is_open = True

    def write(self, _data):
        raise SerialException("injected serial write failure during FIFO clear")

    def close(self):
        self.is_open = False


class CancelThenReadFailureSerial:
    def __init__(self):
        self.is_open = True
        self.timeout = 2.0
        self.entered = threading.Event()
        self.release = threading.Event()

    def write(self, _data):
        pass

    def reset_input_buffer(self):
        pass

    def read(self, _count):
        self.entered.set()
        if not self.release.wait(2):
            raise AssertionError("test coordinator did not release fake serial read")
        raise SerialException("injected transport loss while STOP is pending")

    def close(self):
        self.is_open = False


def configured_driver(transport):
    vna = NanoVNA_V2()
    vna._ser = transport
    vna._sweep_start = REQUEST["start_hz"]
    vna._sweep_step = 1000000
    vna._sweep_points = REQUEST["points"]
    vna._sweep_values_per_freq = 1
    return vna


def terminal(manager, job):
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        result = manager.poll(job["job_id"])
        if result["state"] != "RUNNING":
            return result
        threading.Event().wait(0.001)
    raise AssertionError("fake worker did not terminate")


class TransportContractRegression(unittest.TestCase):
    def test_configuration_failure_keeps_transport_code(self):
        vna = configured_driver(WriteFailureSerial())
        vna._sweep_start = 0  # Force the real configuration path.
        manager = JobManager(bridge.acquire_single, bridge._configure_job, threading.RLock())
        with patch.object(bridge, "_vna", vna), patch.object(bridge, "_jobs", manager):
            result = terminal(manager, manager.start(REQUEST, 1))
        print("CONFIGURATION", result, "driver_connected=", vna.connected, flush=True)
        self.assertEqual(result["error"]["code"], "TRANSPORT")

    def test_fifo_clear_serial_exception_disconnects_and_keeps_transport_code(self):
        vna = configured_driver(WriteFailureSerial())
        manager = JobManager(bridge.acquire_single, lambda _request: None, threading.RLock())
        with patch.object(bridge, "_vna", vna), patch.object(bridge, "_jobs", manager):
            result = terminal(manager, manager.start(REQUEST, 1))
        print("FIFO_CLEAR", result, "driver_connected=", vna.connected, flush=True)
        self.assertTrue(
            result.get("error", {}).get("code") == "TRANSPORT" and not vna.connected,
            "serial write failure must disconnect and reach MATLAB as TRANSPORT",
        )

    def test_cancel_does_not_hide_concurrent_transport_loss(self):
        transport = CancelThenReadFailureSerial()
        vna = configured_driver(transport)
        manager = JobManager(bridge.acquire_single, lambda _request: None, threading.RLock())
        with patch.object(bridge, "_vna", vna), patch.object(bridge, "_jobs", manager):
            job = manager.start(REQUEST, 1)
            try:
                self.assertTrue(transport.entered.wait(2), "fake FIFO read was not reached")
                manager.cancel(job["job_id"])
            finally:
                transport.release.set()
            result = terminal(manager, job)
        print("CANCEL_TRANSPORT", result, "driver_connected=", vna.connected, flush=True)
        self.assertFalse(vna.connected, "the actual FIFO error path closes the serial double")
        self.assertNotIn("raw", result, "cancelled measurements must never publish late raw data")
        self.assertEqual(
            result.get("error", {}).get("code"), "TRANSPORT",
            "terminal cancellation must still report transport loss to invalidate MATLAB's connection",
        )


if __name__ == "__main__":
    print("Reviewed commit:", TARGET, flush=True)
    for relative in (
        "python/nanovna_bridge.py", "python/nanovna_v2.py", "python/vna_jobs.py",
        "matlab/classes/VNAController.m", "CODEX_GUIDE.md",
    ):
        actual = subprocess.check_output(["git", "hash-object", relative], cwd=ROOT, text=True).strip()
        expected = subprocess.check_output(["git", "rev-parse", f"{TARGET}:{relative}"], cwd=ROOT, text=True).strip()
        assert actual == expected, f"source differs from reviewed commit: {relative}"
        print("SOURCE_MATCH", relative, actual, flush=True)
    unittest.main(verbosity=2)
