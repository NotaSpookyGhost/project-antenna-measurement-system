"""Unit checks for FIFO sweep frequency coverage."""

import unittest

from python.nanovna_v2 import FIFORecord, SweepResult


class TestSweepIntegrity(unittest.TestCase):
    def test_complete_requires_each_frequency_index_once(self):
        valid = SweepResult(points=4, records=[FIFORecord(freq_index=i) for i in (2, 3, 0, 1)])
        duplicated = SweepResult(points=4, records=[FIFORecord(freq_index=i) for i in (0, 1, 0, 2)])

        self.assertTrue(valid.complete)
        self.assertFalse(duplicated.complete)


if __name__ == "__main__":
    unittest.main()
