"""The full-window blurred backdrops must not size their MultiEffect with anchors.fill.

An anchored, blurred MultiEffect keeps its old blur texture size after the window is maximized
and restored, so part of the backdrop renders black (playing: song art, paused: wallpaper).
Explicit width/height bindings resize the texture correctly.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TARGETS = [
    ("components/LiquidWarpBackdrop.qml", "finalAtmosphere"),
    ("shell.qml", "wallpaperAtmosphereEffect"),
]


def effect_block(text, effect_id):
    m = re.search(r"MultiEffect\s*\{\s*id:\s*" + effect_id + r"\b", text)
    if not m:
        return None
    depth, i = 0, text.index("{", m.start())
    for j in range(i, len(text)):
        depth += {"{": 1, "}": -1}.get(text[j], 0)
        if depth == 0:
            return text[i:j + 1]
    return None


def main():
    failures = []
    for rel, effect_id in TARGETS:
        block = effect_block((ROOT / rel).read_text(encoding="utf-8"), effect_id)
        if block is None:
            failures.append(f"{rel}: MultiEffect '{effect_id}' not found")
        elif re.search(r"^\s*anchors\.fill\s*:", block, re.M):
            failures.append(f"{rel}: '{effect_id}' uses anchors.fill; bind width/height instead")
        elif not (re.search(r"^\s*width\s*:", block, re.M) and re.search(r"^\s*height\s*:", block, re.M)):
            failures.append(f"{rel}: '{effect_id}' has no explicit width/height")
    for f in failures:
        print("FAIL", f)
    print("RESULT", "FAIL" if failures else "PASS")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
