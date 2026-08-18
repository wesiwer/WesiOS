routerAdd("POST", "/api/wesi/sync/{collection}", (e) => {
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

  if (collection === "roadmap_state" || collection === "crm_state") {
    throw new BadRequestError(
      "Эта версия WesiOS использует устаревший формат Roadmap/CRM. Обновите приложение перед синхронизацией"
    );
  }

  // CRM/File metadata have exact handlers with stronger row-level policy. A
  // partial hook deployment must fail closed rather than fall through here.
  if (collection === "crm_clients" ||
      collection === "crm_deals" ||
      collection === "crm_interactions" ||
      collection === "file_requests" ||
      collection === "file_grants" ||
      collection === "file_handovers") {
    throw new ForbiddenError("Dedicated sync route is not available");
  }

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) throw new BadRequestError("Некорректный id синхронизации");
  let incoming = body.payload && typeof body.payload === "object" ? body.payload : {};
  const deleted = body.deleted === true;

  if (deleted && (
      collection === "organizations" ||
      collection === "accounts" ||
      collection === "inter_org_transfers")) {
    throw new BadRequestError(
      "Эту запись нельзя удалять через синхронизацию; используйте изменение или архивирование"
    );
  }

  const suppliedStamp = Date.parse(String(body.stamp || ""));
  const now = Date.now();
  const stamp = Number.isFinite(suppliedStamp) && suppliedStamp <= now + 5 * 60 * 1000
    ? new Date(suppliedStamp).toISOString() : new Date(now).toISOString();
  if (incoming.id != null && String(incoming.id) !== rid) {
    throw new BadRequestError("id записи не совпадает с rid");
  }
  if (incoming.key != null) {
    const key = String(incoming.key);
    const expectedRid = privateCollections[collection]
      ? String(ctx.employeeId) + "::" + key
      : key;
    if (expectedRid !== rid) {
      throw new BadRequestError("key записи не совпадает с rid");
    }
  }

  const payloadOf = (record) => {
    try {
      const raw = record.get("payload");
      if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
      if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
    } catch (_) {}
    return {};
  };
  const hasModule = (name) => ctx.isOwner || ctx.modules.indexOf(name) >= 0;
  const hasAnyModule = (names) => ctx.isOwner || names.some((n) => ctx.modules.indexOf(n) >= 0);
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
  const orgIdOf = (p) => String(p.organizationId || p.orgId || "org_wesi_inc");
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
  let existing = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
    "wesios_records",
    "owner={:owner} && coll={:coll} && rid={:rid}",
    {"owner": ownerScope, "coll": collection, "rid": rid},
  );
  const before = existing ? payloadOf(existing) : {};

  const requireModule = (name) => {
    if (!hasModule(name)) throw new ForbiddenError("Раздел не открыт этому сотруднику");
  };
  const requireFinanceModule = () => {
    if (!hasAnyModule(["treasury", "forecast", "sandbox", "analytics"])) {
      throw new ForbiddenError("Финансовый раздел не открыт этому сотруднику");
    }
  };

  if (privateCollections[collection]) {
    // Authenticated-account scope is sufficient.
  } else if (collection === "employees") {
    if (!ctx.isOwner) {
      if (rid !== ctx.employeeId || deleted || !existing) {
        throw new ForbiddenError("Сотрудник может синхронизировать только свою аватарку");
      }
      incoming = Object.assign({}, before, {
        "avatarIndex": Number(incoming.avatarIndex || 0),
        "photo": incoming.photo == null ? null : incoming.photo
      });
    }
  } else if (collection === "organizations") {
    if (!ctx.isOwner) {
      const orgId = String(incoming.id || before.id || rid);
      if (!grantApplies(orgId, "manage_org_settings")) {
        throw new ForbiddenError("Нет права менять организацию");
      }
    }
  } else if (collection === "organization_grants") {
    if (!ctx.isOwner) throw new ForbiddenError("Изменять права сотрудников может владелец");
  } else if (collection === "accounts") {
    requireFinanceModule();
    const orgId = orgIdOf(deleted ? before : incoming);
    if (!grantApplies(orgId, "manage_accounts")) {
      throw new ForbiddenError("Нет права изменять счета этой организации");
    }
  } else if (collection === "transactions") {
    requireFinanceModule();
    const target = deleted ? before : incoming;
    const orgId = orgIdOf(target);
    const permission = existing ? "edit_transactions" : "create_transactions";
    if (!grantApplies(orgId, permission)) {
      throw new ForbiddenError("Нет права изменять операции этой организации");
    }
    if ((target.isRecurring === true || before.isRecurring === true) &&
        !grantApplies(orgId, "manage_recurring")) {
      throw new ForbiddenError("Нет права изменять регулярные операции");
    }
  } else if (collection === "tasks") {
    requireModule("tasks");
    const target = deleted ? before : incoming;
    const orgId = orgIdOf(target);
    if (ctx.allowedOrgIds[orgId] !== true || !taskOwned(target)) {
      throw new ForbiddenError("Нет права изменять эту задачу");
    }
    if (!ctx.isOwner && !ctx.canManageTeam && !ctx.canAssignTasks) {
      const assignee = String(target.assignee || "");
      const responsible = String(target.responsibleEmployeeId || "");
      if ((assignee && assignee !== ctx.employeeId) ||
          (responsible && responsible !== ctx.employeeId)) {
        throw new ForbiddenError("Нельзя назначать задачу другому сотруднику");
      }
    }
  } else if (collection === "inter_org_transfers") {
    requireFinanceModule();
    if (!ctx.isOwner) {
      const target = deleted ? before : incoming;
      const fromOrg = String(target.fromOrganizationId || target.sourceOrganizationId || "");
      const toOrg = String(target.toOrganizationId || target.destinationOrganizationId || "");
      if (!fromOrg || !toOrg || !grantApplies(fromOrg, "create_transactions") ||
          !grantApplies(toOrg, "create_transactions")) {
        throw new ForbiddenError("Нет права на межорганизационный перевод");
      }
    }
  } else if (collection === "transaction_audit" || collection === "critical_audit") {
    if (deleted || existing) throw new ForbiddenError("Журнал аудита только дополняется");
    if (collection === "transaction_audit") {
      requireFinanceModule();
      const orgId = orgIdOf(incoming);
      if (!ctx.isOwner && (!grantApplies(orgId, "view_finance") ||
          String(incoming.changedBy || "") !== ctx.employeeId)) {
        throw new ForbiddenError("Нельзя отправить чужую запись финансового аудита");
      }
    } else if (!ctx.isOwner) {
      const orgId = orgIdOf(incoming);
      if (ctx.allowedOrgIds[orgId] !== true || String(incoming.actorId || "") !== ctx.employeeId) {
        throw new ForbiddenError("Нельзя отправить чужую запись аудита");
      }
    }
  } else if (collection === "calendar_events") {
    requireModule("calendar");
  } else if (collection === "articles") {
    requireModule("knowledge");
    if (!ctx.isOwner && !ctx.knowledgeAll &&
        ctx.knowledgeIds.indexOf(rid) < 0 &&
        ctx.knowledgeIds.indexOf(String(incoming.parentId || before.parentId || "")) < 0) {
      throw new ForbiddenError("Нет права изменять этот раздел базы знаний");
    }
  } else if (collection === "chats") {
    requireModule("chats");
    const target = deleted ? before : incoming;
    if (!chatVisible(target)) throw new ForbiddenError("Нет доступа к этому чату");
  } else if (collection === "messages") {
    requireModule("chats");
    const target = deleted ? before : incoming;
    const chatId = String(target.chatId || "");
    const chat = require(`${__hooks}/wesi_sync_data_access.js`).first(e.app,
      "wesios_records",
      "owner={:owner} && coll='chats' && rid={:rid} && deleted=false",
      {"owner": ctx.ownerId, "rid": chatId},
    );
    if (!chat || !chatVisible(payloadOf(chat))) {
      throw new ForbiddenError("Нет доступа к сообщениям этого чата");
    }
  } else if (collection === "roadmap_projects" || collection === "roadmap_items") {
    requireModule("roadmap");
  } else if (collection === "audio_beats") {
    requireModule("audio");
  } else if (collection === "profile") {
    if (!ctx.isOwner && rid !== ctx.employeeId && rid !== "me") {
      throw new ForbiddenError("Чужой профиль править нельзя");
    }
  }

  if (deleted && existing) incoming = before;

  const committed = require(`${__hooks}/wesi_sync_atomic.js`).commit(e.app, {
    "owner": ownerScope,
    "org": privateCollections[collection] ? "private:" + ctx.employeeId : "wesi-inc",
    "coll": collection,
    "rid": rid,
    "payload": incoming,
    "stamp": stamp,
    "deleted": deleted,
    "authorize": function(txApp, current, input) {
      require(`${__hooks}/wesi_sync_generic_policy.js`).authorize(
        txApp,
        current,
        input,
        ctx,
      );
    }
  });

  return e.json(200, {
    "ok": true,
    "rid": rid,
    "stamp": committed.stamp,
    "applied": committed.applied,
    "reason": committed.reason
  });
}, $apis.requireAuth("users"));