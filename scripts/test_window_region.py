"""The rounded Win32 window region must be dropped while maximized or fullscreen.

PySide6 returns QWindow.Visibility as a plain Enum, so comparing it with ints
(`vis in (3, 4)`) is always False and the region stayed rounded when maximized.

Run: python scripts/test_window_region.py
"""
import os
import sys
import unittest

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)

_saved_argv = sys.argv
sys.argv = [sys.argv[0]]
import launcher_win  # noqa: E402
sys.argv = _saved_argv

from PySide6.QtGui import QWindow  # noqa: E402

V = QWindow.Visibility


class WindowRegionTest(unittest.TestCase):
    def test_maximized_and_fullscreen_drop_the_region(self):
        self.assertTrue(launcher_win._fills_screen(V.Maximized))
        self.assertTrue(launcher_win._fills_screen(V.FullScreen))

    def test_other_states_keep_rounded_corners(self):
        for v in (V.Hidden, V.AutomaticVisibility, V.Windowed, V.Minimized):
            self.assertFalse(launcher_win._fills_screen(v), v)

    def test_plain_ints_work_too(self):
        self.assertTrue(launcher_win._fills_screen(4))
        self.assertTrue(launcher_win._fills_screen(5))
        self.assertFalse(launcher_win._fills_screen(3))
        self.assertFalse(launcher_win._fills_screen(None))


if __name__ == "__main__":
    unittest.main(verbosity=2)
