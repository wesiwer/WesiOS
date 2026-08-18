// Row-level synchronization policy for file access metadata.
//
// Files themselves are never synchronized here. These rows describe requests,
// grants and handover history and therefore contain permission-sensitive data.

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

function hasAudio(ctx) {
  return ctx.isOwner || ctx.modules.indexOf("audio") >= 0;
}

function manager(ctx) {
  return ctx.isOwner || ctx.canManageTeam === true;
}

function visible(ctx, collection, row) {
  if (!row) return false;
  if (manager(ctx)) return true;
  const p = payloadOf(row);
  const me = String(ctx.employeeId || "");

  if (collection === "file_requests") {
    const requester = String(p.requesterId || "");
    const holder = String(p.holderId || "");
    return requester === me || holder === me || holder === "";
  }
  if (collection === "file_grants") {
    return String(p.employeeId || "") === me || String(p.grantedBy || "") === me;
  }
  if (collection === "file_handovers") {
    return String(p.fromEmployeeId || "") === me || String(p.toEmployeeId || "") === me;
  }
  return false;
}

function read(e, collection) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!hasAudio(ctx)) return e.json(200, {items: []});

  const rows = require(`${__hooks}/wesi_sync_data_access.js`).records(
    e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll}",
    "id",
    0,
    0,
    {owner: ctx.ownerId, coll: collection},
  );

  const items = [];
  for (const row of rows) {
    if (!visible(ctx, collection, row)) continue;
    items.push({
      rid: row.getString("rid"),
      payload: payloadOf(row),
      stamp: row.getString("stamp"),
      deleted: row.getBool("deleted"),
    });
  }
  return e.json(200, {items: items});
}

function bad(message) { throw new BadRequestError(message); }
function forbidden(message) { throw new ForbiddenError(message); }

function authorizeRequest(txApp, existing, input, ctx) {
  const me = String(ctx.employeeId || "");
  const before = payloadOf(existing);
  const target = input.deleted ? before : input.payload;

  if (!existing) {
    if (input.deleted) bad("Нельзя удалить отсутствующий запрос файла");
    if (String(target.requesterId || "") !== me && !manager(ctx)) {
      forbidden("Нельзя создать запрос от имени другого сотрудника");
    }
    if (!manager(ctx)) {
      input.payload = Object.assign({}, input.payload, {requesterId: me});
    }
    return;
  }

  if (manager(ctx)) return;
  const requester = String(before.requesterId || "");
  const holder = String(before.holderId || "");
  if (requester !== me && holder !== me && holder !== "") {
    forbidden("Нет права изменять этот запрос файла");
  }

  if (!input.deleted) {
    input.payload = Object.assign({}, input.payload, {
      id: before.id,
      subjectKind: before.subjectKind,
      subjectId: before.subjectId,
      fileKind: before.fileKind,
      attachmentId: before.attachmentId,
      requesterId: before.requesterId,
      holderId: before.holderId,
      createdAt: before.createdAt,
    });
  }
}

function authorizeGrant(txApp, existing, input, ctx) {
  if (!manager(ctx)) forbidden("Изменять доступ к файлам может владелец или менеджер");
  if (input.deleted && !existing) bad("Нельзя удалить отсутствующий доступ к файлу");
}

function authorizeHandover(txApp, existing, input, ctx) {
  if (input.deleted) bad("Журнал выдачи файлов нельзя удалять");
  if (existing) return;
  if (manager(ctx)) return;
  const from = String(input.payload.fromEmployeeId || "");
  if (from !== String(ctx.employeeId || "")) {
    forbidden("Нельзя записать выдачу файла от имени другого сотрудника");
  }
}

function write(e, collection) {
  const requestCtx = e.get("wesiSyncContext");
  if (!requestCtx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!hasAudio(requestCtx)) forbidden("Раздел Audio не открыт этому сотруднику");

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) bad("Некорректный id file sync");
  const incoming = body.payload && typeof body.payload === "object" &&
      !Array.isArray(body.payload) ? body.payload : {};
  if (incoming.id != null && String(incoming.id) !== rid) {
    bad("id file sync не совпадает с rid");
  }

  const deleted = body.deleted === true;
  const parsed = Date.parse(String(body.stamp || ""));
  const now = Date.now();
  const stamp = Number.isFinite(parsed) && parsed <= now + 5 * 60 * 1000
    ? new Date(parsed).toISOString()
    : new Date(now).toISOString();

  const authorize = collection === "file_requests"
    ? function(txApp, existing, input) {
        const ctx = require(`${__hooks}/wesi_sync_authz.js`).refresh(txApp, requestCtx);
        if (!hasAudio(ctx)) forbidden("Раздел Audio больше не открыт этому сотруднику");
        authorizeRequest(txApp, existing, input, ctx);
      }
    : collection === "file_grants"
      ? function(txApp, existing, input) {
          const ctx = require(`${__hooks}/wesi_sync_authz.js`).refresh(txApp, requestCtx);
          if (!hasAudio(ctx)) forbidden("Раздел Audio больше не открыт этому сотруднику");
          authorizeGrant(txApp, existing, input, ctx);
        }
      : function(txApp, existing, input) {
          const ctx = require(`${__hooks}/wesi_sync_authz.js`).refresh(txApp, requestCtx);
          if (!hasAudio(ctx)) forbidden("Раздел Audio больше не открыт этому сотруднику");
          authorizeHandover(txApp, existing, input, ctx);
        };

  const result = require(`${__hooks}/wesi_sync_atomic.js`).commit(e.app, {
    owner: requestCtx.ownerId,
    org: "wesi-inc",
    coll: collection,
    rid: rid,
    payload: incoming,
    stamp: stamp,
    deleted: deleted,
    authorize: authorize,
  });

  return e.json(200, {
    ok: true,
    rid: rid,
    stamp: result.stamp,
    applied: result.applied,
    reason: result.reason,
  });
}

module.exports = {
  read,
  write,
  visible,
  authorizeRequest,
  authorizeGrant,
  authorizeHandover,
};