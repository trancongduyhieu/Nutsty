-- Nutsty Global Friends Relay - Cloudflare D1 SQL Schema
-- Supports Discord-style Tags (Username#1234), Immutable User UUIDs, Realtime Event Queues

CREATE TABLE IF NOT EXISTS nutsty_users (
    id TEXT PRIMARY KEY,               -- Immutable UUID v4 (usr_xxxxxxxx...)
    secret_key TEXT NOT NULL,          -- Client secret key for authentication
    username TEXT NOT NULL,            -- Display name ("Shiraori")
    discriminator TEXT NOT NULL,       -- 4-digit number ("6180")
    tag TEXT NOT NULL UNIQUE,          -- Composite: username#discriminator ("Shiraori#6180")
    avatar_url TEXT DEFAULT '',        -- Google avatar URL
    now_playing TEXT DEFAULT '',       -- JSON string of current listening track
    created_at INTEGER NOT NULL,       -- Epoch ms
    updated_at INTEGER NOT NULL,       -- Epoch ms
    last_active_at INTEGER NOT NULL    -- Epoch ms
);

CREATE INDEX IF NOT EXISTS idx_users_tag ON nutsty_users(tag);
CREATE INDEX IF NOT EXISTS idx_users_username ON nutsty_users(username);
CREATE INDEX IF NOT EXISTS idx_users_discriminator ON nutsty_users(discriminator);

CREATE TABLE IF NOT EXISTS nutsty_friendships (
    id TEXT PRIMARY KEY,               -- UUID of friendship relation
    user_id_1 TEXT NOT NULL,           -- min(user_a, user_b) to enforce unique pair
    user_id_2 TEXT NOT NULL,           -- max(user_a, user_b)
    status TEXT NOT NULL,              -- 'pending', 'accepted', 'rejected'
    initiated_by TEXT NOT NULL,        -- User UUID who sent the friend request
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    FOREIGN KEY(user_id_1) REFERENCES nutsty_users(id),
    FOREIGN KEY(user_id_2) REFERENCES nutsty_users(id),
    UNIQUE(user_id_1, user_id_2)
);

CREATE INDEX IF NOT EXISTS idx_friendships_u1 ON nutsty_friendships(user_id_1);
CREATE INDEX IF NOT EXISTS idx_friendships_u2 ON nutsty_friendships(user_id_2);

CREATE TABLE IF NOT EXISTS nutsty_events (
    id TEXT PRIMARY KEY,               -- Event UUID
    to_user_id TEXT NOT NULL,          -- Recipient User UUID
    from_user_id TEXT NOT NULL,        -- Sender User UUID
    event_type TEXT NOT NULL,          -- 'friend_request', 'friend_accepted', 'friend_removed'
    payload TEXT NOT NULL,             -- JSON string with event metadata
    consumed INTEGER DEFAULT 0,        -- 0 = pending, 1 = received/consumed
    created_at INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_events_to_user ON nutsty_events(to_user_id, consumed);

-- 24h Music Capsule Notes
CREATE TABLE IF NOT EXISTS nutsty_notes (
    id TEXT PRIMARY KEY,               -- Note UUID
    user_id TEXT NOT NULL UNIQUE,      -- One active note per user
    tag TEXT NOT NULL,                 -- User tag at time of posting
    username TEXT NOT NULL,            -- Username
    avatar_url TEXT DEFAULT '',        -- Avatar URL
    note_text TEXT DEFAULT '',         -- Note content (up to 80 chars)
    track TEXT DEFAULT '',             -- JSON string of attached track object
    now_playing TEXT DEFAULT '',       -- JSON string or song title
    created_at INTEGER NOT NULL,       -- Epoch ms
    expires_at INTEGER NOT NULL,       -- Epoch ms (created_at + 86400000)
    FOREIGN KEY(user_id) REFERENCES nutsty_users(id)
);

CREATE INDEX IF NOT EXISTS idx_notes_user_id ON nutsty_notes(user_id);
CREATE INDEX IF NOT EXISTS idx_notes_tag ON nutsty_notes(tag);
CREATE INDEX IF NOT EXISTS idx_notes_expires ON nutsty_notes(expires_at);

-- Account sync: playlists, favorite playlists, liked songs, plays and listening progress.
-- One row per item per account; last write wins on updated_at; seq is the per-account pull cursor.
-- The Worker also creates these lazily (ensureSyncSchema), so a deploy alone is enough.
CREATE TABLE IF NOT EXISTS nutsty_sync_items (
    user_id TEXT NOT NULL,
    kind TEXT NOT NULL,                -- 'playlist', 'favorite', 'liked', 'play', 'progress'
    item_id TEXT NOT NULL,
    data TEXT NOT NULL DEFAULT '',     -- JSON of the item ('' when deleted)
    deleted INTEGER NOT NULL DEFAULT 0,
    updated_at INTEGER NOT NULL,       -- Epoch ms from the device that made the change
    device_id TEXT NOT NULL DEFAULT '',
    seq INTEGER NOT NULL,
    PRIMARY KEY (user_id, kind, item_id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_sync_user_seq ON nutsty_sync_items(user_id, seq);

-- One-time codes that link a new device to an account (10 minutes)
CREATE TABLE IF NOT EXISTS nutsty_link_codes (
    code TEXT PRIMARY KEY,
    user_id TEXT NOT NULL,
    expires_at INTEGER NOT NULL,
    created_at INTEGER NOT NULL
);
