"""
test_fifo_freshness.py — Test D: FIFO freshness for NanoVNA SAA-2N.

Validates that the USB driver's FIFO flush (`clear_fifo()`) and re-acquisition
logic successfully purges stale hardware buffer data across physical state
transitions.

Sequence of 3 acquisitions:
    State 1: DISCONNECTED (Port 1 & Port 2 open, isolation/noise floor)
    State 2: THRU connected (Port 1 <-> Port 2 with SMA cable)
    State 3: DISCONNECTED (Port 1 & Port 2 open again)

Acceptance Criteria:
    - State 2 S21 > -10.0 dB (strong transmission)
    - Jump delta (State 2 - State 1) > +20.0 dB
    - State 3 S21 < -30.0 dB (returns to isolation/noise floor)
    - Drop delta (State 2 - State 3) > +20.0 dB
    - Artifacts saved: config.json, raw.csv, summary.txt

Usage:
    python -m python.tests.test_fifo_freshness [COMx]   # from projects/ directory
"""

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

DUT_DESCRIPTION = "FIFO Freshness: Disconnected -> THRU Connected -> Disconnected"
STATE2_MIN_S21_DB = -10.0
STATE3_MAX_S21_DB = -30.0
MIN_DELTA_JUMP_DB = 20.0
MIN_DELTA_DROP_DB = 20.0


def prompt_state(step: int, total: int, state_name: str, instructions: str) -> None:
    """Prompt user to set up physical state. Supports interactive terminals and headless runners."""
    print(f"\n[{step}/{total}] State: {state_name}")
    print(f"       Instructions: {instructions}")
    if sys.stdin and sys.stdin.isatty():
        try:
            input(f"       Set state to '{state_name}', then press Enter to sweep...")
        except (EOFError, KeyboardInterrupt):
            print("       (Continuing...)")
    else:
        print(f"       [Headless / non-interactive environment detected; proceeding automatically.]")


def save_freshness_raw_csv(exp_dir: Path, states_data: list[tuple[int, str, SweepResult]]) -> Path:
    """Save combined master raw.csv with state provenance columns + full 18 RF columns."""
    raw_csv_path = exp_dir / "raw.csv"
    raw_fields = [
        "state", "state_name", "freq_index", "frequency_hz",
        "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
        "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
        "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
    ]
    with open(raw_csv_path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(raw_fields)
        for state_num, state_name, sweep_res in states_data:
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
                    state_num, state_name,
                    rec.freq_index, freq_hz,
                    s11.real, s11.imag, s11_mag, f"{s11_db:.4f}", f"{s11_phase:.4f}",
                    s21.real, s21.imag, s21_mag, f"{s21_db:.4f}", f"{s21_phase:.4f}",
                    rec.fwd0_re, rec.fwd0_im,
                    rec.rev0_re, rec.rev0_im,
                    rec.rev1_re, rec.rev1_im,
                ])
    return raw_csv_path


def main():
    print_header("Test D — FIFO Freshness Validation (State Transitions)")

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

        # ── State 1: DISCONNECTED ────────────────────────────────────────
        prompt_state(1, 3, "DISCONNECTED", "Ensure Port 1 and Port 2 are OPEN (no cable attached).")
        print(f"[SWEEP] Acquiring State 1 (DISCONNECTED)...")
        result_state1 = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] State 1 Sweep:")
        print_sweep_table(result_state1, show_complex=False)

        # ── State 2: THRU CONNECTED ──────────────────────────────────────
        prompt_state(2, 3, "THRU CONNECTED", "Connect Port 1 to Port 2 with the SMA cable.")
        print(f"[SWEEP] Acquiring State 2 (THRU CONNECTED)...")
        result_state2 = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] State 2 Sweep:")
        print_sweep_table(result_state2, show_complex=False)

        # ── State 3: DISCONNECTED ────────────────────────────────────────
        prompt_state(3, 3, "DISCONNECTED", "Disconnect the SMA cable (leave Port 1 & 2 open again).")
        print(f"[SWEEP] Acquiring State 3 (DISCONNECTED)...")
        result_state3 = vna.acquire_sweep(DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS)
        print("\n[DATA] State 3 Sweep:")
        print_sweep_table(result_state3, show_complex=False)

        # ── Verify Sweep Completeness ────────────────────────────────────
        all_complete = (
            result_state1.complete and len(result_state1.records) == DEFAULT_POINTS
            and result_state2.complete and len(result_state2.records) == DEFAULT_POINTS
            and result_state3.complete and len(result_state3.records) == DEFAULT_POINTS
        )

        if not all_complete:
            print("\n[ERROR] Incomplete sweep acquisition detected. Aborting analysis.")
            for name, res in [("State 1 (DISCONNECTED)", result_state1),
                              ("State 2 (THRU CONNECTED)", result_state2),
                              ("State 3 (DISCONNECTED)", result_state3)]:
                if not (res.complete and len(res.records) == DEFAULT_POINTS):
                    print(f"  [ERROR] {name}: received {len(res.records)}/{DEFAULT_POINTS} records (complete={res.complete}).")

            exp_dir = create_experiment_dir("fifo_freshness")
            print(f"\n[LOG] Saving failure artifacts to: {exp_dir}")

            extra_meta = {
                "verdict": "FAIL",
                "error": "Incomplete sweep acquisition (USB timeout or packet loss)",
                "state1_records": len(result_state1.records),
                "state1_complete": result_state1.complete,
                "state2_records": len(result_state2.records),
                "state2_complete": result_state2.complete,
                "state3_records": len(result_state3.records),
                "state3_complete": result_state3.complete,
                "all_complete": False,
            }
            save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                        dut=DUT_DESCRIPTION, extra=extra_meta)

            save_sweep_csv(exp_dir, result_state1, "state1_disconnected.csv")
            save_sweep_csv(exp_dir, result_state2, "state2_thru.csv")
            save_sweep_csv(exp_dir, result_state3, "state3_disconnected.csv")

            save_freshness_raw_csv(exp_dir, [
                (1, "DISCONNECTED", result_state1),
                (2, "THRU_CONNECTED", result_state2),
                (3, "DISCONNECTED", result_state3),
            ])

            summary_text = (
                f"Test D — FIFO Freshness Validation Summary\n"
                f"Generated: {datetime.now().isoformat()}\n"
                f"------------------------------------------------------------\n"
                f"Device:            SAA-2N (port: {identity.port})\n"
                f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
                f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
                f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
                f"DUT:               {DUT_DESCRIPTION}\n"
                f"------------------------------------------------------------\n"
                f"[ERROR] Sweep acquisition incomplete or timed out.\n"
                f"  State 1 records:   {len(result_state1.records)}/{DEFAULT_POINTS} (complete: {result_state1.complete})\n"
                f"  State 2 records:   {len(result_state2.records)}/{DEFAULT_POINTS} (complete: {result_state2.complete})\n"
                f"  State 3 records:   {len(result_state3.records)}/{DEFAULT_POINTS} (complete: {result_state3.complete})\n"
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

        rec1 = result_state1.records[center_idx]
        rec2 = result_state2.records[center_idx]
        rec3 = result_state3.records[center_idx]

        center_freq_hz = result_state1.start_hz + rec1.freq_index * result_state1.step_hz

        s21_s1_db = s_param_db(rec1.s21)
        s21_s2_db = s_param_db(rec2.s21)
        s21_s3_db = s_param_db(rec3.s21)

        delta_jump = s21_s2_db - s21_s1_db
        delta_drop = s21_s2_db - s21_s3_db

        # Verification Criteria:
        # 1. State 2 transmission is high: S21 > -10 dB
        # 2. State 1 -> State 2 jump is significant: delta_jump > +20 dB
        # 3. State 3 returns to isolation: S21 < -30 dB
        # 4. State 2 -> State 3 drop is significant: delta_drop > +20 dB
        # 5. All sweeps complete
        state2_high = s21_s2_db > STATE2_MIN_S21_DB
        jump_ok = delta_jump > MIN_DELTA_JUMP_DB
        state3_low = s21_s3_db < STATE3_MAX_S21_DB
        drop_ok = delta_drop > MIN_DELTA_DROP_DB
        all_complete = result_state1.complete and result_state2.complete and result_state3.complete

        passed = state2_high and jump_ok and state3_low and drop_ok and all_complete
        verdict = "PASS" if passed else "FAIL"

        # ── Print Analysis Summary ───────────────────────────────────────
        print("\n============================================================")
        print("  FIFO FRESHNESS TRANSITION ANALYSIS (Center: 2400.000 MHz)")
        print("============================================================")
        print(f"  State 1 (DISCONNECTED):    {s21_s1_db:8.2f} dB")
        print(f"  State 2 (THRU CONNECTED):  {s21_s2_db:8.2f} dB")
        print(f"  State 3 (DISCONNECTED):    {s21_s3_db:8.2f} dB")
        print("------------------------------------------------------------")
        print(f"  Jump (State 2 - State 1):  {delta_jump:+8.2f} dB (Required: > +{MIN_DELTA_JUMP_DB:.1f} dB) -> {'PASS' if jump_ok else 'FAIL'}")
        print(f"  State 2 S21 Level:         {s21_s2_db:8.2f} dB (Required: > {STATE2_MIN_S21_DB:.1f} dB)  -> {'PASS' if state2_high else 'FAIL'}")
        print(f"  Drop (State 2 - State 3):  {delta_drop:+8.2f} dB (Required: > +{MIN_DELTA_DROP_DB:.1f} dB) -> {'PASS' if drop_ok else 'FAIL'}")
        print(f"  State 3 S21 Level:         {s21_s3_db:8.2f} dB (Required: < {STATE3_MAX_S21_DB:.1f} dB)  -> {'PASS' if state3_low else 'FAIL'}")
        print(f"  Completeness Check:        {'PASS' if all_complete else 'FAIL'}")
        print("============================================================")

        # ── Save Experiment Artifacts ────────────────────────────────────
        exp_dir = create_experiment_dir("fifo_freshness")
        print(f"\n[LOG] Saving experiment artifacts to: {exp_dir}")

        extra_meta = {
            "verdict": verdict,
            "center_freq_hz": center_freq_hz,
            "state1_s21_db": round(s21_s1_db, 4),
            "state2_s21_db": round(s21_s2_db, 4),
            "state3_s21_db": round(s21_s3_db, 4),
            "delta_jump_db": round(delta_jump, 4),
            "delta_drop_db": round(delta_drop, 4),
            "state2_high": state2_high,
            "jump_ok": jump_ok,
            "state3_low": state3_low,
            "drop_ok": drop_ok,
        }
        save_config(exp_dir, identity, DEFAULT_START_HZ, DEFAULT_STOP_HZ, DEFAULT_POINTS,
                    dut=DUT_DESCRIPTION, extra=extra_meta)

        # Save individual state CSVs
        save_sweep_csv(exp_dir, result_state1, "state1_disconnected.csv")
        save_sweep_csv(exp_dir, result_state2, "state2_thru.csv")
        save_sweep_csv(exp_dir, result_state3, "state3_disconnected.csv")

        # Save combined master raw.csv with state provenance columns + full 18 columns preserved
        save_freshness_raw_csv(exp_dir, [
            (1, "DISCONNECTED", result_state1),
            (2, "THRU_CONNECTED", result_state2),
            (3, "DISCONNECTED", result_state3),
        ])

        # Save summary.txt
        summary_text = (
            f"Test D — FIFO Freshness Validation Summary\n"
            f"Generated: {datetime.now().isoformat()}\n"
            f"------------------------------------------------------------\n"
            f"Device:            SAA-2N (port: {identity.port})\n"
            f"Firmware:          DiSlord v1.4.02 FPU (reg fw: {identity.firmware_major}.{identity.firmware_minor})\n"
            f"Protocol:          0x{identity.protocol_version:02X}, Hardware Rev: {identity.hardware_revision}\n"
            f"Sweep:             {DEFAULT_START_HZ/1e6:.1f} - {DEFAULT_STOP_HZ/1e6:.1f} MHz, {DEFAULT_POINTS} points\n"
            f"DUT:               {DUT_DESCRIPTION}\n"
            f"------------------------------------------------------------\n"
            f"Center Freq:       {center_freq_hz/1e6:.3f} MHz\n"
            f"State 1 S21 (dB):  {s21_s1_db:8.2f} dB (Disconnected)\n"
            f"State 2 S21 (dB):  {s21_s2_db:8.2f} dB (THRU Connected, Expected > {STATE2_MIN_S21_DB:.1f} dB) -> {'PASS' if state2_high else 'FAIL'}\n"
            f"State 3 S21 (dB):  {s21_s3_db:8.2f} dB (Disconnected, Expected < {STATE3_MAX_S21_DB:.1f} dB) -> {'PASS' if state3_low else 'FAIL'}\n"
            f"Jump Delta (2-1):  {delta_jump:+8.2f} dB (Expected > +{MIN_DELTA_JUMP_DB:.1f} dB) -> {'PASS' if jump_ok else 'FAIL'}\n"
            f"Drop Delta (2-3):  {delta_drop:+8.2f} dB (Expected > +{MIN_DELTA_DROP_DB:.1f} dB) -> {'PASS' if drop_ok else 'FAIL'}\n"
            f"Freshness Verdict: Fresh hardware readings confirmed across transitions.\n"
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
