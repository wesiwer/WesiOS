function moduleAllowed(ctx, name) {
  return Boolean(ctx && (ctx.isOwner || (Array.isArray(ctx.modules) && ctx.modules.indexOf(name) >= 0)));
}

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) {
      const parsed = JSON.parse(raw);
      return parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {};
    }
  } catch (_) {}
  return {};
}

function dataAccess() {
  return require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_sync_data_access.js");
}

function records(e, ctx, coll) {
  return dataAccess().records(
    e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && deleted=false",
    "id",
    10000,
    0,
    {owner: ctx.ownerId, coll: coll},
  );
}

function first(e, ctx, coll, rid) {
  return dataAccess().first(
    e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, coll: coll, rid: String(rid || "")},
  );
}

function orgAllowed(ctx, payload) {
  if (ctx.isOwner) return true;
  const id = String((payload && (payload.organizationId || payload.orgId)) || "org_wesi_inc");
  return Boolean(ctx.allowedOrgIds && ctx.allowedOrgIds[id] === true);
}

function crmState(e, ctx) {
  const clients = records(e, ctx, "crm_clients").map(payloadOf);
  const deals = records(e, ctx, "crm_deals").map(payloadOf);
  const clientById = {};
  const dealById = {};
  for (const client of clients) clientById[String(client.id || "")] = client;
  for (const deal of deals) dealById[String(deal.id || "")] = deal;
  return {clients: clients, deals: deals, clientById: clientById, dealById: dealById};
}

function crmClientVisible(ctx, state, client) {
  if (ctx.isOwner) return true;
  if (!orgAllowed(ctx, client)) return false;
  if (ctx.canManageTeam) return true;
  if (String(client.ownerEmployeeId || "") === String(ctx.employeeId || "")) return true;
  const clientId = String(client.id || "");
  return state.deals.some(function(deal) {
    return String(deal.clientId || "") === clientId &&
      orgAllowed(ctx, deal) &&
      String(deal.responsibleEmployeeId || "") === String(ctx.employeeId || "");
  });
}

function crmDealVisible(ctx, state, deal) {
  if (ctx.isOwner) return true;
  if (!orgAllowed(ctx, deal)) return false;
  if (ctx.canManageTeam) return true;
  if (String(deal.responsibleEmployeeId || "") === String(ctx.employeeId || "")) return true;
  const client = state.clientById[String(deal.clientId || "")] || {};
  return orgAllowed(ctx, client) &&
    String(client.ownerEmployeeId || "") === String(ctx.employeeId || "");
}

function crmInteractionVisible(ctx, state, interaction) {
  if (ctx.isOwner) return true;
  const client = state.clientById[String(interaction.clientId || "")];
  if (!client || !crmClientVisible(ctx, state, client)) return false;
  const dealId = String(interaction.dealId || "");
  if (!dealId) return true;
  const deal = state.dealById[dealId];
  return Boolean(deal && crmDealVisible(ctx, state, deal));
}

function activeReshareGrant(e, ctx, kind, subjectId) {
  const employeeId = String(ctx.employeeId || "");
  const now = Date.now();
  return records(e, ctx, "file_grants").some(function(row) {
    const grant = payloadOf(row);
    if (String(grant.subjectKind || "") !== kind ||
        String(grant.subjectId || "") !== subjectId ||
        String(grant.employeeId || "") !== employeeId ||
        grant.canReshare !== true) return false;
    const expires = Date.parse(String(grant.expiresAt || ""));
    return !String(grant.expiresAt || "").trim() || (Number.isFinite(expires) && expires > now);
  });
}

function canSupplySubject(e, ctx, payload) {
  if (ctx.isOwner) return true;
  const kind = String(payload.subjectKind || "beat");
  const subjectId = String(payload.subjectId || "");
  if (!subjectId) return false;
  if (kind === "employeeDocument") return subjectId === String(ctx.employeeId || "");
  if (kind !== "beat" || !moduleAllowed(ctx, "audio")) return false;
  const beatRow = first(e, ctx, "audio_beats", subjectId);
  const beat = payloadOf(beatRow);
  if (String(beat.authorEmployeeId || "") === String(ctx.employeeId || "")) return true;
  return activeReshareGrant(e, ctx, kind, subjectId);
}

function fileReadVisible(e, ctx, collection, payload) {
  if (ctx.isOwner) return true;
  const employeeId = String(ctx.employeeId || "");
  if (collection === "file_grants") {
    return String(payload.employeeId || "") === employeeId ||
      String(payload.grantedBy || "") === employeeId ||
      canSupplySubject(e, ctx, payload);
  }
  if (collection === "file_requests") {
    if (String(payload.requesterId || "") === employeeId || String(payload.holderId || "") === employeeId) return true;
    return !String(payload.holderId || "").trim() && canSupplySubject(e, ctx, payload);
  }
  if (collection === "file_handovers") {
    return String(payload.fromEmployeeId || "") === employeeId ||
      String(payload.toEmployeeId || "") === employeeId ||
      canSupplySubject(e, ctx, payload);
  }
  return false;
}

function reader(e, ctx, collection) {
  if (collection === "roadmap_projects" || collection === "roadmap_items") {
    if (!moduleAllowed(ctx, "roadmap")) return function() { return false; };
    return function() { return true; };
  }
  if (collection === "audio_beats") {
    if (!moduleAllowed(ctx, "audio")) return function() { return false; };
    return function() { return true; };
  }
  if (collection === "crm_clients" || collection === "crm_deals" || collection === "crm_interactions") {
    if (!moduleAllowed(ctx, "crm")) return function() { return false; };
    if (ctx.isOwner) return function() { return true; };
    const state = crmState(e, ctx);
    if (collection === "crm_clients") return function(payload) { return crmClientVisible(ctx, state, payload); };
    if (collection === "crm_deals") return function(payload) { return crmDealVisible(ctx, state, payload); };
    return function(payload) { return crmInteractionVisible(ctx, state, payload); };
  }
  if (collection === "file_grants" || collection === "file_requests" || collection === "file_handovers") {
    return function(payload) { return fileReadVisible(e, ctx, collection, payload); };
  }
  return null;
}

function forbid(message) {
  throw new ForbiddenError(message);
}

function sameRequestCore(a, b) {
  const keys = ["id", "subjectKind", "subjectId", "fileKind", "attachmentId", "requesterId", "holderId", "createdAt"];
  return keys.every(function(key) { return String((a && a[key]) || "") === String((b && b[key]) || ""); });
}

function assertWrite(e, ctx, collection, incoming, before, existing, deleted) {
  const target = deleted ? before : incoming;
  if (collection === "roadmap_projects" || collection === "roadmap_items") {
    if (!moduleAllowed(ctx, "roadmap")) forbid("Раздел Roadmap не открыт этому сотруднику");
    return true;
  }
  if (collection === "audio_beats") {
    if (!moduleAllowed(ctx, "audio")) forbid("Audio Vault не открыт этому сотруднику");
    return true;
  }
  if (collection === "crm_clients" || collection === "crm_deals" || collection === "crm_interactions") {
    if (!moduleAllowed(ctx, "crm")) forbid("CRM не открыт этому сотруднику");
    if (ctx.isOwner) return true;
    const state = crmState(e, ctx);
    if (collection === "crm_clients") {
      if (!crmClientVisible(ctx, state, target)) forbid("Нет доступа к этому клиенту CRM");
      return true;
    }
    if (collection === "crm_deals") {
      if (!state.clientById[String(target.clientId || "")]) forbid("Сделка ссылается на неизвестного клиента CRM");
      if (!crmDealVisible(ctx, state, target)) forbid("Нет доступа к этой сделке CRM");
      return true;
    }
    if (!crmInteractionVisible(ctx, state, target)) forbid("Нет доступа к этому взаимодействию CRM");
    return true;
  }

  if (collection === "file_grants") {
    if (ctx.isOwner) return true;
    if (!canSupplySubject(e, ctx, target)) forbid("Нет права выдавать доступ к этому файлу");
    if (!deleted && String(target.grantedBy || "") !== String(ctx.employeeId || "")) {
      forbid("Нельзя создать доступ от имени другого сотрудника");
    }
    return true;
  }

  if (collection === "file_requests") {
    if (ctx.isOwner) return true;
    const employeeId = String(ctx.employeeId || "");
    if (!existing) {
      if (deleted || String(incoming.requesterId || "") !== employeeId || String(incoming.status || "pending") !== "pending") {
        forbid("Нельзя создать чужой или уже решённый запрос файла");
      }
      return true;
    }
    if (deleted) {
      if (String(before.requesterId || "") !== employeeId && !canSupplySubject(e, ctx, before)) forbid("Нет права удалить этот запрос файла");
      return true;
    }
    if (!sameRequestCore(before, incoming)) forbid("Нельзя подменить участников запроса файла");
    const requester = String(before.requesterId || "") === employeeId;
    const supplier = String(before.holderId || "") === employeeId || (!String(before.holderId || "").trim() && canSupplySubject(e, ctx, before));
    const status = String(incoming.status || "pending");
    if (requester && (status === "cancelled" || status === "expired")) return true;
    if (supplier && ["approved", "declined", "delivered", "expired"].indexOf(status) >= 0) {
      if (status !== "expired" && String(incoming.decidedBy || "") !== employeeId) forbid("Решение по запросу должно принадлежать текущему сотруднику");
      return true;
    }
    forbid("Нет права изменить состояние этого запроса файла");
  }

  if (collection === "file_handovers") {
    if (ctx.isOwner) return true;
    if (existing || deleted) forbid("Журнал выдачи файлов только дополняется");
    if (String(incoming.fromEmployeeId || "") !== String(ctx.employeeId || "") || !canSupplySubject(e, ctx, incoming)) {
      forbid("Нельзя записать выдачу файла от имени другого сотрудника");
    }
    return true;
  }

  return false;
}

module.exports = {
  reader: reader,
  assertWrite: assertWrite,
  _test: {
    crmClientVisible: crmClientVisible,
    crmDealVisible: crmDealVisible,
    crmInteractionVisible: crmInteractionVisible,
    orgAllowed: orgAllowed,
  },
};
