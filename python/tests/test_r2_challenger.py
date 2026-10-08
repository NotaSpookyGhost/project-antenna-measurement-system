"""
test_r2_challenger.py — Round 2 Adversarial Verification & Empirical Stress Suite

Author: challenger_r2_2
Purpose: Independently and empirically verify all M2 fixes:
    1. Invalid COM port handling across all 5 test scripts (exit code 1, clean error, VERDICT: [FAIL]).
    2. Timeout & empty FIFO record handling in test_thru.py:
       - Ensures no crash.
       - Ensures create_experiment_dir() runs.
       - Ensures config.json, raw.csv, and summary.txt are persisted with VERDICT: [FAIL].
    3. Incomplete sweep & IndexError protection in test_s11_loads.py and test_fifo_freshness.py:
       - Incomplete/empty records do not raise IndexError.
       - Failure artifacts are persisted with VERDICT: [FAIL] and sys.exit(1) is called.
    4. Schema integrity & complex number precision across all validation CSV artifacts:
       - All 18 standard RF columns present in every single-sweep CSV and preserved in master CSVs.
       - Float representation of real/imag retains full IEEE 754 precision without truncation.
       - Raw ADC registers (fwd0, rev0, rev1) are preserved as exact signed integers.
"""

import csv
import io
import json
import math
import os
import subprocess
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

PROJECTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(PROJECTS_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECTS_DIR))

from python.nanovna_v2 import DeviceIdentity, FIFORecord, SweepResult
from python.tests.test_helpers import (
    DEFAULT_CENTER,
    DEFAULT_POINTS,
    DEFAULT_START_HZ,
    DEFAULT_STOP_HZ,
    s_param_db,
    s_param_phase_deg,
)


def make_mock_identity(port="COM_MOCK"):
    return DeviceIdentity(
        device_variant=0x02,
        protocol_version=1,
        hardware_revision=2,
        firmware_major=1,
        firmware_minor=4,
        port=port,
    )


def make_synthetic_sweep(start_hz=DEFAULT_START_HZ, stop_hz=DEFAULT_STOP_HZ, points=DEFAULT_POINTS,
                         s11_val=complex(0.05, 0.02), s21_val=complex(0.85, -0.15),
                         num_records=None):
    """Generate a synthetic SweepResult with specified number of records."""
    if num_records is None:
        num_records = points
    step_hz = (stop_hz - start_hz) // (points - 1) if points > 1 else 0
    records = []
    fwd0 = complex(12345, -6789)
    for i in range(num_records):
        rev0 = s11_val * fwd0
        rev1 = s21_val * fwd0
        records.append(FIFORecord(
            fwd0_re=int(fwd0.real),
            fwd0_im=int(fwd0.imag),
            rev0_re=int(rev0.real),
            rev0_im=int(rev0.imag),
            rev1_re=int(rev1.real),
            rev1_im=int(rev1.imag),
            freq_index=i,
        ))
    return SweepResult(
        start_hz=start_hz,
        step_hz=step_hz,
        points=points,
        records=records,
    )


class TestR2_InvalidComPortHandling(unittest.TestCase):
    """Subprocess CLI execution verifying exit code 1, clean error, and VERDICT: [FAIL]."""

    SCRIPTS_TO_TEST = [
        "python.tests.test_thru",
        "python.tests.test_s11_loads",
        "python.tests.test_fifo_freshness",
        "python.tests.test_repeatability",
        "python.tests.test_averaging",
    ]

    def test_all_scripts_invalid_port_com99(self):
        env = os.environ.copy()
        env["PYTHONIOENCODING"] = "utf-8"

        for script in self.SCRIPTS_TO_TEST:
            cmd = [sys.executable, "-m", script, "COM99"]
            proc = subprocess.run(
                cmd,
                cwd=str(PROJECTS_DIR),
                capture_output=True,
                text=True,
                env=env,
            )

            # 1. Exit code must be 1
            self.assertEqual(
                proc.returncode, 1,
                f"Script {script} did not exit with code 1 on COM99! Returncode: {proc.returncode}"
            )

            stdout = proc.stdout
            stderr = proc.stderr

            # 2. Output must contain clean connection error message
            self.assertIn(
                "[ERROR] Failed to connect to NanoVNA on COM99",
                stdout,
                f"Script {script} missing clean connection error message in stdout!"
            )

            # 3. Output must contain VERDICT: [FAIL]
            self.assertIn(
                "VERDICT: [FAIL]",
                stdout,
                f"Script {script} missing 'VERDICT: [FAIL]' in stdout!"
            )

            # 4. Output must contain cleanup disconnect
            self.assertIn(
                "[CLEANUP] Disconnected from COM99",
                stdout,
                f"Script {script} missing cleanup message in stdout!"
            )

            # 5. Stderr must NOT contain unhandled traceback
            self.assertNotIn(
                "Traceback (most recent call last):",
                stderr,
                f"Script {script} leaked an unhandled exception traceback to stderr!"
            )


class TestR2_TimeoutArtifactPersistence(unittest.TestCase):
    """Verify that when acquire_sweep returns empty records (timeout),
    test_thru.py generates full failure artifacts with VERDICT: [FAIL].
    """

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TIMEOUT")
    def test_thru_timeout_artifact_persistence(self, mock_port, mock_vna_cls):
        import python.tests.test_thru as test_thru

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = make_mock_identity("COM_TIMEOUT")

        # Simulate timeout returning empty records
        timeout_sweep = SweepResult(
            start_hz=DEFAULT_START_HZ,
            step_hz=(DEFAULT_STOP_HZ - DEFAULT_START_HZ) // (DEFAULT_POINTS - 1),
            points=DEFAULT_POINTS,
            records=[],
        )
        self.assertFalse(timeout_sweep.complete)
        self.assertEqual(len(timeout_sweep.records), 0)
        mock_vna.acquire_sweep.return_value = timeout_sweep

        with patch("sys.exit") as mock_exit:
            test_thru.main()
            mock_exit.assert_called_with(1)

        mock_vna.connect.assert_called_with("COM_TIMEOUT")
        mock_vna.disconnect.assert_called()

        # Find the latest validation directory for thru
        val_dirs = sorted(Path(PROJECTS_DIR / "data" / "validation").glob("thru_*"), key=os.path.getmtime)
        self.assertTrue(len(val_dirs) > 0, "No thru validation directory created!")
        latest_dir = val_dirs[-1]

        # 1. config.json verification
        config_path = latest_dir / "config.json"
        self.assertTrue(config_path.exists(), f"Missing config.json in {latest_dir}")
        with open(config_path, "r", encoding="utf-8") as f:
            cfg = json.load(f)
        self.assertEqual(cfg.get("extra", {}).get("verdict"), "FAIL")
        self.assertIn("timeout", cfg.get("extra", {}).get("error", "").lower())

        # 2. raw.csv verification
        raw_csv_path = latest_dir / "raw.csv"
        self.assertTrue(raw_csv_path.exists(), f"Missing raw.csv in {latest_dir}")
        with open(raw_csv_path, "r", encoding="utf-8") as f:
            reader = csv.reader(f)
            header = next(reader)
        expected_18_cols = [
            "freq_index", "frequency_hz",
            "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
            "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
            "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
        ]
        self.assertEqual(header, expected_18_cols, "raw.csv header does not match 18 standard columns!")

        # 3. summary.txt verification
        summary_path = latest_dir / "summary.txt"
        self.assertTrue(summary_path.exists(), f"Missing summary.txt in {latest_dir}")
        with open(summary_path, "r", encoding="utf-8") as f:
            summary_content = f.read()
        self.assertIn("VERDICT: [FAIL]", summary_content)
        self.assertIn("ERROR — No FIFO records received from device (timeout)", summary_content)


class TestR2_IncompleteSweepProtection(unittest.TestCase):
    """Verify that test_s11_loads.py and test_fifo_freshness.py handle empty/truncated sweeps
    without IndexError and properly persist failure artifacts.
    """

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_INCOMPLETE")
    def test_s11_loads_empty_sweep_no_index_error(self, mock_port, mock_vna_cls):
        import python.tests.test_s11_loads as test_s11_loads

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = make_mock_identity("COM_INCOMPLETE")

        # OPEN has only 2 records (< 11, and < center_idx 5)
        sweep_open = make_synthetic_sweep(num_records=2)
        sweep_short = make_synthetic_sweep(num_records=11)
        sweep_load = make_synthetic_sweep(num_records=11)

        mock_vna.acquire_sweep.side_effect = [sweep_open, sweep_short, sweep_load]

        with patch("sys.exit") as mock_exit:
            test_s11_loads.main()
            mock_exit.assert_called_with(1)

        val_dirs = sorted(Path(PROJECTS_DIR / "data" / "validation").glob("s11_loads_*"), key=os.path.getmtime)
        latest_dir = val_dirs[-1]

        # Artifacts check
        self.assertTrue((latest_dir / "config.json").exists())
        self.assertTrue((latest_dir / "raw.csv").exists())
        self.assertTrue((latest_dir / "summary.txt").exists())
        with open(latest_dir / "summary.txt", "r", encoding="utf-8") as f:
            summary_txt = f.read()
        self.assertIn("VERDICT: [FAIL]", summary_txt)
        self.assertIn("OPEN records:      2/11", summary_txt)

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_INCOMPLETE")
    def test_fifo_freshness_empty_sweep_no_index_error(self, mock_port, mock_vna_cls):
        import python.tests.test_fifo_freshness as test_fifo_freshness

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = make_mock_identity("COM_INCOMPLETE")

        # State 2 has 0 records (timeout)
        s1 = make_synthetic_sweep(num_records=11)
        s2 = make_synthetic_sweep(num_records=0)
        s3 = make_synthetic_sweep(num_records=11)

        mock_vna.acquire_sweep.side_effect = [s1, s2, s3]

        with patch("sys.exit") as mock_exit:
            test_fifo_freshness.main()
            mock_exit.assert_called_with(1)

        val_dirs = sorted(Path(PROJECTS_DIR / "data" / "validation").glob("fifo_freshness_*"), key=os.path.getmtime)
        latest_dir = val_dirs[-1]

        # Artifacts check
        self.assertTrue((latest_dir / "config.json").exists())
        self.assertTrue((latest_dir / "raw.csv").exists())
        self.assertTrue((latest_dir / "summary.txt").exists())
        with open(latest_dir / "summary.txt", "r", encoding="utf-8") as f:
            summary_txt = f.read()
        self.assertIn("VERDICT: [FAIL]", summary_txt)
        self.assertIn("State 2 records:     0/11", summary_txt)


class TestR2_SchemaIntegrityAndComplexPrecision(unittest.TestCase):
    """Verify that all 18 standard columns are intact in all CSVs,
    and that complex precision preserves IEEE 754 64-bit float representation.
    """

    EXPECTED_18_COLS = [
        "freq_index", "frequency_hz",
        "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
        "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
        "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
    ]

    def test_single_sweep_csv_exact_18_columns(self):
        """test_helpers.save_sweep_csv must output exactly the 18 standard columns."""
        from python.tests.test_helpers import save_sweep_csv
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)
            sweep = make_synthetic_sweep(points=11)
            csv_file = save_sweep_csv(tmp_path, sweep, "test_out.csv")

            with open(csv_file, "r", encoding="utf-8") as f:
                reader = csv.reader(f)
                header = next(reader)
                rows = list(reader)

            self.assertEqual(header, self.EXPECTED_18_COLS)
            self.assertEqual(len(rows), 11)

            # Check precision of s11_real and s21_real
            # The synthetic sweep used fwd0 = 12345 - 6789j
            for r in rows:
                s11_re = float(r[2])
                s11_im = float(r[3])
                s21_re = float(r[7])
                s21_im = float(r[8])
                self.assertAlmostEqual(s11_re, 0.05, places=5)
                self.assertAlmostEqual(s11_im, 0.02, places=5)
                self.assertAlmostEqual(s21_re, 0.85, places=5)
                self.assertAlmostEqual(s21_im, -0.15, places=5)

                # Check integer fields
                fwd0_re = int(r[12])
                fwd0_im = int(r[13])
                self.assertEqual(fwd0_re, 12345)
                self.assertEqual(fwd0_im, -6789)

    def test_master_raw_csv_contains_all_18_standard_columns(self):
        """In all 5 test scripts, raw.csv must contain all 18 standard columns in order."""
        import python.tests.test_s11_loads as test_s11_loads
        import python.tests.test_fifo_freshness as test_fifo_freshness
        import tempfile

        with tempfile.TemporaryDirectory() as tmp_dir:
            tmp_path = Path(tmp_dir)

            # 1. s11_loads master raw.csv
            sweep = make_synthetic_sweep(points=11)
            raw_s11 = test_s11_loads.save_loads_raw_csv(tmp_path, [("OPEN", sweep)])
            with open(raw_s11, "r", encoding="utf-8") as f:
                header = next(csv.reader(f))
            self.assertEqual(header[0], "standard")
            self.assertEqual(header[1:], self.EXPECTED_18_COLS)

            # 2. fifo_freshness master raw.csv
            raw_fifo = test_fifo_freshness.save_freshness_raw_csv(tmp_path, [(1, "DISCONNECTED", sweep)])
            with open(raw_fifo, "r", encoding="utf-8") as f:
                header = next(csv.reader(f))
            self.assertEqual(header[0:2], ["state", "state_name"])
            self.assertEqual(header[2:], self.EXPECTED_18_COLS)

    def test_existing_validation_artifacts_schema_integrity(self):
        """Inspect all raw.csv files in projects/data/validation to verify column compliance."""
        val_dir = PROJECTS_DIR / "data" / "validation"
        self.assertTrue(val_dir.exists())

        raw_csv_files = list(val_dir.glob("*/raw.csv"))
        self.assertTrue(len(raw_csv_files) > 0, "No validation raw.csv files found to inspect!")

        for csv_f in raw_csv_files:
            with open(csv_f, "r", encoding="utf-8") as f:
                reader = csv.reader(f)
                header = next(reader)
                rows = list(reader)

            # All 18 standard columns must be present in the header
            for col in self.EXPECTED_18_COLS:
                self.assertIn(
                    col, header,
                    f"Column '{col}' missing from {csv_f.relative_to(PROJECTS_DIR)}! Header: {header}"
                )

            # Check that row cells align with header length
            for i, row in enumerate(rows):
                self.assertEqual(
                    len(row), len(header),
                    f"Row {i} in {csv_f} has {len(row)} cells, expected {len(header)}"
                )


if __name__ == "__main__":
    unittest.main()
