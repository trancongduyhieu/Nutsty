#!/usr/bin/env python3
"""
Nutsty Crossfade & AutoMix engine.

The main mpv stays the single source of truth for playback state. For a
crossfade a short-lived "tail" mpv plays the last seconds of the outgoing
track while the main mpv switches to the incoming one. Both fades are lavfi
`afade` filters keyed to stream timestamps (equal-power quarter-sine), so they
are sample accurate and need no volume ramp loop. Per-file loadfile options
reset by themselves when the next file starts.

AutoMix decodes a few seconds of audio at 8 kHz mono through mpv itself (no
ffmpeg needed, works on Windows too) and reads the loudness structure: where
the outgoing song's music really ends, how long its outro is, and where the
incoming song's silent intro stops.
"""
import os
import sys
import json
import time
import math
import array
import signal
import subprocess

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

FRAME_SEC = 0.1
ANALYSIS_RATE = 8000
SILENCE_DB = -55.0
MIN_FADE = 4.0
MAX_FADE = 12.0


def tail_title(profile_suffix):
    return f"nutsty-xftail{profile_suffix}"


def tail_target(profile_suffix):
    return pc.get_mpv_ipc_target(profile_suffix + "_xf")


def _pid_file(temp_dir, profile_suffix):
    return os.path.join(temp_dir, f"nutsty_xf_tail{profile_suffix}.pid")


def ipc_call(ipc_type, target, command, timeout=1.0):
    """Send one JSON IPC command and return its reply, skipping broadcast events."""
    s = None
    try:
        s = pc.connect_mpv_socket(ipc_type, target, timeout=timeout)
        s.sendall((json.dumps({"command": command, "request_id": 7}) + "\n").encode("utf-8"))
        buf = ""
        deadline = time.time() + timeout
        while time.time() < deadline:
            data = s.recv(65536)
            if not data:
                break
            buf += data.decode("utf-8", errors="ignore")
            while "\n" in buf:
                line, buf = buf.split("\n", 1)
                if not line.strip():
                    continue
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if obj.get("request_id") == 7:
                    return obj
        return {"error": "timeout"}
    except Exception as e:
        return {"error": str(e)}
    finally:
        if s is not None:
            try:
                s.close()
            except Exception:
                pass


def ipc_get(ipc_type, target, prop, timeout=0.6):
    res = ipc_call(ipc_type, target, ["get_property", prop], timeout=timeout)
    return res.get("data") if res.get("error") == "success" else None


def kill_tail(temp_dir, profile_suffix):
    """Stop the tail mpv if one is alive (safe to call any time)."""
    ipc_type, target = tail_target(profile_suffix)
    pid_path = _pid_file(temp_dir, profile_suffix)
    if not os.path.exists(pid_path):
        return
    ipc_call(ipc_type, target, ["quit"], timeout=0.3)
    pid = 0
    try:
        with open(pid_path, "r", encoding="utf-8") as f:
            pid = int(f.read().strip() or "0")
    except Exception:
        pid = 0
    if pid > 0:
        try:
            if pc.IS_WINDOWS:
                subprocess.run(["taskkill", "/F", "/PID", str(pid)], capture_output=True, timeout=2,
                               creationflags=0x08000000)
            else:
                os.kill(pid, signal.SIGTERM)
        except Exception:
            pass
    try:
        os.remove(pid_path)
    except Exception:
        pass
    if ipc_type == "unix" and os.path.exists(target):
        try:
            os.remove(target)
        except Exception:
            pass


def spawn_tail(temp_dir, profile_suffix, stream_args, volume=100.0, mute=False):
    """Start a paused, idle tail mpv on its own IPC endpoint. Returns True once it answers."""
    kill_tail(temp_dir, profile_suffix)
    ipc_type, target = tail_target(profile_suffix)
    if ipc_type == "unix" and os.path.exists(target):
        try:
            os.remove(target)
        except Exception:
            pass
    cmd = [
        pc.get_binary_path("mpv"),
        "--no-config",
        "--idle=yes",
        "--pause=yes",
        "--no-video",
        "--no-terminal",
        "--force-window=no",
        pc.get_mpv_ipc_arg(ipc_type, target),
        "--cache=yes",
        "--demuxer-readahead-secs=30",
        "--audio-buffer=0.8",
        "--network-timeout=10",
        f"--title={tail_title(profile_suffix)}",
        "--audio-client-name=Nutsty",
        f"--volume={max(0.0, min(130.0, float(volume)))}",
        f"--mute={'yes' if mute else 'no'}",
    ] + list(stream_args)
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                **pc.get_daemon_popen_kwargs())
    except Exception as e:
        sys.stderr.write(f"[crossfade] could not start tail mpv: {e}\n")
        return False
    try:
        with open(_pid_file(temp_dir, profile_suffix), "w", encoding="utf-8") as f:
            f.write(str(proc.pid))
    except Exception:
        pass
    for _ in range(30):
        time.sleep(0.05)
        if ipc_call(ipc_type, target, ["get_property", "idle-active"], timeout=0.3).get("error") == "success":
            return True
    kill_tail(temp_dir, profile_suffix)
    return False


def fade_filter(kind, start, duration):
    """Equal-power fade: qsin in, its mirror out (sin/cos of the same quarter turn)."""
    return f"lavfi=[afade=t={kind}:st={start:.3f}:d={duration:.3f}:curve=qsin]"


def loadfile_with_options(ipc_type, target, url, options):
    return ipc_call(ipc_type, target, {
        "name": "loadfile", "url": url, "flags": "replace", "index": -1,
        "options": {k: str(v) for k, v in options.items()},
    }, timeout=1.5)


# --------------------------------------------------------------------------
# Loudness analysis (AutoMix)
# --------------------------------------------------------------------------

def decode_levels(url, start, length, stream_args, temp_dir, tag="a"):
    """Decode [start, start+length] to 8 kHz mono and return per-100 ms levels in dBFS."""
    if not url or length <= 0.5:
        return []
    out_path = os.path.join(temp_dir, f"nutsty_automix_{tag}_{os.getpid()}.raw")
    cmd = [
        pc.get_binary_path("mpv"),
        "--no-config", "--no-video", "--really-quiet", "--untimed",
        "--ao=pcm", f"--ao-pcm-file={out_path}", "--ao-pcm-waveheader=no",
        "--audio-format=s16", f"--audio-samplerate={ANALYSIS_RATE}", "--audio-channels=mono",
        f"--start={max(0.0, start):.2f}", f"--length={length:.2f}",
        "--network-timeout=8",
    ] + list(stream_args) + [url]
    try:
        kwargs = pc.get_daemon_popen_kwargs()
        kwargs.pop("start_new_session", None)
        subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20, **kwargs)
        with open(out_path, "rb") as f:
            raw = f.read()
    except Exception as e:
        sys.stderr.write(f"[automix] decode failed: {e}\n")
        return []
    finally:
        try:
            os.remove(out_path)
        except Exception:
            pass
    samples = array.array("h")
    samples.frombytes(raw[: len(raw) - (len(raw) % 2)])
    step = int(ANALYSIS_RATE * FRAME_SEC)
    levels = []
    for i in range(0, len(samples) - step + 1, step):
        seg = samples[i:i + step]
        acc = 0
        for x in seg:
            acc += x * x
        rms = math.sqrt(acc / step)
        levels.append(20.0 * math.log10(max(rms, 1.0) / 32768.0))
    # Light smoothing so single drum hits or gaps don't decide the window
    if len(levels) >= 3:
        levels = [levels[0]] + [(levels[i - 1] + levels[i] + levels[i + 1]) / 3.0
                                for i in range(1, len(levels) - 1)] + [levels[-1]]
    return levels


def _median(values):
    vals = sorted(values)
    n = len(vals)
    if n == 0:
        return SILENCE_DB
    return vals[n // 2] if n % 2 else 0.5 * (vals[n // 2 - 1] + vals[n // 2])


def build_plan(out_levels, out_window_start, out_duration, in_levels, base_seconds):
    """Pick the crossfade window from loudness structure.

    - music end: last moment within 10 dB of the song's typical level
      (everything after is fade-out tail or silence, so the blend ends there)
    - outro length: from the last full-energy moment (within 3 dB) to music end;
      an abrupt ending gets a short blend, a long fade-out a long one
    - incoming start: skip a silent or near-silent intro
    """
    base = max(MIN_FADE, min(MAX_FADE, float(base_seconds or 6.0)))
    plan = {"ok": True, "fade_at": max(0.0, out_duration - base), "duration": base,
            "in_start": 0.0, "music_end": out_duration, "analysed": False}

    audible = [x for x in out_levels if x > SILENCE_DB]
    if len(audible) >= 30:
        med = _median(audible)
        music_idx = max((i for i, x in enumerate(out_levels) if x >= med - 10.0), default=-1)
        energy_idx = max((i for i, x in enumerate(out_levels) if x >= med - 3.0), default=-1)
        if music_idx >= 0:
            music_end = out_window_start + (music_idx + 1) * FRAME_SEC
            energy_end = out_window_start + (energy_idx + 1) * FRAME_SEC if energy_idx >= 0 else music_end
            outro = max(0.0, music_end - energy_end)
            dur = max(MIN_FADE + 1.0, min(MAX_FADE, outro + 2.0))
            window_end = min(out_duration - 0.25, music_end + 0.6)
            fade_at = max(out_window_start, window_end - dur)
            dur = max(MIN_FADE, min(dur, out_duration - 0.25 - fade_at))
            plan.update({"fade_at": round(fade_at, 2), "duration": round(dur, 2),
                         "music_end": round(music_end, 2), "analysed": True})

    audible_in = [x for x in in_levels if x > SILENCE_DB]
    if len(audible_in) >= 10:
        med_in = _median(audible_in)
        first = next((i for i, x in enumerate(in_levels) if x >= med_in - 20.0), 0)
        intro = first * FRAME_SEC - 0.15
        plan["in_start"] = round(intro, 2) if 0.4 <= intro <= 10.0 else 0.0
    return plan
