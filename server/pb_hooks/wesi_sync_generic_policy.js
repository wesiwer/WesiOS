// Transaction-time authorization for generic WesiOS sync collections.
//
// The route performs a fast preflight for clear errors, but row-dependent
// authorization must be repeated inside the same transaction as the LWW save.

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

function forbidden(message) { throw new ForbiddenError(message); }

function hasModule(ctx, name) {
  return ctx.isOwner || ctx.modules.indexOf(name) >= 0;
}

function hasAnyModule(ctx, names) {
  return ctx.isOwner || names.some((name) => ctx.modules.indexOf(name) >= 0);
}

function grantApplies(ctx, orgId, permission) {
  if (ctx.isOwner) return true;
  let cursor = String(orgId || "");
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
}

function orgIdOf(p) {
  return String((p && (p.organizationId || p.orgId)) || "org_wesi_inc");
}

function taskOwned(ctx, p) {
  if (ctx.isOwner || ctx.canManageTeam || ctx.canAssignTasks) return true;
  if (String(p.assignee || "") === ctx.employeeId) return true;
  if (String(p.responsibleEmployeeId || "") === ctx.employeeId) return true;
  const tags = Array.isArray(p.tags) ? p.tags.map(String) : [];
  return tags.indexOf("wesios:employee:" + ctx.employeeId) >= 0;
}

function chatVisible(ctx, p) {
  if (String(p.kind || "work") !== "work") return false;
  if (ctx.isOwner) return true;
  const participants = Array.isArray(p.participants) ? p.participants.map(String) : [];
  return participants.indexOf(ctx.employeeId) >= 0;
}

function requireFinance(ctx) {
  if (!hasAnyModule(ctx, ["treasury", "forecast", "sandbox", "analytics"])) {
    forbidden("Финансовый раздел не открыт этому сотруднику");
  }
}

function knowledgeVisible(ctx, id, p) {
  if (ctx.isOwner || ctx.knowledgeAll) return true;
  const parentId = String((p && p.parentId) || "");
  return ctx.knowledgeIds.indexOf(String(id || "")) >= 0 ||
      (!!parentId && ctx.knowledgeIds.indexOf(parentId) >= 0);
}

function requireChat(txApp, ctx, chatId) {
  const row = require(`${__hooks}/wesi_sync_data_access.js`).first(
    txApp,
    "wesios_records",
    "owner={:owner} && coll='chats' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: String(chatId || "")},
  );
  if (!row || !chatVisible(ctx, payloadOf(row))) {
    forbidden("Нет доступа к сообщениям этого чата");
  }
}

function authorize(txApp, existing, input, ctx) {
  const coll = input.coll;
  const before = payloadOf(existing);
  const target = input.deleted ? before : input.payload;

  if (coll === "crm_clients" || coll === "crm_deals" || coll === "crm_interactions" ||
      coll === "file_requests" || coll === "file_grants" || coll === "file_handovers") {
    forbidden("Для коллекции требуется специализированный sync route");
  }

  if (coll === "employees") {
    if (ctx.isOwner) return;
    if (!existing || input.deleted || input.rid !== ctx.employeeId) {
      forbidden("Сотрудник может синхронизировать только свою аватарку");
    }
    // Preserve the transaction-current employee row. A preflight merge based
    // on an older snapshot must never revert owner-updated permissions/contact
    // fields while the employee uploads a new avatar.
    input.payload = Object.assign({}, before, {
      avatarIndex: Number(input.payload.avatarIndex || 0),
      photo: input.payload.photo == null ? null : input.payload.photo,
    });
    return;
  }

  if (coll === "organizations") {
    if (ctx.isOwner) return;
    const beforeOrg = String(before.id || input.rid);
    const targetOrg = String(target.id || input.rid);
    if (!grantApplies(ctx, beforeOrg, "manage_org_settings") ||
        !grantApplies(ctx, targetOrg, "manage_org_settings")) {
      forbidden("Нет права менять организацию");
    }
    return;
  }

  if (coll === "organization_grants") {
    if (!ctx.isOwner) forbidden("Изменять права сотрудников может владелец");
    return;
  }

  if (coll === "accounts") {
    requireFinance(ctx);
    const oldOrg = orgIdOf(before);
    const newOrg = orgIdOf(target);
    if ((existing && !grantApplies(ctx, oldOrg, "manage_accounts")) ||
        !grantApplies(ctx, newOrg, "manage_accounts")) {
      forbidden("Нет права изменять счета этой организации");
    }
    return;
  }

  if (coll === "transactions") {
    requireFinance(ctx);
    const oldOrg = orgIdOf(before);
    const newOrg = orgIdOf(target);
    if (existing && !grantApplies(ctx, oldOrg, "edit_transactions")) {
      forbidden("Нет права изменять исходную операцию");
    }
    const needed = existing ? "edit_transactions" : "create_transactions";
    if (!grantApplies(ctx, newOrg, needed)) {
      forbidden("Нет права изменять операции этой организации");
    }
    if (before.isRecurring === true && !grantApplies(ctx, oldOrg, "manage_recurring")) {
      forbidden("Нет права изменять исходную регулярную операцию");
    }
    if (target.isRecurring === true && !grantApplies(ctx, newOrg, "manage_recurring")) {
      forbidden("Нет права изменять регулярные операции");
    }
    return;
  }

  if (coll === "tasks") {
    if (!hasModule(ctx, "tasks")) forbidden("Раздел не открыт этому сотруднику");
    const oldOrg = orgIdOf(before);
    const newOrg = orgIdOf(target);
    if ((existing && (ctx.allowedOrgIds[oldOrg] !== true || !taskOwned(ctx, before))) ||
        ctx.allowedOrgIds[newOrg] !== true || !taskOwned(ctx, target)) {
      forbidden("Нет права изменять эту задачу");
    }
    if (!ctx.isOwner && !ctx.canManageTeam && !ctx.canAssignTasks && !input.deleted) {
      const assignee = String(target.assignee || "");
      const responsible = String(target.responsibleEmployeeId || "");
      if ((assignee && assignee !== ctx.employeeId) ||
          (responsible && responsible !== ctx.employeeId)) {
        forbidden("Нельзя назначать задачу другому сотруднику");
      }
    }
    return;
  }

  if (coll === "inter_org_transfers") {
    requireFinance(ctx);
    if (ctx.isOwner) return;
    for (const p of existing ? [before, target] : [target]) {
      const fromOrg = String(p.fromOrganizationId || p.sourceOrganizationId || "");
      const toOrg = String(p.toOrganizationId || p.destinationOrganizationId || "");
      if (!fromOrg || !toOrg ||
          !grantApplies(ctx, fromOrg, "create_transactions") ||
          !grantApplies(ctx, toOrg, "create_transactions")) {
        forbidden("Нет права на межорганизационный перевод");
      }
    }
    return;
  }

  if (coll === "transaction_audit" || coll === "critical_audit") {
    if (existing || input.deleted) forbidden("Журнал аудита только дополняется");
    if (coll === "transaction_audit") {
      requireFinance(ctx);
      const org = orgIdOf(target);
      if (!ctx.isOwner && (!grantApplies(ctx, org, "view_finance") ||
          String(target.changedBy || "") !== ctx.employeeId)) {
        forbidden("Нельзя отправить чужую запись финансового аудита");
      }
    } else if (!ctx.isOwner) {
      const org = orgIdOf(target);
      if (ctx.allowedOrgIds[org] !== true || String(target.actorId || "") !== ctx.employeeId) {
        forbidden("Нельзя отправить чужую запись аудита");
      }
    }
    return;
  }

  if (coll === "calendar_events") {
    if (!hasModule(ctx, "calendar")) forbidden("Раздел не открыт этому сотруднику");
    return;
  }

  if (coll === "articles") {
    if (!hasModule(ctx, "knowledge")) forbidden("Раздел не открыт этому сотруднику");
    if (existing && !knowledgeVisible(ctx, input.rid, before)) {
      forbidden("Нет права изменять исходный раздел базы знаний");
    }
    if (!knowledgeVisible(ctx, input.rid, target)) {
      forbidden("Нет права изменять этот раздел базы знаний");
    }
    return;
  }

  if (coll === "chats") {
    if (!hasModule(ctx, "chats")) forbidden("Раздел не открыт этому сотруднику");
    if ((existing && !chatVisible(ctx, before)) || !chatVisible(ctx, target)) {
      forbidden("Нет доступа к этому чату");
    }
    return;
  }

  if (coll === "messages") {
    if (!hasModule(ctx, "chats")) forbidden("Раздел не открыт этому сотруднику");
    if (existing) requireChat(txApp, ctx, before.chatId);
    requireChat(txApp, ctx, target.chatId);
    return;
  }

  if (coll === "roadmap_projects" || coll === "roadmap_items" || coll === "roadmap_state") {
    if (!hasModule(ctx, "roadmap")) forbidden("Раздел не открыт этому сотруднику");
    return;
  }

  if (coll === "audio_beats") {
    if (!hasModule(ctx, "audio")) forbidden("Раздел не открыт этому сотруднику");
    return;
  }
}

module.exports = {authorize, payloadOf, grantApplies, taskOwned, chatVisible};