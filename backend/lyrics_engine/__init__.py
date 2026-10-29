#!/usr/bin/env python3
"""
Nutsty Lyrics Engine — Modular 7-Tier Synced Lyrics & Rich Syllables System.
"""

from .parsers import (
    clean_vocal_markers,
    strip_rich_sync_tags,
    parse_rich_sync_words,
    parse_lrc,
    parse_ttml_time,
    parse_ttml_body
)
from .base_provider import BaseLyricsProvider

__all__ = [
    "clean_vocal_markers",
    "strip_rich_sync_tags",
    "parse_rich_sync_words",
    "parse_lrc",
    "parse_ttml_time",
    "parse_ttml_body",
    "BaseLyricsProvider",
]
