// Row-level CRM synchronization policy shared by exact GET/POST routes.
//
// The client CRM service scopes rows by organization plus employee ownership:
// ordinary employees see their clients, clients for deals assigned to them,
// their assigned deals (or deals of their clients), and interactions whose
// parent client/deal is visible. Keep the exact same model on the server so
// moving CRM from list snapshots to per-record sync cannot expose the whole
// company CRM to every employee with the module enabled.

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

function hasCrm(ctx) {
  return ctx.isOwner || ctx.modules.indexOf("crm") >= 0;
}

function manager(ctx) {
  return ctx.isOwner || ctx.canManageTeam === true || ctx.canSeeOthersStats === true;
}

function orgIdOf(payload) {
  return String((payload && payload.organizationId) || "org_wesi_inc");
}

function orgAllowed(ctx, orgId) {
  return ctx.isOwner || ctx.allowedOrgIds[String(orgId || "")] === true;
}

function allRows(app, owner, collection) {
  return require(`${__hooks}/wesi_sync_data_access.js`).records(
    app,
    "wesios_records",
    "owner={:owner} && coll={:coll}",
    "id",
    0,
    0,
    {owner: owner, coll: collection},
  );
}

function mapRows(rows) {
  const out = {};
  for (const row of rows) {
    const id = String(row.getString("rid") || payloadOf(row).id || "");
    if (id) out[id] = row;
  }
  return out;
}

function state(app, ctx) {
  const owner = ctx.ownerId;
  const clients = allRows(app, owner, "crm_clients");
  const deals = allRows(app, owner, "crm_deals");
  return {
    clients: mapRows(clients),
    deals: mapRows(deals),
    clientRows: clients,
    dealRows: deals,
  };
}

function clientVisible(ctx, crm, row, includeDeletedRelations) {
  if (!row) return false;
  const p = payloadOf(row);
  const id = String(p.id || row.getString("rid") || "");
  const orgId = orgIdOf(p);
  if (!id || !orgAllowed(ctx, orgId)) return false;
  if (manager(ctx)) return true;
  if (String(p.ownerEmployeeId || "") === ctx.employeeId) return true;

  for (const dealRow of crm.dealRows) {
    if (!includeDeletedRelations && dealRow.getBool("deleted")) continue;
    const d = payloadOf(dealRow);
    if (String(d.clientId || "") !== id) continue;
    if (!orgAllowed(ctx, orgIdOf(d))) continue;
    if (String(d.responsibleEmployeeId || "") === ctx.employeeId) return true;
  }
  return false;
}

function dealVisible(ctx, crm, row, includeDeletedRelations) {
  if (!row) return false;
  const p = payloadOf(row);
  const orgId = orgIdOf(p);
  if (!orgAllowed(ctx, orgId)) return false;
  if (manager(ctx)) return true;
  if (String(p.responsibleEmployeeId || "") === ctx.employeeId) return true;

  const client = crm.clients[String(p.clientId || "")];
  if (!client) return false;
  if (!includeDeletedRelations && client.getBool("deleted")) return false;
  const cp = payloadOf(client);
  if (orgIdOf(cp) !== orgId) return false;
  return String(cp.ownerEmployeeId || "") === ctx.employeeId;
}

function interactionVisible(ctx, crm, row) {
  if (!row) return false;
  const p = payloadOf(row);
  const includeDeletedRelations = row.getBool("deleted");
  const client = crm.clients[String(p.clientId || "")];
  if (!client || (!includeDeletedRelations && client.getBool("deleted"))) {
    return false;
  }
  if (!clientVisible(ctx, crm, client, includeDeletedRelations)) return false;

  const dealId = p.dealId == null ? "" : String(p.dealId || "");
  if (!dealId) return true;
  const deal = crm.deals[dealId];
  if (!deal || (!includeDeletedRelations && deal.getBool("deleted"))) return false;
  const dp = payloadOf(deal);
  if (String(dp.clientId || "") !== String(p.clientId || "")) return false;
  return dealVisible(ctx, crm, deal, includeDeletedRelations);
}

function visible(ctx, crm, collection, row) {
  if (collection === "crm_clients") {
    return clientVisible(ctx, crm, row, row.getBool("deleted"));
  }
  if (collection === "crm_deals") {
    return dealVisible(ctx, crm, row, row.getBool("deleted"));
  }
  if (collection === "crm_interactions") {
    return interactionVisible(ctx, crm, row);
  }
  return false;
}

function read(e, collection) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!hasCrm(ctx)) return e.json(200, {items: []});

  const crm = state(e.app, ctx);
  const rows = collection === "crm_clients"
    ? crm.clientRows
    : collection === "crm_deals"
      ? crm.dealRows
      : allRows(e.app, ctx.ownerId, "crm_interactions");

  const items = [];
  for (const row of rows) {
    if (!visible(ctx, crm, collection, row)) continue;
    items.push({
      rid: row.getString("rid"),
      payload: payloadOf(row),
      stamp: row.getString("stamp"),
      deleted: row.getBool("deleted"),
    });
  }
  return e.json(200, {items: items});
}

function bad(message) {
  throw new BadRequestError(message);
}

function forbidden(message) {
  throw new ForbiddenError(message);
}

function requireOrg(ctx, orgId) {
  if (!orgAllowed(ctx, orgId)) forbidden("Нет доступа к CRM этой организации");
}

function parentClient(crm, id, allowDeleted) {
  const row = crm.clients[String(id || "")];
  if (!row || (!allowDeleted && row.getBool("deleted"))) {
    bad("CRM-клиент не найден");
  }
  return row;
}

function parentDeal(crm, id, allowDeleted) {
  const row = crm.deals[String(id || "")];
  if (!row || (!allowDeleted && row.getBool("deleted"))) {
    bad("CRM-сделка не найдена");
  }
  return row;
}

function clientWritable(ctx, row) {
  if (manager(ctx)) return true;
  return String(payloadOf(row).ownerEmployeeId || "") === ctx.employeeId;
}

function dealWritable(ctx, crm, row, includeDeletedRelations) {
  if (manager(ctx)) return true;
  const p = payloadOf(row);
  if (String(p.responsibleEmployeeId || "") === ctx.employeeId) return true;
  const client = crm.clients[String(p.clientId || "")];
  if (!client || (!includeDeletedRelations && client.getBool("deleted"))) return false;
  return String(payloadOf(client).ownerEmployeeId || "") === ctx.employeeId;
}

function authorizeClient(txApp, existing, input, ctx) {
  if (input.deleted && !existing) bad("Нельзя удалить отсутствующего CRM-клиента");
  const before = payloadOf(existing);
  const target = input.deleted ? before : input.payload;
  const newOrg = orgIdOf(target);
  requireOrg(ctx, newOrg);
  if (existing) requireOrg(ctx, orgIdOf(before));

  if (!manager(ctx)) {
    if (existing && !clientWritable(ctx, existing)) {
      forbidden("CRM-клиент принадлежит другому сотруднику");
    }
    if (!input.deleted) {
      const requestedOwner = target.ownerEmployeeId == null
        ? ""
        : String(target.ownerEmployeeId || "");
      if (requestedOwner && requestedOwner !== ctx.employeeId) {
        forbidden("Нельзя назначить CRM-клиента другому сотруднику");
      }
      input.payload = Object.assign({}, input.payload, {
        organizationId: newOrg,
        ownerEmployeeId: ctx.employeeId,
      });
    }
  }
}

function authorizeDeal(txApp, existing, input, ctx) {
  if (input.deleted && !existing) bad("Нельзя удалить отсутствующую CRM-сделку");
  const before = payloadOf(existing);
  const target = input.deleted ? before : input.payload;
  const newOrg = orgIdOf(target);
  requireOrg(ctx, newOrg);
  if (existing) requireOrg(ctx, orgIdOf(before));

  const crm = state(txApp, ctx);
  const client = parentClient(crm, target.clientId, input.deleted);
  const cp = payloadOf(client);
  if (orgIdOf(cp) !== newOrg) {
    bad("CRM-сделка и клиент должны принадлежать одной организации");
  }

  if (!manager(ctx)) {
    if (existing && !dealWritable(ctx, crm, existing, input.deleted)) {
      forbidden("CRM-сделка принадлежит другому сотруднику");
    }
    if (!existing && String(cp.ownerEmployeeId || "") !== ctx.employeeId) {
      forbidden("Нельзя создать сделку для чужого CRM-клиента");
    }
    if (!input.deleted) {
      const requested = target.responsibleEmployeeId == null
        ? ""
        : String(target.responsibleEmployeeId || "");
      if (requested && requested !== ctx.employeeId) {
        forbidden("Нельзя назначить CRM-сделку другому сотруднику");
      }
      input.payload = Object.assign({}, input.payload, {
        organizationId: newOrg,
        responsibleEmployeeId: ctx.employeeId,
      });
    }
  }
}

function interactionParentWritable(ctx, crm, payload, allowDeleted) {
  const client = parentClient(crm, payload.clientId, allowDeleted);
  const cp = payloadOf(client);
  requireOrg(ctx, orgIdOf(cp));
  if (manager(ctx)) return true;
  if (String(cp.ownerEmployeeId || "") === ctx.employeeId) return true;

  const dealId = payload.dealId == null ? "" : String(payload.dealId || "");
  if (!dealId) return false;
  const deal = parentDeal(crm, dealId, allowDeleted);
  const dp = payloadOf(deal);
  if (String(dp.clientId || "") !== String(payload.clientId || "") ||
      orgIdOf(dp) !== orgIdOf(cp)) {
    bad("CRM-касание связано с чужой сделкой или организацией");
  }
  return dealWritable(ctx, crm, deal, allowDeleted);
}

function authorizeInteraction(txApp, existing, input, ctx) {
  if (input.deleted && !existing) bad("Нельзя удалить отсутствующее CRM-касание");
  const crm = state(txApp, ctx);
  const before = payloadOf(existing);
  const target = input.deleted ? before : input.payload;

  if (existing && !interactionParentWritable(ctx, crm, before, input.deleted)) {
    forbidden("Старый родитель CRM-касания больше не доступен сотруднику");
  }
  if (!interactionParentWritable(ctx, crm, target, input.deleted)) {
    forbidden("CRM-касание находится вне области сотрудника");
  }
}

function write(e, collection) {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  if (!hasCrm(ctx)) forbidden("Раздел CRM не открыт этому сотруднику");

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) bad("Некорректный id CRM-записи");
  const incoming = body.payload && typeof body.payload === "object" &&
      !Array.isArray(body.payload)
    ? body.payload
    : {};
  if (incoming.id != null && String(incoming.id) !== rid) {
    bad("id CRM-записи не совпадает с rid");
  }
  const deleted = body.deleted === true;
  const parsedStamp = Date.parse(String(body.stamp || ""));
  const now = Date.now();
  const stamp = Number.isFinite(parsedStamp) && parsedStamp <= now + 5 * 60 * 1000
    ? new Date(parsedStamp).toISOString()
    : new Date(now).toISOString();

  const authorize = collection === "crm_clients"
    ? function(txApp, existing, input) {
        authorizeClient(txApp, existing, input, ctx);
      }
    : collection === "crm_deals"
      ? function(txApp, existing, input) {
          authorizeDeal(txApp, existing, input, ctx);
        }
      : function(txApp, existing, input) {
          authorizeInteraction(txApp, existing, input, ctx);
        };

  const committed = require(`${__hooks}/wesi_sync_atomic.js`).commit(e.app, {
    owner: ctx.ownerId,
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
    stamp: committed.stamp,
    applied: committed.applied,
    reason: committed.reason,
  });
}

module.exports = {
  read: read,
  write: write,
  visible: visible,
  state: state,
  clientVisible: clientVisible,
  dealVisible: dealVisible,
  interactionVisible: interactionVisible,
  authorizeClient: authorizeClient,
  authorizeDeal: authorizeDeal,
  authorizeInteraction: authorizeInteraction,
};
