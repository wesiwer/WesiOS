const ROOT_ORG = "org_wesi_inc";

function payload(record) {
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
}

function rows(e, ctx, collection) {
  try {
    return e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && deleted=false",
      "-stamp,-id", 0, 0,
      {owner: ctx.ownerId, coll: collection},
    );
  } catch (_) { return []; }
}

function state(e, ctx) {
  let permissions = {};
  if (ctx.isOwner) {
    permissions = {
      modules: ["calendar", "knowledge", "crm", "ai"],
      knowledgeIds: [], knowledgeAll: true,
      canManageTeam: true, canSeeOthersStats: true,
      canSeeNotes: true, canAssignTasks: true,
    };
  } else {
    let employee = null;
    try {
      employee = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, rid: ctx.employeeId},
      );
    } catch (_) { employee = null; }
    const p = payload(employee);
    permissions = p.permissions && typeof p.permissions === "object" ? p.permissions : {};
  }

  const modules = Array.isArray(permissions.modules) ? permissions.modules.map(String) : [];
  const knowledgeIds = Array.isArray(permissions.knowledgeIds) ? permissions.knowledgeIds.map(String) : [];
  const organizations = {};
  const parents = {};
  const orgRows = rows(e, ctx, "organizations");
  for (const row of orgRows) {
    const p = payload(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    organizations[id] = {
      id: id,
      name: String(p.name || id),
      parentId: p.parentId == null || String(p.parentId || "") === "" ? null : String(p.parentId),
      baseCurrency: String(p.baseCurrency || "RUB").toUpperCase(),
      status: String(p.status || "active"),
    };
    parents[id] = organizations[id].parentId;
  }

  const grants = [];
  if (!ctx.isOwner) {
    for (const row of rows(e, ctx, "organization_grants")) {
      const p = payload(row);
      if (String(p.employeeId || "") === ctx.employeeId) grants.push(p);
    }
  }

  const grantApplies = function(orgId, permission) {
    if (ctx.isOwner) return true;
    let cursor = orgId;
    let first = true;
    while (cursor) {
      for (const g of grants) {
        if (String(g.organizationId || "") !== cursor) continue;
        if (!first && g.includeSubtree !== true) continue;
        const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
        if (perms.indexOf(permission) >= 0) return true;
      }
      first = false;
      cursor = parents[cursor];
    }
    return false;
  };

  const allowedOrgIds = {};
  if (ctx.isOwner) {
    for (const id of Object.keys(organizations)) allowedOrgIds[id] = true;
  } else {
    for (const id of Object.keys(organizations)) {
      if (grantApplies(id, "view")) allowedOrgIds[id] = true;
    }
  }
  const structuralOrgIds = {};
  for (const id of Object.keys(allowedOrgIds)) {
    structuralOrgIds[id] = true;
    let cursor = parents[id];
    while (cursor) {
      structuralOrgIds[cursor] = true;
      cursor = parents[cursor];
    }
  }

  return {
    permissions: permissions,
    modules: modules,
    knowledgeIds: knowledgeIds,
    knowledgeAll: ctx.isOwner || permissions.knowledgeAll === true,
    canManageTeam: ctx.isOwner || permissions.canManageTeam === true,
    organizations: organizations,
    parents: parents,
    grants: grants,
    grantApplies: grantApplies,
    allowedOrgIds: allowedOrgIds,
    structuralOrgIds: structuralOrgIds,
  };
}

function moduleAllowed(ctx, access, name) {
  return ctx.isOwner || access.modules.indexOf(name) >= 0;
}

function orgIdOf(p) {
  return String((p && (p.organizationId || p.orgId)) || ROOT_ORG);
}

function limitOf(value, fallback, max) {
  const n = Number(value == null ? fallback : value);
  if (!Number.isFinite(n)) return fallback;
  return Math.max(1, Math.min(max, Math.floor(n)));
}

function lower(value) { return String(value || "").toLowerCase(); }

function plainKnowledgeBody(body) {
  const raw = String(body || "");
  const trimmed = raw.trimLeft ? raw.trimLeft() : raw.replace(/^\s+/, "");
  if (!trimmed.startsWith("[")) return raw;
  try {
    const decoded = JSON.parse(raw);
    if (!Array.isArray(decoded)) return raw;
    let text = "";
    for (const op of decoded) {
      if (op && typeof op === "object" && typeof op.insert === "string") text += op.insert;
    }
    return text.trim() || raw;
  } catch (_) { return raw; }
}

function crmVisible(e, ctx, access) {
  const clients = [];
  const deals = [];
  const interactions = [];
  for (const row of rows(e, ctx, "crm_clients")) clients.push(payload(row));
  for (const row of rows(e, ctx, "crm_deals")) deals.push(payload(row));
  for (const row of rows(e, ctx, "crm_interactions")) interactions.push(payload(row));

  const manager = access.canManageTeam;
  const clientById = {};
  for (const client of clients) clientById[String(client.id || "")] = client;
  const allowedOrg = function(item) { return access.allowedOrgIds[orgIdOf(item)] === true; };
  const ownDealClientIds = {};
  if (!ctx.isOwner && !manager) {
    for (const deal of deals) {
      if (allowedOrg(deal) && String(deal.responsibleEmployeeId || "") === ctx.employeeId) {
        ownDealClientIds[String(deal.clientId || "")] = true;
      }
    }
  }

  const visibleClients = clients.filter(function(client) {
    if (!allowedOrg(client)) return false;
    if (ctx.isOwner || manager) return true;
    return String(client.ownerEmployeeId || "") === ctx.employeeId || ownDealClientIds[String(client.id || "")] === true;
  });
  const visibleClientIds = {};
  for (const client of visibleClients) visibleClientIds[String(client.id || "")] = true;

  const visibleDeals = deals.filter(function(deal) {
    if (!allowedOrg(deal)) return false;
    if (ctx.isOwner || manager) return true;
    const client = clientById[String(deal.clientId || "")] || {};
    return String(deal.responsibleEmployeeId || "") === ctx.employeeId || String(client.ownerEmployeeId || "") === ctx.employeeId;
  });
  const visibleDealIds = {};
  for (const deal of visibleDeals) {
    visibleDealIds[String(deal.id || "")] = true;
    visibleClientIds[String(deal.clientId || "")] = true;
  }

  const visibleInteractions = interactions.filter(function(item) {
    if (!visibleClientIds[String(item.clientId || "")]) return false;
    return !item.dealId || visibleDealIds[String(item.dealId || "")] === true;
  });
  return {clients: visibleClients, deals: visibleDeals, interactions: visibleInteractions};
}

module.exports = {
  definitions: function(e, ctx) {
    const access = state(e, ctx);
    const out = [{
      name: "organizations_list",
      description: "Получить видимую сотруднику структуру организаций WesiOS. structural=true означает только видимость узла дерева; dataAccessible показывает право читать бизнес-данные организации.",
      parameters: {type: "object", properties: {}},
    }];
    if (moduleAllowed(ctx, access, "calendar")) out.push({
      name: "calendar_events",
      description: "Получить реальные события календаря WesiOS. Календарь в текущей модели WesiOS имеет общий модульный scope и не содержит organizationId.",
      parameters: {type: "object", properties: {from: {type: "string", description: "ISO дата/время, необязательно"}, to: {type: "string", description: "ISO дата/время, необязательно"}, query: {type: "string"}, limit: {type: "integer", minimum: 1, maximum: 100}}},
    });
    if (moduleAllowed(ctx, access, "knowledge")) out.push({
      name: "knowledge_search",
      description: "Искать только разрешённые текущему сотруднику статьи Базы знаний WesiOS.",
      parameters: {type: "object", properties: {query: {type: "string"}, limit: {type: "integer", minimum: 1, maximum: 30}}},
    });
    if (moduleAllowed(ctx, access, "crm")) {
      out.push({name: "crm_clients", description: "Получить только разрешённых текущему сотруднику CRM-клиентов WesiOS.", parameters: {type: "object", properties: {organizationId: {type: "string"}, query: {type: "string"}, status: {type: "string"}, limit: {type: "integer", minimum: 1, maximum: 50}}}});
      out.push({name: "crm_deals", description: "Получить только разрешённые текущему сотруднику CRM-сделки WesiOS.", parameters: {type: "object", properties: {organizationId: {type: "string"}, query: {type: "string"}, stage: {type: "string"}, limit: {type: "integer", minimum: 1, maximum: 50}}}});
      out.push({name: "crm_pipeline_summary", description: "Посчитать на Main Server сводку разрешённой CRM-воронки по этапам без раскрытия чужих строк.", parameters: {type: "object", properties: {organizationId: {type: "string"}}}});
    }
    return out;
  },

  context: function(e, ctx, activeOrganizationId) {
    const access = state(e, ctx);
    const organizations = Object.keys(access.structuralOrgIds)
      .filter(function(id) { return access.structuralOrgIds[id] === true && access.organizations[id]; })
      .map(function(id) {
        const org = access.organizations[id];
        return {id: id, name: org.name, parentId: org.parentId, dataAccessible: access.allowedOrgIds[id] === true};
      });
    return {
      activeOrganizationId: String(activeOrganizationId || ""),
      workspaceOrganizations: organizations,
      workspaceModules: ["calendar", "knowledge", "crm"].filter(function(name) { return moduleAllowed(ctx, access, name); }),
    };
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    const input = args && typeof args === "object" ? args : {};
    const access = state(e, ctx);

    if (name === "organizations_list") {
      const items = Object.keys(access.structuralOrgIds)
        .filter(function(id) { return access.structuralOrgIds[id] === true && access.organizations[id]; })
        .map(function(id) {
          const org = access.organizations[id];
          return {id: id, name: org.name, parentId: org.parentId, baseCurrency: org.baseCurrency, structural: true, dataAccessible: access.allowedOrgIds[id] === true};
        });
      return {ok: true, result: {organizations: items}};
    }

    if (name === "calendar_events") {
      if (!moduleAllowed(ctx, access, "calendar")) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к календарю"};
      const now = new Date();
      const from = input.from ? new Date(String(input.from)) : now;
      const to = input.to ? new Date(String(input.to)) : new Date(now.getTime() + 31 * 86400000);
      if (!Number.isFinite(from.getTime()) || !Number.isFinite(to.getTime()) || from > to || to.getTime() - from.getTime() > 366 * 86400000) {
        return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный период календаря"};
      }
      const query = lower(input.query).trim();
      const max = limitOf(input.limit, 30, 100);
      const items = [];
      for (const row of rows(e, ctx, "calendar_events")) {
        const p = payload(row);
        if (p.enabled === false) continue;
        const start = new Date(String(p.startAt || ""));
        if (!Number.isFinite(start.getTime())) continue;
        const repeat = String(p.repeat || "none");
        if (repeat === "none" && (start < from || start > to)) continue;
        if (repeat !== "none" && start > to) continue;
        if (query && lower(p.title).indexOf(query) < 0 && lower(p.notes).indexOf(query) < 0) continue;
        items.push({
          id: String(p.id || row.getString("rid") || ""), title: String(p.title || ""), notes: String(p.notes || "").slice(0, 2000),
          startAt: start.toISOString(), durationMinutes: Number(p.durationMinutes || 60), allDay: p.allDay === true,
          repeat: repeat, reminderMinutesBefore: p.reminderMinutesBefore == null ? null : Number(p.reminderMinutesBefore), enabled: true,
        });
      }
      items.sort(function(a, b) { return String(a.startAt).localeCompare(String(b.startAt)); });
      return {ok: true, result: {from: from.toISOString(), to: to.toISOString(), events: items.slice(0, max)}};
    }

    if (name === "knowledge_search") {
      if (!moduleAllowed(ctx, access, "knowledge")) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к Базе знаний"};
      const query = lower(input.query).trim();
      const max = limitOf(input.limit, 10, 30);
      const items = [];
      for (const row of rows(e, ctx, "articles")) {
        const p = payload(row);
        const id = String(p.id || row.getString("rid") || "");
        const parentId = String(p.parentId || "");
        if (!ctx.isOwner && !access.knowledgeAll && access.knowledgeIds.indexOf(id) < 0 && (!parentId || access.knowledgeIds.indexOf(parentId) < 0)) continue;
        const body = plainKnowledgeBody(p.body);
        const tags = Array.isArray(p.tags) ? p.tags.map(String) : [];
        const haystack = lower(p.title) + "\n" + lower(body) + "\n" + lower(tags.join(" "));
        if (query && haystack.indexOf(query) < 0) continue;
        items.push({id: id, title: String(p.title || ""), parentId: parentId || null, section: String(p.section || "playbook"), tags: tags, pinned: p.pinned === true, isFolder: p.isFolder === true, text: body.slice(0, 4000), updatedAt: String(p.updatedAt || "")});
      }
      items.sort(function(a, b) { return (b.pinned === true ? 1 : 0) - (a.pinned === true ? 1 : 0) || String(b.updatedAt).localeCompare(String(a.updatedAt)); });
      return {ok: true, result: {query: String(input.query || ""), articles: items.slice(0, max)}};
    }

    if (name === "crm_clients" || name === "crm_deals" || name === "crm_pipeline_summary") {
      if (!moduleAllowed(ctx, access, "crm")) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к CRM"};
      const organizationId = String(input.organizationId || activeOrganizationId || "").trim();
      if (organizationId && access.allowedOrgIds[organizationId] !== true) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к CRM этой организации"};
      const crm = crmVisible(e, ctx, access);
      const inOrg = function(item) { return !organizationId || orgIdOf(item) === organizationId; };

      if (name === "crm_clients") {
        const query = lower(input.query).trim();
        const status = String(input.status || "").trim();
        const max = limitOf(input.limit, 20, 50);
        const selected = crm.clients.filter(function(p) {
          if (!inOrg(p) || (status && String(p.status || "") !== status)) return false;
          if (!query) return true;
          return [p.name, p.company, p.email, p.phone, p.source, p.tags].some(function(v) { return lower(Array.isArray(v) ? v.join(" ") : v).indexOf(query) >= 0; });
        }).slice(0, max).map(function(p) {
          return {id: String(p.id || ""), organizationId: orgIdOf(p), name: String(p.name || ""), company: String(p.company || ""), phone: String(p.phone || ""), email: String(p.email || ""), status: String(p.status || "lead"), source: String(p.source || ""), tags: Array.isArray(p.tags) ? p.tags.map(String) : [], nextContactAt: p.nextContactAt == null ? null : String(p.nextContactAt), ownerEmployeeId: p.ownerEmployeeId == null ? null : String(p.ownerEmployeeId)};
        });
        return {ok: true, result: {organizationId: organizationId || null, clients: selected}};
      }

      if (name === "crm_deals") {
        const query = lower(input.query).trim();
        const stage = String(input.stage || "").trim();
        const max = limitOf(input.limit, 20, 50);
        const selected = crm.deals.filter(function(p) {
          if (!inOrg(p) || (stage && String(p.stage || "") !== stage)) return false;
          return !query || lower(p.title).indexOf(query) >= 0 || lower(p.notes).indexOf(query) >= 0;
        }).slice(0, max).map(function(p) {
          return {id: String(p.id || ""), clientId: String(p.clientId || ""), organizationId: orgIdOf(p), title: String(p.title || ""), amount: Number(p.amount || 0), currency: String(p.currency || "RUB"), stage: String(p.stage || "newLead"), probability: Number(p.probability || 0), expectedCloseAt: p.expectedCloseAt == null ? null : String(p.expectedCloseAt), responsibleEmployeeId: p.responsibleEmployeeId == null ? null : String(p.responsibleEmployeeId)};
        });
        return {ok: true, result: {organizationId: organizationId || null, deals: selected}};
      }

      const byStage = {};
      let totalAmount = 0, weightedAmount = 0, openCount = 0;
      for (const p of crm.deals) {
        if (!inOrg(p)) continue;
        const stage = String(p.stage || "newLead");
        const amount = Number(p.amount || 0);
        const probability = Math.max(0, Math.min(100, Number(p.probability || 0)));
        if (!byStage[stage]) byStage[stage] = {count: 0, amount: 0, weightedAmount: 0};
        byStage[stage].count++;
        byStage[stage].amount += Number.isFinite(amount) ? amount : 0;
        byStage[stage].weightedAmount += Number.isFinite(amount) ? amount * probability / 100 : 0;
        if (stage !== "won" && stage !== "lost") {
          openCount++;
          totalAmount += Number.isFinite(amount) ? amount : 0;
          weightedAmount += Number.isFinite(amount) ? amount * probability / 100 : 0;
        }
      }
      return {ok: true, result: {organizationId: organizationId || null, openCount: openCount, openAmount: Math.round(totalAmount * 100) / 100, weightedOpenAmount: Math.round(weightedAmount * 100) / 100, stages: byStage}};
    }

    return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный workspace-инструмент"};
  },
};
