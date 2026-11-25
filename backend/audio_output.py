"""What the listener really hears: the quality label data and the rate the sound card runs at.
Pure helpers, no mpv access, so tests feed them plain dicts."""
import glob
import os
import re
from pathlib import Path

LOSSLESS_CODECS = ("flac", "alac", "wavpack", "ape", "tta", "truehd", "mlp")


def read_alsa_running_rate(proc_root="/proc/asound"):
    """Rate of the first playback stream in state RUNNING, or None. Linux only."""
    for status_path in sorted(glob.glob(os.path.join(proc_root, "card*", "pcm*p", "sub*", "status"))):
        try:
            with open(status_path, "r", encoding="utf-8", errors="replace") as f:
                if "RUNNING" not in f.read():
                    continue
            with open(os.path.join(os.path.dirname(status_path), "hw_params"), "r", encoding="utf-8", errors="replace") as f:
                m = re.search(r"^rate:\s*(\d+)", f.read(), re.MULTILINE)
            if m:
                return int(m.group(1))
        except OSError:
            continue
    return None


def is_lossless_codec(codec):
    c = (codec or "").lower()
    return c in LOSSLESS_CODECS or c.startswith("pcm")


def _bit_depth_from_format(fmt, lossless):
    f = (fmt or "").lower()
    if f.startswith("s16"):
        return 16
    if lossless and (f.startswith("s24") or f.startswith("s32")):
        return 24
    return None


def _source_of(path, now_source):
    tidal = (now_source or {}).get("tidal") or {}
    if path and (now_source or {}).get("source") == "tidal" and tidal.get("url") == path:
        return "tidal"
    if not path:
        return ""
    lower = path.lower()
    if lower.startswith(("http://", "https://", "ytdl://", "edl://")):
        return "youtube"
    return "local"


def _rate_str(rate):
    return f"{rate / 1000:g} kHz" if rate else ""


def _channels_str(n):
    if not n:
        return ""
    if n == 1:
        return "Mono (1ch)"
    if n == 2:
        return "Stereo (2ch)"
    return f"{n}ch"


def build_audio_specs(props, now_source, dac_mode, suspended, is_windows, alsa_rate):
    """props: mpv properties audio-codec-name, audio-bitrate, audio-params, path.
    Unknown values stay None or "" so the UI shows a dash instead of a made-up number."""
    props = props or {}
    params = props.get("audio-params")
    params = params if isinstance(params, dict) else {}
    codec = (props.get("audio-codec-name") or "").lower()
    path = props.get("path") or ""
    lossless = is_lossless_codec(codec)
    source = _source_of(path, now_source)

    sample_rate = params.get("samplerate") or None
    channels = params.get("channel-count") or None
    bitrate = props.get("audio-bitrate") or 0
    bitrate_kbps = int(round(bitrate / 1000)) if bitrate else None

    bit_depth = None
    if source == "tidal":
        bit_depth = ((now_source or {}).get("tidal") or {}).get("bit_depth") or None
    if bit_depth is None:
        bit_depth = _bit_depth_from_format(params.get("format"), lossless)

    output_rate = None
    if not is_windows and alsa_rate and sample_rate and alsa_rate != sample_rate:
        output_rate = alsa_rate

    return {
        "source": source,
        "codec": codec.upper(),
        "bit_depth": bit_depth,
        "sample_rate": sample_rate,
        "bitrate_kbps": bitrate_kbps,
        "channels": channels,
        "lossless": lossless,
        "output_rate": output_rate,
        "via_windows_mixer": bool(is_windows and dac_mode != "exclusive"),
        "lossless_suspended": bool(suspended),
        "bitrate_str": f"{bitrate_kbps} kbps" if bitrate_kbps else "",
        "sample_rate_str": _rate_str(sample_rate),
        "channels_str": _channels_str(channels),
    }


# --- DAC output modes ------------------------------------------------------------------
RATES = [44100, 48000, 88200, 96000, 176400, 192000]
DROPIN_NAME = "90-nutsty-rates.conf"
PIPEWIRE_DROPIN = Path.home() / ".config/pipewire/pipewire.conf.d" / DROPIN_NAME
SYSTEM_PIPEWIRE = Path("/etc/pipewire")   # admin config, read only (never written)


def mpv_output_args(settings):
    """Extra mpv flags for the DAC mode, Tidal on or off. Only bit-perfect needs one."""
    s = settings or {}
    if s.get("dac_mode") == "exclusive":
        return ["--audio-exclusive=yes"]
    return []


def find_existing_allowed_rates(conf_dir):
    """(file, line) for every other PipeWire file that already sets allowed-rates: the other
    drop-ins next to ours, the user's main pipewire.conf, and the same two under /etc/pipewire."""
    conf_dir = Path(conf_dir)
    files = []
    for d in (conf_dir, SYSTEM_PIPEWIRE / "pipewire.conf.d"):
        if d.is_dir():
            files += [f for f in sorted(d.glob("*.conf")) if f.name != DROPIN_NAME]
    files += [p for p in (conf_dir.parent / "pipewire.conf", SYSTEM_PIPEWIRE / "pipewire.conf") if p.is_file()]
    found = []
    for f in files:
        try:
            for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
                if "allowed-rates" in line and not line.lstrip().startswith("#"):
                    found.append((str(f), line.strip()))
        except OSError:
            continue
    return found


def write_rate_dropin(conf_dir):
    """Let PipeWire switch to each song's rate. Never written when another file sets allowed-rates."""
    conf_dir = Path(conf_dir)
    path = conf_dir / DROPIN_NAME
    conflicts = find_existing_allowed_rates(conf_dir)
    if conflicts:
        return {"written": False, "path": str(path), "conflicts": conflicts}
    rates = " ".join(str(r) for r in RATES)
    conf_dir.mkdir(parents=True, exist_ok=True)
    path.write_text("# Written by Nutsty (lossless, original sample rate). Delete this file to undo.\n"
                    "context.properties = {\n"
                    f"    default.clock.allowed-rates = [ {rates} ]\n"
                    "}\n", encoding="utf-8")
    return {"written": True, "path": str(path), "conflicts": []}


def remove_rate_dropin(conf_dir):
    """Delete only Nutsty's own drop-in. True when a file was removed."""
    path = Path(conf_dir) / DROPIN_NAME
    try:
        path.unlink()
        return True
    except FileNotFoundError:
        return False
