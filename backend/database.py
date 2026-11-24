#!/usr/bin/env python3
"""
Nutsty Safe Data Vault & Analytics Engine (SQLite)
Manages user persistent data outside the repository codebase:
- Daily Mood Diary & Year in Pixels Mosaic
- Listening History & Analytics
- 6-Axis Music RPG Persona Radar Calculation

Safe Path Resolution:
- Linux: $XDG_DATA_HOME/nutsty/user_vault.db (~/.local/share/nutsty/user_vault.db)
- Windows: %APPDATA%/Nutsty/data/user_vault.db
- macOS: ~/Library/Application Support/Nutsty/user_vault.db
"""

import os
import hashlib
import sys
import json
import sqlite3
import platform
from pathlib import Path
from datetime import datetime, date, timedelta
from typing import Dict, Any, List, Optional, Tuple


def get_vault_db_path() -> Path:
    """Resolve the OS-standard persistent data directory to prevent data loss on app updates."""
    sys_name = platform.system()
    if sys_name == "Windows":
        app_data = os.getenv("APPDATA")
        if app_data:
            base_dir = Path(app_data) / "Nutsty" / "data"
        else:
            base_dir = Path.home() / "AppData" / "Roaming" / "Nutsty" / "data"
    elif sys_name == "Darwin":
        base_dir = Path.home() / "Library" / "Application Support" / "Nutsty"
    else:
        # Linux / Unix standard XDG
        xdg_data = os.getenv("XDG_DATA_HOME")
        if xdg_data:
            base_dir = Path(xdg_data) / "nutsty"
        else:
            base_dir = Path.home() / ".local" / "share" / "nutsty"

    base_dir.mkdir(parents=True, exist_ok=True)
    return base_dir / "user_vault.db"


def get_connection() -> sqlite3.Connection:
    """Create a thread-safe connection with WAL mode enabled for high concurrency."""
    db_path = get_vault_db_path()
    conn = sqlite3.connect(str(db_path), timeout=10.0)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA journal_mode=WAL;")
    conn.execute("PRAGMA synchronous=NORMAL;")
    conn.execute("PRAGMA foreign_keys=ON;")
    return conn


def init_db() -> None:
    """Initialize database tables idempotently."""
    conn = get_connection()
    with conn:
        conn.executescript("""
        CREATE TABLE IF NOT EXISTS mood_entries (
            entry_date TEXT PRIMARY KEY,
            mood_tag TEXT NOT NULL,
            mood_color TEXT NOT NULL,
            note TEXT,
            top_track_id TEXT,
            top_track_title TEXT,
            top_track_artist TEXT,
            top_track_cover TEXT,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS playback_events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            track_id TEXT NOT NULL,
            title TEXT NOT NULL,
            artist TEXT,
            album TEXT,
            cover_url TEXT,
            duration_ms INTEGER DEFAULT 0,
            listened_ms INTEGER DEFAULT 0,
            completion_rate REAL DEFAULT 0.0,
            genre TEXT,
            is_radio BOOLEAN DEFAULT 0,
            is_deep_cut BOOLEAN DEFAULT 0,
            timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );

        CREATE INDEX IF NOT EXISTS idx_playback_timestamp ON playback_events(timestamp);
        CREATE INDEX IF NOT EXISTS idx_playback_track_id ON playback_events(track_id);
        CREATE INDEX IF NOT EXISTS idx_playback_artist ON playback_events(artist);

        CREATE TABLE IF NOT EXISTS user_stats_cache (
            period_key TEXT PRIMARY KEY,
            stats_json TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        );
        """)
        # One row per play instance (QML sends the same play_id again as listening goes on)
        cols = {r["name"] for r in conn.execute("PRAGMA table_info(playback_events);")}
        if "play_id" not in cols:
            conn.execute("ALTER TABLE playback_events ADD COLUMN play_id TEXT;")
        conn.execute("CREATE UNIQUE INDEX IF NOT EXISTS idx_playback_play_id ON playback_events(play_id);")
        # Account sync: 0 = this device has a change the cloud has not got yet
        if "synced" not in cols:
            conn.execute("ALTER TABLE playback_events ADD COLUMN synced INTEGER NOT NULL DEFAULT 0;")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_playback_synced ON playback_events(synced);")
    conn.close()


# ---------------------------------------------------------------------------
# 1. MOOD DIARY OPERATIONS
# ---------------------------------------------------------------------------

DEFAULT_MOOD_PALETTE = {
    "peaceful": {"name_vi": "Bình yên", "name_en": "Peaceful", "color": "#10b981"},  # Emerald
    "melancholy": {"name_vi": "Trầm lắng", "name_en": "Melancholy", "color": "#3b82f6"},  # Blue
    "energetic": {"name_vi": "Nhiệt huyết", "name_en": "Energetic", "color": "#f97316"},  # Orange
    "dreamy": {"name_vi": "Thơ mộng", "name_en": "Dreamy", "color": "#a855f7"},  # Lavender
    "inspired": {"name_vi": "Cảm hứng", "name_en": "Inspired", "color": "#eab308"},  # Gold
}

def record_daily_mood(entry_date: str, mood_tag: str, mood_color: str,
                      note: Optional[str] = None,
                      top_track: Optional[Dict[str, Any]] = None) -> bool:
    """Save or update today's mood entry."""
    conn = get_connection()
    t_id = top_track.get("id", "") if top_track else ""
    t_title = top_track.get("title", "") if top_track else ""
    t_artist = top_track.get("artist", "") if top_track else ""
    t_cover = top_track.get("image", "") or top_track.get("cover", "") if top_track else ""

    with conn:
        conn.execute("""
        INSERT INTO mood_entries (
            entry_date, mood_tag, mood_color, note,
            top_track_id, top_track_title, top_track_artist, top_track_cover,
            updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP)
        ON CONFLICT(entry_date) DO UPDATE SET
            mood_tag = excluded.mood_tag,
            mood_color = excluded.mood_color,
            note = COALESCE(excluded.note, mood_entries.note),
            top_track_id = CASE WHEN excluded.top_track_id != '' THEN excluded.top_track_id ELSE mood_entries.top_track_id END,
            top_track_title = CASE WHEN excluded.top_track_title != '' THEN excluded.top_track_title ELSE mood_entries.top_track_title END,
            top_track_artist = CASE WHEN excluded.top_track_artist != '' THEN excluded.top_track_artist ELSE mood_entries.top_track_artist END,
            top_track_cover = CASE WHEN excluded.top_track_cover != '' THEN excluded.top_track_cover ELSE mood_entries.top_track_cover END,
            updated_at = CURRENT_TIMESTAMP;
        """, (entry_date, mood_tag, mood_color, note, t_id, t_title, t_artist, t_cover))
    conn.close()
    return True


def get_mood_entries(start_date: Optional[str] = None, end_date: Optional[str] = None) -> List[Dict[str, Any]]:
    """Retrieve mood entries in date range [start_date, end_date]."""
    conn = get_connection()
    query = "SELECT * FROM mood_entries WHERE 1=1"
    params = []

    if start_date:
        query += " AND entry_date >= ?"
        params.append(start_date)
    if end_date:
        query += " AND entry_date <= ?"
        params.append(end_date)

    query += " ORDER BY entry_date ASC;"

    cursor = conn.execute(query, params)
    rows = [dict(row) for row in cursor.fetchall()]
    conn.close()
    return rows


# ---------------------------------------------------------------------------
# 2. LISTENING ANALYTICS & PLAYBACK EVENTS
# ---------------------------------------------------------------------------

def record_playback_event(track_data: Dict[str, Any], listened_seconds: float,
                          total_seconds: float, is_radio: bool = False) -> None:
    """Record completed or partial playback event for stats and RPG computation."""
    if listened_seconds < 5.0:
        return  # Ignore accidental clicks under 5 seconds

    t_id = str(track_data.get("id") or track_data.get("videoId") or "")
    title = str(track_data.get("title") or "Unknown")
    artist = str(track_data.get("artist") or track_data.get("author") or "Unknown")
    album = str(track_data.get("album") or "")
    cover = str(track_data.get("image") or track_data.get("cover") or "")
    genre = str(track_data.get("genre") or "")

    duration_ms = int(total_seconds * 1000)
    listened_ms = int(listened_seconds * 1000)
    completion_rate = min(1.0, listened_seconds / max(1.0, total_seconds))
    is_deep_cut = bool(track_data.get("isDeepCut", False) or "deep" in str(track_data.get("source", "")).lower())

    conn = get_connection()
    with conn:
        conn.execute("""
        INSERT INTO playback_events (
            track_id, title, artist, album, cover_url,
            duration_ms, listened_ms, completion_rate,
            genre, is_radio, is_deep_cut
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """, (t_id, title, artist, album, cover, duration_ms, listened_ms,
              completion_rate, genre, is_radio, is_deep_cut))
    conn.close()


PLAY_THRESHOLD_SECONDS = 30.0


def upsert_play(play_id: str, track_data: Dict[str, Any], listened_seconds: float,
                total_seconds: float) -> bool:
    """Count a play once it reaches 30s; later calls with the same play_id only extend listened time."""
    if not play_id or listened_seconds < PLAY_THRESHOLD_SECONDS:
        return False
    t_id = str(track_data.get("id") or track_data.get("videoId") or track_data.get("path") or "")
    title = str(track_data.get("title") or "Unknown")
    artist = str(track_data.get("artist") or track_data.get("author") or "Unknown")
    album = str(track_data.get("album") or "")
    cover = str(track_data.get("image") or track_data.get("cover") or "")
    duration_ms = int(max(0.0, total_seconds) * 1000)
    listened_ms = int(listened_seconds * 1000)
    completion = min(1.0, listened_seconds / max(1.0, total_seconds))
    conn = get_connection()
    with conn:
        conn.execute("""
        INSERT INTO playback_events (play_id, track_id, title, artist, album, cover_url,
                                     duration_ms, listened_ms, completion_rate)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(play_id) DO UPDATE SET
            listened_ms = MAX(playback_events.listened_ms, excluded.listened_ms),
            completion_rate = MAX(playback_events.completion_rate, excluded.completion_rate),
            duration_ms = MAX(playback_events.duration_ms, excluded.duration_ms),
            synced = 0;
        """, (play_id, t_id, title, artist, album, cover, duration_ms, listened_ms, completion))
    conn.close()
    return True


# ---------------------------------------------------------------------------
# Account sync helpers (backend/account_sync.py): plays travel between devices by play_id
# ---------------------------------------------------------------------------

_PLAY_SYNC_COLS = ("track_id", "title", "artist", "album", "cover_url", "duration_ms",
                   "listened_ms", "completion_rate", "genre", "is_radio", "is_deep_cut", "timestamp")


def unsynced_plays(limit: int = 100) -> List[Dict[str, Any]]:
    """Plays this device has not sent to the cloud yet. Old rows without a play_id get a stable one."""
    conn = get_connection()
    with conn:
        rows = conn.execute("SELECT id, track_id, title, timestamp FROM playback_events "
                            "WHERE play_id IS NULL OR play_id = '' LIMIT 500;").fetchall()
        for r in rows:
            raw = f"{r['id']}|{r['track_id']}|{r['title']}|{r['timestamp']}".encode("utf-8", "replace")
            conn.execute("UPDATE playback_events SET play_id = ? WHERE id = ?;",
                         ("legacy_" + hashlib.sha1(raw).hexdigest()[:20], r["id"]))
    rows = conn.execute(f"SELECT play_id, {', '.join(_PLAY_SYNC_COLS)} FROM playback_events "
                        "WHERE synced = 0 AND play_id IS NOT NULL AND play_id != '' "
                        "ORDER BY id LIMIT ?;", (int(limit),)).fetchall()
    conn.close()
    return [dict(r) for r in rows]


def mark_plays_synced(play_ids: List[str], listened: Dict[str, int]) -> None:
    """Flag plays as sent, unless they grew while the request was in flight."""
    if not play_ids:
        return
    conn = get_connection()
    with conn:
        for pid in play_ids:
            conn.execute("UPDATE playback_events SET synced = 1 WHERE play_id = ? AND listened_ms <= ?;",
                         (pid, int(listened.get(pid, 0))))
    conn.close()


def merge_remote_plays(plays: List[Dict[str, Any]]) -> int:
    """Insert plays made on another device (same play_id only grows). Returns how many changed."""
    if not plays:
        return 0
    changed = 0
    conn = get_connection()
    with conn:
        for p in plays:
            pid = str(p.get("play_id") or "")
            if not pid:
                continue
            vals = [p.get(c) for c in _PLAY_SYNC_COLS]
            if not vals[-1]:
                vals[-1] = datetime.utcnow().strftime("%Y-%m-%d %H:%M:%S")
            cur = conn.execute(f"""
            INSERT INTO playback_events (play_id, {', '.join(_PLAY_SYNC_COLS)}, synced)
            VALUES (?, {', '.join('?' for _ in _PLAY_SYNC_COLS)}, 1)
            ON CONFLICT(play_id) DO UPDATE SET
                listened_ms = MAX(playback_events.listened_ms, excluded.listened_ms),
                completion_rate = MAX(playback_events.completion_rate, excluded.completion_rate),
                duration_ms = MAX(playback_events.duration_ms, excluded.duration_ms)
            WHERE excluded.listened_ms > playback_events.listened_ms;
            """, [pid] + vals)
            changed += cur.rowcount or 0
        if changed:
            conn.execute("DELETE FROM user_stats_cache;")
    conn.close()
    return changed


def get_lifetime_totals() -> Dict[str, Any]:
    """All-time play count, listened minutes and first play time (for the profile header)."""
    conn = get_connection()
    row = conn.execute("""
        SELECT COUNT(*) AS play_count, COALESCE(SUM(listened_ms), 0) AS total_ms,
               MIN(timestamp) AS first_play
        FROM playback_events;
    """).fetchone()
    conn.close()
    total_ms = int(row["total_ms"] or 0)
    return {
        "play_count": int(row["play_count"] or 0),
        "total_minutes": total_ms // 60000,
        "total_hours": round(total_ms / 3600000.0, 1),
        "first_play": row["first_play"] or "",
    }


def get_profile_overview(recent_limit: int = 16, artist_limit: int = 10) -> Dict[str, Any]:
    """Profile page data: totals per period, recently played tracks and most played artists."""
    conn = get_connection()
    periods = []
    # timestamps are stored by SQLite in UTC, so compare against SQLite's own clock
    for key, cutoff in (("week", "-7 days"), ("month", "-30 days"), ("all", None)):
        where = "WHERE timestamp >= datetime('now', ?)" if cutoff else ""
        args = (cutoff,) if cutoff else ()
        row = conn.execute(f"""
            SELECT COUNT(*) AS plays, COUNT(DISTINCT track_id) AS songs,
                   COALESCE(SUM(listened_ms), 0) AS total_ms
            FROM playback_events {where};
        """, args).fetchone()
        periods.append({"key": key, "plays": int(row["plays"] or 0), "songs": int(row["songs"] or 0),
                        "total_minutes": int(row["total_ms"] or 0) // 60000})
    recent = [dict(r) for r in conn.execute("""
        SELECT p.track_id, p.title, p.artist, p.cover_url, p.timestamp AS last_played
        FROM playback_events p
        -- the same song can arrive as a stream id or as its cached file, so group by title and artist
        JOIN (SELECT MAX(id) AS mid FROM playback_events
              WHERE track_id != '' GROUP BY lower(title), lower(COALESCE(artist, ''))) last
          ON p.id = last.mid
        ORDER BY p.timestamp DESC, p.id DESC
        LIMIT ?;
    """, (recent_limit,)).fetchall()]
    artists = [dict(r) for r in conn.execute("""
        SELECT artist, COUNT(*) AS plays, COALESCE(SUM(listened_ms), 0) / 60000 AS minutes,
               (SELECT cover_url FROM playback_events c WHERE c.artist = p.artist AND c.cover_url != ''
                ORDER BY c.id DESC LIMIT 1) AS cover_url
        FROM playback_events p
        WHERE artist NOT IN ('', 'Unknown')
        GROUP BY artist
        ORDER BY plays DESC, minutes DESC
        LIMIT ?;
    """, (artist_limit,)).fetchall()]
    conn.close()
    return {"periods": periods, "recent": recent, "artists": artists}


RECAP_MIN_SONGS = 10   # a month's recap opens once it has this many different songs
RECAP_FIRST_DAY = 3    # ...and not before this day; on the 1st and 2nd the previous month shows


def _recap_month_stats(conn, year: int, month: int) -> Dict[str, Any]:
    """Everything the recap shows for one calendar month (local time)."""
    return _period_stats(conn, year, month)


def _period_stats(conn, year: int, month: int = 0) -> Dict[str, Any]:
    """One calendar month (month 1..12) or one whole year (month 0), in local time."""
    if month:
        ym = f"{year:04d}-{month:02d}"
        # stored in UTC; the month, weekday and hour are the listener's own
        where = "strftime('%Y-%m', timestamp, 'localtime') = ?"
    else:
        ym = f"{year:04d}"
        where = "strftime('%Y', timestamp, 'localtime') = ?"
    song_key = "lower(title) || '|' || lower(COALESCE(artist, ''))"
    tot = conn.execute(f"""
        SELECT COUNT(*) AS plays, COALESCE(SUM(listened_ms), 0) AS ms,
               COUNT(DISTINCT {song_key}) AS songs,
               COUNT(DISTINCT CASE WHEN artist NOT IN ('', 'Unknown') THEN lower(artist) END) AS artists,
               COUNT(DISTINCT CASE WHEN COALESCE(album, '') != '' THEN lower(album) END) AS albums
        FROM playback_events WHERE {where};
    """, (ym,)).fetchone()
    songs = [dict(r) for r in conn.execute(f"""
        SELECT MAX(title) AS title, MAX(artist) AS artist, MAX(track_id) AS track_id,
               (SELECT cover_url FROM playback_events c WHERE {song_key.replace('title', 'c.title').replace('artist', 'c.artist')}
                  = {song_key.replace('title', 'p.title').replace('artist', 'p.artist')} AND c.cover_url != ''
                ORDER BY c.id DESC LIMIT 1) AS cover_url,
               COUNT(*) AS plays, COALESCE(SUM(listened_ms), 0) / 60000 AS minutes
        FROM playback_events p WHERE {where} AND track_id != ''
        GROUP BY {song_key.replace('title', 'p.title').replace('artist', 'p.artist')}
        ORDER BY plays DESC, minutes DESC LIMIT 10;
    """, (ym,)).fetchall()]
    # the song page's cover wall: every distinct cover played this month, most played first
    grid = [dict(r) for r in conn.execute(f"""
        SELECT MAX(title) AS title, MAX(artist) AS artist, MAX(cover_url) AS cover_url, COUNT(*) AS plays
        FROM playback_events WHERE {where} AND cover_url != ''
        GROUP BY cover_url ORDER BY plays DESC LIMIT 60;
    """, (ym,)).fetchall()]
    artists = [dict(r) for r in conn.execute(f"""
        SELECT artist, COUNT(*) AS plays, COALESCE(SUM(listened_ms), 0) / 60000 AS minutes,
               (SELECT cover_url FROM playback_events c WHERE c.artist = p.artist AND c.cover_url != ''
                ORDER BY c.id DESC LIMIT 1) AS cover_url
        FROM playback_events p WHERE {where} AND artist NOT IN ('', 'Unknown')
        GROUP BY artist ORDER BY plays DESC, minutes DESC LIMIT 10;
    """, (ym,)).fetchall()]
    for a in artists:
        top = next((s for s in songs if (s.get("artist") or "") == a["artist"]), None)
        a["top_song"] = top["title"] if top else ""
        a["top_song_track_id"] = top["track_id"] if top else ""
        a["top_song_cover"] = top["cover_url"] if top else ""

    def buckets(fmt: str, size: int, offset: int = 0) -> List[int]:
        out = [0] * size
        for r in conn.execute(f"""
            SELECT CAST(strftime('{fmt}', timestamp, 'localtime') AS INTEGER) AS k,
                   COALESCE(SUM(listened_ms), 0) / 60000 AS m
            FROM playback_events WHERE {where} GROUP BY k;
        """, (ym,)).fetchall():
            i = int(r["k"]) - offset
            if 0 <= i < size:
                out[i] = int(r["m"] or 0)
        return out

    if month:
        days_in_month = (datetime(year + (month == 12), month % 12 + 1, 1) - datetime(year, month, 1)).days
        day_minutes = buckets("%d", days_in_month, offset=1)
    else:
        day_minutes = buckets("%m", 12, offset=1)     # a year: one bucket per month
    sun_first = buckets("%w", 7)                      # SQLite: 0 = Sunday
    return {
        "year": year, "month": month,
        "plays": int(tot["plays"] or 0), "total_minutes": int(tot["ms"] or 0) // 60000,
        "song_count": int(tot["songs"] or 0), "artist_count": int(tot["artists"] or 0),
        "album_count": int(tot["albums"] or 0),
        "top_songs": songs, "top_artists": artists, "grid_songs": grid,
        "weekday_minutes": sun_first[1:] + sun_first[:1],  # Monday first
        "hour_minutes": buckets("%H", 24),
        "day_minutes": day_minutes,
    }


def get_artist_minutes(year: int, month: int = 0) -> List[Dict[str, Any]]:
    """Every artist played in the month (or year, month 0) with their listening minutes, most first."""
    ym, fmt = (f"{year:04d}-{month:02d}", "%Y-%m") if month else (f"{year:04d}", "%Y")
    conn = get_connection()
    try:
        return [{"artist": r["artist"], "minutes": int(r["m"] or 0)} for r in conn.execute(f"""
            SELECT artist, COALESCE(SUM(listened_ms), 0) / 60000.0 AS m FROM playback_events
            WHERE strftime('{fmt}', timestamp, 'localtime') = ? AND artist NOT IN ('', 'Unknown')
            GROUP BY lower(artist) ORDER BY m DESC LIMIT 60;
        """, (ym,)).fetchall()]
    finally:
        conn.close()


def get_period_stats(year: int, month: int = 0) -> Dict[str, Any]:
    """The Stats page for one month or year, plus every month that has any listening (for the ruler)."""
    conn = get_connection()
    try:
        stats = _period_stats(conn, year, month)
        first = conn.execute(
            "SELECT strftime('%Y-%m-%d', MIN(timestamp), 'localtime') AS d FROM playback_events;").fetchone()["d"]
        # minutes per local day, all time: the ruler draws each day's tick as tall as its listening
        days: Dict[str, int] = {}
        for r in conn.execute("""
            SELECT strftime('%Y-%m-%d', timestamp, 'localtime') AS d, COALESCE(SUM(listened_ms), 0) / 60000 AS m
            FROM playback_events GROUP BY d;
        """).fetchall():
            days[r["d"]] = int(r["m"] or 0)
        stats["first_day"] = first or ""
        stats["daily_minutes"] = days
        return stats
    finally:
        conn.close()


def get_artist_other_song(year: int, month: int, artist: str, exclude_title: str) -> Optional[Dict[str, Any]]:
    """The artist's most played song that month other than `exclude_title`, read live, so a song
    played after the recap was built still counts."""
    conn = get_connection()
    try:
        # SQLite's lower() leaves non-ASCII letters (Đ, Ạ...) alone, so titles are matched in Python
        skip = (exclude_title or "").strip().casefold()
        for r in conn.execute("""
            SELECT MAX(title) AS title, MAX(track_id) AS track_id, COUNT(*) AS plays,
                   (SELECT c.cover_url FROM playback_events c WHERE c.title = p.title
                      AND c.artist = p.artist AND c.cover_url != '' ORDER BY c.id DESC LIMIT 1) AS cover_url
            FROM playback_events p
            WHERE strftime('%Y-%m', timestamp, 'localtime') = ? AND artist = ? AND track_id != ''
            GROUP BY title ORDER BY plays DESC, SUM(listened_ms) DESC LIMIT 10;
        """, (f"{int(year):04d}-{int(month):02d}", artist)).fetchall():
            if (r["title"] or "").strip().casefold() != skip:
                return dict(r)
        return None
    finally:
        conn.close()


def get_monthly_recap(force: bool = False, today: Optional[datetime] = None) -> Dict[str, Any]:
    """The monthly recap if one is ready, by the same rules as Mochy; force shows whatever exists."""
    today = today or datetime.now()
    prev_year, prev_month = (today.year - 1, 12) if today.month == 1 else (today.year, today.month - 1)
    conn = get_connection()
    try:
        all_ms = conn.execute("SELECT COALESCE(SUM(listened_ms), 0) AS ms FROM playback_events;").fetchone()["ms"]
        def ready(stats, progress):
            return {"ready": True, "stats": stats, "month_progress": progress,
                    "all_time_minutes": int(all_ms or 0) // 60000}
        days_in_month = (datetime(today.year + (today.month == 12), today.month % 12 + 1, 1)
                         - datetime(today.year, today.month, 1)).days
        progress_now = max(1, min(100, round(today.day * 100 / days_in_month)))
        if today.day < RECAP_FIRST_DAY:
            prev = _recap_month_stats(conn, prev_year, prev_month)
            if prev["song_count"] >= RECAP_MIN_SONGS or (force and prev["song_count"] > 0):
                return ready(prev, 100)
            missing = RECAP_MIN_SONGS
        else:
            cur = _recap_month_stats(conn, today.year, today.month)
            if cur["song_count"] >= RECAP_MIN_SONGS:
                return ready(cur, progress_now)
            missing = RECAP_MIN_SONGS - cur["song_count"]
        if force:
            for y, m, p in ((today.year, today.month, progress_now), (prev_year, prev_month, 100)):
                stats = _recap_month_stats(conn, y, m)
                if stats["song_count"] > 0:
                    return ready(stats, p)
        return {"ready": False, "missing_songs": missing, "first_day": RECAP_FIRST_DAY,
                "all_time_minutes": int(all_ms or 0) // 60000}
    finally:
        conn.close()


def get_listening_summary(days: int = 30) -> Dict[str, Any]:
    """Calculate aggregated listening statistics for the past N days."""
    since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    conn = get_connection()

    # Total listening time
    cur = conn.execute("""
        SELECT COUNT(*) as play_count,
               COALESCE(SUM(listened_ms), 0) as total_listened_ms,
               COALESCE(AVG(completion_rate), 0.0) as avg_completion
        FROM playback_events
        WHERE timestamp >= ?;
    """, (since_date,))
    totals = dict(cur.fetchone())

    # Top 5 Artists
    cur = conn.execute("""
        SELECT artist, COUNT(*) as play_count, SUM(listened_ms) as total_ms
        FROM playback_events
        WHERE timestamp >= ? AND artist != 'Unknown'
        GROUP BY artist
        ORDER BY total_ms DESC
        LIMIT 5;
    """, (since_date,))
    top_artists = [dict(row) for row in cur.fetchall()]

    # Top 5 Tracks
    cur = conn.execute("""
        SELECT track_id, title, artist, cover_url, COUNT(*) as play_count, SUM(listened_ms) as total_ms
        FROM playback_events
        WHERE timestamp >= ?
        GROUP BY track_id, title, artist
        ORDER BY play_count DESC, total_ms DESC
        LIMIT 5;
    """, (since_date,))
    top_tracks = [dict(row) for row in cur.fetchall()]

    conn.close()

    total_hours = round(totals["total_listened_ms"] / (1000.0 * 3600.0), 1)
    total_minutes = int(totals["total_listened_ms"] / (1000.0 * 60.0))

    return {
        "period_days": days,
        "play_count": totals["play_count"],
        "total_minutes": total_minutes,
        "total_hours": total_hours,
        "avg_completion_rate": round(totals["avg_completion"] * 100, 1),
        "top_artists": top_artists,
        "top_tracks": top_tracks,
    }


# ---------------------------------------------------------------------------
# 3. 6-AXIS MUSIC RPG PERSONA CALCULATION
# ---------------------------------------------------------------------------

def calculate_rpg_persona(days: int = 30) -> Dict[str, Any]:
    """
    Compute 6-axis RPG Persona Radar Chart (0 to 100 score on each axis):
    1. Explorer (Khám Phá): Ratio of distinct new tracks/artists vs repeats.
    2. Energy (Năng Lượng): Uptempo/daytime listening distribution.
    3. Deep Cuts (Chiều Sâu): Listening to niche/indie/album tracks vs top hits.
    4. Eclectic (Đa Dạng): Number of diverse artists and genres.
    5. Focus (Tập Trung): Long tracks, instrumental listening sessions.
    6. Loyalty (Gắn Kết): High completion rate, low skipping.
    """
    since_date = (datetime.now() - timedelta(days=days)).strftime("%Y-%m-%d %H:%M:%S")
    conn = get_connection()

    cur = conn.execute("""
        SELECT COUNT(*) as total_events,
               COUNT(DISTINCT track_id) as unique_tracks,
               COUNT(DISTINCT artist) as unique_artists,
               COALESCE(AVG(completion_rate), 0.5) as avg_completion,
               COALESCE(AVG(duration_ms), 180000) as avg_duration,
               SUM(CASE WHEN is_deep_cut = 1 THEN 1 ELSE 0 END) as deep_cuts_count,
               SUM(CASE WHEN is_radio = 1 THEN 1 ELSE 0 END) as radio_count
        FROM playback_events
        WHERE timestamp >= ?;
    """, (since_date,))
    row = dict(cur.fetchone())
    conn.close()

    total = max(1, row["total_events"])
    unique_t = row["unique_tracks"]
    unique_a = row["unique_artists"]
    avg_comp = row["avg_completion"]
    avg_dur_sec = row["avg_duration"] / 1000.0
    deep_cuts = row["deep_cuts_count"]
    radio_plays = row["radio_count"]

    if total < 5:
        # Default balanced archetype for new users
        scores = {
            "explorer": 50.0,
            "energy": 50.0,
            "deep_cuts": 50.0,
            "eclectic": 50.0,
            "focus": 50.0,
            "loyalty": 50.0,
        }
        title_vi = "Nhà Du Lữ Mới Khởi Hành"
        title_en = "Novice Journeyer"
        desc_vi = "Hãy nghe thêm nhạc để hệ thống khắc họa rõ nét chân dung RPG của bạn!"
        desc_en = "Listen to more tracks to unlock your distinct musical RPG persona!"
    else:
        # 1. Explorer score: high unique tracks + radio exploration
        explorer_val = min(100.0, ((unique_t / total) * 60.0) + ((radio_plays / total) * 40.0))
        # 2. Energy score: based on listening velocity
        energy_val = min(100.0, max(20.0, (total / max(1, days)) * 8.0 + 30.0))
        # 3. Deep cuts score: niche tracks & low repetition
        deep_cuts_val = min(100.0, ((deep_cuts / total) * 70.0) + 30.0)
        # 4. Eclectic score: variety of artists
        eclectic_val = min(100.0, (unique_a / max(1, total * 0.5)) * 100.0)
        # 5. Focus score: long durations (instrumental, classical, lofi)
        focus_val = min(100.0, max(20.0, (avg_dur_sec / 240.0) * 80.0))
        # 6. Loyalty score: high completion, full album listening
        loyalty_val = min(100.0, max(20.0, avg_comp * 100.0))

        scores = {
            "explorer": round(explorer_val, 1),
            "energy": round(energy_val, 1),
            "deep_cuts": round(deep_cuts_val, 1),
            "eclectic": round(eclectic_val, 1),
            "focus": round(focus_val, 1),
            "loyalty": round(loyalty_val, 1),
        }

        # Determine highest dominant traits and bestow RPG Title
        dominant_trait = max(scores, key=scores.get)

        archetypes = {
            "explorer": {
                "title_vi": "Nhà Thám Hiểm Không Gian Âm Nhạc",
                "title_en": "Cosmic Music Explorer",
                "desc_vi": "Bạn luôn khao khát tìm kiếm những thanh âm mới lạ và không ngừng mở rộng chân trời âm nhạc.",
                "desc_en": "Constantly seeking uncharted frequencies and expanding your musical horizon."
            },
            "energy": {
                "title_vi": "Chiến Binh Nhịp Điệu Bốc Lửa",
                "title_en": "Kinetic Beat Paladin",
                "desc_vi": "Âm nhạc của bạn tràn đầy năng lượng bùng nổ, thúc đẩy mọi khoảnh khắc thăng hoa.",
                "desc_en": "Driven by high tempo and pulsating grooves that power your everyday hustle."
            },
            "deep_cuts": {
                "title_vi": "Nhà Giả Kim Indie Trầm Lắng",
                "title_en": "Ethereal Indie Alchemist",
                "desc_vi": "Bạn yêu thích những viên ngọc quý ẩn giấu và những giai điệu ít người chạm tới.",
                "desc_en": "You cherish hidden gems, indie poetry and sounds that live outside the mainstream."
            },
            "eclectic": {
                "title_vi": "Phù Thủy Đa Thể Loại",
                "title_en": "Eclectic Genre Sorcerer",
                "desc_vi": "Gu âm nhạc của bạn vô biên, hòa trộn mọi dòng nhạc từ Anime, Pop đến Classical.",
                "desc_en": "Boundless musical tastes weaving freely through diverse cultures and styles."
            },
            "focus": {
                "title_vi": "Ẩn Sĩ Lofi & Chiều Sâu Tâm Hồn",
                "title_en": "Deep Focus Monk",
                "desc_vi": "Âm nhạc là không gian tĩnh tại giúp bạn tập trung cao độ và tìm về sự an yên.",
                "desc_en": "Music is your sanctuary of deep focus, instrumental flow and tranquility."
            },
            "loyalty": {
                "title_vi": "Hiệp Sĩ Hoài Niệm Thuần Khiết",
                "title_en": "Nostalgic Melody Knight",
                "desc_vi": "Bạn luôn trân trọng từng nốt nhạc, gắn bó sâu sắc và nghe trọn vẹn từng tác phẩm yêu thích.",
                "desc_en": "Steadfast loyalty to your favorite albums, listening to every track with devotion."
            },
        }

        arch = archetypes.get(dominant_trait, archetypes["explorer"])
        title_vi = arch["title_vi"]
        title_en = arch["title_en"]
        desc_vi = arch["desc_vi"]
        desc_en = arch["desc_en"]

    return {
        "period_days": days,
        "scores": scores,
        "title_vi": title_vi,
        "title_en": title_en,
        "description_vi": desc_vi,
        "description_en": desc_en,
        "dominant_trait": max(scores, key=scores.get),
        "db_path": str(get_vault_db_path())
    }


# ---------------------------------------------------------------------------
# CLI INTERFACE FOR IPC / TESTING
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    init_db()
    args = sys.argv[1:]

    if not args:
        print(f"Nutsty Safe Vault DB initialized at: {get_vault_db_path()}")
        sys.exit(0)

    cmd = args[0]
    if cmd == "init":
        print(f"OK: {get_vault_db_path()}")

    elif cmd == "mood":
        sub = args[1] if len(args) > 1 else "list"
        if sub == "save" and len(args) >= 5:
            d_str, m_tag, m_col = args[2], args[3], args[4]
            note = args[5] if len(args) > 5 else None
            record_daily_mood(d_str, m_tag, m_col, note=note)
            print(json.dumps({"status": "saved", "date": d_str}))
        elif sub == "list":
            start_d = args[2] if len(args) > 2 else None
            end_d = args[3] if len(args) > 3 else None
            entries = get_mood_entries(start_d, end_d)
            print(json.dumps(entries, ensure_ascii=False))

    elif cmd == "stats":
        d_count = int(args[1]) if len(args) > 1 else 30
        res = get_listening_summary(d_count)
        print(json.dumps(res, ensure_ascii=False, indent=2))

    elif cmd == "rpg":
        d_count = int(args[1]) if len(args) > 1 else 30
        res = calculate_rpg_persona(d_count)
        print(json.dumps(res, ensure_ascii=False, indent=2))
    else:
        print(f"Unknown command: {cmd}")
