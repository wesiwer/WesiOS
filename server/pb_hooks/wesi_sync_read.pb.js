routerAdd("GET", "/api/wesi/sync/revision", (e) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  let rows = [];
  rows = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
      "wesios_records",
      "owner={:company} || owner={:private}",
      "-stamp,-id", 1, 0,
      {"company": ctx.ownerId, "private": e.auth.id},
    );
  if (!rows.length) return e.json(200, {"revision": "empty"});
  const first = rows[0];
  return e.json(200, {
    "revision": String(first.id || "") + "|" + first.getString("stamp")
  });
}, $apis.requireAuth("users"));

routerAdd("GET", "/api/wesi/sync/{collection}", (e) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  const collection = String(e.request.pathValue("collection") || "");
  const privateCollections = {"profile": true, "profile_private": true, "vault_private": true};
  const known = {
    "organizations": true, "employees": true, "organization_grants": true,
    "accounts": true, "transactions": true, "tasks": true,
    "inter_org_transfers": true, "transaction_audit": true,
    "critical_audit": true, "calendar_events": true, "articles": true,
    "chats": true, "messages": true, "roadmap_state": true,
    "crm_state": true, "profile_private": true, "vault_private": true,
    "roadmap_projects": true, "roadmap_items": true,
    "crm_clients": true, "crm_deals": true, "crm_interactions": true,
    "audio_beats": true, "profile": true,
    "file_grants": true, "file_requests": true, "file_handovers": true
  };
  if (!known[collection]) throw new BadRequestError("Неизвестная коллекция синхронизации");

  // These collections require exact row-level policy handlers. Reaching the
  // generic gateway means the dedicated hook set is incomplete/old; fail
  // closed instead of returning company-wide sensitive rows.
  if (collection === "crm_clients" ||
      collection === "crm_deals" ||
      collection === "crm_interactions" ||
      collection === "file_requests" ||
      collection === "file_grants" ||
      collection === "file_handovers") {
    throw new ForbiddenError("Dedicated sync route is not available");
  }

  const hasModule = (name) => ctx.isOwner || ctx.modules.indexOf(name) >= 0;
  const hasAnyModule = (names) => ctx.isOwner || names.some((n) => ctx.modules.indexOf(n) >= 0);
  const moduleAllowed = () => {
    if (privateCollections[collection] || collection === "employees" ||
        collection === "organizations" || collection === "organization_grants" ||
        collection === "critical_audit") return true;
    if (["accounts", "transactions", "inter_org_transfers", "transaction_audit"].indexOf(collection) >= 0) {
      return hasAnyModule(["treasury", "forecast", "sandbox", "analytics"]);
    }
    const map = {
      "tasks": "tasks", "calendar_events": "calendar", "articles": "knowledge",
      "chats": "chats", "messages": "chats", "roadmap_state": "roadmap",
      "crm_state": "crm",
      "roadmap_projects": "roadmap", "roadmap_items": "roadmap",
      "audio_beats": "audio"
    };
    return map[collection] ? hasModule(map[collection]) : true;
  };
  if (!moduleAllowed()) return e.json(200, {"items": []});

  const payloadOf = (record) => {
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };

  // Organization rows have lived through several client schemas. The server
  // stores the original payload verbatim, so an old root row can otherwise be
  // returned forever with a missing/non-boolean isRoot, legacy timestamp keys
  // or a stale parentId. Current clients intentionally validate the tree
  // strictly and reject that row; every child is then deferred as well. Repair
  // only transport representation here. The stored business row is untouched.
  const normalizeOrganizationPayload = (payload, record) => {
    const p = Object.assign({}, payload && typeof payload === "object" ? payload : {});
    const id = String(p.id || record.getString("rid") || "");
    const stamp = String(record.getString("stamp") || new Date(0).toISOString());
    p.id = id;

    if (!p.createdAt) p.createdAt = String(p.created || p.updatedAt || p.updated || stamp);
    if (!p.updatedAt) p.updatedAt = String(p.updated || p.createdAt || stamp);
    if (!p.baseCurrency) p.baseCurrency = "RUB";
    if (!p.createdBy) p.createdBy = "sync-server";

    if (!p.status) {
      const rawArchived = p.archived;
      const archived = rawArchived === true || rawArchived === 1 ||
        String(rawArchived || "").trim().toLowerCase() === "true" ||
        String(rawArchived || "").trim() === "1";
      p.status = archived ? "archived" : "active";
    }

    if (id === "org_wesi_inc") {
      // The root identity is immutable across WesiOS versions. Canonicalise by
      // id instead of trusting legacy flags, and remove stale legacy parents.
      p.isRoot = true;
      p.parentId = null;
    } else {
      // No other organization may promote itself to a second root through an
      // old numeric/string flag.
      p.isRoot = false;
    }
    return p;
  };

  const orgIdOf = (p) => String(p.organizationId || p.orgId || "org_wesi_inc");
  const grantApplies = (orgId, permission) => {
    if (ctx.isOwner) return true;
    let cursor = orgId;
    let first = true;
    while (cursor) {
      for (const g of ctx.ownGrants) {
        if (String(g.organizationId || "") !== cursor) continue;
        if (!first && g.includeSubtree !== true) continue;
        const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
        if (perms.indexOf(permission) >= 0) return true;
      }
      first = false;
      cursor = ctx.orgParents[cursor];
    }
    return false;
  };
  const taskOwned = (p) => {
    if (ctx.isOwner || ctx.canManageTeam || ctx.canAssignTasks) return true;
    if (String(p.assignee || "") === ctx.employeeId) return true;
    if (String(p.responsibleEmployeeId || "") === ctx.employeeId) return true;
    const tags = Array.isArray(p.tags) ? p.tags.map(String) : [];
    return tags.indexOf("wesios:employee:" + ctx.employeeId) >= 0;
  };
  const chatVisible = (p) => {
    if (String(p.kind || "work") !== "work") return false;
    if (ctx.isOwner) return true;
    const participants = Array.isArray(p.participants) ? p.participants.map(String) : [];
    return participants.indexOf(ctx.employeeId) >= 0;
  };

  const ownerScope = privateCollections[collection] ? e.auth.id : ctx.ownerId;
  let records = [];
  records = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
      "wesios_records",
      "owner={:owner} && coll={:coll}",
      "id", 10000, 0, {"owner": ownerScope, "coll": collection},
    );

  const visibleChatIds = {};
  if (collection === "messages" && !ctx.isOwner) {
    let chats = [];
    chats = require(`${__hooks}/wesi_sync_data_access.js`).records(e.app,
        "wesios_records",
        "owner={:owner} && coll='chats' && deleted=false",
        "id", 10000, 0, {"owner": ctx.ownerId},
      );
    for (const row of chats) {
      const p = payloadOf(row);
      if (chatVisible(p)) visibleChatIds[String(p.id || row.getString("rid"))] = true;
    }
  }

  let crmFiltered = null;
  if (collection === "crm_state" && !ctx.isOwner) {
    const byKey = {};
    const parseList = (value) => {
      if (Array.isArray(value)) return value;
      if (typeof value !== "string" || !value.trim()) return [];
      try {
        const parsed = JSON.parse(value);
        return Array.isArray(parsed) ? parsed : [];
      } catch (_) { return []; }
    };
    for (const row of records) {
      const p = payloadOf(row);
      byKey[String(p.key || row.getString("rid"))] = parseList(p.value);
    }
    const clients = byKey.clients_v1 || [];
    const deals = byKey.deals_v1 || [];
    const manager = ctx.canManageTeam;
    const allowedOrg = (row) => ctx.allowedOrgIds[String(row.organizationId || "org_wesi_inc")] === true;
    const ownDealClientIds = {};
    for (const d of deals) {
      if (allowedOrg(d) && String(d.responsibleEmployeeId || "") === ctx.employeeId) {
        ownDealClientIds[String(d.clientId || "")] = true;
      }
    }
    const visibleClients = clients.filter((c) => allowedOrg(c) &&
      (manager || String(c.ownerEmployeeId || "") === ctx.employeeId || ownDealClientIds[String(c.id || "")]));
    const clientById = {};
    for (const c of clients) clientById[String(c.id || "")] = c;
    const visibleDeals = deals.filter((d) => allowedOrg(d) &&
      (manager || String(d.responsibleEmployeeId || "") === ctx.employeeId ||
       String((clientById[String(d.clientId || "")] || {}).ownerEmployeeId || "") === ctx.employeeId));
    const visibleClientIds = {};
    const visibleDealIds = {};
    for (const c of visibleClients) visibleClientIds[String(c.id || "")] = true;
    for (const d of visibleDeals) visibleDealIds[String(d.id || "")] = true;
    const visibleInteractions = (byKey.interactions_v1 || []).filter((i) =>
      visibleClientIds[String(i.clientId || "")] &&
      (!i.dealId || visibleDealIds[String(i.dealId || "")])
    );
    crmFiltered = {
      "clients_v1": visibleClients,
      "deals_v1": visibleDeals,
      "interactions_v1": visibleInteractions
    };
  }

  const items = [];
  for (const row of records) {
    let p = payloadOf(row);
    if (collection === "organizations") {
      p = normalizeOrganizationPayload(p, row);
    }
    let allowed = true;

    if (collection === "organizations" && !ctx.isOwner) {
      allowed = ctx.structuralOrgIds[String(p.id || row.getString("rid"))] === true;
    } else if (collection === "organization_grants" && !ctx.isOwner) {
      allowed = ctx.canManageTeam || String(p.employeeId || "") === ctx.employeeId;
    } else if (collection === "employees" && !ctx.isOwner) {
      const self = String(p.id || row.getString("rid")) === ctx.employeeId;
      const contacts = hasModule("contacts");
      p = {
        "id": String(p.id || row.getString("rid")),
        "login": String(p.login || ""),
        "fullName": String(p.fullName || ""),
        "nickname": String(p.nickname || ""),
        "position": String(p.position || ""),
        "phone": contacts ? String(p.phone || "") : "",
        "email": contacts ? String(p.email || "") : "",
        "socials": contacts && p.socials && typeof p.socials === "object" ? p.socials : {},
        "notes": ctx.canSeeNotes ? String(p.notes || "") : "",
        "permissions": (self || ctx.canManageTeam) && p.permissions && typeof p.permissions === "object"
          ? p.permissions : {},
        "passwordHash": "",
        "passwordSalt": "",
        "avatarIndex": Number(p.avatarIndex || 0),
        "createdAt": String(p.createdAt || new Date(0).toISOString()),
        "isOwner": self && p.isOwner === true,
        "demoStats": (self || ctx.canSeeOthersStats) && p.demoStats && typeof p.demoStats === "object"
          ? p.demoStats : {},
        "photo": p.photo == null ? null : p.photo,
        "skills": Array.isArray(p.skills) ? p.skills.map(String) : [],
        "weeklyCapacityPoints": Number(p.weeklyCapacityPoints || 10),
        "workloadMinRatio": Number(p.workloadMinRatio == null ? 0.65 : p.workloadMinRatio),
        "workloadMaxRatio": Number(p.workloadMaxRatio == null ? 1.10 : p.workloadMaxRatio),
        "managerEmployeeId": p.managerEmployeeId == null ? null : String(p.managerEmployeeId),
        "workloadAlertTarget": String(p.workloadAlertTarget || "manager")
      };
    } else if (collection === "tasks") {
      const orgId = orgIdOf(p);
      allowed = ctx.allowedOrgIds[orgId] === true && taskOwned(p);
    } else if (collection === "accounts" || collection === "transactions" || collection === "transaction_audit") {
      const orgId = orgIdOf(p);
      allowed = ctx.allowedOrgIds[orgId] === true && grantApplies(orgId, "view_finance");
    } else if (collection === "inter_org_transfers") {
      const fromOrg = String(p.fromOrganizationId || p.sourceOrganizationId || "");
      const toOrg = String(p.toOrganizationId || p.destinationOrganizationId || "");
      allowed = ctx.isOwner ||
        (!!fromOrg && !!toOrg && grantApplies(fromOrg, "view_finance") && grantApplies(toOrg, "view_finance"));
    } else if (collection === "critical_audit" && !ctx.isOwner && !ctx.canManageTeam) {
      allowed = String(p.actorId || p.changedBy || p.createdBy || "") === ctx.employeeId;
    } else if (collection === "articles" && !ctx.isOwner && !ctx.knowledgeAll) {
      const id = String(p.id || row.getString("rid"));
      const parentId = String(p.parentId || "");
      allowed = ctx.knowledgeIds.indexOf(id) >= 0 || (parentId && ctx.knowledgeIds.indexOf(parentId) >= 0);
    } else if (collection === "chats") {
      allowed = chatVisible(p);
    } else if (collection === "messages" && !ctx.isOwner) {
      allowed = visibleChatIds[String(p.chatId || "")] === true;
    } else if (collection === "crm_state" && crmFiltered) {
      const key = String(p.key || row.getString("rid"));
      if (crmFiltered[key] !== undefined) {
        p = {"key": key, "value": JSON.stringify(crmFiltered[key])};
      }
    }

    if (!allowed) continue;

    // Хэш и соль пароля не покидают сервер ни для кого, включая владельца.
    //
    // Зачистка стоит здесь, последней и без условий, а не внутри ветки про
    // сотрудников: ветка выполняется только для не-владельца, и владелец
    // получал эти поля по всем сотрудникам сразу. На его устройстве это
    // готовая база для офлайн-перебора чужих паролей, а локальное хранилище
    // приложения не шифруется.
    //
    // Проверять пароль локально приложение давно перестало — вход идёт через
    // сервер, — поэтому клиенту эти поля не нужны вообще.
    if (collection === "employees" && p && typeof p === "object") {
      p = Object.assign({}, p, {"passwordHash": "", "passwordSalt": ""});
    }

    items.push({
      "rid": row.getString("rid"),
      "payload": p,
      "stamp": row.getString("stamp"),
      "deleted": row.getBool("deleted")
    });
  }
  return e.json(200, {"items": items});
}, $apis.requireAuth("users"));