#!/usr/bin/env python3
"""Linux git checkout: the update dialog gets a real download size from the plan, not an endless spinner."""
import os
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "backend"))
import platform_compat as pc  # noqa: E402
import updater  # noqa: E402


def git(cwd, *args):
    subprocess.run(["git", "-C", cwd, *args], check=True, capture_output=True,
                   env=dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
                            GIT_COMMITTER_EMAIL="t@t"))


def main():
    tmp = tempfile.mkdtemp()
    try:
        origin, app = os.path.join(tmp, "origin"), os.path.join(tmp, "app")
        os.makedirs(origin)
        git(origin, "init", "-q", "-b", "main")
        open(os.path.join(origin, "shell.qml"), "w").write("v1\n")
        git(origin, "add", ".")
        git(origin, "commit", "-q", "-m", "v1")
        subprocess.run(["git", "clone", "-q", origin, app], check=True)
        # new release upstream: one changed file, one new file with some weight
        open(os.path.join(origin, "shell.qml"), "w").write("v2\n")
        open(os.path.join(origin, "big.bin"), "wb").write(os.urandom(50_000))
        git(origin, "add", ".")
        git(origin, "commit", "-q", "-m", "v2")

        pc.IS_WINDOWS = False
        updater.source_app_dir = lambda: app
        m = updater.DirectUpdateManager()
        m._compute_plan("https://github.com/x/y/archive/refs/tags/v2.zip")
        st = m.get_status()
        assert st["mode"] == "delta", st
        plan = st["plan"]
        assert plan and plan["changed"] == 2, plan
        assert 50_000 <= plan["download_bytes"] < 200_000, plan

        # already up to date: nothing to download
        git(app, "pull", "-q", "--ff-only")
        m2 = updater.DirectUpdateManager()
        m2._compute_plan("https://github.com/x/y/archive/refs/tags/v2.zip")
        assert m2.get_status()["plan"]["changed"] == 0

        # no remote reachable: no plan, and the dialog falls back to its plain button
        git(app, "remote", "set-url", "origin", os.path.join(tmp, "missing"))
        m3 = updater.DirectUpdateManager()
        m3._compute_plan("https://github.com/x/y/archive/refs/tags/v2.zip")
        assert m3.get_status()["mode"] == "full" and m3.get_status()["plan"] is None
        print("test_update_git_plan: OK")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
