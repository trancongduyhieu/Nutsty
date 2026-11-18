"""Headless worker launches of Nutsty.exe must never fall through to the GUI.

In the PyInstaller build sys.executable is Nutsty.exe, so a backend module that
spawns [sys.executable, <its own file>, ...] relaunches the app. If
launcher_win.check_cli_dispatch does not recognise the script, main() runs, the
single-instance check sends SHOW, and the hidden main window jumps to the front
over a fullscreen game (issue #2, from stream_resolver's cache_worker).

Run: python scripts/test_cli_dispatch.py
"""
import os
import sys
import unittest
from unittest import mock

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, REPO)

_saved_argv = sys.argv
sys.argv = [sys.argv[0]]
import launcher_win  # noqa: E402  (check_cli_dispatch runs at import; no args -> no-op)
sys.argv = _saved_argv


def dispatch(*args):
    """Run check_cli_dispatch with argv as Nutsty.exe would receive it.
    Returns (exit_code or None when it fell through to the GUI, imported module names)."""
    imported = []

    def fake_import(name):
        imported.append(name)
        return mock.Mock(spec=["handle_cli"])

    # runpy is patched before importlib: mock.patch resolves its target through import_module
    with mock.patch("runpy.run_module"), \
         mock.patch.object(sys, "argv", ["Nutsty.exe", *args]), \
         mock.patch("importlib.import_module", side_effect=fake_import), \
         mock.patch.object(sys, "stderr"):
        try:
            launcher_win.check_cli_dispatch()
        except SystemExit as e:
            return e.code, imported
    return None, imported


class CliDispatchTest(unittest.TestCase):
    def test_stream_resolver_cache_worker_runs_headless(self):
        script = os.path.join(REPO, "backend", "stream_resolver.py")
        code, imported = dispatch(script, "cache_worker", "vid", "https://x", "", "")
        self.assertEqual(code, 0, "cache_worker fell through to the GUI launch path")
        self.assertEqual(imported, ["stream_resolver"])

    def test_frozen_pyc_path_runs_headless(self):
        # Inside the PyInstaller bundle a module's __file__ ends in .pyc
        script = os.path.join(REPO, "_internal", "stream_resolver.pyc")
        code, imported = dispatch(script, "cache_worker", "vid", "https://x")
        self.assertEqual(code, 0)
        self.assertEqual(imported, ["stream_resolver"])

    def test_unknown_script_never_opens_gui(self):
        code, imported = dispatch(os.path.join(REPO, "backend", "not_a_backend_module.py"), "go")
        self.assertIsNotNone(code, "unknown script argument fell through to the GUI launch path")
        self.assertNotEqual(code, 0)
        self.assertEqual(imported, [])

    def test_plain_launch_still_opens_gui(self):
        self.assertEqual(dispatch(), (None, []))

    def test_every_backend_module_that_respawns_itself_is_mapped(self):
        # Modules that spawn [sys.executable, <their own __file__>, ...]
        backend = os.path.join(REPO, "backend")
        for name in sorted(os.listdir(backend)):
            if not name.endswith(".py"):
                continue
            with open(os.path.join(backend, name), encoding="utf-8") as f:
                src = f.read()
            if "sys.executable" in src and "abspath(__file__)" in src and "Popen" in src:
                self.assertIn(name, launcher_win.BACKEND_MAP, f"{name} respawns itself but is not in BACKEND_MAP")


if __name__ == "__main__":
    unittest.main(verbosity=2)
