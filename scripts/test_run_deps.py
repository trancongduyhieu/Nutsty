#!/usr/bin/env python3
"""run.sh installs the Python packages the Linux backend imports at runtime.
tidalapi was missing, so Tidal login failed on Linux with a generic network error."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class RunShDepsTest(unittest.TestCase):
    def test_tidalapi_checked_and_installed(self):
        text = (ROOT / "run.sh").read_text()
        check = re.search(r'python3 -c "import ([^"]+)"', text)
        self.assertIsNotNone(check, "run.sh lost its dependency check")
        self.assertIn("tidalapi", [m.strip() for m in check.group(1).split(",")])
        installs = [l for l in text.splitlines() if "pip install" in l and "mutagen" in l]
        self.assertTrue(installs)
        for line in installs:
            self.assertIn("tidalapi", line)

    def test_requirements_pin_tidalapi(self):
        for name in ("requirements.txt", "requirements_win.txt"):
            self.assertIn("tidalapi==0.8.11", (ROOT / name).read_text())


if __name__ == "__main__":
    unittest.main()
