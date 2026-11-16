"""Unit checks for FIFO sweep frequency coverage."""

import unittest

from python.nanovna_v2 import FIFORecord, SweepResult
from python.nanovna_bridge import _result_to_dict


class TestSweepIntegrity(unittest.TestCase):
    def test_complete_requires_each_frequency_index_once(self):
        valid = SweepResult(points=4, records=[FIFORecord(freq_index=i) for i in (2, 3, 0, 1)])
        duplicated = SweepResult(points=4, records=[FIFORecord(freq_index=i) for i in (0, 1, 0, 2)])

        self.assertTrue(valid.complete)
        self.assertFalse(duplicated.complete)

    def test_bridge_aligns_frequency_and_s_parameters_by_index(self):
        def sweep(indices):
            return SweepResult(start_hz=100_000_000, step_hz=1_000_000, points=4,
                               records=[FIFORecord(fwd0_re=100, rev0_re=10 + i,
                                                   rev1_re=20 + i, freq_index=i)
                                        for i in indices])

        ordered = _result_to_dict(sweep((0, 1, 2, 3)), 4)
        rotated = _result_to_dict(sweep((2, 3, 0, 1)), 4)

        self.assertEqual(rotated, ordered)
        self.assertEqual(rotated["frequency_hz"], [100_000_000, 101_000_000,
                                                    102_000_000, 103_000_000])
        self.assertEqual(rotated["s11_real"], [0.10, 0.11, 0.12, 0.13])
        self.assertEqual(rotated["s21_real"], [0.20, 0.21, 0.22, 0.23])

    def test_bridge_rejects_duplicate_or_missing_frequency_index(self):
        invalid = SweepResult(start_hz=100_000_000, step_hz=1_000_000,
                              points=4, records=[FIFORecord(freq_index=i)
                                                 for i in (0, 1, 1, 3)])

        result = _result_to_dict(invalid, 4)

        self.assertTrue(result["status"].startswith("ERROR:"))
        self.assertFalse(result["complete"])
        self.assertEqual(result["frequency_hz"], [])


if __name__ == "__main__":
    unittest.main()
