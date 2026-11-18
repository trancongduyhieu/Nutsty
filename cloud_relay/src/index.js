/**
 * Nutsty Global Friends Relay - Cloudflare Worker
 * Fully Serverless Backend on Cloudflare Edge + D1 SQLite
 */

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
    },
  });
}

function errorResponse(message, status = 400, extra = {}) {
  return jsonResponse({ success: false, error: message, ...extra }, status);
}

function normalizeTag(username, discriminator) {
  return `${username.trim()}#${String(discriminator).padStart(4, "0")}`;
}

async function authenticateUser(db, userId, secretKey) {
  if (!userId || !secretKey) return null;
  const user = await db
    .prepare("SELECT * FROM nutsty_users WHERE id = ? AND secret_key = ?")
    .bind(userId, secretKey)
    .first();
  return user || null;
}

async function findAvailableDiscriminator(db, username, preferred = null) {
  const cleanUsername = username.trim();
  if (preferred && /^\d{4}$/.test(preferred)) {
    const candidateTag = normalizeTag(cleanUsername, preferred);
    const existing = await db
      .prepare("SELECT id FROM nutsty_users WHERE tag = ?")
      .bind(candidateTag)
      .first();
    if (!existing) return preferred;
  }

  for (let attempt = 0; attempt < 25; attempt++) {
    const randomNum = String(Math.floor(1000 + Math.random() * 9000));
    const candidateTag = normalizeTag(cleanUsername, randomNum);
    const existing = await db
      .prepare("SELECT id FROM nutsty_users WHERE tag = ?")
      .bind(candidateTag)
      .first();
    if (!existing) return randomNum;
  }

  // Fallback sequential search
  for (let i = 1; i <= 9999; i++) {
    const padNum = String(i).padStart(4, "0");
    const candidateTag = normalizeTag(cleanUsername, padNum);
    const existing = await db
      .prepare("SELECT id FROM nutsty_users WHERE tag = ?")
      .bind(candidateTag)
      .first();
    if (!existing) return padNum;
  }

  return null;
}

async function consolidateDuplicateUserAccounts(db, keepUserId, username, avatarUrl) {
  if (!keepUserId) return;
  const cleanName = (username || "").trim();
  const isGenericName = !cleanName || ["user", "nutsty user", "khách", "guest"].includes(cleanName.toLowerCase());
  if (isGenericName) return;

  const res = await db
    .prepare("SELECT id FROM nutsty_users WHERE id != ? AND LOWER(username) = LOWER(?)")
    .bind(keepUserId, cleanName)
    .all();
  const staleRows = res.results || [];

  for (const r of staleRows) {
    const oldId = r.id;
    if (!oldId || oldId === keepUserId) continue;

    // Migrate friendships from oldId -> keepUserId
    const fRows = await db
      .prepare("SELECT * FROM nutsty_friendships WHERE user_id_1 = ? OR user_id_2 = ?")
      .bind(oldId, oldId)
      .all();
    for (const f of fRows.results || []) {
      const peerId = f.user_id_1 === oldId ? f.user_id_2 : f.user_id_1;
      if (!peerId || peerId === keepUserId) continue;
      const u1 = keepUserId < peerId ? keepUserId : peerId;
      const u2 = keepUserId < peerId ? peerId : keepUserId;
      const initBy = f.initiated_by === oldId ? keepUserId : f.initiated_by;
      await db
        .prepare(
          `INSERT INTO nutsty_friendships (id, user_id_1, user_id_2, status, initiated_by, created_at, updated_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)
           ON CONFLICT(user_id_1, user_id_2) DO UPDATE SET
             status = CASE WHEN nutsty_friendships.status = 'accepted' OR excluded.status = 'accepted' THEN 'accepted' ELSE excluded.status END,
             updated_at = MAX(nutsty_friendships.updated_at, excluded.updated_at)`
        )
        .bind("fr_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16), u1, u2, f.status, initBy, f.created_at, f.updated_at)
        .run();
    }
    await db.prepare("DELETE FROM nutsty_friendships WHERE user_id_1 = ? OR user_id_2 = ?").bind(oldId, oldId).run();
    await db.prepare("DELETE FROM nutsty_notes WHERE user_id = ?").bind(oldId).run();
    await db.prepare("DELETE FROM nutsty_users WHERE id = ?").bind(oldId).run();
  }
}

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Methods": "GET, POST, PUT, DELETE, OPTIONS",
          "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Requested-With",
        },
      });
    }

    const db = env.DB;
    if (!db) {
      return errorResponse("Database binding (DB) not configured", 500);
    }

    const url = new URL(request.url);
    const path = url.pathname;

    try {
      if (path === "/" || path === "/health") {
        return jsonResponse({
          status: "ok",
          service: "Nutsty Global Relay",
          version: "1.0.0",
          time: Date.now(),
        });
      }

      // 1. REGISTER OR RESTORE IDENTITY
      if (path === "/api/users/register" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { username, avatar_url, client_secret, user_id, preferred_discriminator } = body;

        const cleanUsername = (username || "User").trim().slice(0, 32);

        // Restore if secret and user_id match
        if (user_id && client_secret) {
          const existing = await authenticateUser(db, user_id, client_secret);
          if (existing) {
            const now = Date.now();
            await db
              .prepare(
                "UPDATE nutsty_users SET avatar_url = COALESCE(NULLIF(?, ''), avatar_url), last_active_at = ? WHERE id = ?"
              )
              .bind(avatar_url || "", now, user_id)
              .run();

            const refreshed = await db
              .prepare("SELECT id, username, discriminator, tag, avatar_url, now_playing, created_at FROM nutsty_users WHERE id = ?")
              .bind(user_id)
              .first();

            await consolidateDuplicateUserAccounts(db, user_id, refreshed.username, refreshed.avatar_url);

            return jsonResponse({
              success: true,
              user: refreshed,
              secret_key: client_secret,
              restored: true,
            });
          }
        }

        // Generate new user
        const newUserId = "usr_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        const newSecret = crypto.randomUUID().replace(/-/g, "") + crypto.randomUUID().replace(/-/g, "");
        const disc = await findAvailableDiscriminator(db, cleanUsername, preferred_discriminator);
        if (!disc) {
          return errorResponse("All tags for this username are occupied", 409);
        }

        const tag = normalizeTag(cleanUsername, disc);
        const now = Date.now();

        await db
          .prepare(
            `INSERT INTO nutsty_users (id, secret_key, username, discriminator, tag, avatar_url, now_playing, created_at, updated_at, last_active_at)
             VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?)`
          )
          .bind(newUserId, newSecret, cleanUsername, disc, tag, avatar_url || "", now, now, now)
          .run();

        await consolidateDuplicateUserAccounts(db, newUserId, cleanUsername, avatar_url || "");

        return jsonResponse({
          success: true,
          user: {
            id: newUserId,
            username: cleanUsername,
            discriminator: disc,
            tag: tag,
            avatar_url: avatar_url || "",
            now_playing: "",
            created_at: now,
          },
          secret_key: newSecret,
          restored: false,
        });
      }

      // 2. UPDATE PROFILE (Change name or discriminator)
      if (path === "/api/users/update_profile" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, new_username, new_discriminator, avatar_url } = body;

        const user = await authenticateUser(db, user_id, secret_key);
        if (!user) return errorResponse("Unauthorized", 401);

        const targetUsername = (new_username !== undefined && new_username !== null ? new_username.trim() : user.username).slice(0, 32);
        if (!targetUsername) return errorResponse("Username cannot be empty", 400);

        let targetDisc = user.discriminator;
        if (new_discriminator !== undefined && new_discriminator !== null) {
          const dStr = String(new_discriminator).padStart(4, "0");
          if (!/^\d{4}$/.test(dStr) || dStr === "0000") {
            return errorResponse("Discriminator must be a 4-digit number between 0001 and 9999", 400);
          }
          targetDisc = dStr;
        }

        const targetTag = normalizeTag(targetUsername, targetDisc);

        if (targetTag !== user.tag) {
          const collision = await db
            .prepare("SELECT id FROM nutsty_users WHERE tag = ? AND id != ?")
            .bind(targetTag, user_id)
            .first();

          if (collision) {
            const suggested = await findAvailableDiscriminator(db, targetUsername);
            return errorResponse("Tag already taken by another user", 409, {
              suggested_discriminator: suggested,
              suggested_tag: suggested ? normalizeTag(targetUsername, suggested) : null,
            });
          }
        }

        const now = Date.now();
        const targetAvatar = avatar_url !== undefined ? avatar_url : user.avatar_url;

        await db
          .prepare(
            `UPDATE nutsty_users 
             SET username = ?, discriminator = ?, tag = ?, avatar_url = ?, updated_at = ?, last_active_at = ? 
             WHERE id = ?`
          )
          .bind(targetUsername, targetDisc, targetTag, targetAvatar, now, now, user_id)
          .run();

        await consolidateDuplicateUserAccounts(db, user_id, targetUsername, targetAvatar);

        const updated = await db
          .prepare("SELECT id, username, discriminator, tag, avatar_url, now_playing, created_at FROM nutsty_users WHERE id = ?")
          .bind(user_id)
          .first();

        return jsonResponse({
          success: true,
          user: updated,
        });
      }

      // 3. SEARCH USERS
      if (path === "/api/users/search" && request.method === "GET") {
        const rawQ = (url.searchParams.get("q") || "").trim();
        const callerUserId = url.searchParams.get("user_id") || "";

        if (!rawQ) {
          return jsonResponse({ results: [] });
        }

        const q = rawQ.replace(/\s+/g, " ");

        let querySql = "";
        let binds = [];

        if (q.includes("#")) {
          const parts = q.split("#");
          const u = parts[0].trim();
          const d = parts[1].trim();
          if (d.length > 0) {
            // Fault-tolerant tag search: matches exact tag, or discriminator if username mistyped, or username
            const padDisc = d.padStart(4, "0");
            querySql = `SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at 
                        FROM nutsty_users 
                        WHERE LOWER(tag) LIKE ? 
                           OR discriminator = ?
                           OR discriminator LIKE ?
                           OR (LOWER(username) LIKE ? AND discriminator LIKE ?)
                           OR LOWER(username) LIKE ?
                        ORDER BY 
                          CASE 
                            WHEN LOWER(tag) = ? THEN 1
                            WHEN LOWER(tag) LIKE ? THEN 2
                            WHEN discriminator = ? AND LOWER(username) LIKE ? THEN 3
                            WHEN discriminator = ? THEN 4
                            WHEN LOWER(username) LIKE ? THEN 5
                            ELSE 6
                          END,
                          last_active_at DESC
                        LIMIT 20`;
            binds = [
              `${u.toLowerCase()}#${d}%`,
              padDisc,
              `${d}%`,
              `%${u.toLowerCase()}%`, `${d}%`,
              `%${u.toLowerCase()}%`,
              `${u.toLowerCase()}#${d}`,
              `${u.toLowerCase()}#${d}%`,
              padDisc, `%${u.toLowerCase()}%`,
              padDisc,
              `%${u.toLowerCase()}%`
            ];
          } else {
            querySql = "SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at FROM nutsty_users WHERE LOWER(username) LIKE ? ORDER BY last_active_at DESC LIMIT 20";
            binds = [`%${u.toLowerCase()}%`];
          }
        } else if (/^\d{1,4}$/.test(q)) {
          // Searching by discriminator
          const padDisc = q.padStart(4, "0");
          querySql = `SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at 
                      FROM nutsty_users 
                      WHERE discriminator = ? OR discriminator LIKE ? OR LOWER(username) LIKE ? 
                      ORDER BY CASE WHEN discriminator = ? THEN 1 ELSE 2 END, last_active_at DESC 
                      LIMIT 20`;
          binds = [padDisc, `${q}%`, `%${q.toLowerCase()}%`, padDisc];
        } else {
          // General search by username or tag
          querySql = `SELECT id, username, discriminator, tag, avatar_url, now_playing, last_active_at 
                      FROM nutsty_users 
                      WHERE LOWER(username) LIKE ? OR LOWER(tag) LIKE ? 
                      ORDER BY CASE WHEN LOWER(username) = ? THEN 1 WHEN LOWER(username) LIKE ? THEN 2 ELSE 3 END, last_active_at DESC 
                      LIMIT 20`;
          binds = [
            `%${q.toLowerCase()}%`,
            `%${q.toLowerCase()}%`,
            q.toLowerCase(),
            `${q.toLowerCase()}%`
          ];
        }

        const stmt = db.prepare(querySql);
        const { results } = await stmt.bind(...binds).all();
        const rawList = results || [];

        // Auto-consolidate duplicate accounts (keep the most recently active row per username/avatar)
        const seenPersons = new Set();
        const list = [];
        for (const item of rawList) {
          const unameLow = (item.username || "").trim().toLowerCase();
          const av = (item.avatar_url || "").trim();
          const pKey = unameLow && !["user", "nutsty user", "khách", "guest"].includes(unameLow) ? `u:${unameLow}` : (av ? `av:${av}` : `id:${item.id}`);
          if (!seenPersons.has(pKey)) {
            seenPersons.add(pKey);
            list.push(item);
            await consolidateDuplicateUserAccounts(db, item.id, item.username, item.avatar_url);
          }
        }

        // Check friendship status if callerUserId is present
        const processed = [];
        for (const item of list) {
          if (callerUserId && item.id === callerUserId) continue; // skip self

          let status = "none";
          let initiatedBy = "";

          if (callerUserId) {
            const u1 = callerUserId < item.id ? callerUserId : item.id;
            const u2 = callerUserId < item.id ? item.id : callerUserId;
            const f = await db
              .prepare("SELECT status, initiated_by FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?")
              .bind(u1, u2)
              .first();
            if (f) {
              status = f.status;
              initiatedBy = f.initiated_by;
            }
          }

          processed.push({
            id: item.id,
            username: item.username,
            discriminator: item.discriminator,
            tag: item.tag,
            avatar_url: item.avatar_url,
            now_playing: item.now_playing,
            last_active_at: item.last_active_at,
            friendship_status: status,
            is_friend: status === "accepted",
            initiated_by: initiatedBy,
          });
        }

        return jsonResponse({ results: processed });
      }

      // 4. SEND FRIEND REQUEST
      if (path === "/api/friends/request" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { from_user_id, secret_key, target_user_id } = body;

        const caller = await authenticateUser(db, from_user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        if (!target_user_id || target_user_id === from_user_id) {
          return errorResponse("Invalid target user", 400);
        }

        const target = await db
          .prepare("SELECT id, username, discriminator, tag, avatar_url FROM nutsty_users WHERE id = ?")
          .bind(target_user_id)
          .first();
        if (!target) return errorResponse("Target user not found", 404);

        const u1 = from_user_id < target_user_id ? from_user_id : target_user_id;
        const u2 = from_user_id < target_user_id ? target_user_id : from_user_id;

        const existing = await db
          .prepare("SELECT * FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?")
          .bind(u1, u2)
          .first();

        const now = Date.now();

        if (existing) {
          if (existing.status === "accepted") {
            return jsonResponse({ success: true, message: "Already friends", status: "accepted" });
          }
          if (existing.status === "pending") {
            if (existing.initiated_by === from_user_id) {
              return jsonResponse({ success: true, message: "Friend request already sent", status: "pending" });
            } else {
              // Mutual request auto-accepts
              await db
                .prepare("UPDATE nutsty_friendships SET status = 'accepted', updated_at = ? WHERE id = ?")
                .bind(now, existing.id)
                .run();

              // Send event to target
              const eventId = "evt_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
              await db
                .prepare(
                  `INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at)
                   VALUES (?, ?, ?, 'friend_accepted', ?, 0, ?)`
                )
                .bind(
                  eventId,
                  target_user_id,
                  from_user_id,
                  JSON.stringify({
                    id: caller.id,
                    username: caller.username,
                    discriminator: caller.discriminator,
                    tag: caller.tag,
                    avatar_url: caller.avatar_url,
                  }),
                  now
                )
                .run();

              return jsonResponse({ success: true, message: "Friend request accepted", status: "accepted" });
            }
          }
        }

        // Create new pending friendship
        const relId = "rel_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        await db
          .prepare(
            `INSERT INTO nutsty_friendships (id, user_id_1, user_id_2, status, initiated_by, created_at, updated_at)
             VALUES (?, ?, ?, 'pending', ?, ?, ?)
             ON CONFLICT(user_id_1, user_id_2) DO UPDATE SET status = 'pending', initiated_by = ?, updated_at = ?`
          )
          .bind(relId, u1, u2, from_user_id, now, now, from_user_id, now)
          .run();

        // Queue event for target user
        const eventId = "evt_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        await db
          .prepare(
            `INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at)
             VALUES (?, ?, ?, 'friend_request', ?, 0, ?)`
          )
          .bind(
            eventId,
            target_user_id,
            from_user_id,
            JSON.stringify({
              id: caller.id,
              username: caller.username,
              discriminator: caller.discriminator,
              tag: caller.tag,
              avatar_url: caller.avatar_url,
            }),
            now
          )
          .run();

        return jsonResponse({
          success: true,
          message: "Friend request sent",
          status: "pending",
        });
      }

      // 5. RESPOND TO FRIEND REQUEST (Accept or Reject)
      if (path === "/api/friends/respond" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, from_user_id, action } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        const u1 = user_id < from_user_id ? user_id : from_user_id;
        const u2 = user_id < from_user_id ? from_user_id : user_id;

        const rel = await db
          .prepare("SELECT * FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?")
          .bind(u1, u2)
          .first();

        if (!rel) return errorResponse("No friendship relation found", 404);

        const now = Date.now();

        if (action === "accept") {
          await db
            .prepare("UPDATE nutsty_friendships SET status = 'accepted', updated_at = ? WHERE id = ?")
            .bind(now, rel.id)
            .run();

          // Notify sender
          const eventId = "evt_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
          await db
            .prepare(
              `INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at)
               VALUES (?, ?, ?, 'friend_accepted', ?, 0, ?)`
            )
            .bind(
              eventId,
              from_user_id,
              user_id,
              JSON.stringify({
                id: caller.id,
                username: caller.username,
                discriminator: caller.discriminator,
                tag: caller.tag,
                avatar_url: caller.avatar_url,
              }),
              now
            )
            .run();

          return jsonResponse({ success: true, status: "accepted" });
        } else {
          // Reject: remove relationship
          await db
            .prepare("DELETE FROM nutsty_friendships WHERE id = ?")
            .bind(rel.id)
            .run();

          return jsonResponse({ success: true, status: "rejected" });
        }
      }

      // 6. REMOVE FRIEND
      if (path === "/api/friends/remove" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, target_user_id } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        const u1 = user_id < target_user_id ? user_id : target_user_id;
        const u2 = user_id < target_user_id ? target_user_id : user_id;

        await db
          .prepare("DELETE FROM nutsty_friendships WHERE user_id_1 = ? AND user_id_2 = ?")
          .bind(u1, u2)
          .run();

        const now = Date.now();
        const eventId = "evt_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        await db
          .prepare(
            `INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at)
             VALUES (?, ?, ?, 'friend_removed', ?, 0, ?)`
          )
          .bind(eventId, target_user_id, user_id, JSON.stringify({ user_id }), now)
          .run();

        return jsonResponse({ success: true, message: "Friend removed" });
      }

      // 7. GET FRIENDS & INCOMING REQUESTS
      if (path === "/api/friends" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const secretKey = url.searchParams.get("secret_key");

        const caller = await authenticateUser(db, userId, secretKey);
        if (!caller) return errorResponse("Unauthorized", 401);

        // Fetch accepted friends
        const friendsQuery = await db
          .prepare(
            `SELECT u.id, u.username, u.discriminator, u.tag, u.avatar_url, u.now_playing, u.last_active_at, f.created_at as friendship_created_at
             FROM nutsty_friendships f
             JOIN nutsty_users u ON u.id = CASE WHEN f.user_id_1 = ? THEN f.user_id_2 ELSE f.user_id_1 END
             WHERE (f.user_id_1 = ? OR f.user_id_2 = ?) AND f.status = 'accepted'
             ORDER BY u.last_active_at DESC`
          )
          .bind(userId, userId, userId)
          .all();

        // Fetch incoming pending requests
        const requestsQuery = await db
          .prepare(
            `SELECT u.id, u.username, u.discriminator, u.tag, u.avatar_url, f.created_at as requested_at
             FROM nutsty_friendships f
             JOIN nutsty_users u ON u.id = f.initiated_by
             WHERE (f.user_id_1 = ? OR f.user_id_2 = ?) AND f.status = 'pending' AND f.initiated_by != ?
             ORDER BY f.created_at DESC`
          )
          .bind(userId, userId, userId)
          .all();

        const now = Date.now();
        const ONLINE_THRESHOLD_MS = 25000;
        const processedFriends = (friendsQuery.results || []).map((u) => {
          const isOnline = (now - (u.last_active_at || 0)) < ONLINE_THRESHOLD_MS;
          let npVal = "";
          if (isOnline && u.now_playing) {
            try {
              if (typeof u.now_playing === "string" && u.now_playing.trim().startsWith("{")) {
                npVal = JSON.parse(u.now_playing);
              } else {
                npVal = u.now_playing;
              }
            } catch (_) {
              npVal = u.now_playing;
            }
          }
          return {
            ...u,
            is_online: isOnline,
            now_playing: npVal,
          };
        });

        return jsonResponse({
          success: true,
          friends: processedFriends,
          incoming_requests: requestsQuery.results || [],
        });
      }

      // 8. GET REALTIME EVENTS
      if (path === "/api/events" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const secretKey = url.searchParams.get("secret_key");

        const caller = await authenticateUser(db, userId, secretKey);
        if (!caller) return errorResponse("Unauthorized", 401);

        const events = await db
          .prepare(
            "SELECT id, to_user_id, from_user_id, event_type, payload, created_at FROM nutsty_events WHERE to_user_id = ? AND consumed = 0 ORDER BY created_at ASC"
          )
          .bind(userId)
          .all();

        const list = events.results || [];
        if (list.length > 0) {
          await db
            .prepare("UPDATE nutsty_events SET consumed = 1 WHERE to_user_id = ? AND consumed = 0")
            .bind(userId)
            .run();
        }

        const parsedEvents = list.map((e) => {
          let payloadObj = null;
          try {
            payloadObj = JSON.parse(e.payload);
          } catch (_) {
            payloadObj = e.payload;
          }
          return {
            id: e.id,
            from_user_id: e.from_user_id,
            event_type: e.event_type,
            payload: payloadObj,
            created_at: e.created_at,
          };
        });

        return jsonResponse({ success: true, events: parsedEvents });
      }

      // 9. UPDATE PRESENCE (Now Playing)
      if ((path === "/api/users/presence" || path === "/api/now_playing") && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, now_playing } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        const now = Date.now();
        const nowPlayingStr = typeof now_playing === "object" ? JSON.stringify(now_playing) : String(now_playing || "");

        await db
          .prepare("UPDATE nutsty_users SET now_playing = ?, last_active_at = ? WHERE id = ?")
          .bind(nowPlayingStr, now, user_id)
          .run();

        return jsonResponse({ success: true });
      }

      // 9b. SET OFFLINE (Disconnect signal)
      if (path === "/api/users/offline" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        await db
          .prepare("UPDATE nutsty_users SET now_playing = '', last_active_at = 0 WHERE id = ?")
          .bind(user_id)
          .run();

        return jsonResponse({ success: true, message: "User is now offline" });
      }

      // 10. POST 24H NOTE
      if (path === "/api/notes" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, note_text, track, now_playing } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        const cleanText = (note_text || "").trim().slice(0, 80);
        let trackObj = track;
        if (typeof track === "object" && track !== null) {
          if (!track.title && !track.name && !track.id) {
            trackObj = null;
          }
        } else {
          trackObj = null;
        }

        if (!cleanText && !trackObj) {
          return errorResponse("Either text or track is required", 400);
        }

        const now = Date.now();
        const ttl = 86400 * 1000;
        const expiresAt = now + ttl;
        const noteId = "nte_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        const trackJson = trackObj ? JSON.stringify(trackObj) : "";
        const nowPlayingStr = now_playing ? (typeof now_playing === "object" ? JSON.stringify(now_playing) : String(now_playing)) : "";

        await db
          .prepare(
            `INSERT INTO nutsty_notes (id, user_id, tag, username, avatar_url, note_text, track, now_playing, created_at, expires_at)
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
             ON CONFLICT(user_id) DO UPDATE SET
               tag = excluded.tag,
               username = excluded.username,
               avatar_url = excluded.avatar_url,
               note_text = excluded.note_text,
               track = excluded.track,
               now_playing = excluded.now_playing,
               created_at = excluded.created_at,
               expires_at = excluded.expires_at`
          )
          .bind(noteId, user_id, caller.tag, caller.username, caller.avatar_url || "", cleanText, trackJson, nowPlayingStr, now, expiresAt)
          .run();

        const accentColor = (trackObj && trackObj.accent_color)
          || (now_playing && typeof now_playing === "object" && now_playing.accent_color)
          || (caller.now_playing && typeof caller.now_playing === "object" && caller.now_playing.accent_color)
          || "";

        const savedNote = {
          id: noteId,
          user_id: user_id,
          user_email: caller.tag.toLowerCase(),
          tag: caller.tag,
          user_name: caller.username,
          avatar_url: caller.avatar_url || "",
          note_text: cleanText,
          track: trackObj,
          now_playing: now_playing || caller.now_playing || "",
          accent_color: accentColor,
          created_at: new Date(now).toISOString(),
          expires_at: new Date(expiresAt).toISOString(),
          _expires_ts: expiresAt / 1000,
        };

        return jsonResponse({ success: true, note: savedNote });
      }

      // 11. GET 24H NOTES (Friends & My Note)
      if (path === "/api/notes" && request.method === "GET") {
        const userId = url.searchParams.get("user_id");
        const secretKey = url.searchParams.get("secret_key");

        const caller = await authenticateUser(db, userId, secretKey);
        if (!caller) return errorResponse("Unauthorized", 401);

        const now = Date.now();

        // 1. Fetch caller's active note
        const myNoteRow = await db
          .prepare("SELECT * FROM nutsty_notes WHERE user_id = ? AND expires_at > ?")
          .bind(userId, now)
          .first();

        let myNote = null;
        if (myNoteRow) {
          let parsedTrack = null;
          try {
            parsedTrack = myNoteRow.track ? JSON.parse(myNoteRow.track) : null;
          } catch (_) {}
          let myNp = myNoteRow.now_playing || caller.now_playing || "";
          try {
            if (typeof myNp === "string" && myNp.trim().startsWith("{")) {
              myNp = JSON.parse(myNp);
            }
          } catch (_) {}
          const noteAccent = (parsedTrack && parsedTrack.accent_color)
            || (myNp && typeof myNp === "object" && myNp.accent_color)
            || "";
          myNote = {
            id: myNoteRow.id,
            user_id: myNoteRow.user_id,
            user_email: myNoteRow.tag.toLowerCase(),
            tag: myNoteRow.tag,
            user_name: myNoteRow.username,
            avatar_url: myNoteRow.avatar_url,
            note_text: myNoteRow.note_text,
            track: parsedTrack,
            now_playing: myNp,
            accent_color: noteAccent,
            created_at: new Date(myNoteRow.created_at).toISOString(),
            expires_at: new Date(myNoteRow.expires_at).toISOString(),
            _expires_ts: myNoteRow.expires_at / 1000,
          };
        }

        // 2. Fetch accepted friends and their notes
        const friendsWithNotes = await db
          .prepare(
            `SELECT u.id as user_id, u.username, u.discriminator, u.tag, u.avatar_url, u.now_playing, u.last_active_at,
                    n.id as note_id, n.note_text, n.track as note_track, n.created_at as note_created_at, n.expires_at as note_expires_at
             FROM nutsty_friendships f
             JOIN nutsty_users u ON u.id = CASE WHEN f.user_id_1 = ? THEN f.user_id_2 ELSE f.user_id_1 END
             LEFT JOIN nutsty_notes n ON n.user_id = u.id AND n.expires_at > ?
             WHERE (f.user_id_1 = ? OR f.user_id_2 = ?) AND f.status = 'accepted'
             ORDER BY u.last_active_at DESC`
          )
          .bind(userId, now, userId, userId)
          .all();

        const ONLINE_THRESHOLD_MS = 25000;
        const notesList = (friendsWithNotes.results || []).map((row) => {
          let trk = null;
          if (row.note_track) {
            try {
              trk = JSON.parse(row.note_track);
            } catch (_) {}
          }
          const isOnline = (now - (row.last_active_at || 0)) < ONLINE_THRESHOLD_MS;
          let npVal = "";
          if (isOnline && row.now_playing) {
            try {
              if (typeof row.now_playing === "string" && row.now_playing.trim().startsWith("{")) {
                npVal = JSON.parse(row.now_playing);
              } else {
                npVal = row.now_playing;
              }
            } catch (_) {
              npVal = row.now_playing;
            }
          }
          return {
            user_id: row.user_id,
            user_email: row.tag ? row.tag.toLowerCase() : "",
            user_name: row.username,
            avatar_url: row.avatar_url || "",
            tag: row.tag,
            note_text: row.note_text || "",
            track: trk,
            created_at: row.note_created_at ? new Date(row.note_created_at).toISOString() : 0,
            is_friend: true,
            is_online: isOnline,
            last_active_at: row.last_active_at || 0,
            now_playing: npVal,
          };
        });

        return jsonResponse({
          success: true,
          count: notesList.length,
          notes: notesList,
          my_note: myNote,
        });
      }

      // 12. DELETE 24H NOTE
      if (path === "/api/notes/delete" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        await db.prepare("DELETE FROM nutsty_notes WHERE user_id = ?").bind(user_id).run();
        return jsonResponse({ success: true });
      }

      // 13. POST SOCIAL EVENT (Danmaku, reactions, suggestions)
      if (path === "/api/notes/events" && request.method === "POST") {
        const body = await request.json().catch(() => ({}));
        const { user_id, secret_key, event, to_user_id, to_tag, data } = body;

        const caller = await authenticateUser(db, user_id, secret_key);
        if (!caller) return errorResponse("Unauthorized", 401);

        let targetId = to_user_id;
        if (!targetId && to_tag) {
          const t = await db.prepare("SELECT id FROM nutsty_users WHERE LOWER(tag) = LOWER(?)").bind(to_tag).first();
          if (t) targetId = t.id;
        }

        if (!targetId) return errorResponse("Recipient user_id or tag required", 400);

        const eventId = "evt_" + crypto.randomUUID().replace(/-/g, "").slice(0, 16);
        const now = Date.now();
        const payloadStr = JSON.stringify({
          from_id: caller.id,
          from_name: caller.username,
          from_tag: caller.tag,
          from_avatar: caller.avatar_url || "",
          data: data,
        });

        await db
          .prepare(
            `INSERT INTO nutsty_events (id, to_user_id, from_user_id, event_type, payload, consumed, created_at)
             VALUES (?, ?, ?, ?, ?, 0, ?)`
          )
          .bind(eventId, targetId, user_id, event || "chat_bubble", payloadStr, now)
          .run();

        return jsonResponse({ success: true, event_id: eventId });
      }

      return errorResponse("Endpoint not found", 404);
    } catch (err) {
      return errorResponse(err.message || "Internal Server Error", 500);
    }
  },
};
