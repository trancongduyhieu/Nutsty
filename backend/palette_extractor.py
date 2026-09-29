#!/usr/bin/env python3
from __future__ import annotations
"""
Nutsty - Intelligent Adaptive Wallpaper Palette & Luminance Inversion Engine
Analyzes the desktop wallpaper and local lyric region (x: 14%..52%, y: 69%..77%).
Detects light vs dark background contrast, extracts harmonic highlight colors,
and outputs dynamic styling parameters to ~/.config/noctalia/nutsty_palette.json.
"""

import sys
import os
import json
import re
import math
import colorsys
from pathlib import Path
from typing import Any

try:
    from . import platform_compat as pc
except (ImportError, ValueError):
    import platform_compat as pc

try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False
    Image = None

def get_current_wallpaper() -> Path:
    # 1. Check CLI argument
    if len(sys.argv) > 1 and sys.argv[1].strip():
        candidate = Path(os.path.expanduser(sys.argv[1].strip()))
        if candidate.exists():
            return candidate

    # 1b. Windows native wallpaper detection
    if sys.platform == "win32" or pc.IS_WINDOWS:
        try:
            import ctypes
            buf = ctypes.create_unicode_buffer(512)
            if ctypes.windll.user32.SystemParametersInfoW(0x0073, 512, buf, 0) and buf.value:
                p = Path(buf.value)
                if p.exists():
                    return p
        except Exception:
            pass
        try:
            import winreg
            key = winreg.OpenKey(winreg.HKEY_CURRENT_USER, r"Control Panel\Desktop")
            val, _ = winreg.QueryValueEx(key, "Wallpaper")
            if val and Path(val).exists():
                return Path(val)
        except Exception:
            pass
        appdata = os.environ.get("APPDATA", "")
        if appdata:
            tw = Path(appdata) / "Microsoft" / "Windows" / "Themes" / "TranscodedWallpaper"
            if tw.exists():
                return tw

    home = Path.home()

    # 2. Check theme_hook.log for most recent wallpaper change
    theme_log = home / "theme_hook.log"
    if theme_log.exists():
        try:
            lines = theme_log.read_text(encoding="utf-8", errors="ignore").splitlines()
            for line in reversed(lines):
                match = re.search(r"Wallpaper changed to (.*?) on", line)
                if match:
                    p = Path(match.group(1).strip())
                    if p.exists():
                        return p
        except Exception:
            pass

    # 3. Check noctalia settings.json
    settings_file = home / ".config" / "noctalia" / "settings.json"
    if settings_file.exists():
        try:
            data = json.loads(settings_file.read_text(encoding="utf-8"))
            wp_list = data.get("wallpaper", {}).get("monitors", [])
            for m in wp_list:
                p_str = m.get("path", "")
                if p_str:
                    p = Path(os.path.expanduser(p_str))
                    if p.exists():
                        return p
        except Exception:
            pass

    # 4. Check wallbash thumb
    thumb = Path("/tmp/noctalia_wallbash/thumb.png")
    if thumb.exists():
        return thumb

    return Path.home() / "Pictures" / "Wallpapers" / "wallhaven_k8d276.jpg"

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def linear_to_srgb(c):
    c = max(0.0, min(1.0, c))
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1.0 / 2.4)) - 0.055

def rgb_to_oklab(r, g, b):
    lr = srgb_to_linear(r / 255.0)
    lg = srgb_to_linear(g / 255.0)
    lb = srgb_to_linear(b / 255.0)
    l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb) ** (1/3)
    m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb) ** (1/3)
    s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb) ** (1/3)
    L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
    a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
    b_val = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
    C = math.sqrt(a * a + b_val * b_val)
    h = math.atan2(b_val, a)
    return L, a, b_val, C, h

def oklch_to_hex(L, C, h):
    a = C * math.cos(h)
    b_val = C * math.sin(h)
    l = (L + 0.3963377774 * a + 0.2158037573 * b_val) ** 3
    m = (L - 0.1055613458 * a - 0.0638541728 * b_val) ** 3
    s = (L - 0.0894841775 * a - 1.2914855480 * b_val) ** 3
    lr = +4.0767434721 * l - 3.3077115913 * m + 0.2309699292 * s
    lg = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    lb = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    r = int(round(linear_to_srgb(lr) * 255))
    g = int(round(linear_to_srgb(lg) * 255))
    b = int(round(linear_to_srgb(lb) * 255))
    return f"#{r:02x}{g:02x}{b:02x}"

def kmeans_oklab(points, k=5, iters=8):
    if len(points) <= k:
        return points
    # Deterministic farthest-point seeding
    centroids = [points[0]]
    while len(centroids) < k:
        best_pt, max_d = points[0], -1
        for p in points[::6]:
            d = min((p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2 for c in centroids)
            if d > max_d:
                max_d = d
                best_pt = p
        centroids.append(best_pt)

    for _ in range(iters):
        clusters = [[] for _ in range(k)]
        for p in points:
            best_idx, best_dist = 0, 999999
            for i, c in enumerate(centroids):
                d = (p[0]-c[0])**2 + (p[1]-c[1])**2 + (p[2]-c[2])**2
                if d < best_dist:
                    best_dist = d
                    best_idx = i
            clusters[best_idx].append(p)
        new_centroids = []
        for i in range(k):
            if not clusters[i]:
                new_centroids.append(centroids[i])
            else:
                L = sum(p[0] for p in clusters[i]) / len(clusters[i])
                a = sum(p[1] for p in clusters[i]) / len(clusters[i])
                b = sum(p[2] for p in clusters[i]) / len(clusters[i])
                new_centroids.append((L, a, b, len(clusters[i])))
        centroids = [(c[0], c[1], c[2]) for c in new_centroids]
    return new_centroids

def get_theme_name_from_deg(deg):
    deg = deg % 360
    if 330 <= deg or deg < 38:
        return "crimson"
    elif 38 <= deg < 75:
        return "gold"
    elif 75 <= deg < 170:
        return "emerald"
    elif 170 <= deg < 260:
        return "sapphire"
    else:
        return "amethyst"

def analyze_crop(img: Any, box_norm=(0.14, 0.69, 0.52, 0.77)):
    """Analyze mean luminance and bright pixel ratio of lyric region."""
    if not HAS_PIL or img is None:
        return 0.3, 0.0, False
    w, h = img.size
    x1, y1 = int(box_norm[0] * w), int(box_norm[1] * h)
    x2, y2 = int(box_norm[2] * w), int(box_norm[3] * h)

    crop = img.crop((max(0, x1), max(0, y1), min(w, x2), min(h, y2))).convert("RGB")
    crop_small = crop.resize((48, 24))
    pixels = [crop_small.getpixel((x, y)) for y in range(crop_small.height) for x in range(crop_small.width)]
    if not pixels:
        return 0.3, 0.0, False

    lums = [(0.299 * r + 0.587 * g + 0.114 * b) / 255.0 for r, g, b in pixels]
    mean_lum = sum(lums) / len(lums)
    bright_ratio = sum(1 for l in lums if l > 0.55) / len(lums)
    is_light = (mean_lum > 0.45) or (bright_ratio > 0.20)

    return round(mean_lum, 3), round(bright_ratio, 3), is_light

def extract_adaptive_palette(img: Any, is_light: bool):
    """
    Extract aesthetic, readable colors based on OKLAB Chromatic Salience Clustering,
    and OKLCH Jewel Tone normalization with universal cinematic dark drop shadows.
    """
    if not HAS_PIL or img is None:
        return {
            "isLightArea": False,
            "theme": "crimson",
            "baseTextColor": "#f8fafc",
            "highlightColor": "#f4afb3",
            "deadTextColor": "rgba(248, 250, 252, 0.45)",
            "shadowDirectional": "rgba(0, 0, 0, 0.70)",
            "shadowAmbient": "rgba(0, 0, 0, 0.45)"
        }
    thumb = img.resize((96, 96)).convert("RGB")
    pixels = [thumb.getpixel((x, y)) for y in range(thumb.height) for x in range(thumb.width)]
    ok_all = [rgb_to_oklab(r, g, b) for r, g, b in pixels]

    # Pre-filter pixels with noticeable artistic color (Chroma >= 0.028)
    chroma_pixels = [p[:3] for p in ok_all if p[3] >= 0.028]
    chroma_ratio = len(chroma_pixels) / len(pixels)

    if chroma_ratio >= 0.05:
        # Cluster chromatic pixels into 4 distinct artistic hue candidates
        clusters = kmeans_oklab(chroma_pixels, k=4, iters=8)
        # Select best cluster by Visual Salience: count^0.35 * C
        best = max(clusters, key=lambda c: (c[3] ** 0.35) * math.sqrt(c[1]**2 + c[2]**2))
        best_c = math.sqrt(best[1]**2 + best[2]**2)
        best_h = math.atan2(best[2], best[1])
        best_deg = math.degrees(best_h) % 360
        top_theme = get_theme_name_from_deg(best_deg)

        # Calibrate to Luminous Jewel Tone (L=0.82, C in [0.08, 0.12])
        norm_c = min(0.12, max(0.08, best_c * 1.4))
        hl_color = oklch_to_hex(0.82, norm_c, best_h)
    else:
        # Pure monochrome/pencil sketch without color:
        # Fallback to timeless, luxurious Vintage Champagne Gold
        top_theme = "warm_classic"
        hl_color = "#deb06c"

    # Universal High-End Cinematic Typography (Pure white base + custom jewel highlight + deep dark shadows)
    # Eliminates cheap/blurry white halos completely across all wallpapers
    base_text = "#f8fafc"       # Crisp Pure White
    dead_text = "#f1f5f9"       # Pristine Soft White for graceful exit fade
    shadow_dir = "#a6020305"    # Sharp dark drop shadow (contrast on all backgrounds)
    shadow_amb = "#66000000"    # Deep ambient diffuse shadow

    return {
        "theme": top_theme,
        "isLightArea": is_light,
        "baseTextColor": base_text,
        "highlightColor": hl_color,
        "deadTextColor": dead_text,
        "shadowDirectional": shadow_dir,
        "shadowAmbient": shadow_amb
    }

def main():
    wp_path = get_current_wallpaper()
    if not wp_path or not wp_path.exists():
        wp_path = Path.home() / "Pictures" / "Wallpapers" / "wallhaven_k8d276.jpg"

    print(f"Analyzing wallpaper: {wp_path}")

    # Handle video files if needed
    img_to_open = wp_path
    if wp_path.suffix.lower() in [".mp4", ".webm", ".mkv", ".gif"]:
        thumb = Path("/tmp/noctalia_wallbash/thumb.png")
        if thumb.exists():
            img_to_open = thumb
        else:
            os.system(f'magick "{wp_path}[0]" /tmp/noctalia_wallbash_frame.png')
            img_to_open = Path("/tmp/noctalia_wallbash_frame.png")

    if not HAS_PIL:
        result = {
            "wallpaper": str(wp_path or ""),
            "meanLuminance": 0.2,
            "brightRatio": 0.0,
            "isLightArea": False,
            "theme": "crimson",
            "baseTextColor": "#f8fafc",
            "highlightColor": "#f4afb3",
            "deadTextColor": "rgba(248, 250, 252, 0.45)",
            "shadowDirectional": "rgba(0, 0, 0, 0.70)",
            "shadowAmbient": "rgba(0, 0, 0, 0.45)"
        }
        out_file = Path(pc.get_config_dir()) / "nutsty_palette.json"
        out_file.parent.mkdir(parents=True, exist_ok=True)
        out_file.write_text(json.dumps(result, indent=2), encoding="utf-8")
        if not pc.IS_WINDOWS:
            legacy_out = Path.home() / ".config" / "noctalia" / "frostify_palette.json"
            legacy_out.write_text(json.dumps(result, indent=2), encoding="utf-8")
        print(f"Fallback palette generated at {out_file}")
        print(json.dumps(result, indent=2))
        return

    try:
        img = Image.open(img_to_open).convert("RGB")
    except Exception as e:
        print(f"Error opening image {img_to_open}: {e}", file=sys.stderr)
        sys.exit(1)

    mean_lum, bright_ratio, is_light = analyze_crop(img, (0.14, 0.69, 0.52, 0.77))
    palette_info = extract_adaptive_palette(img, is_light)

    wp_str = str(wp_path).replace("\\", "/")
    result = {
        "wallpaper": wp_str,
        "meanLuminance": mean_lum,
        "brightRatio": bright_ratio,
        "isLightArea": palette_info["isLightArea"],
        "theme": palette_info["theme"],
        "baseTextColor": palette_info["baseTextColor"],
        "highlightColor": palette_info["highlightColor"],
        "deadTextColor": palette_info["deadTextColor"],
        "shadowDirectional": palette_info["shadowDirectional"],
        "shadowAmbient": palette_info["shadowAmbient"]
    }

    out_file = Path(pc.get_config_dir()) / "nutsty_palette.json"
    out_file.parent.mkdir(parents=True, exist_ok=True)
    out_file.write_text(json.dumps(result, indent=2), encoding="utf-8")

    # Always ensure ~/.config/noctalia/nutsty_palette.json is updated on all platforms for QML FileView
    noctalia_out = Path.home() / ".config" / "noctalia" / "nutsty_palette.json"
    noctalia_out.parent.mkdir(parents=True, exist_ok=True)
    noctalia_out.write_text(json.dumps(result, indent=2), encoding="utf-8")

    if not pc.IS_WINDOWS:
        legacy_out = Path.home() / ".config" / "noctalia" / "frostify_palette.json"
        legacy_out.write_text(json.dumps(result, indent=2), encoding="utf-8")

    local_out = Path(__file__).resolve().parent.parent / "assets" / "nutsty_palette.json"
    local_out.parent.mkdir(parents=True, exist_ok=True)
    local_out.write_text(json.dumps(result, indent=2), encoding="utf-8")

    print(f"Successfully generated palette at {out_file}")
    print(json.dumps(result, indent=2))

SONG_PALETTES_CACHE = Path(pc.get_cache_dir()) / "song_palettes.json"

def extract_song_palette(img_src: str) -> dict:
    default_res = {"highlightColor": "", "theme": "default"}
    if not HAS_PIL or not img_src or not str(img_src).strip():
        return default_res

    clean_src = str(img_src).strip()
    cache_key = clean_src

    try:
        if SONG_PALETTES_CACHE.exists():
            data = json.loads(SONG_PALETTES_CACHE.read_text(encoding="utf-8"))
            if cache_key in data:
                return data[cache_key]
    except Exception:
        pass

    try:
        if clean_src.startswith("http://") or clean_src.startswith("https://"):
            import urllib.request
            import io
            req = urllib.request.Request(clean_src, headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
                "Accept": "image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8"
            })
            with urllib.request.urlopen(req, timeout=6, context=pc.get_ssl_context()) as resp:
                content = resp.read()
            img = Image.open(io.BytesIO(content))
        else:
            path_str = clean_src.replace("file:///", "").replace("file://", "")
            p = Path(os.path.expanduser(path_str))
            if not p.exists():
                return default_res
            img = Image.open(p)

        pal = extract_adaptive_palette(img, is_light=False)
        res = {
            "highlightColor": pal["highlightColor"],
            "theme": pal["theme"],
            "baseTextColor": pal.get("baseTextColor", "#f8fafc")
        }

        try:
            SONG_PALETTES_CACHE.parent.mkdir(parents=True, exist_ok=True)
            existing = {}
            if SONG_PALETTES_CACHE.exists():
                try:
                    existing = json.loads(SONG_PALETTES_CACHE.read_text(encoding="utf-8"))
                except Exception:
                    existing = {}
            existing[cache_key] = res
            if len(existing) > 500:
                # Keep cache bounded
                existing = dict(list(existing.items())[-400:])
            SONG_PALETTES_CACHE.write_text(json.dumps(existing, indent=2), encoding="utf-8")
        except Exception:
            pass

        return res
    except Exception as e:
        sys.stderr.write(f"[extract_song_palette error]: {e}\n")
        return default_res

def handle_cli(args=None):
    if args is None:
        args = sys.argv[1:]
    if args and args[0] == "song_palette":
        src = args[1] if len(args) > 1 else ""
        res = extract_song_palette(src)
        print(json.dumps(res, ensure_ascii=False))
        return res
    return main()

if __name__ == "__main__":
    handle_cli()
