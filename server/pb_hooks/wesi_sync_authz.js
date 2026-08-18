// Rebuild WesiOS authorization context inside a writer transaction.
//
// Request middleware produces a fast context snapshot for reads/preflight, but
// an owner may revoke modules or organization grants while a long POST is
// waiting. Write authorization therefore must re-read employee permissions,
// organizations and grants through txApp immediately before save.

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

function ownerContext(base) {
  return Object.assign({}, base, {
    isOwner: true,
    modules: [
      "treasury", "forecast", "sandbox", "analytics", "tasks", "calendar",
      "knowledge", "contacts", "chats", "shield", "keys", "crm", "ai",
      "audio", "roadmap", "sysadmin"
    ],
    knowledgeIds: [], knowledgeAll: true, canManageTeam: true,
    canSeeOthersStats: true, canSeeNotes: true, canAssignTasks: true,
  });
}

function refresh(txApp, base) {
  if (!base) throw new UnauthorizedError("Нет контекста синхронизации");
  if (base.isOwner) {
    const organizations = require(`${__hooks}/wesi_sync_data_access.js`).records(
      txApp, "wesios_records",
      "owner={:owner} && coll='organizations' && deleted=false", "id", 0, 0,
      {owner: base.ownerId},
    );
    const allowed = {};
    const parents = {};
    for (const row of organizations) {
      const p = payloadOf(row);
      const id = String(p.id || row.getString("rid") || "");
      if (!id) continue;
      allowed[id] = true;
      parents[id] = p.parentId == null || String(p.parentId || "") === ""
        ? null : String(p.parentId);
    }
    return Object.assign(ownerContext(base), {
      allowedOrgIds: allowed,
      structuralOrgIds: Object.assign({}, allowed),
      orgParents: parents,
      ownGrants: [],
    });
  }

  const employee = require(`${__hooks}/wesi_sync_data_access.js`).first(
    txApp,
    "wesios_records",
    "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
    {owner: base.ownerId, rid: base.employeeId},
  );
  if (!employee) {
    throw new UnauthorizedError("Сотрудник деактивирован или удалён");
  }

  const snapshot = payloadOf(employee);
  const permissions = snapshot.permissions && typeof snapshot.permissions === "object"
    ? snapshot.permissions : {};
  const modules = Array.isArray(permissions.modules) ? permissions.modules.map(String) : [];
  const knowledgeIds = Array.isArray(permissions.knowledgeIds)
    ? permissions.knowledgeIds.map(String) : [];

  const access = require(`${__hooks}/wesi_sync_data_access.js`);
  const organizations = access.records(
    txApp, "wesios_records",
    "owner={:owner} && coll='organizations' && deleted=false", "id", 0, 0,
    {owner: base.ownerId},
  );
  const grants = access.records(
    txApp, "wesios_records",
    "owner={:owner} && coll='organization_grants' && deleted=false", "id", 0, 0,
    {owner: base.ownerId},
  );

  const orgParents = {};
  const allOrgIds = {};
  for (const row of organizations) {
    const p = payloadOf(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id) continue;
    allOrgIds[id] = true;
    orgParents[id] = p.parentId == null || String(p.parentId || "") === ""
      ? null : String(p.parentId);
  }

  const ownGrants = [];
  for (const row of grants) {
    const p = payloadOf(row);
    if (String(p.employeeId || "") === String(base.employeeId || "")) ownGrants.push(p);
  }

  const allowedOrgIds = {};
  for (const g of ownGrants) {
    const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
    if (perms.indexOf("view") < 0) continue;
    const id = String(g.organizationId || "");
    if (id) allowedOrgIds[id] = true;
  }
  for (const id of Object.keys(allOrgIds)) {
    if (allowedOrgIds[id]) continue;
    let cursor = orgParents[id];
    while (cursor) {
      const grant = ownGrants.find((g) =>
        String(g.organizationId || "") === cursor &&
        g.includeSubtree === true &&
        Array.isArray(g.permissions) &&
        g.permissions.map(String).indexOf("view") >= 0
      );
      if (grant) {
        allowedOrgIds[id] = true;
        break;
      }
      cursor = orgParents[cursor];
    }
  }

  const structuralOrgIds = {};
  for (const id of Object.keys(allowedOrgIds)) structuralOrgIds[id] = true;
  for (const id of Object.keys(allowedOrgIds)) {
    let cursor = orgParents[id];
    while (cursor) {
      structuralOrgIds[cursor] = true;
      cursor = orgParents[cursor];
    }
  }

  return Object.assign({}, base, {
    permissions,
    modules,
    knowledgeIds,
    knowledgeAll: permissions.knowledgeAll === true,
    canManageTeam: permissions.canManageTeam === true,
    canSeeOthersStats: permissions.canSeeOthersStats === true,
    canSeeNotes: permissions.canSeeNotes === true,
    canAssignTasks: permissions.canAssignTasks === true,
    allowedOrgIds,
    structuralOrgIds,
    orgParents,
    ownGrants,
  });
}

module.exports = {refresh, payloadOf};