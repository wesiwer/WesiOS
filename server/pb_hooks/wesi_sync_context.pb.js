/// WesiOS company-wide synchronization gateway.
///
/// Built-in PocketBase record routes stay owner-only. This gateway is the
/// only place where an employee account can read/write company data and it
/// applies module, organization and row-level policy before returning rows.
/// Private profile/Shield/Vault collections are scoped to the authenticated
/// account instead of the company owner.

routerUse((e) => {
  const path = String(e.request.url.path || "");
  // sync-v3 uses the same authorization context as the legacy sync gateway.
  // Without this prefix the v3 runtime sees no wesiSyncContext, returns 401,
  // and the client correctly interprets that as an ended session — which was
  // kicking a freshly OTP-authenticated user straight back to /login.
  const isSyncPath =
    path.startsWith("/api/wesi/sync/") ||
    path.startsWith("/api/wesi/sync-v3/");
  if (!isSyncPath) return e.next();
  if (!e.auth || e.hasSuperuserAuth()) {
    if (e.hasSuperuserAuth()) return e.next();
    throw new UnauthorizedError("Требуется вход WesiOS");
  }

  const payloadOf = (record) => {
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

  const sessionPayloadOf = (record) => {
    if (!record) return {};
    try {
      const model = new DynamicModel({
        "userId": "",
        "expiresAt": "",
        "revokedAt": "",
      });
      record.unmarshalJSONField("payload", model);
      return {
        "userId": String(model.userId || ""),
        "expiresAt": String(model.expiresAt || ""),
        "revokedAt": String(model.revokedAt || ""),
      };
    } catch (_) {
      return {};
    }
  };

  const sid = String(e.request.header.get("X-WesiOS-Session") || "").trim();
  if (!/^[A-Za-z0-9_-]{24,96}$/.test(sid)) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }
  const session = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
    "wesios_records",
    "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false",
    {"rid": "session:" + sid},
  );
  if (!session) throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  const sessionPayload = sessionPayloadOf(session);
  const expiresAt = Date.parse(String(sessionPayload.expiresAt || ""));
  if (String(sessionPayload.userId || "") !== e.auth.id ||
      String(sessionPayload.revokedAt || "") ||
      !Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }

  const ownerMarker = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
    "wesios_records",
    "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false",
    {"owner": e.auth.id},
  );

  let ownerId = "";
  let employeeId = "";
  let isOwner = false;
  let snapshot = {};
  if (ownerMarker) {
    ownerId = e.auth.id;
    employeeId = "owner";
    isOwner = true;
    snapshot = {
      "id": "owner",
      "permissions": {
        "modules": [
          "treasury", "forecast", "sandbox", "analytics", "tasks", "calendar",
          "knowledge", "contacts", "chats", "shield", "keys", "crm", "ai",
          "audio", "roadmap", "sysadmin"
        ],
        "knowledgeIds": [],
        "knowledgeAll": true,
        "canManageTeam": true,
        "canSeeOthersStats": true,
        "canSeeNotes": true,
        "canAssignTasks": true
      }
    };
  } else {
    const link = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
      "wesios_records",
      "coll='system' && rid={:rid} && deleted=false",
      {"rid": "portal-account:" + e.auth.id},
    );
    if (!link) throw new ForbiddenError("Учётная запись не привязана к сотруднику WesiOS");
    const linkPayload = payloadOf(link);
    ownerId = link.getString("owner");
    employeeId = String(linkPayload.employeeId || "");
    if (!ownerId || !employeeId) throw new ForbiddenError("Привязка сотрудника повреждена");

    const employee = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
      "wesios_records",
      "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
      {"owner": ownerId, "rid": employeeId},
    );
    // Never fall back to portal-account.snapshot for authorization. That
    // snapshot is historical/bootstrap metadata and can outlive deactivation.
    // A missing live employee row means the linked identity has no company
    // authorization anymore and must terminate the local sync session.
    if (!employee) {
      throw new UnauthorizedError("Сотрудник деактивирован или удалён. Войдите заново");
    }
    snapshot = payloadOf(employee);
  }

  const permissions = snapshot.permissions && typeof snapshot.permissions === "object"
    ? snapshot.permissions : {};
  const modules = Array.isArray(permissions.modules) ? permissions.modules.map(String) : [];
  const knowledgeIds = Array.isArray(permissions.knowledgeIds)
    ? permissions.knowledgeIds.map(String) : [];

  const organizations = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
    "wesios_records",
    "owner={:owner} && coll='organizations' && deleted=false",
    "id", 0, 0, {"owner": ownerId},
  );
  const grants = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
    "wesios_records",
    "owner={:owner} && coll='organization_grants' && deleted=false",
    "id", 0, 0, {"owner": ownerId},
  );

  const orgParents = {};
  const allOrgIds = {};
  for (const record of organizations) {
    const p = payloadOf(record);
    const id = String(p.id || record.getString("rid") || "");
    if (!id) continue;
    allOrgIds[id] = true;
    orgParents[id] = p.parentId == null || String(p.parentId || "") === ""
      ? null : String(p.parentId);
  }

  const ownGrants = [];
  for (const record of grants) {
    const p = payloadOf(record);
    if (isOwner || String(p.employeeId || "") === employeeId) ownGrants.push(p);
  }

  const allowedOrgIds = {};
  if (isOwner) {
    for (const id of Object.keys(allOrgIds)) allowedOrgIds[id] = true;
  } else {
    for (const g of ownGrants) {
      const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
      if (perms.indexOf("view") < 0) continue;
      const id = String(g.organizationId || "");
      if (id) allowedOrgIds[id] = true;
    }
    let changed = true;
    while (changed) {
      changed = false;
      for (const id of Object.keys(allOrgIds)) {
        if (allowedOrgIds[id]) continue;
        let cursor = orgParents[id];
        while (cursor) {
          const grant = ownGrants.find((g) =>
            String(g.organizationId || "") === cursor && g.includeSubtree === true &&
            Array.isArray(g.permissions) && g.permissions.map(String).indexOf("view") >= 0
          );
          if (grant) {
            allowedOrgIds[id] = true;
            changed = true;
            break;
          }
          cursor = orgParents[cursor];
        }
      }
    }
  }

  const structuralOrgIds = {};
  for (const id of Object.keys(allowedOrgIds)) structuralOrgIds[id] = true;
  if (!isOwner) {
    for (const id of Object.keys(allowedOrgIds)) {
      let cursor = orgParents[id];
      while (cursor) {
        structuralOrgIds[cursor] = true;
        cursor = orgParents[cursor];
      }
    }
  }

  e.set("wesiSyncContext", {
    "ownerId": ownerId,
    "employeeId": employeeId,
    "isOwner": isOwner,
    "permissions": permissions,
    "modules": modules,
    "knowledgeIds": knowledgeIds,
    "knowledgeAll": permissions.knowledgeAll === true,
    "canManageTeam": permissions.canManageTeam === true,
    "canSeeOthersStats": permissions.canSeeOthersStats === true,
    "canSeeNotes": permissions.canSeeNotes === true,
    "canAssignTasks": permissions.canAssignTasks === true,
    "allowedOrgIds": allowedOrgIds,
    "structuralOrgIds": structuralOrgIds,
    "orgParents": orgParents,
    "ownGrants": ownGrants
  });
  return e.next();
});

// Fast preflight message integrity guard. The exact same invariants are also
// repeated inside wesi_sync_generic_policy.js under the atomic transaction;
// keeping this layer gives modified clients an immediate error before opening
// a writer transaction, while transaction-time authorization closes TOCTOU.
routerUse((e) => {
  const path = String(e.request.url.path || "");
  const method = String(e.request.method || "").toUpperCase();
  if (path !== "/api/wesi/sync/messages" || method !== "POST") return e.next();

  const ctx = e.get("wesiSyncContext");
  if (!ctx || ctx.isOwner) return e.next();

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  const incoming = body.payload && typeof body.payload === "object" ? body.payload : {};
  const deleted = body.deleted === true;
  if (!rid) throw new BadRequestError("Некорректный id сообщения");

  const payloadOf = (record) => {
    if (!record) return {};
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };
  const mapOf = (value) => value && typeof value === "object" && !Array.isArray(value)
    ? value : {};
  const sameJson = (a, b) => JSON.stringify(a == null ? null : a) === JSON.stringify(b == null ? null : b);

  const existing = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
    "wesios_records",
    "owner={:owner} && coll='messages' && rid={:rid}",
    {"owner": ctx.ownerId, "rid": rid},
  );

  if (!existing) {
    if (String(incoming.authorId || "") !== ctx.employeeId) {
      throw new ForbiddenError("Нельзя отправлять сообщения от имени другого сотрудника");
    }
    const reactions = mapOf(incoming.reactions);
    for (const actorId of Object.keys(reactions)) {
      if (actorId !== ctx.employeeId) {
        throw new ForbiddenError("Нельзя создавать реакции от имени другого сотрудника");
      }
    }
    return e.next();
  }

  const before = payloadOf(existing);
  const beforeAuthor = String(before.authorId || "");
  if (String(incoming.authorId || beforeAuthor) !== beforeAuthor) {
    throw new ForbiddenError("Автор сообщения неизменяем");
  }
  if (String(incoming.chatId || before.chatId || "") !== String(before.chatId || "")) {
    throw new ForbiddenError("Нельзя перенести сообщение в другой чат");
  }

  const beforeReactions = mapOf(before.reactions);
  const incomingReactions = mapOf(incoming.reactions);
  const reactionActors = {};
  for (const id of Object.keys(beforeReactions)) reactionActors[id] = true;
  for (const id of Object.keys(incomingReactions)) reactionActors[id] = true;
  for (const actorId of Object.keys(reactionActors)) {
    if (actorId === ctx.employeeId) continue;
    if (String(beforeReactions[actorId] || "") !== String(incomingReactions[actorId] || "")) {
      throw new ForbiddenError("Нельзя менять реакцию другого сотрудника");
    }
  }

  if (beforeAuthor !== ctx.employeeId) {
    if (deleted) throw new ForbiddenError("Нельзя удалить чужое сообщение");
    const protectedFields = [
      "body", "kind", "at", "expiresAt", "archived", "replyTo", "editedAt", "attachment"
    ];
    for (const field of protectedFields) {
      if (!sameJson(incoming[field], before[field])) {
        throw new ForbiddenError("Нельзя изменять содержимое чужого сообщения");
      }
    }
  }

  return e.next();
});
