"""
test_thru.py — Test A: THRU validation for NanoVNA SAA-2N.

Tests forward transmission (S21) across the RF chain by connecting Port 1 (TX)
directly to Port 2 (RX) via a short 50-ohm SMA coaxial cable.

Validates that:
    1. Sweep acquisition succeeds across 2395–2405 MHz (11 points).
    2. Full complex S11 and S21 data is displayed.
    3. Transmission S21 at center frequency (2400 MHz) is > -10.0 dB
       (indicating a genuine signal path rather than noise floor ~-70 dB).
    4. Experiment artifacts (config.json, raw.csv, summary.txt) are saved.

Usage:
    python -m python.tests.test_thru [COMx]   # from projects/ directory
"""

import sys
from datetime import datetime
from pathlib import Path

import serial

# Ensure 'projects' directory is in sys.path for robust resolution
PROJECTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(PROJECTS_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECTS_DIR))

from python.nanovna_v2 import NanoVNA_V2, DeviceIdentity, NanoVNAError, SweepResult
from python.tests.test_helpers import (
    DEFAULT_CENTER,
    DEFAULT_POINTS,
    DEFAULT_START_HZ,
    DEFAULT_STOP_HZ,
    create_experiment_dir,
    get_port_from_args_or_detect,
    print_header,
    print_identity,
    print_sweep_table,
    s_param_db,
    s_param_phase_deg,
    save_config,
    save_summary,
    save_sweep_csv,
)

DUT_DESCRIPTION = "THRU SMA cable Port 1 <-> Port 2"
S21_PASS_THRESHOLD_DB = -10.0


def main():
    print_header("Test A — THRU Validation (Port 1 <-> Port 2)")

    port = get_port_from_args_or_detect()
    vna = NanoVNA_V2()

    try:
        print(f"\n[CONNECT] Connecting to {port}...")
        try:
            vna.connect(port)
            identity = vna.identify()
        except (serial.SerialException, NanoVNAError, OSError) as e:
            print(f"[ERROR] Failed to connect to NanoVNA on {port}: {e}")
            print(f"\n============================================================")
            print(f"  VERDICT: [FAIL]")
            print(f"============================================================")
            sys.exit(1)

        print_identity(identity)

        print(f"\n[SWEEP] Acquiring sweep ({DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points)...")
        result = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)

        # Save experiment artifacts
        exp_dir = create_experiment_dir("thru")
        print(f"\n[LOG] Saving experiment artifacts to: {exp_dir}")

        if not result.records:
            print("[ERROR] No FIFO records received from device.")
            verdict = "FAIL"
            passed = False

            extra_meta = {
                "verdict": verdict,
                "error": "No FIFO records received from device (timeout)",
                "threshold_db": S21_PASS_THRESHOLD_DB,
            }
            save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                        dut=DUT_DESCRIPTION, extra=extra_meta)
            save_sweep_csv(exp_dir, result, "raw.csv")

            summary_text = (
                f"Test A — THRU Validation Summary\n"
                f"Generated: {datetime.now().isoformat()}\n"
                f"------------------------------------------------------------\n"
                f"Device:            SAA-2N (port: {identity.port})\n"
                f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
                f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
                f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
                f"DUT:               {DUT_DESCRIPTION}\n"
                f"------------------------------------------------------------\n"
                f"Status:            ERROR — No FIFO records received from device (timeout)\n"
                f"Complete:          False (0/{DEFAULT_POINTS} points)\n"
                f"Criterion:         S21 > {S21_PASS_THRESHOLD_DB:.1f} dB\n"
                f"------------------------------------------------------------\n"
                f"VERDICT: [FAIL]\n"
            )
            save_summary(exp_dir, summary_text)
        else:
            print("\n[DATA] Sweep results (show_complex=True):")
            print_sweep_table(result, show_complex=True)

            # Locate center frequency record (2400 MHz)
            center_idx = len(result.records) // 2
            center_rec = result.records[center_idx]
            center_freq_hz = result.start_hz + center_rec.freq_index * result.step_hz
            center_s21 = center_rec.s21
            center_s21_db = s_param_db(center_s21)
            center_s21_phase = s_param_phase_deg(center_s21)

            center_s11 = center_rec.s11
            center_s11_db = s_param_db(center_s11)
            center_s11_phase = s_param_phase_deg(center_s11)

            # Evaluate S21 transmission across all points
            all_s21_db = [s_param_db(r.s21) for r in result.records]
            min_s21_db = min(all_s21_db)
            max_s21_db = max(all_s21_db)
            mean_s21_db = sum(all_s21_db) / len(all_s21_db)

            # Verdict criteria: Center frequency S21 > -10.0 dB
            passed = (center_s21_db > S21_PASS_THRESHOLD_DB) and result.complete
            verdict = "PASS" if passed else "FAIL"

            print(f"\n[ANALYSIS] Transmission Metrics:")
            print(f"  Center Freq:       {center_freq_hz/1e6:.3f} MHz")
            print(f"  Center S21:        {center_s21_db:.2f} dB (Phase: {center_s21_phase:.2f}°)")
            print(f"  Center S11:        {center_s11_db:.2f} dB (Phase: {center_s11_phase:.2f}°)")
            print(f"  S21 Band Range:    {min_s21_db:.2f} to {max_s21_db:.2f} dB (Mean: {mean_s21_db:.2f} dB)")
            print(f"  Complete Sweep:    {result.complete} ({len(result.records)}/{result.points} points)")
            print(f"  Threshold Check:   S21 > {S21_PASS_THRESHOLD_DB:.1f} dB -> {'OK' if center_s21_db > S21_PASS_THRESHOLD_DB else 'FAILED'}")

            extra_meta = {
                "verdict": verdict,
                "center_freq_hz": center_freq_hz,
                "center_s21_db": round(center_s21_db, 4),
                "center_s21_phase_deg": round(center_s21_phase, 4),
                "center_s11_db": round(center_s11_db, 4),
                "center_s11_phase_deg": round(center_s11_phase, 4),
                "min_s21_db": round(min_s21_db, 4),
                "max_s21_db": round(max_s21_db, 4),
                "mean_s21_db": round(mean_s21_db, 4),
                "threshold_db": S21_PASS_THRESHOLD_DB,
            }
            save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                        dut=DUT_DESCRIPTION, extra=extra_meta)
            save_sweep_csv(exp_dir, result, "raw.csv")

            summary_text = (
                f"Test A — THRU Validation Summary\n"
                f"Generated: {datetime.now().isoformat()}\n"
                f"------------------------------------------------------------\n"
                f"Device:            SAA-2N (port: {identity.port})\n"
                f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
                f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
                f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
                f"DUT:               {DUT_DESCRIPTION}\n"
                f"------------------------------------------------------------\n"
                f"Center Freq:       {center_freq_hz/1e6:.3f} MHz\n"
                f"Center S21 (dB):   {center_s21_db:.2f} dB (phase: {center_s21_phase:.2f}°)\n"
                f"Center S11 (dB):   {center_s11_db:.2f} dB (phase: {center_s11_phase:.2f}°)\n"
                f"S21 Band Range:    {min_s21_db:.2f} to {max_s21_db:.2f} dB\n"
                f"Complete:          {result.complete} ({len(result.records)}/{result.points})\n"
                f"Criterion:         S21 > {S21_PASS_THRESHOLD_DB:.1f} dB\n"
                f"------------------------------------------------------------\n"
                f"VERDICT: [{verdict}]\n"
            )
            save_summary(exp_dir, summary_text)

        print(f"\n============================================================")
        print(f"  VERDICT: [{verdict}]")
        print(f"============================================================")

        if not passed:
            sys.exit(1)
        return 0

    finally:
        vna.disconnect()
        print(f"[CLEANUP] Disconnected from {port}.")


if __name__ == "__main__":
    main()
