import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from python.tests import test_helpers


class TestRuntimeHygiene(unittest.TestCase):
    def test_validation_artifacts_can_be_redirected_outside_repo(self):
        with tempfile.TemporaryDirectory() as temporary:
            with patch.dict(os.environ,{'ANTENNA_VALIDATION_DIR':temporary}):
                folder=test_helpers.create_experiment_dir('probe')
            self.assertEqual(folder.parent,Path(temporary))
            self.assertTrue(folder.is_dir())


if __name__=='__main__':
    unittest.main()
