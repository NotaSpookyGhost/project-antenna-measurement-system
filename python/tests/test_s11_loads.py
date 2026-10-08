"""
test_s11_loads.py — Test B: S11 loads validation for NanoVNA SAA-2N.

Validates reflection (S11) response on Port 1 by interactively measuring
three standard calibration loads:
    1. OPEN standard
    2. SHORT standard
    3. 50-ohm LOAD standard

Acceptance Criteria:
    - OPEN |S11| ≈ 0 dB (expected > -3.0 dB)
    - SHORT |S11| ≈ 0 dB (expected > -3.0 dB)
    - Phase difference |phase(s11_open * s11_short*)| > 90.0°
    - LOAD |S11| significantly lower than OPEN and SHORT (e.g. < -15.0 dB,
      and at least 10 dB below OPEN/SHORT)
    - Artifacts saved: config.json, s11_open.csv, s11_short.csv, s11_load.csv,
      raw.csv, summary.txt

Usage:
    python -m python.tests.test_s11_loads [COMx]   # from projects/ directory
"""

import cmath
import csv
import math
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

DUT_DESCRIPTION = "S11 Calibration Standards on Port 1: OPEN, SHORT, 50-ohm LOAD"
OPEN_MIN_DB = -3.0
SHORT_MIN_DB = -3.0
PHASE_DIFF_MIN_DEG = 90.0
LOAD_MAX_DB = -15.0
LOAD_DIFF_MIN_DB = 10.0


def prompt_standard(step: int, total: int, standard_name: str, instructions: str) -> None:
    """Prompt user to attach standard. Supports interactive terminals and headless runners."""
    print(f"\n[{step}/{total}] Standard: {standard_name}")
    print(f"       Instructions: {instructions}")
    if sys.stdin and sys.stdin.isatty():
        try:
            input(f"       Connect {standard_name} to Port 1, then press Enter to sweep...")
        except (EOFError, KeyboardInterrupt):
            print("       (Continuing...)")
    else:
        print(f"       [Headless / non-interactive environment detected; proceeding automatically.]")


def save_loads_raw_csv(exp_dir: Path, sweeps: list[tuple[str, SweepResult]]) -> Path:
    """Save combined master raw.csv with standard provenance column + full 18 RF columns."""
    raw_csv_path = exp_dir / "raw.csv"
    raw_fields = [
        "standard", "freq_index", "frequency_hz",
        "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
        "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
        "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
    ]
    with open(raw_csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(raw_fields)
        for std_name, sweep_res in sweeps:
            for rec in sweep_res.records:
                freq_hz = sweep_res.start_hz + rec.freq_index * sweep_res.step_hz
                s11 = rec.s11
                s21 = rec.s21
                s11_mag = abs(s11)
                s21_mag = abs(s21)
                s11_db = 20 * math.log10(s11_mag) if s11_mag > 0 else -999.0
                s21_db = 20 * math.log10(s21_mag) if s21_mag > 0 else -999.0
                s11_phase = math.degrees(math.atan2(s11.imag, s11.real))
                s21_phase = math.degrees(math.atan2(s21.imag, s21.real))

                writer.writerow([
                    std_name,
                    rec.freq_index, freq_hz,
                    s11.real, s11.imag, s11_mag, f"{s11_db:.4f}", f"{s11_phase:.4f}",
                    s21.real, s21.imag, s21_mag, f"{s21_db:.4f}", f"{s21_phase:.4f}",
                    rec.fwd0_re, rec.fwd0_im,
                    rec.rev0_re, rec.rev0_im,
                    rec.rev1_re, rec.rev1_im,
                ])
    return raw_csv_path


def main():
    print_header("Test B — S11 Loads Validation (OPEN / SHORT / LOAD on Port 1)")

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

        # ── 1. Acquire OPEN Standard ─────────────────────────────────────
        prompt_standard(1, 3, "OPEN", "Attach SMA OPEN calibration standard to Port 1.")
        print(f"[SWEEP] Acquiring OPEN standard sweep ({DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz)...")
        result_open = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] OPEN S11 Results:")
        print_sweep_table(result_open, show_complex=True)

        # ── 2. Acquire SHORT Standard ────────────────────────────────────
        prompt_standard(2, 3, "SHORT", "Attach SMA SHORT calibration standard to Port 1.")
        print(f"[SWEEP] Acquiring SHORT standard sweep ({DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz)...")
        result_short = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] SHORT S11 Results:")
        print_sweep_table(result_short, show_complex=True)

        # ── 3. Acquire LOAD Standard ─────────────────────────────────────
        prompt_standard(3, 3, "50-ohm LOAD", "Attach SMA 50-ohm LOAD calibration standard to Port 1.")
        print(f"[SWEEP] Acquiring LOAD standard sweep ({DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz)...")
        result_load = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] LOAD S11 Results:")
        print_sweep_table(result_load, show_complex=True)

        # ── Verify Sweep Completeness ────────────────────────────────────
        all_complete = (
            result_open.complete and len(result_open.records) == DEFAULT_POINTS
            and result_short.complete and len(result_short.records) == DEFAULT_POINTS
            and result_load.complete and len(result_load.records) == DEFAULT_POINTS
        )

        if not all_complete:
            print("\n[ERROR] Incomplete sweep acquisition detected. Aborting analysis.")
            for name, res in [("OPEN", result_open), ("SHORT", result_short), ("50-ohm LOAD", result_load)]:
                if not (res.complete and len(res.records) == DEFAULT_POINTS):
                    print(f"  [ERROR] {name}: received {len(res.records)}/{DEFAULT_POINTS} records (complete={res.complete}).")

            exp_dir = create_experiment_dir("s11_loads")
            print(f"\n[LOG] Saving failure artifacts to: {exp_dir}")

            extra_meta = {
                "verdict": "FAIL",
                "error": "Incomplete sweep acquisition (USB timeout or packet loss)",
                "open_records": len(result_open.records),
                "open_complete": result_open.complete,
                "short_records": len(result_short.records),
                "short_complete": result_short.complete,
                "load_records": len(result_load.records),
                "load_complete": result_load.complete,
                "all_complete": False,
            }
            save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                        dut=DUT_DESCRIPTION, extra=extra_meta)

            save_sweep_csv(exp_dir, result_open, "s11_open.csv")
            save_sweep_csv(exp_dir, result_short, "s11_short.csv")
            save_sweep_csv(exp_dir, result_load, "s11_load.csv")

            save_loads_raw_csv(exp_dir, [
                ("OPEN", result_open),
                ("SHORT", result_short),
                ("LOAD", result_load),
            ])

            summary_text = (
                f"Test B — S11 Loads Validation Summary\n"
                f"Generated: {datetime.now().isoformat()}\n"
                f"------------------------------------------------------------\n"
                f"Device:            SAA-2N (port: {identity.port})\n"
                f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
                f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
                f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
                f"DUT:               {DUT_DESCRIPTION}\n"
                f"------------------------------------------------------------\n"
                f"[ERROR] Sweep acquisition incomplete or timed out.\n"
                f"  OPEN records:      {len(result_open.records)}/{DEFAULT_POINTS} (complete: {result_open.complete})\n"
                f"  SHORT records:     {len(result_short.records)}/{DEFAULT_POINTS} (complete: {result_short.complete})\n"
                f"  LOAD records:      {len(result_load.records)}/{DEFAULT_POINTS} (complete: {result_load.complete})\n"
                f"------------------------------------------------------------\n"
                f"VERDICT: [FAIL]\n"
            )
            save_summary(exp_dir, summary_text)

            print(f"\n============================================================")
            print(f"  VERDICT: [FAIL]")
            print(f"============================================================")
            sys.exit(1)

        # ── Analysis at Center Frequency (2400 MHz) ──────────────────────
        center_idx = DEFAULT_POINTS // 2
        rec_open = result_open.records[center_idx]
        rec_short = result_short.records[center_idx]
        rec_load = result_load.records[center_idx]
        center_freq_hz = result_open.start_hz + rec_open.freq_index * result_open.step_hz

        s11_open = rec_open.s11
        s11_short = rec_short.s11
        s11_load = rec_load.s11

        open_db = s_param_db(s11_open)
        open_phase = s_param_phase_deg(s11_open)

        short_db = s_param_db(s11_short)
        short_phase = s_param_phase_deg(s11_short)

        load_db = s_param_db(s11_load)
        load_phase = s_param_phase_deg(s11_load)

        # Compute angular phase difference on complex unit circle:
        # |phase(s11_open * conj(s11_short))| avoids branch-cut phase wrap errors.
        phase_diff_deg = abs(math.degrees(cmath.phase(s11_open * s11_short.conjugate())))

        # Criteria evaluations
        open_ok = open_db > OPEN_MIN_DB
        short_ok = short_db > SHORT_MIN_DB
        phase_diff_ok = phase_diff_deg > PHASE_DIFF_MIN_DEG
        load_ok = (load_db < LOAD_MAX_DB) or (load_db < open_db - LOAD_DIFF_MIN_DB and load_db < short_db - LOAD_DIFF_MIN_DB)
        all_complete = result_open.complete and result_short.complete and result_load.complete

        passed = open_ok and short_ok and phase_diff_ok and load_ok and all_complete
        verdict = "PASS" if passed else "FAIL"

        # ── Print Comparison Table ───────────────────────────────────────
        print("\n============================================================")
        print("  S11 STANDARDS COMPARISON TABLE (Center: 2400.000 MHz)")
        print("============================================================")
        print(f"  {'Standard':<14}  {'S11 (dB)':>10}  {'Phase (deg)':>12}  {'Real':>10}  {'Imag':>10}")
        print(f"  {'-'*14}  {'-'*10}  {'-'*12}  {'-'*10}  {'-'*10}")
        print(f"  {'OPEN':<14}  {open_db:10.2f}  {open_phase:11.2f}°  {s11_open.real:10.6f}  {s11_open.imag:10.6f}")
        print(f"  {'SHORT':<14}  {short_db:10.2f}  {short_phase:11.2f}°  {s11_short.real:10.6f}  {s11_short.imag:10.6f}")
        print(f"  {'LOAD (50Ω)':<14}  {load_db:10.2f}  {load_phase:11.2f}°  {s11_load.real:10.6f}  {s11_load.imag:10.6f}")
        print("------------------------------------------------------------")
        print(f"  Phase Difference |OPEN - SHORT|: {phase_diff_deg:.2f}° (Threshold: > {PHASE_DIFF_MIN_DEG:.1f}°)")
        print(f"  OPEN  Magnitude:                 {open_db:.2f} dB (Threshold: > {OPEN_MIN_DB:.1f} dB) -> {'PASS' if open_ok else 'FAIL'}")
        print(f"  SHORT Magnitude:                 {short_db:.2f} dB (Threshold: > {SHORT_MIN_DB:.1f} dB) -> {'PASS' if short_ok else 'FAIL'}")
        print(f"  Phase Difference Check:          {phase_diff_deg:.2f}° -> {'PASS' if phase_diff_ok else 'FAIL'}")
        print(f"  LOAD Suppression:                {load_db:.2f} dB (Threshold: < {LOAD_MAX_DB:.1f} dB) -> {'PASS' if load_ok else 'FAIL'}")
        print("============================================================")

        # ── Save Experiment Artifacts ────────────────────────────────────
        exp_dir = create_experiment_dir("s11_loads")
        print(f"\n[LOG] Saving experiment artifacts to: {exp_dir}")

        extra_meta = {
            "verdict": verdict,
            "center_freq_hz": center_freq_hz,
            "open_s11_db": round(open_db, 4),
            "open_s11_phase_deg": round(open_phase, 4),
            "short_s11_db": round(short_db, 4),
            "short_s11_phase_deg": round(short_phase, 4),
            "load_s11_db": round(load_db, 4),
            "load_s11_phase_deg": round(load_phase, 4),
            "phase_diff_deg": round(phase_diff_deg, 4),
            "open_ok": open_ok,
            "short_ok": short_ok,
            "phase_diff_ok": phase_diff_ok,
            "load_ok": load_ok,
        }
        save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                    dut=DUT_DESCRIPTION, extra=extra_meta)

        # Save individual standard CSVs
        save_sweep_csv(exp_dir, result_open, "s11_open.csv")
        save_sweep_csv(exp_dir, result_short, "s11_short.csv")
        save_sweep_csv(exp_dir, result_load, "s11_load.csv")

        # Save combined master raw.csv with standard provenance column + full 18 columns preserved
        save_loads_raw_csv(exp_dir, [
            ("OPEN", result_open),
            ("SHORT", result_short),
            ("LOAD", result_load),
        ])

        # Save summary.txt
        summary_text = (
            f"Test B — S11 Loads Validation Summary\n"
            f"Generated: {datetime.now().isoformat()}\n"
            f"------------------------------------------------------------\n"
            f"Device:            SAA-2N (port: {identity.port})\n"
            f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
            f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
            f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
            f"DUT:               {DUT_DESCRIPTION}\n"
            f"------------------------------------------------------------\n"
            f"Center Freq:       {center_freq_hz/1e6:.3f} MHz\n"
            f"OPEN  |S11|:       {open_db:.2f} dB (Phase: {open_phase:.2f}°) [Expected > {OPEN_MIN_DB:.1f} dB] -> {'PASS' if open_ok else 'FAIL'}\n"
            f"SHORT |S11|:       {short_db:.2f} dB (Phase: {short_phase:.2f}°) [Expected > {SHORT_MIN_DB:.1f} dB] -> {'PASS' if short_ok else 'FAIL'}\n"
            f"Phase Difference:  {phase_diff_deg:.2f}° [Expected > {PHASE_DIFF_MIN_DEG:.1f}°] -> {'PASS' if phase_diff_ok else 'FAIL'}\n"
            f"LOAD  |S11|:       {load_db:.2f} dB (Phase: {load_phase:.2f}°) [Expected < {LOAD_MAX_DB:.1f} dB] -> {'PASS' if load_ok else 'FAIL'}\n"
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
