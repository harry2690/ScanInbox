import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent

class UILogicTests(unittest.TestCase):
    @unittest.skipUnless(shutil.which("xcrun"), "Requires Apple development tools")
    def test_navigation_and_dock_policy(self):
        with tempfile.TemporaryDirectory() as d:
            binary = Path(d) / "navigation-tests"
            subprocess.run(["xcrun", "swiftc", "-parse-as-library", "-module-cache-path", str(Path(d)/"cache"), str(ROOT/"Sources/ScanInbox/Navigation.swift"), str(ROOT/"Tests/NavigationTests.swift"), "-o", str(binary)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn("14 checks passed", result.stdout)
