#!/usr/bin/env python3
"""
Nutsty Cross-Platform Launcher (Windows & Desktop Qt Quick)
Launches Nutsty with PySide6 / PyQt6, injects compatibility bridges for Quickshell APIs,
starts background services, and displays the main window.
"""
import os
import sys
import json
import time
import subprocess
import threading
from pathlib import Path

# Safe logging for Windows PyInstaller GUI mode (where sys.stdout/stderr are None)
class SafeLogWriter:
    def __init__(self, log_path=None):
        self.log_file = None
        if log_path:
            try:
                os.makedirs(os.path.dirname(log_path), exist_ok=True)
                self.log_file = open(log_path, "a", encoding="utf-8", errors="replace")
            except Exception:
                pass

    def write(self, s):
        if self.log_file:
            try:
                self.log_file.write(str(s))
                self.log_file.flush()
            except Exception:
                pass

    def flush(self):
        if self.log_file:
            try:
                self.log_file.flush()
            except Exception:
                pass

class ThreadLocalStream:
    def __init__(self, default_stream):
        self._local = threading.local()
        self._default = default_stream

    def set_stream(self, stream):
        self._local.stream = stream

    def clear_stream(self):
        if hasattr(self._local, "stream"):
            del self._local.stream

    def write(self, s):
        stream = getattr(self._local, "stream", self._default)
        if stream:
            try:
                return stream.write(s)
            except Exception:
                pass

    def flush(self):
        stream = getattr(self._local, "stream", self._default)
        if stream and hasattr(stream, "flush"):
            try:
                return stream.flush()
            except Exception:
                pass

log_dir = os.path.join(os.environ.get("TEMP", os.path.expanduser("~")), "nutsty")
log_file_path = os.path.join(log_dir, "launcher.log")
default_out = sys.stdout if sys.stdout is not None else SafeLogWriter(log_file_path)
default_err = sys.stderr if sys.stderr is not None else SafeLogWriter(log_file_path)

sys.stdout = ThreadLocalStream(default_out)
sys.stderr = ThreadLocalStream(default_err)

# Resolve App and Resource Root across source runs and PyInstaller onedir bundles
def resolve_app_root():
    if getattr(sys, "frozen", False):
        meipass = getattr(sys, "_MEIPASS", None)
        if meipass and os.path.exists(os.path.join(meipass, "shell.qml")):
            return meipass
        exe_dir = os.path.dirname(sys.executable)
        internal_dir = os.path.join(exe_dir, "_internal")
        if os.path.exists(os.path.join(internal_dir, "shell.qml")):
            return internal_dir
        if os.path.exists(os.path.join(exe_dir, "shell.qml")):
            return exe_dir
        return meipass or exe_dir
    return os.path.dirname(os.path.abspath(__file__))

APP_ROOT = resolve_app_root()
os.environ["NUTSTY_APP_DIR"] = APP_ROOT
if "HOME" not in os.environ:
    os.environ["HOME"] = os.path.expanduser("~")

bin_dir = os.path.join(APP_ROOT, "bin")
if os.path.exists(bin_dir) and bin_dir not in os.environ.get("PATH", ""):
    os.environ["PATH"] = bin_dir + os.pathsep + os.environ.get("PATH", "")

sys.path.insert(0, os.path.join(APP_ROOT, "backend"))

import platform_compat as pc
pc.configure_windows_ssl()

sys_argv_lock = threading.Lock()

BACKEND_MAP = {
    "player_daemon.py": "player_daemon",
    "auth_server.py": "auth_server",
    "download_manager.py": "download_manager",
    "library.py": "library",
    "palette_extractor.py": "palette_extractor",
    "lyrics_helper.py": "lyrics_helper",
    "playlist_manager.py": "playlist_manager",
    "ytmusic_helper.py": "ytmusic_helper",
    "social_notes.py": "social_notes",
    "browser_login.py": "browser_login",
}

# Backend CLI Dispatcher: Prevents re-launching GUI when invoked as backend worker
def check_cli_dispatch():
    """
    If Nutsty.exe is invoked with backend script arguments (e.g. from QML Process
    or external scripts), dispatch to that script in headless mode and exit.
    This prevents fork bombs and infinite window popup loops.
    """
    args = sys.argv[1:]
    if not args:
        return
    for i, a in enumerate(args):
        base_a = os.path.basename(a)
        if base_a in BACKEND_MAP:
            mod_name = BACKEND_MAP[base_a]
            sys.argv = [a] + args[i + 1:]
            try:
                import importlib
                mod = importlib.import_module(mod_name)
                if hasattr(mod, "handle_cli"):
                    mod.handle_cli(args[i + 1:])
                elif hasattr(mod, "main"):
                    mod.main()
                else:
                    import runpy
                    runpy.run_module(mod_name, run_name="__main__", alter_sys=True)
                sys.exit(0)
            except SystemExit as se:
                sys.exit(se.code if isinstance(se.code, int) else 0)
            except Exception as e:
                sys.stderr.write(f"Error running {base_a}: {e}\n")
                sys.exit(1)

# Run CLI dispatch check immediately
check_cli_dispatch()

# Detect Qt bindings (PySide6 or PyQt6)
try:
    from PySide6.QtCore import QObject, Signal, Property, Slot, QUrl, QTimer, QThread, QRect
    from PySide6.QtGui import QGuiApplication, QIcon, QWindow, QRegion
    from PySide6.QtQml import QQmlApplicationEngine, qmlRegisterType, QmlAttached
    from PySide6.QtQuick import QQuickWindow
    IS_PYSIDE = True
except ImportError:
    try:
        from PyQt6.QtCore import QObject, pyqtSignal as Signal, pyqtProperty as Property, pyqtSlot as Slot, QUrl, QTimer, QThread, QRect
        from PyQt6.QtGui import QGuiApplication, QIcon, QWindow, QRegion
        from PyQt6.QtQml import QQmlApplicationEngine, qmlRegisterType
        from PyQt6.QtQuick import QQuickWindow
        IS_PYSIDE = False
    except ImportError:
        sys.stderr.write("Fatal: Neither PySide6 nor PyQt6 is installed.\n")
        sys.stderr.write("Please run: pip install PySide6\n")
        sys.exit(1)

class NutstyBridge(QObject):
    processFinished = Signal(int, str, str, int)

    def __init__(self, parent=None):
        super().__init__(parent)
        self._callbacks = {}
        self._cb_id = 0
        self._cb_lock = threading.Lock()
        self.processFinished.connect(self._onProcessFinished)

    @Slot(int, str, str, int)
    def _onProcessFinished(self, cb_id, out, err, code):
        cb = None
        with self._cb_lock:
            cb = self._callbacks.pop(cb_id, None)
        if cb:
            try:
                if IS_PYSIDE:
                    from PySide6.QtQml import QJSValue
                    cb.call([QJSValue(str(out or "")), QJSValue(str(err or "")), QJSValue(int(code or 0))])
                else:
                    cb.call([str(out or ""), str(err or ""), int(code or 0)])
            except Exception as e:
                sys.stderr.write(f"Process callback execution error: {e}\n")

    @Slot(str, result=str)
    def getEnv(self, key: str) -> str:
        if key == "HOME":
            return os.path.expanduser("~")
        elif key == "NUTSTY_APP_DIR":
            return APP_ROOT
        return os.environ.get(key, "")

    @Slot(str, result=str)
    def readFile(self, path: str) -> str:
        if not path:
            return ""
        if path.startswith("/tmp"):
            path = os.path.join(pc.get_temp_dir(), path[5:].lstrip("/\\"))
        if not os.path.exists(path):
            return ""
        try:
            with open(path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        except Exception:
            return ""

    @Slot(str, result=str)
    def checkFileMtime(self, path: str) -> str:
        if not path:
            return ""
        if path.startswith("/tmp"):
            path = os.path.join(pc.get_temp_dir(), path[5:].lstrip("/\\"))
        if not os.path.exists(path):
            return ""
        try:
            return str(os.path.getmtime(path))
        except Exception:
            return ""

    @Slot(str)
    def copyToClipboard(self, text: str):
        try:
            from PySide6.QtGui import QGuiApplication
            cb = QGuiApplication.clipboard()
            if cb:
                cb.setText(str(text))
        except Exception as e:
            sys.stderr.write(f"copyToClipboard failed: {e}\n")

    @Slot(result=str)
    def getClipboardText(self) -> str:
        try:
            from PySide6.QtGui import QGuiApplication
            cb = QGuiApplication.clipboard()
            if cb:
                return cb.text() or ""
        except Exception as e:
            sys.stderr.write(f"getClipboardText failed: {e}\n")
        return ""

    @Slot(QObject, int, int, int, int)
    def setWindowMaskRect(self, win_obj, x: int, y: int, w: int, h: int):
        try:
            if win_obj and hasattr(win_obj, "setMask"):
                if w <= 0 or h <= 0:
                    win_obj.setMask(QRegion(QRect(-100, -100, 1, 1)))
                else:
                    win_obj.setMask(QRegion(QRect(int(x), int(y), int(w), int(h))))
                self.pinWindowToDesktopBottom(win_obj)
        except Exception as e:
            sys.stderr.write(f"setWindowMaskRect error: {e}\n")

    @Slot(QObject)
    def clearWindowMask(self, win_obj):
        try:
            if win_obj and hasattr(win_obj, "setMask"):
                win_obj.setMask(QRegion())
                self.pinWindowToDesktopBottom(win_obj)
        except Exception as e:
            sys.stderr.write(f"clearWindowMask error: {e}\n")

    @Slot(QObject)
    def pinWindowToDesktopBottom(self, win_obj):
        """Pin DesktopMusicWidget and DesktopLyricsWidget to Win32 HWND_BOTTOM (matching WlrLayer.Bottom)."""
        try:
            if not win_obj:
                return
            if hasattr(win_obj, "lower"):
                win_obj.lower()
            if pc.IS_WINDOWS and hasattr(win_obj, "winId"):
                import ctypes
                hwnd = int(win_obj.winId())
                if hwnd:
                    user32 = ctypes.windll.user32
                    GWL_EXSTYLE = -20
                    WS_EX_NOACTIVATE = 0x08000000
                    WS_EX_TOOLWINDOW = 0x00000080
                    WS_EX_APPWINDOW = 0x00040000
                    WS_EX_TOPMOST = 0x00000008
                    ex_style = user32.GetWindowLongW(hwnd, GWL_EXSTYLE)
                    target_ex = (ex_style | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW) & ~(WS_EX_APPWINDOW | WS_EX_TOPMOST)
                    if ex_style != target_ex:
                        user32.SetWindowLongW(hwnd, GWL_EXSTYLE, target_ex)
                    HWND_BOTTOM = 1
                    SWP_NOSIZE = 0x0001
                    SWP_NOMOVE = 0x0002
                    SWP_NOACTIVATE = 0x0010
                    user32.SetWindowPos(hwnd, HWND_BOTTOM, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE)
        except Exception as e:
            sys.stderr.write(f"pinWindowToDesktopBottom error: {e}\n")

    @Slot(QObject)
    def restoreWindow(self, win_obj):
        try:
            if not win_obj:
                return
            if hasattr(win_obj, "setVisible"):
                win_obj.setVisible(True)
            if hasattr(win_obj, "showNormal"):
                win_obj.showNormal()
            if hasattr(win_obj, "show"):
                win_obj.show()
            if hasattr(win_obj, "raise_"):
                win_obj.raise_()
            elif hasattr(win_obj, "raise"):
                getattr(win_obj, "raise")()
            if hasattr(win_obj, "requestActivate"):
                win_obj.requestActivate()
            if pc.IS_WINDOWS and hasattr(win_obj, "winId"):
                import ctypes
                hwnd = int(win_obj.winId())
                if hwnd:
                    user32 = ctypes.windll.user32
                    SW_RESTORE = 9
                    SW_SHOW = 5
                    user32.ShowWindow(hwnd, SW_RESTORE)
                    user32.ShowWindow(hwnd, SW_SHOW)
                    user32.BringWindowToTop(hwnd)
                    user32.SetForegroundWindow(hwnd)
        except Exception as e:
            sys.stderr.write(f"restoreWindow error: {e}\n")

    @Slot(list)
    def execDetached(self, args: list):
        if not args:
            return

        if args[0] == "wl-copy":
            self.copyToClipboard(args[1] if len(args) > 1 else "")
            return

        if args[0] == "xdg-open" and len(args) > 1:
            try:
                target_path = os.path.normpath(args[1])
                os.makedirs(target_path, exist_ok=True)
                if hasattr(os, "startfile"):
                    os.startfile(target_path)
            except Exception as e:
                sys.stderr.write(f"xdg-open failed: {e}\n")
            return

        # In-process fast path for backend Python scripts (prevents heavy Nutsty.exe subprocess spawn)
        target_script = ""
        script_args = []
        for i, a in enumerate(args):
            base_a = os.path.basename(a)
            if base_a in BACKEND_MAP:
                target_script = base_a
                script_args = list(args[i+1:])
                break

        if target_script:
            mod_name = BACKEND_MAP[target_script]
            def _in_proc_detached():
                try:
                    import importlib
                    if mod_name in sys.modules:
                        mod = sys.modules[mod_name]
                    else:
                        mod = importlib.import_module(mod_name)
                    if hasattr(mod, "handle_cli"):
                        mod.handle_cli(script_args)
                    elif hasattr(mod, "main"):
                        with sys_argv_lock:
                            old_argv = sys.argv
                            sys.argv = [target_script] + script_args
                            try:
                                mod.main()
                            finally:
                                sys.argv = old_argv
                    else:
                        import runpy
                        with sys_argv_lock:
                            old_argv = sys.argv
                            sys.argv = [target_script] + script_args
                            try:
                                runpy.run_module(mod_name, run_name="__main__", alter_sys=False)
                            finally:
                                sys.argv = old_argv
                except SystemExit:
                    pass
                except Exception as e:
                    sys.stderr.write(f"In-process execDetached {target_script} failed: {e}\n")
            threading.Thread(target=_in_proc_detached, daemon=True).start()
            return

        cmd = list(args)
        if cmd[0] == "python3" or cmd[0] == "python":
            cmd[0] = sys.executable
        try:
            subprocess.Popen(cmd, **pc.get_daemon_popen_kwargs())
        except Exception as e:
            sys.stderr.write(f"execDetached failed: {e}\n")

    @Slot(list, "QJSValue")
    def runProcess(self, args: list, callback):
        """Run process asynchronously and invoke JS callback(stdout, stderr, exitCode)."""
        if not args:
            return

        with self._cb_lock:
            self._cb_id += 1
            cb_id = self._cb_id
            self._callbacks[cb_id] = callback

        if args[0] == "wl-copy":
            self.copyToClipboard(args[1] if len(args) > 1 else "")
            self.processFinished.emit(cb_id, "", "", 0)
            return

        target_script = ""
        script_args = []
        for i, a in enumerate(args):
            base_a = os.path.basename(a)
            if base_a in BACKEND_MAP:
                target_script = base_a
                script_args = list(args[i+1:])
                break

        # Fast path for player_daemon status (executes in 0.1ms in-process with direct JSON getter)
        if target_script == "player_daemon.py" and script_args and script_args[0] == "status":
            def _status_worker():
                try:
                    import player_daemon
                    out = player_daemon.get_status_json()
                    err = ""
                    code = 0
                except Exception as e:
                    out = ""
                    err = str(e)
                    code = 1
                self.processFinished.emit(cb_id, out, err, code)
            threading.Thread(target=_status_worker, daemon=True).start()
            return

        # Fast unified in-process execution for all backend scripts in BACKEND_MAP (except browser_login which requires isolated subprocess)
        if target_script and target_script != "browser_login.py":
            mod_name = BACKEND_MAP[target_script]
            def _in_proc_run():
                import io, importlib
                out_buf = io.StringIO()
                err_buf = io.StringIO()
                code = 0

                # Set thread-local output streams so concurrent calls don't interfere
                if hasattr(sys.stdout, "set_stream"):
                    sys.stdout.set_stream(out_buf)
                if hasattr(sys.stderr, "set_stream"):
                    sys.stderr.set_stream(err_buf)

                try:
                    if mod_name in sys.modules:
                        mod = sys.modules[mod_name]
                    else:
                        mod = importlib.import_module(mod_name)

                    if hasattr(mod, "handle_cli"):
                        mod.handle_cli(script_args)
                    elif hasattr(mod, "main"):
                        with sys_argv_lock:
                            old_argv = sys.argv
                            sys.argv = [target_script] + script_args
                            try:
                                mod.main()
                            finally:
                                sys.argv = old_argv
                    else:
                        import runpy
                        with sys_argv_lock:
                            old_argv = sys.argv
                            sys.argv = [target_script] + script_args
                            try:
                                runpy.run_module(mod_name, run_name="__main__", alter_sys=False)
                            finally:
                                sys.argv = old_argv
                except SystemExit as se:
                    code = se.code if isinstance(se.code, int) else 0
                except Exception as e:
                    err_buf.write(str(e))
                    code = 1
                finally:
                    if hasattr(sys.stdout, "clear_stream"):
                        sys.stdout.clear_stream()
                    if hasattr(sys.stderr, "clear_stream"):
                        sys.stderr.clear_stream()

                out = out_buf.getvalue()
                err = err_buf.getvalue()
                if err and default_err:
                    try:
                        default_err.write(f"[_in_proc_run {target_script}]: {err}\n")
                        default_err.flush()
                    except Exception:
                        pass
                self.processFinished.emit(cb_id, out, err, code)

            threading.Thread(target=_in_proc_run, daemon=True).start()
            return

        cmd = list(args)
        if cmd[0] == "python3" or cmd[0] == "python":
            cmd[0] = sys.executable

        def _worker():
            try:
                proc_timeout = 360 if any("browser_login" in str(x) for x in cmd) else 60
                res = subprocess.run(cmd, capture_output=True, text=True, timeout=proc_timeout, **pc.get_daemon_popen_kwargs())
                out = res.stdout or ""
                err = res.stderr or ""
                code = res.returncode
            except Exception as e:
                out = ""
                err = str(e)
                code = 1
            
            self.processFinished.emit(cb_id, out, err, code)

        threading.Thread(target=_worker, daemon=True).start()

# Quickshell Compatibility Classes
class WlrLayershellAttached(QObject):
    def __init__(self, parent=None):
        super().__init__(parent)
        self._layer = 0
        self._namespace = ""
    @Property(int)
    def layer(self): return self._layer
    @layer.setter
    def layer(self, v): self._layer = v
    @Property(str)
    def namespace(self): return self._namespace
    @namespace.setter
    def namespace(self, v): self._namespace = v

def register_qml_types():
    if IS_PYSIDE:
        @QmlAttached(WlrLayershellAttached)
        class WlrLayershell(QObject):
            @staticmethod
            def qmlAttachedProperties(*args, **kwargs):
                parent = args[-1] if (args and isinstance(args[-1], QObject)) else None
                return WlrLayershellAttached(parent)
        qmlRegisterType(WlrLayershell, "Quickshell.Wayland", 1, 0, "WlrLayershell")
    else:
        class WlrLayershell(QObject):
            qmlAttachedProperties = WlrLayershellAttached
        qmlRegisterType(WlrLayershell, "Quickshell.Wayland", 1, 0, "WlrLayershell", attachedProperties=WlrLayershellAttached)

def start_daemons():
    """Start resident backend daemons (auth_server HTTP daemon, palette_extractor)."""
    def _auth_runner():
        try:
            import auth_server
            if hasattr(auth_server, "run_server"):
                auth_server.run_server()
            elif hasattr(auth_server, "main"):
                auth_server.main()
        except Exception as e:
            sys.stderr.write(f"auth_server daemon thread error: {e}\n")

    def _palette_runner():
        try:
            import palette_extractor
            if hasattr(palette_extractor, "main"):
                palette_extractor.main()
        except Exception as e:
            sys.stderr.write(f"palette_extractor daemon thread error: {e}\n")

    def _library_runner():
        try:
            import library
            if hasattr(library, "main"):
                library.main()
        except Exception as e:
            sys.stderr.write(f"library scanner daemon thread error: {e}\n")

    threading.Thread(target=_auth_runner, daemon=True).start()
    threading.Thread(target=_palette_runner, daemon=True).start()
    threading.Thread(target=_library_runner, daemon=True).start()

def _create_nutsty_app_icon(icon_save_path: str) -> QIcon:
    """Create a crisp Dark Glass + Equalizer wave icon for Nutsty taskbar & Windows System Tray."""
    try:
        from PySide6.QtGui import QPixmap, QPainter, QColor, QPen, QBrush
        from PySide6.QtCore import Qt, QRectF
        pix = QPixmap(64, 64)
        pix.fill(Qt.GlobalColor.transparent)
        painter = QPainter(pix)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing, True)

        # Outer Dark Glass Rounded Square (R=16)
        bg_rect = QRectF(2, 2, 60, 60)
        painter.setPen(QPen(QColor(222, 176, 108, 210), 2.5))
        painter.setBrush(QBrush(QColor(16, 18, 24, 248)))
        painter.drawRoundedRect(bg_rect, 16, 16)

        # 3 Warm Gold Equalizer Bars (Nutsty signature soundwave)
        painter.setPen(Qt.PenStyle.NoPen)
        painter.setBrush(QBrush(QColor(222, 176, 108, 255)))
        painter.drawRoundedRect(QRectF(16, 24, 6, 18), 3, 3)
        painter.drawRoundedRect(QRectF(29, 15, 6, 34), 3, 3)
        painter.drawRoundedRect(QRectF(42, 21, 6, 24), 3, 3)
        painter.end()

        if icon_save_path and not os.path.exists(icon_save_path):
            try:
                os.makedirs(os.path.dirname(icon_save_path), exist_ok=True)
                pix.save(icon_save_path, "PNG")
            except Exception:
                pass
        return QIcon(pix)
    except Exception:
        return QIcon()


def main():
    os.environ["QT_QUICK_CONTROLS_STYLE"] = "Basic"

    try:
        from PySide6.QtWidgets import QApplication, QSystemTrayIcon, QMenu
        from PySide6.QtGui import QCursor, QAction
        app = QApplication(sys.argv)
        has_widgets = True
    except Exception:
        app = QGuiApplication(sys.argv)
        has_widgets = False

    app.setQuitOnLastWindowClosed(False)
    app.setApplicationName("Nutsty")
    app.setOrganizationName("Nutsty")

    icon_path = os.path.join(APP_ROOT, "assets", "icons", "nutsty.png")
    app_icon = _create_nutsty_app_icon(icon_path)
    if os.path.exists(icon_path) and app_icon.isNull():
        app_icon = QIcon(icon_path)
    if not app_icon.isNull():
        app.setWindowIcon(app_icon)

    register_qml_types()
    start_daemons()

    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda warns: [sys.stderr.write(f"QML Warning: {w.toString()}\n") for w in warns])

    compat_path = os.path.join(APP_ROOT, "compat")
    engine.addImportPath(compat_path)
    engine.addImportPath(APP_ROOT)
    engine.addImportPath(os.path.join(APP_ROOT, "components"))

    if getattr(sys, "frozen", False):
        pyside_qml = os.path.join(APP_ROOT, "PySide6", "qml")
        if os.path.exists(pyside_qml):
            engine.addImportPath(pyside_qml)
        exe_dir = os.path.dirname(sys.executable)
        alt_pyside_qml = os.path.join(exe_dir, "_internal", "PySide6", "qml")
        if os.path.exists(alt_pyside_qml):
            engine.addImportPath(alt_pyside_qml)

    bridge = NutstyBridge()
    engine.rootContext().setContextProperty("__NutstyBridge", bridge)

    shell_qml = os.path.join(APP_ROOT, "shell.qml")
    engine.load(QUrl.fromLocalFile(shell_qml))

    if not engine.rootObjects():
        err_details = [
            f"Target QML: {shell_qml}",
            f"File Exists: {os.path.exists(shell_qml)}",
            f"APP_ROOT: {APP_ROOT}",
            f"Executable: {sys.executable}",
            f"sys._MEIPASS: {getattr(sys, '_MEIPASS', 'N/A')}",
            f"Log File: {log_file_path}",
        ]
        msg = "Fatal: Failed to load QML root object.\n\n" + "\n".join(err_details)
        sys.stderr.write(msg + "\n")
        try:
            if sys.platform == "win32":
                import ctypes
                ctypes.windll.user32.MessageBoxW(0, msg, "Nutsty Error", 0x10)
        except Exception:
            pass
        sys.exit(1)

    def _is_bottom_panel(w):
        try:
            return bool(w.property("isDesktopBottomPanel"))
        except Exception:
            return False

    def _init_win(w):
        if _is_bottom_panel(w):
            w.show()
            bridge.pinWindowToDesktopBottom(w)
        else:
            if main_win_ref[0] is None and w.width() >= 500:
                main_win_ref[0] = w
            w.show()
            w.raise_()
            w.requestActivate()

    main_win_ref = [None]
    for obj in engine.rootObjects():
        if isinstance(obj, (QWindow, QQuickWindow)):
            _init_win(obj)
        if hasattr(obj, "findChildren"):
            for child_win in obj.findChildren(QWindow):
                _init_win(child_win)

    for top_win in app.topLevelWindows():
        _init_win(top_win)

    # Setup Windows System Tray Icon with "Mở toàn màn hình / Mở cửa sổ chính" & "Tắt ứng dụng"
    tray_icon = None
    if has_widgets and QSystemTrayIcon.isSystemTrayAvailable():
        tray_icon = QSystemTrayIcon(app_icon, app)
        tray_icon.setToolTip("Nutsty Music Player")

        tray_menu = QMenu()
        tray_menu.setStyleSheet("""
            QMenu {
                background-color: #101218;
                color: #ffffff;
                border: 1px solid rgba(222, 176, 108, 0.38);
                border-radius: 10px;
                padding: 6px;
                font-family: 'Segoe UI', 'Inter', sans-serif;
                font-size: 13px;
                font-weight: 600;
            }
            QMenu::item {
                padding: 8px 18px;
                border-radius: 6px;
                margin: 2px 2px;
            }
            QMenu::item:selected {
                background-color: rgba(222, 176, 108, 0.22);
                color: #ffffff;
            }
            QMenu::separator {
                height: 1px;
                background: rgba(255, 255, 255, 0.10);
                margin: 4px 8px;
            }
        """)

        def _open_full_window():
            target_w = main_win_ref[0]
            if not target_w or _is_bottom_panel(target_w):
                for tw in app.topLevelWindows():
                    if not _is_bottom_panel(tw) and tw.width() >= 500:
                        target_w = tw
                        main_win_ref[0] = tw
                        break
            if target_w:
                target_w.setProperty("visible", True)
                bridge.restoreWindow(target_w)

        def _quit_nutsty_completely():
            try:
                if tray_icon:
                    tray_icon.hide()
            except Exception:
                pass
            try:
                import player_daemon
                player_daemon.handle_cli(["stop"])
            except Exception:
                pass
            os._exit(0)

        act_open = QAction("Mở cửa sổ chính (Open Full)", tray_menu)
        act_open.triggered.connect(_open_full_window)
        tray_menu.addAction(act_open)

        tray_menu.addSeparator()

        act_quit = QAction("Tắt ứng dụng (Quit)", tray_menu)
        act_quit.triggered.connect(_quit_nutsty_completely)
        tray_menu.addAction(act_quit)

        tray_icon.setContextMenu(tray_menu)

        def _on_tray_activated(reason):
            if reason == QSystemTrayIcon.ActivationReason.DoubleClick:
                _open_full_window()
            elif reason in (QSystemTrayIcon.ActivationReason.Trigger, QSystemTrayIcon.ActivationReason.Context):
                tray_menu.popup(QCursor.pos())
                tray_menu.activateWindow()

        tray_icon.activated.connect(_on_tray_activated)
        tray_icon.show()

    # Periodic RAM optimization timer (Runs gc & trims Working Set on Windows every 60s)
    def _trim_ram():
        try:
            import gc
            gc.collect()
            if sys.platform == "win32":
                import ctypes
                kernel32 = ctypes.windll.kernel32
                psapi = ctypes.windll.psapi
                kernel32.GetCurrentProcess.restype = ctypes.c_void_p
                psapi.EmptyWorkingSet.argtypes = [ctypes.c_void_p]
                psapi.EmptyWorkingSet.restype = ctypes.c_bool
                psapi.EmptyWorkingSet(kernel32.GetCurrentProcess())
        except Exception:
            pass

    mem_timer = QTimer(app)
    mem_timer.setInterval(60000)
    mem_timer.timeout.connect(_trim_ram)
    mem_timer.start()
    QTimer.singleShot(8000, _trim_ram)

    sys.exit(app.exec())

if __name__ == "__main__":
    main()

