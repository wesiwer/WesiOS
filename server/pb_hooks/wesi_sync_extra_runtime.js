// Request-local runtime for the extended WesiOS sync routes.
//
// PocketBase may preserve already-registered route callbacks across a hot hook
// reload. Route callbacks therefore must not close over helpers declared in a
// .pb.js file. This module is required inside every request callback, so helper
// functions are resolved from the current file on disk for each request.

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed)
        ? parsed
        : {};
    }
  } catch (_) {}
  return {};
}

function moduleAllowed(ctx, requiredModule) {
  if (!requiredModule || ctx.isOwner) return true;
  if (Array.isArray(requiredModule)) {
    return requiredModule.some(function(moduleName) {
      return ctx.modules.indexOf(String(moduleName)) >= 0;
    });
  }
  return ctx.modules.indexOf(String(requiredModule)) >= 0;
}

function safeStamp(raw) {
  const parsed = Date.parse(String(raw || ""));
  const now = Date.now();
  if (!Number.isFinite(parsed)) return new Date(now).toISOString();
  return new Date(Math.min(parsed, now)).toISOString();
}

function legacyBytesToBase64(value) {
  if (typeof value === "string" && value.trim()) return value;
  if (value && typeof value === "object" &&
      typeof value.__wesios_bytes_v1 === "string") {
    return value.__wesios_bytes_v1;
  }
  return null;
}

function migrateLegacyProfilePrivate(e) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");

  const owner = String(e.auth.id || "");
  if (!owner) return;

  const access = require(`${__hooks}/wesi_sync_data_access.js`);
  const atomic = require(`${__hooks}/wesi_sync_atomic.js`);
  const legacy = access.records(
    e.app,
    "wesios_records",
    "owner={:owner} && coll='profile_private' && deleted=false",
    "id",
    0,
    0,
    {owner: owner},
  );
  if (!legacy.length) return;

  const profileKeys = {
    profile_name: "name",
    profile_email: "email",
    profile_gender: "gender",
    profile_country: "country",
    profile_birth: "birth",
    avatar_index: "avatarIndex",
    avatar_custom: "photo",
  };
  const shieldKeys = {
    shield_hash: true,
    shield_salt: true,
    shield_iterations: true,
    shield_scope: true,
    shield_timeout_minutes: true,
    shield_wipe_after: true,
    shield_password_hint: true,
  };

  const profilePayload = {};
  let profileStampMs = -1;
  let hasProfileValue = false;

  for (const row of legacy) {
    const old = payloadOf(row);
    const key = String(old.key || "");
    if (!key) continue;

    if (shieldKeys[key] === true) {
      const rid = String(ctx.employeeId) + "::" + key;
      atomic.createIfAbsent(e.app, {
        owner: owner,
        org: "private:" + String(ctx.employeeId),
        coll: "shield_private",
        rid: rid,
        payload: {key: key, value: old.value},
        stamp: safeStamp(row.getString("stamp")),
        deleted: false,
      });
    }

    const target = profileKeys[key];
    if (!target) continue;
    let value = old.value;
    if (target === "photo") value = legacyBytesToBase64(value);
    if (target === "avatarIndex") {
      const numeric = Number(value);
      value = Number.isFinite(numeric) ? Math.trunc(numeric) : 0;
    }
    if (value == null) continue;
    profilePayload[target] = value;
    hasProfileValue = true;
    const parsed = Date.parse(String(row.getString("stamp") || ""));
    if (Number.isFinite(parsed) && parsed > profileStampMs) profileStampMs = parsed;
  }

  if (!hasProfileValue) return;

  atomic.createIfAbsent(e.app, {
    owner: owner,
    org: "private:" + String(ctx.employeeId),
    coll: "profile",
    rid: "me",
    payload: profilePayload,
    stamp: safeStamp(
      profileStampMs >= 0 ? new Date(profileStampMs).toISOString() : null,
    ),
    deleted: false,
  });
}

function read(e, collection, scope, requiredModule, privateKeyed) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!moduleAllowed(ctx, requiredModule)) {
    return e.json(200, {items: []});
  }

  if (collection === "profile" || collection === "shield_private") {
    migrateLegacyProfilePrivate(e);
  }

  const privateScope = scope === "private" || privateKeyed === true;
  const owner = privateScope ? e.auth.id : ctx.ownerId;
  let records = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll}",
    "id",
    0,
    0,
    {owner: owner, coll: collection},
  );

  // Profile is a singleton channel. Historical malformed rows with another rid
  // must never be delivered into the same local ProfileService key.
  if (collection === "profile") {
    records = records.filter((row) => row.getString("rid") === "me");
  }

  return e.json(200, {
    items: records.map(function(row) {
      return {
        rid: row.getString("rid"),
        payload: payloadOf(row),
        stamp: row.getString("stamp"),
        deleted: row.getBool("deleted"),
      };
    }),
  });
}

function write(e, collection, scope, requiredModule, privateKeyed) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!moduleAllowed(ctx, requiredModule)) {
    throw new ForbiddenError("Раздел не открыт этому сотруднику");
  }

  if (collection === "profile" || collection === "shield_private") {
    migrateLegacyProfilePrivate(e);
  }

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) {
    throw new BadRequestError("Некорректный id синхронизации");
  }
  if (collection === "profile" && rid !== "me") {
    throw new BadRequestError("Профиль синхронизируется только как profile/me");
  }

  const incoming =
    body.payload && typeof body.payload === "object" && !Array.isArray(body.payload)
      ? body.payload
      : {};
  const deleted = body.deleted === true;
  const suppliedStamp = Date.parse(String(body.stamp || ""));
  const now = Date.now();
  const stamp =
    Number.isFinite(suppliedStamp) && suppliedStamp <= now + 5 * 60 * 1000
      ? new Date(suppliedStamp).toISOString()
      : new Date(now).toISOString();

  if (incoming.id != null && String(incoming.id) !== rid) {
    throw new BadRequestError("id записи не совпадает с rid");
  }
  if (incoming.key != null) {
    const key = String(incoming.key);
    const expected =
      privateKeyed === true ? String(ctx.employeeId) + "::" + key : key;
    if (expected !== rid) {
      throw new BadRequestError("key записи не совпадает с rid");
    }
  }

  const privateScope = scope === "private" || privateKeyed === true;
  const owner = privateScope ? e.auth.id : ctx.ownerId;
  const committed = require(`${__hooks}/wesi_sync_atomic.js`).commit(e.app, {
    owner: owner,
    org: privateScope ? "private:" + String(ctx.employeeId) : "wesi-inc",
    coll: collection,
    rid: rid,
    payload: incoming,
    stamp: stamp,
    deleted: deleted,
  });

  return e.json(200, {
    ok: true,
    rid: rid,
    stamp: committed.stamp,
    applied: committed.applied,
    reason: committed.reason,
  });
}

function revision(e) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");

  const value = require(`${__hooks}/wesi_sync_revision.js`).readForContext(
    e.app,
    ctx.ownerId,
    e.auth.id,
  );
  return e.json(200, {revision: value});
}

module.exports = {
  read: read,
  write: write,
  revision: revision,
  migrateLegacyProfilePrivate: migrateLegacyProfilePrivate,
};