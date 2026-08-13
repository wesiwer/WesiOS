routerAdd("POST", "/api/wesi/sync/{collection}", (e) => {
  const ctx = e.get("wesiSyncContext");
  if (!ctx) throw new UnauthorizedError("Нет контекста синхронизации");
  const collection = String(e.request.pathValue("collection") || "");
  const privateCollections = {"profile_private": true, "vault_private": true};
  const known = {
    "organizations": true, "employees": true, "organization_grants": true,
    "accounts": true, "transactions": true, "tasks": true,
    "inter_org_transfers": true, "transaction_audit": true,
    "critical_audit": true, "calendar_events": true, "articles": true,
    "chats": true, "messages": true, "roadmap_state": true,
    "crm_state": true, "profile_private": true, "vault_private": true,
    // Появились, когда синхронизация перешла с «один список одной строкой»
    // на запись за записью. Без них сервер отвечал 400 на первой же новой
    // коллекции, и обмен вставал целиком — включая те коллекции, что он
    // знал: проход по списку не доходил до конца.
    "roadmap_projects": true, "roadmap_items": true,
    "crm_clients": true, "crm_deals": true, "crm_interactions": true,
    "audio_beats": true, "profile": true,
    "file_grants": true, "file_requests": true, "file_handovers": true
  };
  if (!known[collection]) throw new BadRequestError("Неизвестная коллекция синхронизации");

  const body = e.requestInfo().body || {};
  const rid = String(body.rid || "").trim();
  if (!rid || rid.length > 180) throw new BadRequestError("Некорректный id синхронизации");
  let incoming = body.payload && typeof body.payload === "object" ? body.payload : {};
  const deleted = body.deleted === true;
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
  let existing = null;
  try {
    existing = e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && rid={:rid}",
      {"owner": ownerScope, "coll": collection, "rid": rid},
    );
  } catch (_) { existing = null; }
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
    // Authenticated-account scope is sufficient; records never share owner id
    // with another employee.
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
    if (!ctx.isOwner) {
      // Client code contains additional delegation checks, but server is the
      // authority boundary. Until those checks have a server equivalent only
      // the owner may alter grants; reads for the employee still synchronize.
      throw new ForbiddenError("Изменять права сотрудников может владелец");
    }
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
    if (deleted || existing) {
      throw new ForbiddenError("Журнал аудита только дополняется");
    }
    if (collection === "transaction_audit") {
      requireFinanceModule();
      const orgId = orgIdOf(incoming);
      if (!ctx.isOwner && (!grantApplies(orgId, "view_finance") ||
          String(incoming.changedBy || "") !== ctx.employeeId)) {
        throw new ForbiddenError("Нельзя отправить чужую запись финансового аудита");
      }
    } else if (!ctx.isOwner) {
      const orgId = orgIdOf(incoming);
      if (ctx.allowedOrgIds[orgId] !== true ||
          String(incoming.actorId || "") !== ctx.employeeId) {
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
    let chat = null;
    try {
      chat = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner={:owner} && coll='chats' && rid={:rid} && deleted=false",
        {"owner": ctx.ownerId, "rid": chatId},
      );
    } catch (_) { chat = null; }
    if (!chat || !chatVisible(payloadOf(chat))) {
      throw new ForbiddenError("Нет доступа к сообщениям этого чата");
    }
  } else if (collection === "roadmap_state") {
    requireModule("roadmap");
    if (["projects_v1", "items_v1"].indexOf(rid) < 0) {
      throw new BadRequestError("Некорректный раздел Roadmap");
    }
  } else if (collection === "crm_state") {
    requireModule("crm");
    if (["clients_v1", "deals_v1", "interactions_v1"].indexOf(rid) < 0) {
      throw new BadRequestError("Некорректный раздел CRM");
    }
    if (!ctx.isOwner) {
      if (deleted) throw new ForbiddenError("Нельзя удалить весь раздел CRM");
      const parseList = (value) => {
        if (Array.isArray(value)) return value;
        if (typeof value !== "string" || !value.trim()) return [];
        try {
          const parsed = JSON.parse(value);
          return Array.isArray(parsed) ? parsed : [];
        } catch (_) { throw new BadRequestError("Повреждённый CRM snapshot"); }
      };
      const incomingRows = parseList(incoming.value);
      const existingRows = parseList(before.value);
      const manager = ctx.canManageTeam;
      const allowedOrg = (row) => ctx.allowedOrgIds[String(row.organizationId || "org_wesi_inc")] === true;

      // Load the other CRM snapshots to validate cross references.
      const state = {};
      let crmRows = [];
      try {
        crmRows = e.app.findRecordsByFilter(
          "wesios_records",
          "owner={:owner} && coll='crm_state' && deleted=false",
          "id", 0, 0, {"owner": ctx.ownerId},
        );
      } catch (_) { crmRows = []; }
      for (const row of crmRows) {
        const p = payloadOf(row);
        state[String(p.key || row.getString("rid"))] = parseList(p.value);
      }
      state[rid] = existingRows;
      const clients = state.clients_v1 || [];
      const deals = state.deals_v1 || [];
      const clientById = {};
      for (const c of clients) clientById[String(c.id || "")] = c;

      const visible = (row) => {
        if (rid === "clients_v1") {
          if (!allowedOrg(row)) return false;
          if (manager) return true;
          if (String(row.ownerEmployeeId || "") === ctx.employeeId) return true;
          return deals.some((d) => allowedOrg(d) &&
            String(d.clientId || "") === String(row.id || "") &&
            String(d.responsibleEmployeeId || "") === ctx.employeeId);
        }
        if (rid === "deals_v1") {
          if (!allowedOrg(row)) return false;
          if (manager) return true;
          const client = clientById[String(row.clientId || "")] || {};
          return String(row.responsibleEmployeeId || "") === ctx.employeeId ||
            String(client.ownerEmployeeId || "") === ctx.employeeId;
        }
        const visibleClientIds = {};
        const visibleDealIds = {};
        for (const c of clients) {
          if (allowedOrg(c) && (manager || String(c.ownerEmployeeId || "") === ctx.employeeId)) {
            visibleClientIds[String(c.id || "")] = true;
          }
        }
        for (const d of deals) {
          if (!allowedOrg(d)) continue;
          const client = clientById[String(d.clientId || "")] || {};
          if (manager || String(d.responsibleEmployeeId || "") === ctx.employeeId ||
              String(client.ownerEmployeeId || "") === ctx.employeeId) {
            visibleDealIds[String(d.id || "")] = true;
            visibleClientIds[String(d.clientId || "")] = true;
          }
        }
        return visibleClientIds[String(row.clientId || "")] === true &&
          (!row.dealId || visibleDealIds[String(row.dealId || "")] === true);
      };

      // A shared workstation can still contain rows cached by the previous
      // account. Never reject the whole snapshot because of those rows: drop
      // them from the candidate set and preserve the authoritative hidden
      // server rows unchanged. This lets the current employee sync their own
      // CRM changes without gaining a write channel to someone else's data.
      const accepted = [];
      for (const row of incomingRows) {
        if (!visible(row)) continue;
        if (!manager && rid === "clients_v1" && row.ownerEmployeeId &&
            String(row.ownerEmployeeId) !== ctx.employeeId) continue;
        if (!manager && rid === "deals_v1" && row.responsibleEmployeeId &&
            String(row.responsibleEmployeeId) !== ctx.employeeId) continue;
        accepted.push(row);
      }
      const retained = existingRows.filter((row) => !visible(row));
      incoming = {"key": rid, "value": JSON.stringify(retained.concat(accepted))};
    }
  } else if (collection === "roadmap_projects" || collection === "roadmap_items") {
    requireModule("roadmap");
  } else if (collection === "crm_clients" || collection === "crm_deals" ||
             collection === "crm_interactions") {
    // Теперь запись за записью, а не весь раздел одной строкой. Проверка
    // организации поэтому идёт по самой записи, а не по всему списку.
    requireModule("crm");
    if (!ctx.isOwner) {
      const target = deleted ? before : incoming;
      const orgId = String((target && target.organizationId) || "org_wesi_inc");
      if (ctx.allowedOrgIds[orgId] !== true) {
        throw new ForbiddenError("Нет доступа к этой организации");
      }
    }
  } else if (collection === "audio_beats") {
    requireModule("audio");
  } else if (collection === "profile") {
    // Профиль правит только его хозяин: чужую карточку через этот путь
    // переписать нельзя даже тому, кто управляет командой.
    if (!ctx.isOwner && rid !== ctx.employeeId && rid !== "me") {
      throw new ForbiddenError("Чужой профиль править нельзя");
    }
  } else if (collection === "file_grants" || collection === "file_requests" ||
             collection === "file_handovers") {
    // Доступ к файлам живёт рядом с модулем аудио: биты и документы
    // раздаются оттуда.
    requireModule("audio");
    if (!ctx.isOwner && collection === "file_grants") {
      // Выдать себе доступ к чужому файлу нельзя — это и есть весь смысл
      // разграничения. Право выдавать есть у владельца и у того, кто
      // управляет командой.
      if (!ctx.canManageTeam) {
        throw new ForbiddenError("Выдавать доступ к файлам может владелец");
      }
    }
  }

  // A tombstone keeps the previous payload so other devices can still apply
  // row-level visibility rules and receive the deletion.
  if (deleted && existing) incoming = before;

  const recordsCollection = e.app.findCollectionByNameOrId("wesios_records");
  const record = existing || new Record(recordsCollection);
  record.set("owner", ownerScope);
  record.set("org", privateCollections[collection] ? "private:" + ctx.employeeId : "wesi-inc");
  record.set("coll", collection);
  record.set("rid", rid);
  record.set("payload", incoming);
  record.set("stamp", stamp);
  record.set("deleted", deleted);
  e.app.save(record);

  return e.json(200, {"ok": true, "rid": rid, "stamp": stamp});
}, $apis.requireAuth("users"));