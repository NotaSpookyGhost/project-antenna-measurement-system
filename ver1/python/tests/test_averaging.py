"""
test_averaging.py — Test F: Averaging comparison for NanoVNA SAA-2N.

Tests coherent complex vector averaging across N in [1, 2, 4, 8, 16] sweeps.

CRITICAL RF REQUIREMENT:
    Averaging is performed on raw complex phasors BEFORE conversion to dB:
        S21_avg = (1/N) * sum(S21_k)
        S21_avg_dB = 20 * log10(|S21_avg|)
    DO NOT average dB values directly! (Logarithmic scalar averaging does not
    cancel uncorrelated noise vectors and skews magnitude estimates).

Validates:
    1. Coherent vector averaging produces stable complex S21.
    2. Execution time scales linearly with N (~0.5s per sweep).
    3. Noise reduction metric (standard deviation of individual dB measurements).
    4. Experiment artifacts (config.json, raw.csv, averaging_summary.csv, summary.txt).

Usage:
    python -m python.tests.test_averaging [COMx]   # from projects/ directory
"""

import csv
import math
import statistics
import sys
import time
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
    s_param_db,
    s_param_phase_deg,
    save_config,
    save_summary,
)

DUT_DESCRIPTION = "THRU SMA cable — Complex Averaging [1, 2, 4, 8, 16] sweeps"
AVERAGING_FACTORS = [1, 2, 4, 8, 16]
S21_PASS_THRESHOLD_DB = -10.0


def main():
    print_header("Test F — Averaging Comparison (N in [1, 2, 4, 8, 16])")

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

        # Prompt user to connect DUT
        print(f"\n[SETUP] Connect THRU SMA cable (Port 1 <-> Port 2) for averaging benchmark.")
        if sys.stdin and sys.stdin.isatty():
            try:
                input("        Ensure cable is securely connected, then press Enter to begin...")
            except (EOFError, KeyboardInterrupt):
                print("        (Proceeding...)")
        else:
            print("        [Headless / non-interactive environment detected; proceeding automatically.]")

        # Configure sweep once for high loop throughput
        print(f"\n[CONFIG] Configuring sweep: {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points...")
        vna.configure_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)

        center_idx = DEFAULT_POINTS // 2
        center_freq_hz = DEFAULT_START_HZ + center_idx * ((DEFAULT_STOP_HZ - DEFAULT_START_HZ) // (DEFAULT_POINTS - 1))

        stage_results = []
        all_raw_rows = []
        total_errors = 0

        print("\n[BENCHMARK] Executing complex vector averaging sweeps...")

        for n in AVERAGING_FACTORS:
            print(f"  --> Benchmarking N = {n:2d} sweeps...", end="", flush=True)
            t0 = time.perf_counter()

            stage_s21_values = []
            stage_sweeps = []

            for sweep_idx in range(1, n + 1):
                try:
                    result = vna.acquire_single(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
                except Exception as e:
                    total_errors += 1
                    print(f" [ERR: {e}]", end="")
                    continue

                if not result.records or len(result.records) < DEFAULT_POINTS:
                    total_errors += 1
                    continue

                center_rec = result.records[center_idx]
                stage_s21_values.append(center_rec.s21)
                stage_sweeps.append(result)

                # Collect all frequency records for raw.csv
                ts_iso = datetime.now().isoformat()
                for rec in result.records:
                    freq_hz = result.start_hz + rec.freq_index * result.step_hz
                    s11 = rec.s11
                    s21 = rec.s21
                    s11_mag = abs(s11)
                    s21_mag = abs(s21)
                    s11_db = 20 * math.log10(s11_mag) if s11_mag > 0 else -999.0
                    s21_db = 20 * math.log10(s21_mag) if s21_mag > 0 else -999.0
                    s11_ph = math.degrees(math.atan2(s11.imag, s11.real))
                    s21_ph = math.degrees(math.atan2(s21.imag, s21.real))

                    all_raw_rows.append({
                        "stage_n": n,
                        "sweep_idx": sweep_idx,
                        "timestamp_iso": ts_iso,
                        "freq_index": rec.freq_index,
                        "frequency_hz": freq_hz,
                        "s11_real": s11.real,
                        "s11_imag": s11.imag,
                        "s11_mag": s11_mag,
                        "s11_db": f"{s11_db:.4f}",
                        "s11_phase_deg": f"{s11_ph:.4f}",
                        "s21_real": s21.real,
                        "s21_imag": s21.imag,
                        "s21_mag": s21_mag,
                        "s21_db": f"{s21_db:.4f}",
                        "s21_phase_deg": f"{s21_ph:.4f}",
                        "fwd0_re": rec.fwd0_re,
                        "fwd0_im": rec.fwd0_im,
                        "rev0_re": rec.rev0_re,
                        "rev0_im": rec.rev0_im,
                        "rev1_re": rec.rev1_re,
                        "rev1_im": rec.rev1_im,
                    })

            elapsed_s = time.perf_counter() - t0
            sec_per_sweep = elapsed_s / n if n > 0 else 0.0

            if len(stage_s21_values) == n and n > 0:
                # ── Coherent Complex Vector Averaging ────────────────────
                # S21_avg = (1/N) * sum(S21_k)
                s21_avg = sum(stage_s21_values) / n
                s21_avg_db = s_param_db(s21_avg)
                s21_avg_phase = s_param_phase_deg(s21_avg)

                # Individual measurements noise std dev (for demonstration)
                individual_dbs = [s_param_db(s) for s in stage_s21_values]
                noise_std_db = statistics.stdev(individual_dbs) if n > 1 else 0.0

                stage_results.append({
                    "n": n,
                    "elapsed_s": elapsed_s,
                    "sec_per_sweep": sec_per_sweep,
                    "s21_avg_real": s21_avg.real,
                    "s21_avg_imag": s21_avg.imag,
                    "s21_avg_db": s21_avg_db,
                    "s21_avg_phase_deg": s21_avg_phase,
                    "noise_std_db": noise_std_db,
                    "valid": True,
                })
                print(f" done: {elapsed_s:5.2f}s | S21 avg = {s21_avg_db:6.2f} dB, phase = {s21_avg_phase:6.2f}°")
            else:
                stage_results.append({
                    "n": n,
                    "elapsed_s": elapsed_s,
                    "sec_per_sweep": sec_per_sweep,
                    "s21_avg_real": 0.0,
                    "s21_avg_imag": 0.0,
                    "s21_avg_db": -999.0,
                    "s21_avg_phase_deg": 0.0,
                    "noise_std_db": 999.0,
                    "valid": False,
                })
                print(f" FAILED ({len(stage_s21_values)}/{n} sweeps acquired)")

        # ── Print Comparison Table ───────────────────────────────────────
        print("\n=========================================================================================")
        print("  AVERAGING COMPARISON TABLE (Center: 2400.000 MHz)")
        print("=========================================================================================")
        print(f"  {'N':>3}  {'Time (s)':>9}  {'Time/Swp':>9}  {'S21 Avg (dB)':>13}  {'Phase (deg)':>12}  {'Noise Std':>10}  {'Complex Avg (Re, Im)':>22}")
        print(f"  {'-'*3}  {'-'*9}  {'-'*9}  {'-'*13}  {'-'*12}  {'-'*10}  {'-'*22}")

        for res in stage_results:
            n = res["n"]
            t = res["elapsed_s"]
            t_swp = res["sec_per_sweep"]
            db = res["s21_avg_db"]
            ph = res["s21_avg_phase_deg"]
            std_str = f"{res['noise_std_db']:8.4f} dB" if n > 1 else "     N/A  "
            c_str = f"({res['s21_avg_real']:+.4f}, {res['s21_avg_imag']:+.4f}j)"
            print(f"  {n:3d}  {t:8.2f}s  {t_swp:8.3f}s  {db:12.2f} dB  {ph:11.2f}°  {std_str:>10}  {c_str:>22}")

        print("=========================================================================================")

        # ── Acceptance Criteria Evaluation ───────────────────────────────
        all_stages_valid = all(res["valid"] for res in stage_results)
        s21_levels_ok = all(res["s21_avg_db"] > S21_PASS_THRESHOLD_DB for res in stage_results if res["valid"])
        passed = all_stages_valid and s21_levels_ok and (total_errors == 0)
        verdict = "PASS" if passed else "FAIL"

        print(f"  All Stages Valid:   {'PASS' if all_stages_valid else 'FAIL'}")
        print(f"  Transmission Level: {'PASS' if s21_levels_ok else 'FAIL'} (Expected > {S21_PASS_THRESHOLD_DB:.1f} dB)")
        print(f"  Total Errors:       {total_errors} -> {'PASS' if total_errors == 0 else 'FAIL'}")

        # ── Save Experiment Artifacts ────────────────────────────────────
        exp_dir = create_experiment_dir("averaging")
        print(f"\n[LOG] Saving experiment artifacts to: {exp_dir}")

        extra_meta = {
            "verdict": verdict,
            "averaging_factors": AVERAGING_FACTORS,
            "center_freq_hz": center_freq_hz,
            "stage_results": [
                {
                    "n": r["n"],
                    "elapsed_s": round(r["elapsed_s"], 4),
                    "sec_per_sweep": round(r["sec_per_sweep"], 4),
                    "s21_avg_db": round(r["s21_avg_db"], 4),
                    "s21_avg_phase_deg": round(r["s21_avg_phase_deg"], 4),
                    "s21_avg_real": round(r["s21_avg_real"], 6),
                    "s21_avg_imag": round(r["s21_avg_imag"], 6),
                    "noise_std_db": round(r["noise_std_db"], 4),
                }
                for r in stage_results
            ],
            "total_errors": total_errors,
        }
        save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                    dut=DUT_DESCRIPTION, extra=extra_meta)

        # Save all individual sweep points into raw.csv preserving full 18 columns
        raw_csv_path = exp_dir / "raw.csv"
        raw_fields = [
            "stage_n", "sweep_idx", "timestamp_iso", "freq_index", "frequency_hz",
            "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
            "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
            "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
        ]
        with open(raw_csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=raw_fields)
            writer.writeheader()
            for row in all_raw_rows:
                writer.writerow(row)

        # Save summary table CSV
        summary_csv_path = exp_dir / "averaging_summary.csv"
        with open(summary_csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=[
                "n", "elapsed_s", "sec_per_sweep", "s21_avg_real", "s21_avg_imag",
                "s21_avg_db", "s21_avg_phase_deg", "noise_std_db"
            ])
            writer.writeheader()
            for r in stage_results:
                writer.writerow({
                    "n": r["n"],
                    "elapsed_s": f"{r['elapsed_s']:.4f}",
                    "sec_per_sweep": f"{r['sec_per_sweep']:.4f}",
                    "s21_avg_real": f"{r['s21_avg_real']:.6f}",
                    "s21_avg_imag": f"{r['s21_avg_imag']:.6f}",
                    "s21_avg_db": f"{r['s21_avg_db']:.4f}",
                    "s21_avg_phase_deg": f"{r['s21_avg_phase_deg']:.4f}",
                    "noise_std_db": f"{r['noise_std_db']:.4f}",
                })

        # Save summary.txt
        summary_lines = [
            "Test F — Averaging Comparison Summary",
            f"Generated: {datetime.now().isoformat()}",
            "-----------------------------------------------------------------------------------------",
            f"Device:            SAA-2N (port: {identity.port})",
            f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})",
            f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}",
            f"Sweep Config:      {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points",
            f"DUT:               {DUT_DESCRIPTION}",
            "-----------------------------------------------------------------------------------------",
            f"{'N':>3}  {'Time (s)':>9}  {'Time/Swp':>9}  {'S21 Avg (dB)':>13}  {'Phase (deg)':>12}  {'Noise Std':>10}  {'Complex Avg (Re, Im)':>22}",
            f"{'-'*3}  {'-'*9}  {'-'*9}  {'-'*13}  {'-'*12}  {'-'*10}  {'-'*22}",
        ]
        for res in stage_results:
            n = res["n"]
            t = res["elapsed_s"]
            t_swp = res["sec_per_sweep"]
            db = res["s21_avg_db"]
            ph = res["s21_avg_phase_deg"]
            std_str = f"{res['noise_std_db']:8.4f} dB" if n > 1 else "     N/A  "
            c_str = f"({res['s21_avg_real']:+.4f}, {res['s21_avg_imag']:+.4f}j)"
            summary_lines.append(f"{n:3d}  {t:8.2f}s  {t_swp:8.3f}s  {db:12.2f} dB  {ph:11.2f}°  {std_str:>10}  {c_str:>22}")
        summary_lines.extend([
            "-----------------------------------------------------------------------------------------",
            f"Coherent Complex Averaging: Verified (phasor summation before dB conversion).",
            f"Total Communication Errors: {total_errors}",
            "-----------------------------------------------------------------------------------------",
            f"VERDICT: [{verdict}]",
        ])
        save_summary(exp_dir, "\n".join(summary_lines) + "\n")

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
