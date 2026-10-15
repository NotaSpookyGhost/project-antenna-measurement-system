"""
nanovna_bridge.py — MATLAB-callable Python bridge for NanoVNA SAA-2N.

This module is the ONLY interface between MATLAB R2025b and the NanoVNA V2
driver. MATLAB calls functions here via py.python.nanovna_bridge.*

Design rules (from master-v4 §9.12):
    - MATLAB must NOT know about opcodes, register addresses, FIFO layout,
      endianness, or any protocol internals.
    - All functions accept/return plain Python types (str, int, float, list)
      that MATLAB can convert natively.
    - Complex S11/S21 are returned as separate real/imag lists so MATLAB
      does not need to handle Python complex type.
    - API is coarse-grained: one call per measurement block, not per byte.

Usage from MATLAB:
    pyenv(ExecutionMode="OutOfProcess")
    mod = py.importlib.import_module('python.nanovna_bridge')

    mod.connect('COM6')
    info = mod.identify()
    result = mod.acquire_sweep(2395e6, 2405e6, 11)
    mod.disconnect()

    freq  = double(result{'frequency_hz'})
    s11re = double(result{'s11_real'})
    s11im = double(result{'s11_imag'})
    s21re = double(result{'s21_real'})
    s21im = double(result{'s21_imag'})
"""

import sys
from pathlib import Path

# Ensure package root is on path when called from MATLAB
_PACKAGE_ROOT = Path(__file__).resolve().parent.parent
if str(_PACKAGE_ROOT) not in sys.path:
    sys.path.insert(0, str(_PACKAGE_ROOT))

from python.nanovna_v2 import NanoVNA_V2, DeviceIdentity, NanoVNAError

import serial.tools.list_ports

# ─── Module-level singleton ──────────────────────────────────────────────
# MATLAB OutOfProcess keeps one Python interpreter alive per session.
# A single NanoVNA_V2 instance is shared across calls.

_vna: NanoVNA_V2 | None = None


def _get_vna() -> NanoVNA_V2:
    """Return the active VNA instance or raise if not connected."""
    global _vna
    if _vna is None or not _vna.connected:
        raise RuntimeError(
            "Not connected. Call nanovna_bridge.connect(port) first."
        )
    return _vna


# ─── Connection API ──────────────────────────────────────────────────────

def connect(port: str) -> str:
    """Open connection to SAA-2N on the given COM port.

    Args:
        port: COM port string, e.g. 'COM6'

    Returns:
        Status string, e.g. 'CONNECTED:COM6'

    Raises:
        RuntimeError: if connection or handshake fails
    """
    global _vna
    if _vna is not None and _vna.connected:
        _vna.disconnect()

    _vna = NanoVNA_V2()
    try:
        _vna.connect(str(port))
        if not _vna.indicate():
            _vna.disconnect()
            _vna = None
            raise RuntimeError(
                f"INDICATE handshake failed on {port}. "
                "Device did not respond 0x32."
            )
    except Exception as e:
        _vna = None
        raise RuntimeError(f"connect({port}) failed: {e}") from e

    return f"CONNECTED:{port}"


def disconnect() -> str:
    """Close connection to SAA-2N.

    Returns:
        Status string 'DISCONNECTED'
    """
    global _vna
    if _vna is not None:
        _vna.disconnect()
        _vna = None
    return "DISCONNECTED"


def is_connected() -> bool:
    """Return True if currently connected to SAA-2N."""
    return _vna is not None and _vna.connected


def auto_detect_port() -> str:
    """Scan COM ports and return the first one that responds to INDICATE.

    Returns:
        Port string e.g. 'COM6', or empty string if not found.
    """
    ports = serial.tools.list_ports.comports()
    for p in ports:
        desc = (p.description or "").lower()
        if "bluetooth" in desc:
            continue
        try:
            tmp = NanoVNA_V2()
            tmp.connect(p.device, timeout=1.0)
            ok = tmp.indicate()
            tmp.disconnect()
            if ok:
                return str(p.device)
        except Exception:
            continue
    return ""


# ─── Identity API ────────────────────────────────────────────────────────

def identify() -> dict:
    """Read device identity registers.

    Returns dict with keys:
        device_variant      int  (0x02 for V2)
        protocol_version    int
        hardware_revision   int
        firmware_major      int
        firmware_minor      int
        port                str
        is_v2               bool
        status              str  'OK' or error message

    MATLAB access example:
        info = py.python.nanovna_bridge.identify()
        variant = int32(info{'device_variant'})
    """
    vna = _get_vna()
    try:
        identity = vna.identify()
        return {
            "device_variant":    identity.device_variant,
            "protocol_version":  identity.protocol_version,
            "hardware_revision": identity.hardware_revision,
            "firmware_major":    identity.firmware_major,
            "firmware_minor":    identity.firmware_minor,
            "port":              identity.port,
            "is_v2":             identity.is_v2,
            "status":            "OK",
        }
    except Exception as e:
        return {"status": f"ERROR:{e}"}


# ─── Sweep / Acquisition API ─────────────────────────────────────────────

def configure_sweep(start_hz: float, stop_hz: float, points: int) -> str:
    """Configure sweep parameters on the device.

    Call this once before repeated acquire_single() calls.
    Puts device into USB data mode.

    Args:
        start_hz:  Start frequency in Hz (e.g. 2395e6)
        stop_hz:   Stop frequency in Hz  (e.g. 2405e6)
        points:    Number of sweep points (e.g. 11)

    Returns:
        Status string 'OK' or 'ERROR:...'
    """
    vna = _get_vna()
    try:
        vna.configure_sweep(int(start_hz), int(stop_hz), int(points))
        return "OK"
    except Exception as e:
        return f"ERROR:{e}"


def acquire_sweep(start_hz: float, stop_hz: float, points: int) -> dict:
    """Configure sweep and acquire one complete sweep.

    High-level call: configure + wait + clear stale FIFO + read fresh data.
    Use this for single-shot measurements.

    Args:
        start_hz:  Start frequency in Hz
        stop_hz:   Stop frequency in Hz
        points:    Number of sweep points

    Returns dict with keys:
        frequency_hz    list[float]  — frequency for each point
        s11_real        list[float]  — S11 real parts
        s11_imag        list[float]  — S11 imaginary parts
        s21_real        list[float]  — S21 real parts
        s21_imag        list[float]  — S21 imaginary parts
        s11_db          list[float]  — |S11| in dB
        s21_db          list[float]  — |S21| in dB
        points_requested  int
        points_received   int
        complete          bool
        status            str  'OK' or 'ERROR:...'

    MATLAB access example:
        result = py.python.nanovna_bridge.acquire_sweep(2395e6, 2405e6, 11)
        freq  = double(py.array.array('d', result{'frequency_hz'}))
        s21re = double(py.array.array('d', result{'s21_real'}))
        s21im = double(py.array.array('d', result{'s21_imag'}))
        S21   = complex(s21re, s21im)
    """
    vna = _get_vna()
    try:
        result = vna.acquire_sweep(int(start_hz), int(stop_hz), int(points))
        return _result_to_dict(result, int(points))
    except Exception as e:
        return _error_dict(str(e), int(points))


def acquire_single() -> dict:
    """Acquire one sweep using currently configured parameters.

    Use this in a measurement loop after configure_sweep() has been called.
    Faster than acquire_sweep() because it skips re-configuration.

    Returns same dict structure as acquire_sweep().
    """
    vna = _get_vna()
    try:
        result = vna.acquire_single(
            vna._sweep_start,
            vna._sweep_start + vna._sweep_step * (vna._sweep_points - 1),
            vna._sweep_points,
        )
        return _result_to_dict(result, vna._sweep_points)
    except Exception as e:
        return _error_dict(str(e), 0)


def acquire_at_frequency(freq_hz: float, span_hz: float = 10e6,
                         points: int = 11) -> dict:
    """Acquire sweep centered at a single frequency.

    Convenience wrapper for radiation-pattern MVP:
    configure narrow sweep around freq_hz and acquire.

    Args:
        freq_hz:   Center frequency in Hz (e.g. 2.4e9)
        span_hz:   Sweep span in Hz (default 10 MHz)
        points:    Number of points (default 11)

    Returns same dict structure as acquire_sweep().
    """
    start_hz = int(freq_hz - span_hz / 2)
    stop_hz  = int(freq_hz + span_hz / 2)
    return acquire_sweep(start_hz, stop_hz, points)


# ─── Internal helpers ────────────────────────────────────────────────────

import math


def _result_to_dict(result, points_requested: int) -> dict:
    """Convert SweepResult to MATLAB-compatible dict."""
    if not result.complete:
        error = _error_dict(
            f"Incomplete VNA sweep: expected indices 0..{result.points - 1}, "
            f"received {[rec.freq_index for rec in result.records]}",
            points_requested,
        )
        error["points_received"] = len(result.records)
        return error

    records = sorted(result.records, key=lambda rec: rec.freq_index)
    freq_hz = [result.start_hz + rec.freq_index * result.step_hz for rec in records]
    s11_c   = [rec.s11 for rec in records]
    s21_c   = [rec.s21 for rec in records]

    def safe_db(c: complex) -> float:
        m = abs(c)
        return 20.0 * math.log10(m) if m > 0 else -999.0

    return {
        "frequency_hz":     freq_hz,
        "s11_real":         [s.real for s in s11_c],
        "s11_imag":         [s.imag for s in s11_c],
        "s21_real":         [s.real for s in s21_c],
        "s21_imag":         [s.imag for s in s21_c],
        "s11_db":           [safe_db(s) for s in s11_c],
        "s21_db":           [safe_db(s) for s in s21_c],
        "points_requested": points_requested,
        "points_received":  len(result.records),
        "complete":         result.complete,
        "status":           "OK",
    }


def _error_dict(msg: str, points_requested: int) -> dict:
    """Return an error dict with empty arrays."""
    return {
        "frequency_hz":     [],
        "s11_real":         [],
        "s11_imag":         [],
        "s21_real":         [],
        "s21_imag":         [],
        "s11_db":           [],
        "s21_db":           [],
        "points_requested": points_requested,
        "points_received":  0,
        "complete":         False,
        "status":           f"ERROR:{msg}",
    }
