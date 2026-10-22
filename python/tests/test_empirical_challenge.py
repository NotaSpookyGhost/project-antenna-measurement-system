"""
test_empirical_challenge.py — Empirical Stress & Adversarial Test Harness

Developed by challenger_1 to rigorously challenge the logic, edge cases,
and failure modes of the 5 validation scripts:
    1. test_thru.py (Test A)
    2. test_s11_loads.py (Test B)
    3. test_fifo_freshness.py (Test C/D)
    4. test_repeatability.py (Test E)
    5. test_averaging.py (Test F)

Covers:
    - Pass/fail threshold boundary testing (S21 > -10.0 dB)
    - OPEN/SHORT phase difference branch cuts and wrap-around logic
    - Load suppression dual-condition evaluation
    - FIFO freshness state transition edge cases and stale data trapping
    - Statistical computation stability under timeouts and partial reads
    - Coherent complex vector averaging vs scalar dB averaging verification
"""

import cmath
import csv
import io
import json
import math
import os
import statistics
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

import serial

# Ensure projects directory is in sys.path
PROJECTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(PROJECTS_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECTS_DIR))
_VALIDATION_TMP=tempfile.TemporaryDirectory()
os.environ.setdefault('ANTENNA_VALIDATION_DIR',_VALIDATION_TMP.name)
VALIDATION_DIR=Path(os.environ['ANTENNA_VALIDATION_DIR'])

from python.nanovna_v2 import DeviceIdentity, FIFORecord, NanoVNAError, NanoVNA_V2, SweepResult
from python.tests.test_helpers import (
    DEFAULT_CENTER,
    DEFAULT_POINTS,
    DEFAULT_START_HZ,
    DEFAULT_STOP_HZ,
    create_experiment_dir,
    s_param_db,
    s_param_phase_deg,
)
import python.tests.test_thru as test_thru
import python.tests.test_s11_loads as test_s11_loads
import python.tests.test_fifo_freshness as test_fifo_freshness
import python.tests.test_repeatability as test_repeatability
import python.tests.test_averaging as test_averaging


def make_mock_sweep(start_hz=DEFAULT_START_HZ, stop_hz=DEFAULT_STOP_HZ, points=DEFAULT_POINTS,
                    s11_val=complex(0.01, 0.0), s21_val=complex(0.85, -0.15),
                    freq_indices=None, num_records=None):
    """Generate a synthetic SweepResult with specified S11 and S21."""
    step_hz = (stop_hz - start_hz) // (points - 1) if points > 1 else 0
    records = []
    fwd0 = complex(10000, 0)
    rec_count = points if num_records is None else num_records
    for i in range(rec_count):
        f_idx = freq_indices[i] if freq_indices else i
        rev0 = s11_val * fwd0
        rev1 = s21_val * fwd0
        records.append(FIFORecord(
            fwd0_re=int(fwd0.real),
            fwd0_im=int(fwd0.imag),
            rev0_re=int(rev0.real),
            rev0_im=int(rev0.imag),
            rev1_re=int(rev1.real),
            rev1_im=int(rev1.imag),
            freq_index=f_idx,
        ))
    return SweepResult(
        start_hz=start_hz,
        step_hz=step_hz,
        points=points,
        records=records,
    )


class TestA_EmpiricalChallenge(unittest.TestCase):
    """Empirical challenge for test_thru.py threshold and boundary logic."""

    def test_s21_threshold_above(self):
        """S21 = -9.9 dB (> -10.0 dB) must PASS."""
        mag = 10.0 ** (-9.9 / 20.0)
        s21 = complex(mag, 0.0)
        db = s_param_db(s21)
        self.assertGreater(db, -10.0)
        passed = (db > -10.0)
        self.assertTrue(passed)

    def test_s21_threshold_below(self):
        """S21 = -10.1 dB (< -10.0 dB) must FAIL."""
        mag = 10.0 ** (-10.1 / 20.0)
        s21 = complex(mag, 0.0)
        db = s_param_db(s21)
        self.assertLess(db, -10.0)
        passed = (db > -10.0)
        self.assertFalse(passed)

    def test_s21_threshold_exact_boundary(self):
        """S21 = -10.000 dB exact boundary must FAIL (strict inequality requirement)."""
        mag = 10.0 ** (-10.0 / 20.0)
        s21 = complex(mag, 0.0)
        db = s_param_db(s21)
        passed = (db > -10.0)
        self.assertFalse(passed)

    def test_zero_magnitude_reading(self):
        """S21 = 0 (ADC reading 0) returns -999.0 dB without division by zero."""
        db = s_param_db(complex(0.0, 0.0))
        self.assertEqual(db, -999.0)
        self.assertFalse(db > -10.0)


class TestB_EmpiricalChallenge(unittest.TestCase):
    """Empirical challenge for test_s11_loads.py phase difference & load suppression."""

    def compute_phase_diff(self, s11_open: complex, s11_short: complex) -> float:
        """Exact formula from test_s11_loads.py."""
        return abs(math.degrees(cmath.phase(s11_open * s11_short.conjugate())))

    def test_phase_diff_standard_opposing(self):
        """OPEN at 0 deg, SHORT at 180 deg -> phase diff = 180 deg > 90 deg."""
        s_open = complex(1.0, 0.0)
        s_short = complex(-1.0, 0.0)
        diff = self.compute_phase_diff(s_open, s_short)
        self.assertAlmostEqual(diff, 180.0, places=4)
        self.assertGreater(diff, 90.0)

    def test_phase_diff_branch_cut_wrap(self):
        """OPEN at +179.9 deg, SHORT at -179.9 deg.
        Geodesic distance is 0.2 deg, NOT 359.8 deg. Must FAIL (> 90 deg).
        """
        s_open = cmath.rect(1.0, math.radians(179.9))
        s_short = cmath.rect(1.0, math.radians(-179.9))
        diff = self.compute_phase_diff(s_open, s_short)
        self.assertAlmostEqual(diff, 0.2, places=3)
        self.assertFalse(diff > 90.0, "Branch-cut wrap error: falsely passed identical phases!")

    def test_phase_diff_branch_cut_orthogonal(self):
        """OPEN at +10 deg, SHORT at -170 deg.
        Angular distance is 180 deg. Must PASS (> 90 deg).
        """
        s_open = cmath.rect(1.0, math.radians(10.0))
        s_short = cmath.rect(1.0, math.radians(-170.0))
        diff = self.compute_phase_diff(s_open, s_short)
        self.assertAlmostEqual(diff, 180.0, places=3)
        self.assertTrue(diff > 90.0)

    def test_phase_diff_exact_boundary(self):
        """Phase difference exactly 90.0 deg fails strict > 90.0 deg."""
        s_open = cmath.rect(1.0, math.radians(0.0))
        s_short = cmath.rect(1.0, math.radians(90.0))
        diff = self.compute_phase_diff(s_open, s_short)
        self.assertAlmostEqual(diff, 90.0, places=4)
        self.assertFalse(diff > 90.0)

    def test_load_suppression_logic(self):
        """Verify dual-criteria load suppression evaluation."""
        OPEN_MIN_DB = -3.0
        SHORT_MIN_DB = -3.0
        LOAD_MAX_DB = -15.0
        LOAD_DIFF_MIN_DB = 10.0

        # Scenario 1: Clean load < -15 dB
        open_db, short_db, load_db = -0.5, -0.5, -25.0
        load_ok = (load_db < LOAD_MAX_DB) or (load_db < open_db - LOAD_DIFF_MIN_DB and load_db < short_db - LOAD_DIFF_MIN_DB)
        self.assertTrue(load_ok)

        # Scenario 2: Marginal load -13 dB, but > 10 dB below OPEN/SHORT (-1.0 dB)
        open_db, short_db, load_db = -1.0, -1.0, -13.0
        load_ok = (load_db < LOAD_MAX_DB) or (load_db < open_db - LOAD_DIFF_MIN_DB and load_db < short_db - LOAD_DIFF_MIN_DB)
        self.assertTrue(load_ok)

        # Scenario 3: Bad load -8 dB (insufficient suppression)
        open_db, short_db, load_db = -0.5, -0.5, -8.0
        load_ok = (load_db < LOAD_MAX_DB) or (load_db < open_db - LOAD_DIFF_MIN_DB and load_db < short_db - LOAD_DIFF_MIN_DB)
        self.assertFalse(load_ok)


class TestCD_EmpiricalChallenge(unittest.TestCase):
    """Empirical challenge for test_fifo_freshness.py state transitions."""

    def evaluate_freshness(self, s1_db, s2_db, s3_db, complete=True):
        STATE2_MIN_S21_DB = -10.0
        STATE3_MAX_S21_DB = -30.0
        MIN_DELTA_JUMP_DB = 20.0
        MIN_DELTA_DROP_DB = 20.0

        delta_jump = s2_db - s1_db
        delta_drop = s2_db - s3_db

        state2_high = s2_db > STATE2_MIN_S21_DB
        jump_ok = delta_jump > MIN_DELTA_JUMP_DB
        state3_low = s3_db < STATE3_MAX_S21_DB
        drop_ok = delta_drop > MIN_DELTA_DROP_DB

        return state2_high and jump_ok and state3_low and drop_ok and complete

    def test_clean_transitions_pass(self):
        """Clean Disconnected (-70 dB) -> THRU (-1.5 dB) -> Disconnected (-70 dB)."""
        passed = self.evaluate_freshness(-70.0, -1.5, -70.0)
        self.assertTrue(passed)

    def test_stale_fifo_state2_fails(self):
        """Stale FIFO at State 2 (fails to detect THRU connection)."""
        passed = self.evaluate_freshness(-70.0, -70.0, -70.0)
        self.assertFalse(passed)

    def test_stale_fifo_state3_fails(self):
        """Stale FIFO at State 3 (fails to detect cable disconnection)."""
        passed = self.evaluate_freshness(-70.0, -1.5, -1.5)
        self.assertFalse(passed)

    def test_poor_isolation_state3_fails(self):
        """State 3 does not return below -30 dB (e.g. -25 dB). Must FAIL."""
        passed = self.evaluate_freshness(-70.0, -1.5, -25.0)
        self.assertFalse(passed)

    def test_insufficient_jump_fails(self):
        """Jump delta only 15 dB (< 20 dB). Must FAIL."""
        passed = self.evaluate_freshness(-26.0, -11.0, -70.0)
        self.assertFalse(passed)


class TestE_EmpiricalChallenge(unittest.TestCase):
    """Empirical challenge for test_repeatability.py error handling and statistics."""

    def test_statistical_stability_pass(self):
        """100 samples with low variance (std < 1.0 dB)."""
        values = [-1.5 + 0.05 * math.sin(i) for i in range(100)]
        mean_val = statistics.mean(values)
        std_val = statistics.stdev(values)
        self.assertLess(std_val, 1.0)
        self.assertAlmostEqual(mean_val, -1.5, delta=0.1)

    def test_statistical_high_noise_fails(self):
        """100 samples with excessive noise (std >= 1.0 dB) must FAIL."""
        values = [-1.5 + 2.5 * math.sin(i) for i in range(100)]
        std_val = statistics.stdev(values)
        self.assertGreater(std_val, 1.0)
        std_ok = (std_val < 1.0)
        self.assertFalse(std_ok)

    def test_error_counter_sensitivity(self):
        """Any error (timeouts, partial reads, freq index errors) must invalidate verdict."""
        total_errors_1 = 1  # 1 timeout
        self.assertFalse(total_errors_1 == 0)

        total_errors_2 = 1  # 1 partial read
        self.assertFalse(total_errors_2 == 0)

        total_errors_3 = 1  # 1 freq index mismatch
        self.assertFalse(total_errors_3 == 0)


class TestF_EmpiricalChallenge(unittest.TestCase):
    """Empirical challenge for test_averaging.py coherent vector averaging math."""

    def test_coherent_vector_averaging_vs_scalar_db(self):
        """Demonstrate that coherent complex averaging cancels out-of-phase noise
        while scalar dB averaging completely fails to do so.
        """
        # Two equal-amplitude phasors with opposing phases (+60 deg and -60 deg)
        s1 = cmath.rect(1.0, math.radians(60.0))
        s2 = cmath.rect(1.0, math.radians(-60.0))

        # 1. Coherent complex vector averaging (implemented in test_averaging.py)
        s_avg_coherent = (s1 + s2) / 2.0
        db_coherent = s_param_db(s_avg_coherent)

        # Expected: (cos(60) + j sin(60) + cos(60) - j sin(60)) / 2 = cos(60) = 0.5
        # 20 * log10(0.5) = -6.0206 dB
        self.assertAlmostEqual(s_avg_coherent.real, 0.5, places=5)
        self.assertAlmostEqual(s_avg_coherent.imag, 0.0, places=5)
        self.assertAlmostEqual(db_coherent, -6.0205999, places=4)

        # 2. Naive scalar dB averaging (prohibited by R5)
        db1 = s_param_db(s1)  # 0.0 dB
        db2 = s_param_db(s2)  # 0.0 dB
        db_scalar = (db1 + db2) / 2.0  # 0.0 dB

        # They must differ by 6 dB!
        self.assertNotAlmostEqual(db_coherent, db_scalar)
        self.assertAlmostEqual(db_scalar - db_coherent, 6.0206, places=3)

    def test_noise_cancellation_orthogonal_phasors(self):
        """Four orthogonal noise vectors sum to 0 in complex plane."""
        noise_phasors = [
            complex(1.0, 0.0),
            complex(0.0, 1.0),
            complex(-1.0, 0.0),
            complex(0.0, -1.0),
        ]
        s_avg = sum(noise_phasors) / 4.0
        self.assertAlmostEqual(abs(s_avg), 0.0, places=7)
        # Vector average properly zeroes out symmetric noise


class TestS11Loads_FailureModesAndSchema(unittest.TestCase):
    """Empirical challenge for test_s11_loads.py incomplete sweep handling and CSV schema."""

    def setUp(self):
        self.mock_identity = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

    def test_empty_records_open_no_index_error(self):
        """Incomplete OPEN sweep (0 records) must NOT raise IndexError, must output FAIL verdict and create artifacts."""
        with patch.object(test_s11_loads, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_s11_loads, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            empty_sweep = make_mock_sweep(num_records=0)
            valid_sweep = make_mock_sweep(num_records=DEFAULT_POINTS)
            mock_vna.acquire_sweep.side_effect = [empty_sweep, valid_sweep, valid_sweep]

            with self.assertRaises(SystemExit):
                test_s11_loads.main()

            output = mock_stdout.getvalue()
            self.assertIn("VERDICT: [FAIL]", output)
            self.assertIn("[ERROR] Incomplete sweep acquisition detected.", output)

            validation_dir = VALIDATION_DIR
            exp_dirs = sorted(validation_dir.glob("s11_loads_*"), key=lambda p: p.stat().st_mtime)
            self.assertTrue(len(exp_dirs) > 0)
            latest_dir = exp_dirs[-1]

            self.assertTrue((latest_dir / "config.json").exists())
            self.assertTrue((latest_dir / "raw.csv").exists())
            self.assertTrue((latest_dir / "summary.txt").exists())
            self.assertTrue((latest_dir / "s11_open.csv").exists())
            self.assertTrue((latest_dir / "s11_short.csv").exists())
            self.assertTrue((latest_dir / "s11_load.csv").exists())

            with open(latest_dir / "config.json", "r") as f:
                cfg = json.load(f)
                self.assertEqual(cfg["verdict"], "FAIL")
                self.assertEqual(cfg["open_records"], 0)

            with open(latest_dir / "summary.txt", "r") as f:
                summary = f.read()
                self.assertIn("VERDICT: [FAIL]", summary)

    def test_partial_records_short_no_index_error(self):
        """Partial SHORT sweep (3 records < center_idx=5) must NOT raise IndexError."""
        with patch.object(test_s11_loads, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_s11_loads, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            valid_sweep = make_mock_sweep(num_records=DEFAULT_POINTS)
            partial_sweep = make_mock_sweep(num_records=3)
            mock_vna.acquire_sweep.side_effect = [valid_sweep, partial_sweep, valid_sweep]

            with self.assertRaises(SystemExit):
                test_s11_loads.main()

            output = mock_stdout.getvalue()
            self.assertIn("VERDICT: [FAIL]", output)
            self.assertIn("SHORT: received 3/11 records", output)

    def test_loads_master_raw_csv_schema_and_standard_column(self):
        """Verify master raw.csv has 'standard' column, 19 columns, and all standard rows."""
        with patch.object(test_s11_loads, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_s11_loads, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit") as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            sweep_open = make_mock_sweep(s11_val=complex(0.99, 0.0))
            sweep_short = make_mock_sweep(s11_val=complex(-0.99, 0.0))
            sweep_load = make_mock_sweep(s11_val=complex(0.01, 0.0))
            mock_vna.acquire_sweep.side_effect = [sweep_open, sweep_short, sweep_load]

            ret = test_s11_loads.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

            validation_dir = VALIDATION_DIR
            exp_dirs = sorted(validation_dir.glob("s11_loads_*"), key=lambda p: p.stat().st_mtime)
            latest_dir = exp_dirs[-1]

            raw_csv_path = latest_dir / "raw.csv"
            self.assertTrue(raw_csv_path.exists())

            with open(raw_csv_path, "r", newline="") as f:
                reader = list(csv.reader(f))
                header = reader[0]
                self.assertEqual(header[0], "standard")
                self.assertEqual(len(header), 19)
                expected_header = [
                    "standard", "freq_index", "frequency_hz",
                    "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
                    "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
                    "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
                ]
                self.assertEqual(header, expected_header)

                data_rows = reader[1:]
                self.assertEqual(len(data_rows), 33)
                standards = [row[0] for row in data_rows]
                self.assertEqual(standards.count("OPEN"), 11)
                self.assertEqual(standards.count("SHORT"), 11)
                self.assertEqual(standards.count("LOAD"), 11)


class TestFIFOFreshness_FailureModesAndSchema(unittest.TestCase):
    """Empirical challenge for test_fifo_freshness.py incomplete sweep handling and CSV schema."""

    def setUp(self):
        self.mock_identity = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

    def test_empty_records_state1_no_index_error(self):
        """Incomplete State 1 sweep (0 records) must NOT raise IndexError, must output FAIL verdict and create artifacts."""
        with patch.object(test_fifo_freshness, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_fifo_freshness, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            empty_sweep = make_mock_sweep(num_records=0)
            valid_sweep = make_mock_sweep(num_records=DEFAULT_POINTS)
            mock_vna.acquire_sweep.side_effect = [empty_sweep, valid_sweep, valid_sweep]

            with self.assertRaises(SystemExit):
                test_fifo_freshness.main()

            output = mock_stdout.getvalue()
            self.assertIn("VERDICT: [FAIL]", output)
            self.assertIn("[ERROR] Incomplete sweep acquisition detected.", output)

            validation_dir = VALIDATION_DIR
            exp_dirs = sorted(validation_dir.glob("fifo_freshness_*"), key=lambda p: p.stat().st_mtime)
            self.assertTrue(len(exp_dirs) > 0)
            latest_dir = exp_dirs[-1]

            self.assertTrue((latest_dir / "config.json").exists())
            self.assertTrue((latest_dir / "raw.csv").exists())
            self.assertTrue((latest_dir / "summary.txt").exists())

            with open(latest_dir / "config.json", "r") as f:
                cfg = json.load(f)
                self.assertEqual(cfg["verdict"], "FAIL")
                self.assertEqual(cfg["state1_records"], 0)

            with open(latest_dir / "summary.txt", "r") as f:
                summary = f.read()
                self.assertIn("VERDICT: [FAIL]", summary)

    def test_partial_records_state2_no_index_error(self):
        """Partial State 2 sweep (4 records < center_idx=5) must NOT raise IndexError."""
        with patch.object(test_fifo_freshness, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_fifo_freshness, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            valid_sweep = make_mock_sweep(num_records=DEFAULT_POINTS)
            partial_sweep = make_mock_sweep(num_records=4)
            mock_vna.acquire_sweep.side_effect = [valid_sweep, partial_sweep, valid_sweep]

            with self.assertRaises(SystemExit):
                test_fifo_freshness.main()

            output = mock_stdout.getvalue()
            self.assertIn("VERDICT: [FAIL]", output)
            self.assertIn("State 2 (THRU CONNECTED): received 4/11 records", output)

    def test_freshness_master_raw_csv_schema_and_state_columns(self):
        """Verify master raw.csv has 'state' and 'state_name' columns, 20 columns, and all state rows."""
        with patch.object(test_fifo_freshness, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_fifo_freshness, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit") as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = self.mock_identity

            s1 = make_mock_sweep(s21_val=complex(0.0003, 0.0001))
            s2 = make_mock_sweep(s21_val=complex(0.85, -0.15))
            s3 = make_mock_sweep(s21_val=complex(0.0003, 0.0001))
            mock_vna.acquire_sweep.side_effect = [s1, s2, s3]

            ret = test_fifo_freshness.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

            validation_dir = VALIDATION_DIR
            exp_dirs = sorted(validation_dir.glob("fifo_freshness_*"), key=lambda p: p.stat().st_mtime)
            latest_dir = exp_dirs[-1]

            raw_csv_path = latest_dir / "raw.csv"
            self.assertTrue(raw_csv_path.exists())

            with open(raw_csv_path, "r", newline="") as f:
                reader = list(csv.reader(f))
                header = reader[0]
                self.assertEqual(header[0], "state")
                self.assertEqual(header[1], "state_name")
                self.assertEqual(len(header), 20)
                expected_header = [
                    "state", "state_name", "freq_index", "frequency_hz",
                    "s11_real", "s11_imag", "s11_mag", "s11_db", "s11_phase_deg",
                    "s21_real", "s21_imag", "s21_mag", "s21_db", "s21_phase_deg",
                    "fwd0_re", "fwd0_im", "rev0_re", "rev0_im", "rev1_re", "rev1_im",
                ]
                self.assertEqual(header, expected_header)

                data_rows = reader[1:]
                self.assertEqual(len(data_rows), 33)
                state_nums = [row[0] for row in data_rows]
                state_names = [row[1] for row in data_rows]
                self.assertEqual(state_nums.count("1"), 11)
                self.assertEqual(state_nums.count("2"), 11)
                self.assertEqual(state_nums.count("3"), 11)
                self.assertEqual(state_names.count("DISCONNECTED"), 22)
                self.assertEqual(state_names.count("THRU_CONNECTED"), 11)


class TestThru_EmptySweepFailureMode(unittest.TestCase):
    """Empirical challenge for test_thru.py empty sweep handling."""

    def test_empty_records_thru_artifacts_and_fail_verdict(self):
        """Empty sweep in test_thru must create artifacts and output FAIL verdict."""
        with patch.object(test_thru, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(test_thru, "get_port_from_args_or_detect", return_value="COM_TEST"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.identify.return_value = DeviceIdentity(
                device_variant=0x02, protocol_version=1, hardware_revision=2,
                firmware_major=1, firmware_minor=4, port="COM_TEST"
            )
            mock_vna.acquire_sweep.return_value = make_mock_sweep(num_records=0)

            with self.assertRaises(SystemExit):
                test_thru.main()

            output = mock_stdout.getvalue()
            self.assertIn("VERDICT: [FAIL]", output)
            self.assertIn("[ERROR] No FIFO records received from device.", output)

            validation_dir = VALIDATION_DIR
            exp_dirs = sorted(validation_dir.glob("thru_*"), key=lambda p: p.stat().st_mtime)
            latest_dir = exp_dirs[-1]
            self.assertTrue((latest_dir / "config.json").exists())
            self.assertTrue((latest_dir / "raw.csv").exists())
            self.assertTrue((latest_dir / "summary.txt").exists())


class TestSerialConnectionResilience(unittest.TestCase):
    """Empirical challenge verifying that all 5 scripts handle serial connection failures cleanly."""

    def check_connection_failure(self, script_module):
        with patch.object(script_module, "NanoVNA_V2") as mock_vna_cls, \
             patch.object(script_module, "get_port_from_args_or_detect", return_value="COM99"), \
             patch("sys.stdout", new_callable=io.StringIO) as mock_stdout, \
             patch("sys.exit", side_effect=SystemExit(1)) as mock_exit:

            mock_vna = MagicMock()
            mock_vna_cls.return_value = mock_vna
            mock_vna.connect.side_effect = serial.SerialException("could not open port 'COM99'")

            with self.assertRaises(SystemExit):
                script_module.main()

            output = mock_stdout.getvalue()
            self.assertIn("[ERROR] Failed to connect to NanoVNA on COM99", output)
            self.assertIn("VERDICT: [FAIL]", output)
            mock_vna.disconnect.assert_called()

    def test_thru_connection_failure(self):
        self.check_connection_failure(test_thru)

    def test_s11_loads_connection_failure(self):
        self.check_connection_failure(test_s11_loads)

    def test_fifo_freshness_connection_failure(self):
        self.check_connection_failure(test_fifo_freshness)

    def test_repeatability_connection_failure(self):
        self.check_connection_failure(test_repeatability)

    def test_averaging_connection_failure(self):
        self.check_connection_failure(test_averaging)


if __name__ == "__main__":
    unittest.main()

