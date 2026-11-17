#!/usr/bin/env python3
"""
Contract test for the Quickshell seam: load Nutsty's QML through the Windows compat layer.

shell.qml and components/ are written against Quickshell. On Windows they run on compat/Quickshell
instead, so any Quickshell type, property or signal that compat lacks crashes the app at startup with
"Failed to load QML root object". This script catches that before a release:

1. Every .qml file in components/ and compat/ must compile against compat (unknown properties,
   signal handlers and types are compile errors, including in files only created later by a Loader).
2. shell.qml must create its root object, the same way launcher_win.main() does, and produce no QML
   or JS warning while the event loop settles.

Runs offscreen with the software scene graph and without NutstyBridge, so no backend script is started. Needs PySide6
(on Linux also libegl1, libgl1, libxkbcommon0, libfontconfig1, libdbus-1-3).

Usage: python scripts/verify_qml_compat.py [--settle-ms 1500]
"""

import argparse
import os
import sys
import time
from pathlib import Path

ROOT_DIR = Path(__file__).resolve().parent.parent
# Platform messages Qt prints for the offscreen plugin itself, not for Nutsty's QML
IGNORED_WARNINGS = ("This plugin does not support",)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--settle-ms", type=int, default=1500,
                        help="how long to run the event loop after shell.qml is created")
    args = parser.parse_args()

    os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    # Software scene graph: no GPU or Direct3D needed on CI runners (launcher_win picks d3d11 on Windows)
    os.environ.setdefault("QT_QUICK_BACKEND", "software")
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"
    sys.path.insert(0, str(ROOT_DIR))

    try:
        from PySide6.QtCore import QTimer, QUrl, qInstallMessageHandler, QtMsgType
        from PySide6.QtQml import QQmlComponent, QQmlEngine
        from PySide6.QtWidgets import QApplication
    except ImportError as exc:
        print(f"FAIL: PySide6 is required ({exc}). Install it with: pip install PySide6")
        return 1

    qml_warnings = []

    def on_message(msg_type, context, message):
        if msg_type == QtMsgType.QtDebugMsg or msg_type == QtMsgType.QtInfoMsg:
            return
        if any(message.startswith(prefix) for prefix in IGNORED_WARNINGS):
            return
        source = context.file or ""
        if source.endswith((".qml", ".js")) or ".qml:" in message or ".js:" in message:
            qml_warnings.append(message)

    qInstallMessageHandler(on_message)
    app = QApplication([])

    import launcher_win
    launcher_win.register_qml_types()

    # Same import paths as launcher_win.main(), compat first so it shadows any real Quickshell
    engine = QQmlEngine()
    for sub in ("compat", "", "components"):
        engine.addImportPath(str(ROOT_DIR / sub))

    failures = []
    started = time.perf_counter()

    qml_files = sorted((ROOT_DIR / "components").glob("*.qml")) + sorted((ROOT_DIR / "compat").rglob("*.qml"))
    for path in qml_files:
        component = QQmlComponent(engine, QUrl.fromLocalFile(str(path)))
        if not component.isReady():
            failures.append((path.relative_to(ROOT_DIR).as_posix(), [e.toString() for e in component.errors()]))

    # Warnings from compiling single files are expected (no `win` context); only shell.qml's count
    qml_warnings.clear()
    shell = QQmlComponent(engine, QUrl.fromLocalFile(str(ROOT_DIR / "shell.qml")))
    root = shell.create() if shell.isReady() else None
    if root is None:
        failures.append(("shell.qml", [e.toString() for e in shell.errors()] or ["root object was not created"]))
    else:
        QTimer.singleShot(max(0, args.settle_ms), app.quit)
        app.exec()
        if qml_warnings:
            failures.append(("shell.qml (runtime)", list(dict.fromkeys(qml_warnings))))

    elapsed = time.perf_counter() - started
    if failures:
        for name, errors in failures:
            print(f"FAIL {name}")
            for err in errors:
                print(f"    {err}")
        print(f"\n{len(failures)} failure(s) in {elapsed:.1f}s across {len(qml_files) + 1} QML files")
        return 1

    print(f"OK: {len(qml_files) + 1} QML files load through compat ({elapsed:.1f}s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
