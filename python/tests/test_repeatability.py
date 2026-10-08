"""
test_repeatability.py — Test E: Repeatability for NanoVNA SAA-2N.

Performs exactly 100 consecutive sweep acquisitions with a stable DUT connected
(e.g., THRU SMA cable or fixed attenuator).

Validates:
    1. RF stability: Standard deviation of S21 magnitude < 1.0 dB across 100 sweeps.
    2. USB communication robustness: 0 timeouts, 0 partial FIFO reads, 0 freq_index errors.
    3. Proper use of `configure_sweep()` for setup and `acquire_single()` for loop speed.
    4. Full statistical logging (mean, std, min, max) and complex data persistence.

Usage:
    python -m python.tests.test_repeatability [COMx]   # from projects/ directory
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

DUT_DESCRIPTION = "Stable DUT (THRU SMA cable) — Repeatability 100 sweeps"
NUM_SWEEPS = 100
MAX_ALLOWED_STD_DB = 1.0


def main():
    print_header(f"Test E — Repeatability ({NUM_SWEEPS} Consecutive Sweeps)")

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

        # Inform user to ensure a stable DUT is attached
        print(f"\n[SETUP] Connect a stable DUT (e.g. THRU SMA cable) to Port 1 & 2.")
        if sys.stdin and sys.stdin.isatty():
            try:
                input("        Ensure DUT is securely connected, then press Enter to start 100 sweeps...")
            except (EOFError, KeyboardInterrupt):
                print("        (Proceeding...)")
        else:
            print("        [Headless / non-interactive environment detected; proceeding automatically.]")

        # ── Configure sweep parameters once ──────────────────────────────
        print(f"\n[CONFIG] Configuring sweep: {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points...")
        vna.configure_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)

        # ── Error Counters & Collection ──────────────────────────────────
        timeout_errors = 0
        partial_fifo_errors = 0
        freq_index_errors = 0
        freq_index_warnings = 0  # non-sequential but complete sets

        # Arrays to collect center frequency data
        center_idx = DEFAULT_POINTS // 2
        center_freq_hz = DEFAULT_START_HZ + center_idx * ((DEFAULT_STOP_HZ - DEFAULT_START_HZ) // (DEFAULT_POINTS - 1))

        records_history = []  # List of dicts for CSV export
        s21_db_list = []
        s21_phase_list = []
        s11_db_list = []
        s11_phase_list = []

        print(f"\n[ACQUISITION] Starting {NUM_SWEEPS} sweeps (using acquire_single)...")
        start_time = time.perf_counter()

        for sweep_num in range(1, NUM_SWEEPS + 1):
            ts_iso = datetime.now().isoformat()
            try:
                # Use acquire_single for loop iterations
                result = vna.acquire_single(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
            except Exception as e:
                timeout_errors += 1
                print(f"  [SWEEP {sweep_num:3d}/{NUM_SWEEPS}] EXCEPTION: {e}")
                continue

            num_records = len(result.records)

            # Error detection: Timeouts
            if num_records == 0:
                timeout_errors += 1
                print(f"  [SWEEP {sweep_num:3d}/{NUM_SWEEPS}] TIMEOUT (0 records)")
                continue

            # Error detection: Partial FIFO
            if num_records < DEFAULT_POINTS:
                partial_fifo_errors += 1
                print(f"  [SWEEP {sweep_num:3d}/{NUM_SWEEPS}] PARTIAL FIFO ({num_records}/{DEFAULT_POINTS} records)")
                continue

            # Error detection: freq_index validation
            # Check that all expected indices are present (as a set),
            # not necessarily in sequential order starting from 0.
            # Firmware continuous sweep may produce non-zero-aligned reads.
            actual_indices = set(rec.freq_index for rec in result.records)
            expected_indices = set(range(DEFAULT_POINTS))
            if actual_indices != expected_indices:
                freq_index_errors += 1
                print(f"  [SWEEP {sweep_num:3d}/{NUM_SWEEPS}] FREQ INDEX SET MISMATCH: got {sorted(actual_indices)}")
                # Still usable if center index is present
            elif sorted(rec.freq_index for rec in result.records) != list(range(DEFAULT_POINTS)):
                freq_index_warnings += 1  # non-sequential but complete — just a warning

            # Find center frequency record by freqIndex value, not position
            center_rec = None
            for rec in result.records:
                if rec.freq_index == center_idx:
                    center_rec = rec
                    break

            if center_rec is None:
                # Fallback: use middle position if center freqIndex not found
                center_rec = result.records[center_idx]

            s11 = center_rec.s11
            s21 = center_rec.s21

            s11_mag = abs(s11)
            s21_mag = abs(s21)

            s11_db = s_param_db(s11)
            s21_db = s_param_db(s21)

            s11_phase = s_param_phase_deg(s11)
            s21_phase = s_param_phase_deg(s21)

            s21_db_list.append(s21_db)
            s21_phase_list.append(s21_phase)
            s11_db_list.append(s11_db)
            s11_phase_list.append(s11_phase)

            records_history.append({
                "iteration": sweep_num,
                "timestamp_iso": ts_iso,
                "freq_index": center_rec.freq_index,
                "frequency_hz": center_freq_hz,
                "s11_real": s11.real,
                "s11_imag": s11.imag,
                "s11_mag": s11_mag,
                "s11_db": f"{s11_db:.4f}",
                "s11_phase_deg": f"{s11_phase:.4f}",
                "s21_real": s21.real,
                "s21_imag": s21.imag,
                "s21_mag": s21_mag,
                "s21_db": f"{s21_db:.4f}",
                "s21_phase_deg": f"{s21_phase:.4f}",
                "fwd0_re": center_rec.fwd0_re,
                "fwd0_im": center_rec.fwd0_im,
                "rev0_re": center_rec.rev0_re,
                "rev0_im": center_rec.rev0_im,
                "rev1_re": center_rec.rev1_re,
                "rev1_im": center_rec.rev1_im,
            })

            # Periodic status printout
            if sweep_num == 1 or sweep_num % 10 == 0 or sweep_num == NUM_SWEEPS:
                print(f"  [SWEEP {sweep_num:3d}/{NUM_SWEEPS}] S21 = {s21_db:7.2f} dB, Phase = {s21_phase:7.2f}°")

        total_elapsed_s = time.perf_counter() - start_time
        valid_sweeps = len(s21_db_list)
        print(f"\n[DONE] Completed in {total_elapsed_s:.2f}s ({total_elapsed_s/NUM_SWEEPS:.3f} s/sweep).")
        print(f"       Valid sweeps: {valid_sweeps}/{NUM_SWEEPS}")

        # ── Statistical Calculations ─────────────────────────────────────
        if valid_sweeps >= 2:
            mean_s21_db = statistics.mean(s21_db_list)
            std_s21_db = statistics.stdev(s21_db_list)
            min_s21_db = min(s21_db_list)
            max_s21_db = max(s21_db_list)
            span_s21_db = max_s21_db - min_s21_db

            mean_s21_phase = statistics.mean(s21_phase_list)
            std_s21_phase = statistics.stdev(s21_phase_list)
            min_s21_phase = min(s21_phase_list)
            max_s21_phase = max(s21_phase_list)

            mean_s11_db = statistics.mean(s11_db_list)
            std_s11_db = statistics.stdev(s11_db_list)
        else:
            mean_s21_db = s21_db_list[0] if valid_sweeps == 1 else -999.0
            std_s21_db = 999.0
            min_s21_db = mean_s21_db
            max_s21_db = mean_s21_db
            span_s21_db = 0.0
            mean_s21_phase = 0.0
            std_s21_phase = 0.0
            min_s21_phase = 0.0
            max_s21_phase = 0.0
            mean_s11_db = 0.0
            std_s11_db = 0.0

        # Total errors
        total_errors = timeout_errors + partial_fifo_errors + freq_index_errors

        # Acceptance Criteria:
        # std(S21_dB) < 1.0 dB AND error_counters == 0 AND all 100 valid sweeps
        std_ok = std_s21_db < MAX_ALLOWED_STD_DB
        errors_ok = (total_errors == 0)
        sweeps_ok = (valid_sweeps == NUM_SWEEPS)

        passed = std_ok and errors_ok and sweeps_ok
        verdict = "PASS" if passed else "FAIL"

        # ── Output Summary Table ─────────────────────────────────────────
        print("\n============================================================")
        print("  REPEATABILITY STATISTICAL SUMMARY (Center: 2400.000 MHz)")
        print("============================================================")
        print(f"  Sweeps Attempted:     {NUM_SWEEPS}")
        print(f"  Valid Sweeps:         {valid_sweeps}")
        print(f"  Total Elapsed Time:   {total_elapsed_s:.2f} s ({total_elapsed_s/NUM_SWEEPS:.3f} s/sweep)")
        print("------------------------------------------------------------")
        print(f"  S21 Magnitude (dB):")
        print(f"    Mean:               {mean_s21_db:8.4f} dB")
        print(f"    Std Dev:            {std_s21_db:8.4f} dB  (Threshold: < {MAX_ALLOWED_STD_DB:.1f} dB) -> {'PASS' if std_ok else 'FAIL'}")
        print(f"    Min / Max:          {min_s21_db:8.4f} / {max_s21_db:8.4f} dB (Span: {span_s21_db:.4f} dB)")
        print(f"  S21 Phase (deg):")
        print(f"    Mean:               {mean_s21_phase:8.2f}°")
        print(f"    Std Dev:            {std_s21_phase:8.4f}°")
        print(f"    Min / Max:          {min_s21_phase:8.2f}° / {max_s21_phase:8.2f}°")
        print("------------------------------------------------------------")
        print(f"  Error Counters:")
        print(f"    Timeouts:           {timeout_errors:d} {'(OK)' if timeout_errors == 0 else '(FAIL)'}")
        print(f"    Partial FIFO Reads: {partial_fifo_errors:d} {'(OK)' if partial_fifo_errors == 0 else '(FAIL)'}")
        print(f"    freq_index Missing: {freq_index_errors:d} {'(OK)' if freq_index_errors == 0 else '(FAIL)'}")
        print(f"    freq_index Reorder: {freq_index_warnings:d} (info only — firmware continuous sweep)")
        print(f"    Total Hard Errors:  {total_errors:d} {'(OK)' if errors_ok else '(FAIL)'}")
        print("============================================================")

        # ── Save Experiment Artifacts ────────────────────────────────────
        exp_dir = create_experiment_dir("repeatability")
        print(f"\n[LOG] Saving experiment artifacts to: {exp_dir}")

        extra_meta = {
            "verdict": verdict,
            "sweeps_attempted": NUM_SWEEPS,
            "valid_sweeps": valid_sweeps,
            "center_freq_hz": center_freq_hz,
            "mean_s21_db": round(mean_s21_db, 4),
            "std_s21_db": round(std_s21_db, 4),
            "min_s21_db": round(min_s21_db, 4),
            "max_s21_db": round(max_s21_db, 4),
            "span_s21_db": round(span_s21_db, 4),
            "mean_s21_phase_deg": round(mean_s21_phase, 4),
            "std_s21_phase_deg": round(std_s21_phase, 4),
            "mean_s11_db": round(mean_s11_db, 4),
            "std_s11_db": round(std_s11_db, 4),
            "timeout_errors": timeout_errors,
            "partial_fifo_errors": partial_fifo_errors,
            "freq_index_errors": freq_index_errors,
            "freq_index_warnings": freq_index_warnings,
            "total_errors": total_errors,
            "total_elapsed_s": round(total_elapsed_s, 3),
            "sec_per_sweep": round(total_elapsed_s / NUM_SWEEPS, 4),
            "std_ok": std_ok,
            "errors_ok": errors_ok,
        }
        save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                    dut=DUT_DESCRIPTION, extra=extra_meta)

        # Save all 100 center points to CSV preserving full 18 columns
        csv_path = exp_dir / "raw.csv"
        csv_fields = [
            "iteration", "timestamp_iso", "freq_index", "frequency_hz",
            "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
            "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
            "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
        ]
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=csv_fields)
            writer.writeheader()
            for row in records_history:
                writer.writerow(row)

        # Also save repeatability_100.csv for clarity
        rep_csv_path = exp_dir / "repeatability_100.csv"
        with open(rep_csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=csv_fields)
            writer.writeheader()
            for row in records_history:
                writer.writerow(row)

        # Save summary.txt
        summary_text = (
            f"Test E — Repeatability Summary (100 Sweeps)\n"
            f"Generated: {datetime.now().isoformat()}\n"
            f"------------------------------------------------------------\n"
            f"Device:            SAA-2N (port: {identity.port})\n"
            f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
            f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
            f"Sweep Config:      {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
            f"DUT:               {DUT_DESCRIPTION}\n"
            f"Total Sweeps:      {NUM_SWEEPS} ({valid_sweeps} valid)\n"
            f"Execution Time:    {total_elapsed_s:.2f} s ({total_elapsed_s/NUM_SWEEPS:.3f} s/sweep)\n"
            f"------------------------------------------------------------\n"
            f"Center Freq:       {center_freq_hz/1e6:.3f} MHz\n"
            f"S21 Magnitude (dB):\n"
            f"  Mean:            {mean_s21_db:8.4f} dB\n"
            f"  Std Dev:         {std_s21_db:8.4f} dB [Criterion: < {MAX_ALLOWED_STD_DB:.1f} dB] -> {'PASS' if std_ok else 'FAIL'}\n"
            f"  Min / Max:       {min_s21_db:8.4f} / {max_s21_db:8.4f} dB (Span: {span_s21_db:.4f} dB)\n"
            f"S21 Phase (deg):\n"
            f"  Mean:            {mean_s21_phase:8.2f}°\n"
            f"  Std Dev:         {std_s21_phase:8.4f}°\n"
            f"  Min / Max:       {min_s21_phase:8.2f}° / {max_s21_phase:8.2f}°\n"
            f"Error Counters:\n"
            f"  Timeouts:        {timeout_errors:d}\n"
            f"  Partial FIFO:    {partial_fifo_errors:d}\n"
            f"  freq_index Missing: {freq_index_errors:d}\n"
            f"  freq_index Reorder: {freq_index_warnings:d} (info only)\n"
            f"  Total Hard Errors:  {total_errors:d} -> {'PASS' if errors_ok else 'FAIL'}\n"
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
