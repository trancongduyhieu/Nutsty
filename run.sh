#!/usr/bin/env bash
# Nutsty Entry Script
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CURRENT_COMMIT="$(git -C "$DIR" rev-parse HEAD 2>/dev/null || echo "unknown")"
LAST_COMMIT="$(cat /tmp/nutsty_running_commit 2>/dev/null || echo "")"

# Ensure required Python dependencies before starting backend or UI
if ! python3 -c "import mutagen, ytmusicapi, syncedlyrics, pypinyin" >/dev/null 2>&1; then
    echo "Installing missing Python dependencies (mutagen, ytmusicapi, syncedlyrics, pypinyin)..."
    python3 -m pip install mutagen ytmusicapi syncedlyrics pypinyin --quiet || \
    python3 -m pip install --break-system-packages --user mutagen ytmusicapi syncedlyrics pypinyin --quiet || true
fi

# Terminate legacy heavy Python auth_server if running
pkill -f "backend/auth_server.py" >/dev/null 2>&1 || true

# Always restart nutsty-daemon so backend updates take effect immediately
pkill -f "$DIR/bin/nutsty-daemon" >/dev/null 2>&1 || true
sleep 0.15
if [ -x "$DIR/bin/nutsty-daemon" ]; then
    "$DIR/bin/nutsty-daemon" >/dev/null 2>&1 &
else
    python3 "$DIR/backend/auth_server.py" >/dev/null 2>&1 &
fi

# If git commit changed (e.g. after git pull) or --restart flag passed, restart running Quickshell instance
if [ "$1" == "--restart" ] || { [ -n "$LAST_COMMIT" ] && [ "$CURRENT_COMMIT" != "$LAST_COMMIT" ]; }; then
    echo "Detected updated version ($CURRENT_COMMIT), restarting Nutsty UI..."
    pkill -9 -f "quickshell.*$DIR/shell.qml" >/dev/null 2>&1 || true
    while pgrep -f "quickshell.*$DIR/shell.qml" >/dev/null 2>&1; do
        sleep 0.1
    done
    sleep 0.2
fi

echo "$CURRENT_COMMIT" > /tmp/nutsty_running_commit 2>/dev/null || true

# Ensure high-performance Rust native bridge is ready
if [ ! -f "$DIR/bin/nutsty-bridge" ] && [ -d "$DIR/nutsty-rs" ]; then
    echo "Building high-performance Nutsty Rust bridge..."
    (cd "$DIR/nutsty-rs" && cargo build --release --bin nutsty-bridge)
    cp "$DIR/nutsty-rs/target/release/nutsty-bridge" "$DIR/bin/nutsty-bridge"
    chmod +x "$DIR/bin/nutsty-bridge"
fi

# Ensure high-performance Rust native library scanner is ready
if [ ! -f "$DIR/bin/nutsty-library" ] && [ -d "$DIR/nutsty-rs" ]; then
    echo "Building high-performance Nutsty Rust library scanner..."
    (cd "$DIR/nutsty-rs" && cargo build --release -p nutsty-library --bin nutsty-library)
    cp "$DIR/nutsty-rs/target/release/nutsty-library" "$DIR/bin/nutsty-library"
    chmod +x "$DIR/bin/nutsty-library"
fi

# Ensure ultra-lightweight Rust tray indicator is ready (< 2MB RAM)
if [ ! -f "$DIR/bin/nutsty-tray" ] && [ -d "$DIR/nutsty-rs/crates/nutsty-tray" ]; then
    echo "Building ultra-lightweight Nutsty Rust tray indicator..."
    (cd "$DIR/nutsty-rs/crates/nutsty-tray" && cargo build --release)
    cp "$DIR/nutsty-rs/crates/nutsty-tray/target/release/nutsty-tray" "$DIR/bin/nutsty-tray"
    chmod +x "$DIR/bin/nutsty-tray"
fi

# Ensure high-performance Rust native resident daemon is ready (< 5MB RAM)
if [ ! -f "$DIR/bin/nutsty-daemon" ] && [ -d "$DIR/nutsty-rs/crates/nutsty-daemon" ]; then
    echo "Building high-performance Nutsty Rust resident daemon..."
    (cd "$DIR/nutsty-rs" && cargo build --release -p nutsty-daemon --bin nutsty-daemon)
    cp "$DIR/nutsty-rs/target/release/nutsty-daemon" "$DIR/bin/nutsty-daemon"
    chmod +x "$DIR/bin/nutsty-daemon"
fi

start_tray_indicator() {
    # Terminate legacy heavy Python tray indicator if running
    if pgrep -f "backend/tray_indicator.py" >/dev/null 2>&1; then
        pkill -f "backend/tray_indicator.py" >/dev/null 2>&1 || true
    fi

    # Prefer ultra-lightweight Rust tray indicator (< 2MB RAM), fallback to Python if missing
    if [ -x "$DIR/bin/nutsty-tray" ]; then
        if ! pgrep -f "$DIR/bin/nutsty-tray" >/dev/null 2>&1; then
            "$DIR/bin/nutsty-tray" >/dev/null 2>&1 &
        fi
    elif [ -f "$DIR/backend/tray_indicator.py" ]; then
        if ! pgrep -f "backend/tray_indicator.py" >/dev/null 2>&1; then
            python3 "$DIR/backend/tray_indicator.py" >/dev/null 2>&1 &
        fi
    fi
}

# If an instance of Nutsty is already running (same commit), bring window to front via IPC
if /usr/bin/quickshell ipc -p "$DIR/shell.qml" call nutsty openWindow 2>/dev/null || /usr/bin/quickshell ipc -p "$DIR/shell.qml" call frostify openWindow 2>/dev/null; then
    echo "Nutsty is already running, brought window to front."
    start_tray_indicator
    exit 0
fi

# Ensure background tray indicator is running
start_tray_indicator

# Scan library if missing or requested
if [ ! -f "$DIR/library.json" ] || [ "$1" == "--rescan" ]; then
    echo "Scanning music library..."
    if [ -x "$DIR/bin/nutsty-library" ]; then
        "$DIR/bin/nutsty-library" scan
    else
        python3 "$DIR/backend/library.py"
    fi
fi

# Memory allocator tuning: prevent jemalloc from using 2MB Transparent Huge Pages
# and aggressively return unused dirty memory to the OS (vital for CachyOS/Arch Linux)
export MALLOC_CONF="background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000,thp:never,metadata_thp:disabled"

# Launch Nutsty with Quickshell (with kernel THP disabled to prevent memory inflation)
echo "Launching Nutsty..."
exec python3 -c '
import ctypes, os, sys
try:
    # PR_SET_THP_DISABLE = 41
    ctypes.CDLL(None).prctl(41, 1, 0, 0, 0)
except Exception:
    pass
os.execvp("/usr/bin/quickshell", ["/usr/bin/quickshell", "-p", sys.argv[1]])
' "$DIR/shell.qml"
