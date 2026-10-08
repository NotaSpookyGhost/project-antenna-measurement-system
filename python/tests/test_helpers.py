"""
test_helpers.py — Shared utilities for all SAA-2N validation test scripts.

Provides:
    - COM port auto-detection
    - Structured logging/printing
    - Experiment log directory creation (validation_YYYYMMDD_HHMMSS/)
    - CSV export
    - Config/summary JSON export
    - Common test pass/fail formatting
"""

import csv
import json
import math
import os
import sys
import time
from datetime import datetime
from pathlib import Path

# Add parent to path so tests can import nanovna_v2
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from python.nanovna_v2 import NanoVNA_V2, DeviceIdentity, SweepResult


# ─── Constants ───────────────────────────────────────────────────────────

DEFAULT_START_HZ = 2_395_000_000   # 2395 MHz
DEFAULT_STOP_HZ  = 2_405_000_000   # 2405 MHz
DEFAULT_POINTS   = 11
DEFAULT_CENTER   = 2_400_000_000   # 2400 MHz

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data" / "validation"


# ─── COM port detection ─────────────────────────────────────────────────

def find_nanovna_port() -> str | None:
    """Auto-detect SAA-2N COM port by trying INDICATE on non-Bluetooth ports."""
    import serial.tools.list_ports

    ports = serial.tools.list_ports.comports()
    candidates = []
    for p in ports:
        desc_lower = (p.description or "").lower()
        if "bluetooth" in desc_lower:
            continue
        candidates.append(p.device)

    for port in candidates:
        try:
            vna = NanoVNA_V2()
            vna.connect(port, timeout=1.0)
            ok = vna.indicate()
            vna.disconnect()
            if ok:
                return port
        except Exception:
            continue
    return None


def get_port_from_args_or_detect() -> str:
    """Get COM port from command line arg or auto-detect. Exits on failure."""
    if len(sys.argv) > 1 and not sys.argv[1].startswith("-"):
        port = sys.argv[1]
        print(f"[PORT] Using specified port: {port}")
        return port

    print("[PORT] Auto-detecting SAA-2N...")
    port = find_nanovna_port()
    if port is None:
        print("[FAIL] SAA-2N not found. Connect via USB and retry.")
        print("       Usage: python <script>.py COMx")
        sys.exit(1)
    print(f"[PORT] Detected: {port}")
    return port


# ─── Experiment logging ─────────────────────────────────────────────────

def create_experiment_dir(test_name: str) -> Path:
    """Create timestamped experiment directory.

    Returns path like: data/validation/thru_20260927_160000/
    """
    ts = datetime.now().strftime("%Y%m%d_%H%M%S")
    dirname = f"{test_name}_{ts}"
    exp_dir = DATA_DIR / dirname
    exp_dir.mkdir(parents=True, exist_ok=True)
    return exp_dir


def save_config(exp_dir: Path, identity: DeviceIdentity,
                start_hz: int, stop_hz: int, points: int,
                dut: str, extra: dict | None = None) -> Path:
    """Save experiment config.json."""
    config = {
        "device": "SAA-2N",
        "display_firmware": "DiSlord v1.4.02 FPU",
        "usb_register_firmware_major": identity.firmware_major,
        "usb_register_firmware_minor": identity.firmware_minor,
        "device_variant": f"0x{identity.device_variant:02X}",
        "protocol_version": identity.protocol_version,
        "hardware_revision": identity.hardware_revision,
        "port": identity.port,
        "start_hz": start_hz,
        "stop_hz": stop_hz,
        "points": points,
        "dut": dut,
        "timestamp": datetime.now().isoformat(),
    }
    if extra:
        config.update(extra)

    path = exp_dir / "config.json"
    with open(path, "w") as f:
        json.dump(config, f, indent=2)
    return path


def save_sweep_csv(exp_dir: Path, result: SweepResult,
                   filename: str = "raw.csv") -> Path:
    """Save sweep result as CSV with full complex data."""
    path = exp_dir / filename
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow([
            "freq_index", "frequency_hz",
            "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
            "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
            "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
        ])
        for rec in result.records:
            freq_hz = result.start_hz + rec.freq_index * result.step_hz
            s11 = rec.s11
            s21 = rec.s21
            s11_mag = abs(s11)
            s21_mag = abs(s21)
            s11_db = 20 * math.log10(s11_mag) if s11_mag > 0 else -999.0
            s21_db = 20 * math.log10(s21_mag) if s21_mag > 0 else -999.0
            s11_phase = math.degrees(math.atan2(s11.imag, s11.real))
            s21_phase = math.degrees(math.atan2(s21.imag, s21.real))

            writer.writerow([
                rec.freq_index, freq_hz,
                s11.real, s11.imag, s11_mag, f"{s11_db:.4f}", f"{s11_phase:.4f}",
                s21.real, s21.imag, s21_mag, f"{s21_db:.4f}", f"{s21_phase:.4f}",
                rec.fwd0_re, rec.fwd0_im,
                rec.rev0_re, rec.rev0_im,
                rec.rev1_re, rec.rev1_im,
            ])
    return path


def save_summary(exp_dir: Path, text: str) -> Path:
    """Save summary.txt."""
    path = exp_dir / "summary.txt"
    with open(path, "w") as f:
        f.write(text)
    return path


# ─── Display helpers ─────────────────────────────────────────────────────

def print_header(title: str) -> None:
    print()
    print("=" * 60)
    print(f"  {title}")
    print("=" * 60)
    print()


def print_identity(identity: DeviceIdentity) -> None:
    print(f"  deviceVariant    = 0x{identity.device_variant:02X}"
          + (" ← V2 ✓" if identity.is_v2 else " ← unexpected!"))
    print(f"  protocolVersion  = 0x{identity.protocol_version:02X}")
    print(f"  hardwareRevision = {identity.hardware_revision}")
    print(f"  firmware         = {identity.firmware_major}.{identity.firmware_minor}")
    print(f"  port             = {identity.port}")


def print_sweep_table(result: SweepResult, show_complex: bool = False) -> None:
    """Print sweep results in a formatted table."""
    if show_complex:
        print(f"  {'#':>3}  {'Freq (MHz)':>11}  "
              f"{'S11 dB':>8}  {'S11 phase':>10}  "
              f"{'S21 dB':>8}  {'S21 phase':>10}  "
              f"{'S11 re':>10}  {'S11 im':>10}  "
              f"{'S21 re':>10}  {'S21 im':>10}")
    else:
        print(f"  {'#':>3}  {'Freq (MHz)':>11}  {'S11 dB':>8}  {'S21 dB':>8}")

    for i, rec in enumerate(result.records):
        freq_hz = result.start_hz + rec.freq_index * result.step_hz
        s11 = rec.s11
        s21 = rec.s21
        s11_db = 20 * math.log10(abs(s11)) if abs(s11) > 0 else -999.0
        s21_db = 20 * math.log10(abs(s21)) if abs(s21) > 0 else -999.0
        s11_ph = math.degrees(math.atan2(s11.imag, s11.real))
        s21_ph = math.degrees(math.atan2(s21.imag, s21.real))

        if show_complex:
            print(f"  {i:3d}  {freq_hz/1e6:11.3f}  "
                  f"{s11_db:8.2f}  {s11_ph:10.2f}°  "
                  f"{s21_db:8.2f}  {s21_ph:10.2f}°  "
                  f"{s11.real:10.6f}  {s11.imag:10.6f}  "
                  f"{s21.real:10.6f}  {s21.imag:10.6f}")
        else:
            print(f"  {i:3d}  {freq_hz/1e6:11.3f}  {s11_db:8.2f}  {s21_db:8.2f}")


def s_param_db(s: complex) -> float:
    """Convert complex S-parameter to dB."""
    mag = abs(s)
    if mag == 0:
        return -999.0
    return 20 * math.log10(mag)


def s_param_phase_deg(s: complex) -> float:
    """Phase of complex S-parameter in degrees."""
    return math.degrees(math.atan2(s.imag, s.real))
