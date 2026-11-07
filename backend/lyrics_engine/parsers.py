#!/usr/bin/env python3
"""
Lyrics Engine — Parsers for LRC, Rich-Sync Syllables, and TTML Apple Music.
"""

from __future__ import annotations
import re
import html
from typing import List, Dict, Any, Optional


def clean_vocal_markers(text: str) -> str:
    if not text:
        return ""
    # Strip voice/vocal prefixes like "v1: ", "v2: ", "bgv: ", "[v1] ", "(v1) ", "vocal 1: ", "[vocal 2]"
    t = re.sub(r'^(?:v\d+|bgv|bg|vocal\s*\d*)\s*:\s*', '', text, flags=re.IGNORECASE)
    t = re.sub(r'^[\[\(](?:v\d+|bgv|bg|vocal\s*\d*)[\]\)]\s*:?\s*', '', t, flags=re.IGNORECASE)
    return t.strip()


def strip_rich_sync_tags(text: str) -> str:
    if not text:
        return ""
    # Removing tags directly preserves spaces between words without creating artificial spaces between syllables:
    # e.g. <00:27.124>real<00:27.522>i<00:28.572>zed -> realized
    # e.g. <00:01.00>Hello <00:02.00>world -> Hello world
    t = re.sub(r'<[0-9:.]+>', '', text)
    t = html.unescape(t)
    t = re.sub(r'\s+', ' ', t).strip()
    return clean_vocal_markers(t)


def parse_rich_sync_words(line_str: str, default_start: float = 0.0) -> List[Dict[str, Any]]:
    """Parse <mm:ss.xx> word timestamps embedded in a LRC line."""
    if not line_str or "<" not in line_str or ">" not in line_str:
        return []
    pattern = re.compile(r'<(\d{1,2}):(\d{1,2}(?:\.\d+)?)>([^<]*)')
    matches = list(pattern.finditer(line_str))
    if not matches:
        return []
    words = []
    for i, m in enumerate(matches):
        mins, secs = int(m.group(1)), float(m.group(2))
        start_t = round(mins * 60.0 + secs, 3)
        raw_val = m.group(3)
        has_space = raw_val.endswith(" ") or raw_val.endswith("\t")
        txt = clean_vocal_markers(html.unescape(raw_val.strip()))
        if not txt:
            continue
        if i + 1 < len(matches):
            nm = matches[i + 1]
            end_t = round(int(nm.group(1)) * 60.0 + float(nm.group(2)), 3)
        else:
            end_t = round(start_t + 0.5, 3)
        dur = max(0.08, round(end_t - start_t, 3))
        words.append({
            "text": txt,
            "start": start_t,
            "end": end_t,
            "duration": dur,
            "hasSpace": has_space,
            "isHeld": dur >= 0.85,
        })
    return words


def parse_lrc(lrc_text: str) -> List[Dict[str, Any]]:
    """Parse LRC text -> list of lyric line dicts.
    Lines with <mm:ss.xx> tags get hasWords=True (real syllable data).
    Plain lines get hasWords=False + isSynthetic=True -> Full-Line Highlight in QML.
    """
    if not lrc_text:
        return []
    results = []
    time_regex = re.compile(r'\[(\d{1,2}):(\d{1,2}(?:\.\d+)?)\]')

    source_match = re.search(r'\[(?:source|re):([^\]]+)\]', lrc_text, re.IGNORECASE)
    lrc_source = source_match.group(1).strip() if source_match else None

    for line in lrc_text.splitlines():
        line = line.strip()
        if not line:
            continue
        if re.match(r'^\[[a-zA-Z]+:', line):
            continue
        matches = list(time_regex.finditer(line))
        if not matches:
            continue
        last_match = matches[-1]
        raw_text = line[last_match.end():].strip()
        agent = None
        is_bg = False
        m_agent = re.search(r'\{agent:([^}]+)\}', raw_text)
        if m_agent:
            agent = m_agent.group(1).strip()
            raw_text = re.sub(r'\{agent:[^}]+\}', '', raw_text).strip()
        if "{bg}" in raw_text:
            is_bg = True
            raw_text = raw_text.replace("{bg}", "").strip()

        clean_text = strip_rich_sync_tags(raw_text)
        if not clean_text or clean_text in ("♪", "♫", "🎵"):
            continue
        syllable_words = parse_rich_sync_words(raw_text)
        for m in matches:
            mins, secs = int(m.group(1)), float(m.group(2))
            total_sec = round(mins * 60.0 + secs, 3)
            end_sec = max((w["end"] for w in syllable_words), default=None)
            item = {
                "time": total_sec,
                "endTime": end_sec if end_sec is not None else round(total_sec + 4.5, 3),
                "text": clean_text,
                "hasWords": bool(syllable_words),
                "isSynthetic": not bool(syllable_words),
                "words": syllable_words,
            }
            if agent:
                item["agent"] = agent
            if is_bg:
                item["isBackground"] = True
            if lrc_source:
                item["source"] = lrc_source
            results.append(item)
    results.sort(key=lambda x: x["time"])

    # Fill in endTime for lines without syllable timestamps
    for i, it in enumerate(results):
        if not it.get("hasWords"):
            if i + 1 < len(results):
                it["endTime"] = results[i + 1]["time"]
            else:
                it["endTime"] = round(it["time"] + 5.0, 3)
    return results


def parse_ttml_time(t: str) -> float:
    """Parse TTML time '1:23.456' or '83.456' -> float seconds."""
    t = t.strip()
    parts = t.split(":")
    if len(parts) == 3:
        h, m, s = parts
        return int(h) * 3600 + int(m) * 60 + float(s)
    elif len(parts) == 2:
        m, s = parts
        return int(m) * 60 + float(s)
    else:
        try:
            return float(t.replace("s", ""))
        except ValueError:
            return 0.0


def parse_ttml_body(ttml_text: str) -> List[Dict[str, Any]]:
    """Parse TTML XML string -> list of word-level synced line dicts."""
    if not ttml_text:
        return []
    lines = []
    p_pattern = re.compile(r'<p\s+([^>]*?)>(.*?)</p>', re.DOTALL)
    span_pattern = re.compile(r'<span\s+begin="([^"]+)"\s+end="([^"]+)"[^>]*>([^<]+)</span>')

    for p_match in p_pattern.finditer(ttml_text):
        attrs = p_match.group(1)
        inner = p_match.group(2)

        begin_m = re.search(r'begin="([^"]+)"', attrs)
        end_m = re.search(r'end="([^"]+)"', attrs)
        if not begin_m or not end_m:
            continue

        line_begin = parse_ttml_time(begin_m.group(1))
        line_end = parse_ttml_time(end_m.group(1))

        agent_m = re.search(r'(?:ttm:)?agent="([^"]+)"', attrs)
        agent = agent_m.group(1) if agent_m else None
        is_bg = bool(re.search(r'(?:ttm:)?role="x-bg"', attrs))

        spans = list(span_pattern.finditer(inner))
        words = []
        for i, sm in enumerate(spans):
            wb = parse_ttml_time(sm.group(1))
            we = parse_ttml_time(sm.group(2))
            raw_span = sm.group(3)
            trailing = inner[sm.end():spans[i + 1].start()] if i + 1 < len(spans) else ""
            has_space = raw_span.endswith(" ") or raw_span.endswith("\t") or bool(re.search(r'\s', trailing))
            raw_wtxt = clean_vocal_markers(html.unescape(raw_span).strip())
            if not raw_wtxt:
                continue
            dur = max(0.08, round(we - wb, 3))
            words.append({
                "text": raw_wtxt,
                "start": round(wb, 3),
                "end": round(we, 3),
                "duration": dur,
                "hasSpace": has_space,
                "isHeld": dur >= 0.85,
            })

        plain_text = clean_vocal_markers(html.unescape(re.sub(r'<[^>]+>', '', inner)).strip())
        if not plain_text or plain_text in ("♪", "♫", "🎵"):
            continue

        line_dict: Dict[str, Any] = {
            "time": round(line_begin, 3),
            "endTime": round(line_end, 3),
            "text": plain_text,
            "hasWords": bool(words),
            "isSynthetic": not bool(words),
            "words": words,
        }
        if agent:
            line_dict["agent"] = agent
        if is_bg:
            line_dict["isBackground"] = True

        lines.append(line_dict)

    lines.sort(key=lambda x: x["time"])
    return lines
