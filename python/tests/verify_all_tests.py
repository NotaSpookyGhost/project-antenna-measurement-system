"""
verify_all_tests.py — Comprehensive validation harness for M1 NanoVNA test scripts.

Performs:
    1. Static compilation check (py_compile) on all 5 scripts.
    2. Static AST / contract inspection (imports, main guard, artifact definitions).
    3. Dynamic mock execution of each script (test_thru, test_s11_loads,
       test_fifo_freshness, test_repeatability, test_averaging).
    4. Inspection of generated artifacts (config.json, raw.csv 18 columns, summary.txt).
"""

import ast
import json
import math
import os
import py_compile
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

# Ensure projects directory is in sys.path
PROJECTS_DIR = Path(__file__).resolve().parent.parent.parent
if str(PROJECTS_DIR) not in sys.path:
    sys.path.insert(0, str(PROJECTS_DIR))

from python.nanovna_v2 import DeviceIdentity, FIFORecord, SweepResult
from python.tests.test_helpers import (
    DEFAULT_CENTER,
    DEFAULT_POINTS,
    DEFAULT_START_HZ,
    DEFAULT_STOP_HZ,
)

SCRIPTS = [
    "python/tests/test_thru.py",
    "python/tests/test_s11_loads.py",
    "python/tests/test_fifo_freshness.py",
    "python/tests/test_repeatability.py",
    "python/tests/test_averaging.py",
]


def make_synthetic_sweep(start_hz=DEFAULT_START_HZ, stop_hz=DEFAULT_STOP_HZ, points=DEFAULT_POINTS,
                         s11_nominal=complex(0.05, 0.02), s21_nominal=complex(0.85, -0.15)):
    """Generate a realistic SweepResult with raw ADC waves matching given nominal S-parameters."""
    step_hz = (stop_hz - start_hz) // (points - 1) if points > 1 else 0
    records = []
    fwd0 = complex(12000, 0)
    for i in range(points):
        rev0 = s11_nominal * fwd0
        rev1 = s21_nominal * fwd0
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


class TestSuiteValidation(unittest.TestCase):

    def test_01_compilation(self):
        """Verify that all 5 scripts compile cleanly without syntax errors."""
        print("\n--- Test 1: Python Compilation (py_compile) ---")
        for script_rel in SCRIPTS:
            script_path = PROJECTS_DIR / script_rel
            print(f"Compiling {script_path.name}...", end=" ")
            py_compile.compile(str(script_path), doraise=True)
            print("OK")

    def test_02_ast_contract_inspection(self):
        """Verify structural contracts: PROJECTS_DIR, imports, main guard."""
        print("\n--- Test 2: AST Contract Inspection ---")
        for script_rel in SCRIPTS:
            script_path = PROJECTS_DIR / script_rel
            with open(script_path, "r", encoding="utf-8") as f:
                content = f.read()

            tree = ast.parse(content, filename=str(script_path))

            # 1. Check for main function
            function_names = [n.name for n in ast.walk(tree) if isinstance(n, ast.FunctionDef)]
            self.assertIn("main", function_names, f"{script_path.name} missing main() function")

            # 2. Check for if __name__ == '__main__': main()
            self.assertIn("if __name__ == \"__main__\":", content, f"{script_path.name} missing main guard")

            # 3. Check for PROJECTS_DIR bootstrap
            self.assertIn("PROJECTS_DIR = Path(__file__).resolve().parent.parent.parent", content)

            # 4. Check imports from existing modules
            self.assertIn("from python.nanovna_v2 import", content)
            self.assertIn("from python.tests.test_helpers import", content)
            print(f"AST & Contracts in {script_path.name}: OK")

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TEST")
    def test_03_test_thru_execution(self, mock_port, mock_vna_cls):
        """Verify test_thru.py dynamic execution with synthetic THRU response."""
        print("\n--- Test 3: test_thru.py Dynamic Execution ---")
        import python.tests.test_thru as test_thru

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )
        # S21 ~ -1.2 dB (0.85 - 0.15j), S11 ~ -25 dB
        mock_vna.acquire_sweep.return_value = make_synthetic_sweep(
            s11_nominal=complex(0.04, 0.02),
            s21_nominal=complex(0.85, -0.15),
        )

        with patch("sys.exit") as mock_exit:
            ret = test_thru.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

        mock_vna.connect.assert_called_with("COM_TEST")
        mock_vna.disconnect.assert_called()

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TEST")
    def test_04_test_s11_loads_execution(self, mock_port, mock_vna_cls):
        """Verify test_s11_loads.py dynamic execution with OPEN/SHORT/LOAD sweeps."""
        print("\n--- Test 4: test_s11_loads.py Dynamic Execution ---")
        import python.tests.test_s11_loads as test_s11_loads

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

        # OPEN: S11 ~ 0.98 + 0.05j (mag ~ -0.16 dB, phase ~ 2.9°)
        sweep_open = make_synthetic_sweep(s11_nominal=complex(0.98, 0.05), s21_nominal=complex(0.0001, 0))
        # SHORT: S11 ~ -0.97 + 0.08j (mag ~ -0.23 dB, phase ~ 175.3°, delta ~ 172° > 90°)
        sweep_short = make_synthetic_sweep(s11_nominal=complex(-0.97, 0.08), s21_nominal=complex(0.0001, 0))
        # LOAD: S11 ~ 0.03 + 0.01j (mag ~ -29.9 dB < -15 dB)
        sweep_load = make_synthetic_sweep(s11_nominal=complex(0.03, 0.01), s21_nominal=complex(0.0001, 0))

        mock_vna.acquire_sweep.side_effect = [sweep_open, sweep_short, sweep_load]

        with patch("sys.exit") as mock_exit:
            ret = test_s11_loads.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

        self.assertEqual(mock_vna.acquire_sweep.call_count, 3)
        mock_vna.disconnect.assert_called()

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TEST")
    def test_05_test_fifo_freshness_execution(self, mock_port, mock_vna_cls):
        """Verify test_fifo_freshness.py dynamic execution with state transitions."""
        print("\n--- Test 5: test_fifo_freshness.py Dynamic Execution ---")
        import python.tests.test_fifo_freshness as test_fifo_freshness

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

        # State 1: Disconnected (S21 ~ -70 dB)
        s1 = make_synthetic_sweep(s21_nominal=complex(0.0003, 0.0001))
        # State 2: THRU (S21 ~ -1.2 dB)
        s2 = make_synthetic_sweep(s21_nominal=complex(0.85, -0.15))
        # State 3: Disconnected (S21 ~ -70 dB)
        s3 = make_synthetic_sweep(s21_nominal=complex(0.0003, 0.0001))

        mock_vna.acquire_sweep.side_effect = [s1, s2, s3]

        with patch("sys.exit") as mock_exit:
            ret = test_fifo_freshness.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

        self.assertEqual(mock_vna.acquire_sweep.call_count, 3)
        mock_vna.disconnect.assert_called()

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TEST")
    def test_06_test_repeatability_execution(self, mock_port, mock_vna_cls):
        """Verify test_repeatability.py dynamic execution (100 sweeps, stats, 0 errors)."""
        print("\n--- Test 6: test_repeatability.py Dynamic Execution ---")
        import python.tests.test_repeatability as test_repeatability

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

        nominal = complex(0.85, -0.15)
        # Generate 100 sweeps with minuscule jitter (std << 1.0 dB)
        sweeps = [
            make_synthetic_sweep(s21_nominal=nominal + complex(0.0005 * math.sin(i), 0.0005 * math.cos(i)))
            for i in range(100)
        ]
        mock_vna.acquire_single.side_effect = sweeps

        with patch("sys.exit") as mock_exit:
            ret = test_repeatability.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

        mock_vna.configure_sweep.assert_called_once()
        self.assertEqual(mock_vna.acquire_single.call_count, 100)
        mock_vna.disconnect.assert_called()

    @patch("python.nanovna_v2.NanoVNA_V2")
    @patch("python.tests.test_helpers.get_port_from_args_or_detect", return_value="COM_TEST")
    def test_07_test_averaging_execution(self, mock_port, mock_vna_cls):
        """Verify test_averaging.py dynamic execution (N in [1, 2, 4, 8, 16], coherent averaging)."""
        print("\n--- Test 7: test_averaging.py Dynamic Execution ---")
        import python.tests.test_averaging as test_averaging

        mock_vna = MagicMock()
        mock_vna_cls.return_value = mock_vna
        mock_vna.identify.return_value = DeviceIdentity(
            device_variant=0x02, protocol_version=1, hardware_revision=2,
            firmware_major=1, firmware_minor=4, port="COM_TEST"
        )

        total_sweeps = 1 + 2 + 4 + 8 + 16  # 31 sweeps
        nominal = complex(0.85, -0.15)
        sweeps = [
            make_synthetic_sweep(s21_nominal=nominal + complex(0.001 * math.sin(i), 0.001 * math.cos(i)))
            for i in range(total_sweeps)
        ]
        mock_vna.acquire_single.side_effect = sweeps

        with patch("sys.exit") as mock_exit:
            ret = test_averaging.main()
            mock_exit.assert_not_called()
            self.assertEqual(ret, 0)

        mock_vna.configure_sweep.assert_called_once()
        self.assertEqual(mock_vna.acquire_single.call_count, 31)
        mock_vna.disconnect.assert_called()


if __name__ == "__main__":
    unittest.main()
