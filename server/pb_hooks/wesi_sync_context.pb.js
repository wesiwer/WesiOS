/// WesiOS company-wide synchronization gateway.
///
/// Built-in PocketBase record routes stay owner-only. This gateway is the
/// only place where an employee account can read/write company data and it
/// applies module, organization and row-level policy before returning rows.
/// Private profile/Shield/Vault collections are scoped to the authenticated
/// account instead of the company owner.

routerUse((e) => {
  const path = String(e.request.url.path || "");
  if (!path.startsWith("/api/wesi/sync/")) return e.next();
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

  const sid = String(e.request.header.get("X-WesiOS-Session") || "").trim();
  if (!/^[A-Za-z0-9_-]{24,96}$/.test(sid)) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }
  let session = null;
  try {
    session = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner='__wesios_security__' && coll='security' && rid={:rid} && deleted=false",
      {"rid": "session:" + sid},
    );
  } catch (_) { session = null; }
  if (!session) throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  const sessionPayload = payloadOf(session);
  const expiresAt = Date.parse(String(sessionPayload.expiresAt || ""));
  if (String(sessionPayload.userId || "") !== e.auth.id ||
      String(sessionPayload.revokedAt || "") ||
      !Number.isFinite(expiresAt) || expiresAt <= Date.now()) {
    throw new UnauthorizedError("Сеанс WesiOS завершён. Войдите заново");
  }

  let ownerMarker = null;
  try {
    ownerMarker = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='system' && rid='portal-owner' && deleted=false",
      {"owner": e.auth.id},
    );
  } catch (_) { ownerMarker = null; }

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
    let link = null;
    try {
      link = e.app.findFirstRecordByFilter(
        "wesios_records",
        "coll='system' && rid={:rid} && deleted=false",
        {"rid": "portal-account:" + e.auth.id},
      );
    } catch (_) { link = null; }
    if (!link) throw new ForbiddenError("Учётная запись не привязана к сотруднику WesiOS");
    const linkPayload = payloadOf(link);
    ownerId = link.getString("owner");
    employeeId = String(linkPayload.employeeId || "");
    if (!ownerId || !employeeId) throw new ForbiddenError("Привязка сотрудника повреждена");

    let employee = null;
    try {
      employee = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
        {"owner": ownerId, "rid": employeeId},
      );
    } catch (_) { employee = null; }
    snapshot = employee ? payloadOf(employee) :
      (linkPayload.snapshot && typeof linkPayload.snapshot === "object"
        ? linkPayload.snapshot : linkPayload);
  }

  const permissions = snapshot.permissions && typeof snapshot.permissions === "object"
    ? snapshot.permissions : {};
  const modules = Array.isArray(permissions.modules) ? permissions.modules.map(String) : [];
  const knowledgeIds = Array.isArray(permissions.knowledgeIds)
    ? permissions.knowledgeIds.map(String) : [];

  let organizations = [];
  let grants = [];
  try {
    organizations = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll='organizations' && deleted=false",
      "id", 0, 0, {"owner": ownerId},
    );
  } catch (_) { organizations = []; }
  try {
    grants = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll='organization_grants' && deleted=false",
      "id", 0, 0, {"owner": ownerId},
    );
  } catch (_) { grants = []; }

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
    // Ancestors are structural metadata required to validate/render a granted
    // child organization; granting them here does not grant finance rights.
    for (const id of Object.keys(allowedOrgIds)) {
      let cursor = orgParents[id];
      while (cursor) {
        allowedOrgIds[cursor] = true;
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
    "orgParents": orgParents,
    "ownGrants": ownGrants
  });
  return e.next();
});
