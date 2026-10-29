#!/usr/bin/env python3
"""
Base Lyrics Provider Protocol.
"""

from abc import ABC, abstractmethod
from typing import List, Dict, Any, Optional


class BaseLyricsProvider(ABC):
    @property
    @abstractmethod
    def name(self) -> str:
        """Provider identifier (e.g. 'spotify', 'betterlyrics', 'lrclib', 'netease', 'local')."""
        pass

    @abstractmethod
    def fetch_lyrics(
        self,
        title: str,
        artist: Optional[str] = None,
        duration_sec: Optional[float] = None,
        **kwargs
    ) -> Optional[List[Dict[str, Any]]]:
        """Fetch and return list of synced lyric line dicts, or None if not found/failed."""
        pass
