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

function read(e, collection, scope, requiredModule, privateKeyed) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!moduleAllowed(ctx, requiredModule)) {
    return e.json(200, {items: []});
  }

  const privateScope = scope === "private" || privateKeyed === true;
  const owner = privateScope ? e.auth.id : ctx.ownerId;
  let records = [];
  records = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
      "wesios_records",
      "owner={:owner} && coll={:coll}",
      "id",
      0,
      0,
      {owner: owner, coll: collection},
    );

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

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) {
    throw new BadRequestError("Некорректный id синхронизации");
  }

  let incoming =
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
  let existing = null;
  existing = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid}",
      {owner: owner, coll: collection, rid: rid},
    );

  // Keep the previous payload on tombstones so scoped metadata is not lost.
  if (deleted && existing) incoming = payloadOf(existing);

  if (existing) {
    const decision = require(`${__hooks}/wesi_sync_lww.js`).decide(
      existing.getString("stamp"),
      existing.getBool("deleted"),
      stamp,
      deleted,
    );
    if (!decision.apply) {
      return e.json(200, {
        ok: true,
        rid: rid,
        stamp: existing.getString("stamp"),
        applied: false,
        reason: decision.reason,
      });
    }
  }

  const recordsCollection = e.app.findCollectionByNameOrId("wesios_records");
  const record = existing || new Record(recordsCollection);
  record.set("owner", owner);
  record.set(
    "org",
    privateScope ? "private:" + String(ctx.employeeId) : "wesi-inc",
  );
  record.set("coll", collection);
  record.set("rid", rid);
  record.set("payload", incoming);
  record.set("stamp", stamp);
  record.set("deleted", deleted);
  e.app.save(record);

  return e.json(200, {ok: true, rid: rid, stamp: stamp, applied: true});
}

function revision(e) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");

  // Do not derive a live change token from the single newest business row.
  // Two committed rows may have the same PocketBase `updated` timestamp and
  // leave that max-row token unchanged. The owner-scoped nonce marker is
  // touched by collection-level AfterSuccess hooks for EVERY wesios_records
  // writer, including Wesi AI server tools that bypass the HTTP sync gateway.
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
};
