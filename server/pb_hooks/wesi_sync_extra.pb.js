/// Synchronization additions introduced by the full cross-device audit.
///
/// Kept as explicit routes instead of widening the legacy dynamic gateway so
/// older clients keep their exact contract. Static routes take precedence over
/// /api/wesi/sync/{collection} and still pass through wesi_sync_context.pb.js.

const wesiSyncExtraPayload = (record) => {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" ? parsed : {};
    }
  } catch (_) {}
  return {};
};

const wesiSyncExtraRead = (e, collection, scope, requiredModule, privateKeyed) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  const moduleAllowed = !requiredModule || ctx.isOwner || (Array.isArray(requiredModule)
    ? requiredModule.some((name) => ctx.modules.indexOf(name) >= 0)
    : ctx.modules.indexOf(requiredModule) >= 0);
  if (!moduleAllowed) return e.json(200, {"items": []});
  const privateScope = scope === "private" || privateKeyed === true;
  const owner = privateScope ? e.auth.id : ctx.ownerId;
  let records = [];
  try {
    records = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll}",
      "id", 0, 0, {"owner": owner, "coll": collection},
    );
  } catch (_) { records = []; }
  return e.json(200, {
    "items": records.map((row) => ({
      "rid": row.getString("rid"),
      "payload": wesiSyncExtraPayload(row),
      "stamp": row.getString("stamp"),
      "deleted": row.getBool("deleted")
    }))
  });
};

const wesiSyncExtraWrite = (e, collection, scope, requiredModule, privateKeyed) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  const moduleAllowed = !requiredModule || ctx.isOwner || (Array.isArray(requiredModule)
    ? requiredModule.some((name) => ctx.modules.indexOf(name) >= 0)
    : ctx.modules.indexOf(requiredModule) >= 0);
  if (!moduleAllowed) throw new ForbiddenError("Раздел не открыт этому сотруднику");

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) throw new BadRequestError("Некорректный id синхронизации");
  let incoming = body.payload && typeof body.payload === "object" ? body.payload : {};
  const deleted = body.deleted === true;
  const suppliedStamp = Date.parse(String(body.stamp || ""));
  const now = Date.now();
  const stamp = Number.isFinite(suppliedStamp) && suppliedStamp <= now + 5 * 60 * 1000
    ? new Date(suppliedStamp).toISOString() : new Date(now).toISOString();

  if (incoming.id != null && String(incoming.id) !== rid) {
    throw new BadRequestError("id записи не совпадает с rid");
  }
  if (incoming.key != null) {
    const key = String(incoming.key);
    const expected = privateKeyed === true ? String(ctx.employeeId) + "::" + key : key;
    if (expected !== rid) throw new BadRequestError("key записи не совпадает с rid");
  }

  const privateScope = scope === "private" || privateKeyed === true;
  const owner = privateScope ? e.auth.id : ctx.ownerId;
  let existing = null;
  try {
    existing = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid}",
      {"owner": owner, "coll": collection, "rid": rid},
    );
  } catch (_) { existing = null; }

  // Tombstones keep the previous payload. This is required for deterministic
  // merge and prevents an empty delete record from losing its scope metadata.
  if (deleted && existing) incoming = wesiSyncExtraPayload(existing);

  const recordsCollection = e.app.findCollectionByNameOrId("wesios_records");
  const record = existing || new Record(recordsCollection);
  record.set("owner", owner);
  record.set("org", privateScope ? "private:" + ctx.employeeId : "wesi-inc");
  record.set("coll", collection);
  record.set("rid", rid);
  record.set("payload", incoming);
  record.set("stamp", stamp);
  record.set("deleted", deleted);
  e.app.save(record);
  return e.json(200, {"ok": true, "rid": rid, "stamp": stamp});
};

/// Server-owned revision. Conflict stamps stay client-logical timestamps, but
/// change detection must never depend on them: a valid mutation can carry an
/// older logical stamp than an unrelated record and would then be invisible to
/// already-open devices. PocketBase `updated` changes on every save.
routerAdd("GET", "/api/wesi/sync/revision-v2", (e) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  let rows = [];
  try {
    rows = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:company} || owner={:private}",
      "-updated,-id", 1, 0,
      {"company": ctx.ownerId, "private": e.auth.id},
    );
  } catch (_) { rows = []; }
  if (!rows.length) return e.json(200, {"revision": "empty"});
  const first = rows[0];
  return e.json(200, {
    "revision": String(first.id || "") + "|" + first.getString("updated")
  });
}, $apis.requireAuth("users"));

// Sandbox is intentionally private to the authenticated account: it models
// hypothetical money, not the company's real shared ledger.
routerAdd("GET", "/api/wesi/sync/sandbox_transactions", (e) =>
  wesiSyncExtraRead(e, "sandbox_transactions", "private", "sandbox"),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/sandbox_transactions", (e) =>
  wesiSyncExtraWrite(e, "sandbox_transactions", "private", "sandbox"),
  $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/what_if_presets", (e) =>
  wesiSyncExtraRead(e, "what_if_presets", "private", "sandbox"),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/what_if_presets", (e) =>
  wesiSyncExtraWrite(e, "what_if_presets", "private", "sandbox"),
  $apis.requireAuth("users"));

// Profile record id is `me`; company scope made every employee collide on the
// same rid. Exact route moves it to authenticated-account scope.
routerAdd("GET", "/api/wesi/sync/profile", (e) =>
  wesiSyncExtraRead(e, "profile", "private", null),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/profile", (e) =>
  wesiSyncExtraWrite(e, "profile", "private", null),
  $apis.requireAuth("users"));

// Shield settings are private too, but keyed rows use employee::key rids to
// preserve compatibility with the existing per-account local boxes.
routerAdd("GET", "/api/wesi/sync/shield_private", (e) =>
  wesiSyncExtraRead(e, "shield_private", "private", null, true),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/shield_private", (e) =>
  wesiSyncExtraWrite(e, "shield_private", "private", null, true),
  $apis.requireAuth("users"));

// Business state found by the second audit pass.
routerAdd("GET", "/api/wesi/sync/finance_categories", (e) =>
  wesiSyncExtraRead(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"]),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/finance_categories", (e) =>
  wesiSyncExtraWrite(e, "finance_categories", "company", ["treasury", "forecast", "sandbox", "analytics"]),
  $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/team_skills", (e) =>
  wesiSyncExtraRead(e, "team_skills", "company", ["contacts", "tasks"]),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/team_skills", (e) =>
  wesiSyncExtraWrite(e, "team_skills", "company", ["contacts", "tasks"]),
  $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/time_center", (e) =>
  wesiSyncExtraRead(e, "time_center", "private", null), $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/time_center", (e) =>
  wesiSyncExtraWrite(e, "time_center", "private", null), $apis.requireAuth("users"));

for (const name of ["horizon_predictions", "horizon_learning", "horizon_competition"]) {
  routerAdd("GET", "/api/wesi/sync/" + name, (e) =>
    wesiSyncExtraRead(e, name, "private", ["treasury", "forecast", "analytics"]),
    $apis.requireAuth("users"));
  routerAdd("POST", "/api/wesi/sync/" + name, (e) =>
    wesiSyncExtraWrite(e, name, "private", ["treasury", "forecast", "analytics"]),
    $apis.requireAuth("users"));
}

routerAdd("GET", "/api/wesi/sync/horizon_contracts", (e) =>
  wesiSyncExtraRead(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"]),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/horizon_contracts", (e) =>
  wesiSyncExtraWrite(e, "horizon_contracts", "private", ["audio", "forecast", "analytics"]),
  $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/task_ai_memory", (e) =>
  wesiSyncExtraRead(e, "task_ai_memory", "private", ["tasks", "ai"]),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/task_ai_memory", (e) =>
  wesiSyncExtraWrite(e, "task_ai_memory", "private", ["tasks", "ai"]),
  $apis.requireAuth("users"));

// Audio cards remain company-shared. Extended analysis/QC metadata belongs to
// the same shared Audio Vault, while device paths are stripped by the client.
routerAdd("GET", "/api/wesi/sync/audio_extras", (e) =>
  wesiSyncExtraRead(e, "audio_extras", "company", "audio"),
  $apis.requireAuth("users"));
routerAdd("POST", "/api/wesi/sync/audio_extras", (e) =>
  wesiSyncExtraWrite(e, "audio_extras", "company", "audio"),
  $apis.requireAuth("users"));
