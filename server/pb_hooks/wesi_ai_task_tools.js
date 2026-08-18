const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");
const syncWriter = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_sync_writer.js");
const ROOT_ORG = "org_wesi_inc";

function payloadOf(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function recordAudit(e, ctx, entry) { return false; }

function loadAccess(e, ctx) {
  let permissions = {};
  if (ctx.isOwner) {
    permissions = {canManageTeam: true, canSeeOthersStats: true, canAssignTasks: true};
  } else {
    const employee = dataAccess.first(e.app,
        "wesios_records",
        "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, rid: ctx.employeeId},
      );
    const snapshot = payloadOf(employee);
    permissions = snapshot.permissions && typeof snapshot.permissions === "object"
      ? snapshot.permissions : {};
  }

  const organizations = dataAccess.records(e.app,
      "wesios_records", "owner={:owner} && coll='organizations' && deleted=false",
      "id", 1000, 0, {owner: ctx.ownerId},
    );
  const grants = dataAccess.records(e.app,
      "wesios_records", "owner={:owner} && coll='organization_grants' && deleted=false",
      "id", 1000, 0, {owner: ctx.ownerId},
    );

  const orgs = {};
  const parents = {};
  for (const row of organizations) {
    const p = payloadOf(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    orgs[id] = {id: id, name: String(p.name || id), parentId: p.parentId == null ? null : String(p.parentId)};
    parents[id] = orgs[id].parentId;
  }

  const allowed = {};
  if (ctx.isOwner) {
    for (const id of Object.keys(orgs)) allowed[id] = true;
  } else {
    const own = [];
    for (const row of grants) {
      const p = payloadOf(row);
      if (String(p.employeeId || "") === ctx.employeeId) own.push(p);
    }
    for (const g of own) {
      const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
      if (perms.indexOf("view") < 0) continue;
      const id = String(g.organizationId || "");
      if (orgs[id]) allowed[id] = true;
      if (g.includeSubtree === true) {
        for (const childId of Object.keys(orgs)) {
          let cursor = parents[childId];
          while (cursor) {
            if (cursor === id) { allowed[childId] = true; break; }
            cursor = parents[cursor];
          }
        }
      }
    }
  }

  return {
    permissions: permissions,
    orgs: orgs,
    allowedOrgIds: allowed,
    canReadOthers: ctx.isOwner || permissions.canManageTeam === true || permissions.canAssignTasks === true,
    canAssignOthers: ctx.isOwner || permissions.canManageTeam === true || permissions.canAssignTasks === true,
  };
}

function chooseOrganization(access, requested) {
  const id = String(requested || "").trim();
  if (id && access.allowedOrgIds[id] === true && access.orgs[id]) return id;
  if (access.allowedOrgIds[ROOT_ORG] === true && access.orgs[ROOT_ORG]) return ROOT_ORG;
  const ids = Object.keys(access.allowedOrgIds).filter((x) => access.allowedOrgIds[x] === true && access.orgs[x]);
  return ids.length ? ids[0] : "";
}

function employees(e, ctx) {
  const rows = dataAccess.records(e.app,
      "wesios_records", "owner={:owner} && coll='employees' && deleted=false",
      "id", 1000, 0, {owner: ctx.ownerId},
    );
  return rows.map((row) => {
    const p = payloadOf(row);
    return {
      id: String(p.id || row.getString("rid") || ""),
      login: String(p.login || ""),
      fullName: String(p.fullName || ""),
      nickname: String(p.nickname || ""),
    };
  }).filter((x) => x.id);
}

function resolveEmployee(e, ctx, query) {
  const q = String(query || "").trim().toLowerCase();
  if (!q) return {id: ctx.employeeId, label: ctx.employeeId};
  const all = employees(e, ctx);
  const exact = all.filter((x) => [x.id, x.login, x.fullName, x.nickname].some((v) => v && v.toLowerCase() === q));
  if (exact.length === 1) return {id: exact[0].id, label: exact[0].fullName || exact[0].nickname || exact[0].login || exact[0].id};
  const partial = all.filter((x) => [x.login, x.fullName, x.nickname].some((v) => v && v.toLowerCase().includes(q)));
  if (partial.length === 1) return {id: partial[0].id, label: partial[0].fullName || partial[0].nickname || partial[0].login || partial[0].id};
  if (exact.length > 1 || partial.length > 1) return {error: "AMBIGUOUS_EMPLOYEE"};
  return {error: "EMPLOYEE_NOT_FOUND"};
}

function taskVisible(access, ctx, p) {
  const orgId = String(p.organizationId || ROOT_ORG);
  if (access.allowedOrgIds[orgId] !== true) return false;
  if (access.canReadOthers) return true;
  return String(p.assignee || "") === ctx.employeeId || String(p.responsibleEmployeeId || "") === ctx.employeeId;
}

function localDay(value, offsetMinutes) {
  const date = value instanceof Date ? value : new Date(String(value || ""));
  if (!Number.isFinite(date.getTime())) return "";
  const offset = Math.max(-840, Math.min(840, Number(offsetMinutes || 0)));
  return new Date(date.getTime() + offset * 60000).toISOString().slice(0, 10);
}

function dayState(value, now, offsetMinutes) {
  if (!value) return "none";
  const dueDay = localDay(value, offsetMinutes);
  const nowDay = localDay(now, offsetMinutes);
  if (!dueDay || !nowDay) return "none";
  if (dueDay < nowDay) return "overdue";
  if (dueDay === nowDay) return "today";
  return "future";
}

module.exports = {
  definitions: function(e, ctx) {
    if (!ctx.isOwner && ctx.modules.indexOf("tasks") < 0) return [];
    return [
      {name: "tasks_list", description: "Получить реальные задачи WesiOS, доступные текущему сотруднику. При активной организации список ограничивается ею; dueMode позволяет получить задачи на сегодня или просроченные.", parameters: {type: "object", properties: {organizationId: {type: "string"}, status: {type: "string", enum: ["backlog", "inProgress", "review", "done"]}, dueMode: {type: "string", enum: ["today", "overdue"]}, timezoneOffsetMinutes: {type: "integer", minimum: -840, maximum: 840}, limit: {type: "integer", minimum: 1, maximum: 100}}}},
      {name: "tasks_create", description: "Создать реальную задачу WesiOS. Можно назначить другому сотруднику только при наличии соответствующего права.", parameters: {type: "object", required: ["title"], properties: {title: {type: "string"}, description: {type: "string"}, dueDate: {type: "string", description: "ISO date YYYY-MM-DD"}, assignee: {type: "string", description: "Имя, логин или id сотрудника; пусто означает текущего сотрудника"}, organizationId: {type: "string"}, priority: {type: "string", enum: ["low", "normal", "high", "urgent"]}}},
    ];
  },

  context: function(e, ctx, activeOrganizationId) {
    const access = loadAccess(e, ctx);
    const visible = Object.keys(access.allowedOrgIds).filter((id) => access.allowedOrgIds[id] === true && access.orgs[id]).map((id) => ({id: id, name: access.orgs[id].name}));
    return {serverTime: new Date().toISOString(), activeOrganizationId: chooseOrganization(access, activeOrganizationId), organizations: visible, canAssignTasksToOthers: access.canAssignOthers};
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    if (!ctx.isOwner && ctx.modules.indexOf("tasks") < 0) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к модулю задач"};
    const access = loadAccess(e, ctx);
    const input = args && typeof args === "object" ? args : {};

    if (name === "tasks_list") {
      const rows = dataAccess.records(e.app,
          "wesios_records", "owner={:owner} && coll='tasks' && deleted=false",
          "-stamp", 5000, 0, {owner: ctx.ownerId},
        );
      const status = String(input.status || "");
      const dueMode = String(input.dueMode || "");
      if (dueMode && ["today", "overdue"].indexOf(dueMode) < 0) {
        return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный dueMode"};
      }
      const timezoneOffsetMinutes = Math.max(-840, Math.min(840, Number(input.timezoneOffsetMinutes || 0)));
      const requestedOrg = String(activeOrganizationId || input.organizationId || "").trim();
      let organizationId = "";
      if (requestedOrg) {
        organizationId = chooseOrganization(access, requestedOrg);
        if (!organizationId || organizationId !== requestedOrg) {
          return {ok: false, code: "FORBIDDEN", message: "Нет доступа к задачам этой организации"};
        }
      }
      const limit = Math.max(1, Math.min(100, Number(input.limit || 20)));
      const now = new Date();
      const out = [];
      let totalCount = 0;
      for (const row of rows) {
        const p = payloadOf(row);
        if (!taskVisible(access, ctx, p)) continue;
        const taskOrgId = String(p.organizationId || ROOT_ORG);
        if (organizationId && taskOrgId !== organizationId) continue;
        if (status && String(p.status || "backlog") !== status) continue;
        if (dueMode && dayState(p.dueDate, now, timezoneOffsetMinutes) !== dueMode) continue;
        totalCount++;
        if (out.length >= limit) continue;
        out.push({id: String(p.id || row.getString("rid")), title: String(p.title || ""), status: String(p.status || "backlog"), priority: String(p.priority || "normal"), dueDate: p.dueDate || null, assignee: p.assignee || null, organizationId: taskOrgId});
      }
      return {ok: true, result: {organizationId: organizationId || null, timezoneOffsetMinutes: timezoneOffsetMinutes, totalCount: totalCount, tasks: out}};
    }

    if (name === "tasks_create") {
      const title = String(input.title || "").trim();
      if (!title || title.length > 500) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректное название задачи"};
      const target = resolveEmployee(e, ctx, input.assignee);
      if (target.error) return {ok: false, code: target.error, message: target.error === "AMBIGUOUS_EMPLOYEE" ? "Найдено несколько сотрудников с таким именем" : "Сотрудник не найден"};
      const requestedOrg = String(activeOrganizationId || input.organizationId || ROOT_ORG);
      if (target.id !== ctx.employeeId && !access.canAssignOthers) {
        recordAudit(e, ctx, {tool: "tasks_create", entityType: "wesi_ai_action", entityId: "tasks_create", organizationId: requestedOrg, ok: false, code: "FORBIDDEN", targetEmployeeId: target.id});
        return {ok: false, code: "FORBIDDEN", message: "Нет права назначать задачи другим сотрудникам", alternatives: ["Создать задачу себе", "Подготовить текст для руководителя"]};
      }
      const orgId = chooseOrganization(access, activeOrganizationId || input.organizationId);
      if (!orgId) return {ok: false, code: "FORBIDDEN", message: "Нет доступной организации для задачи"};
      let dueDate = null;
      if (input.dueDate != null && String(input.dueDate).trim()) {
        const raw = String(input.dueDate).trim();
        if (!/^\d{4}-\d{2}-\d{2}$/.test(raw) || !Number.isFinite(Date.parse(raw + "T12:00:00Z"))) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный срок задачи"};
        dueDate = raw + "T12:00:00.000Z";
      }
      const priority = ["low", "normal", "high", "urgent"].indexOf(String(input.priority || "normal")) >= 0 ? String(input.priority || "normal") : "normal";
      const now = new Date().toISOString();
      const id = "wai_task_" + Date.now() + "_" + $security.randomString(8);
      const value = {
        id: id,
        title: title,
        description: input.description == null ? null : String(input.description).slice(0, 10000),
        status: "backlog",
        priority: priority,
        createdAt: now,
        dueDate: dueDate,
        assignee: target.id,
        tags: ["wesios:org:" + orgId, "wesios:employee:" + target.id],
        order: 0,
        organizationId: orgId,
        responsibleEmployeeId: target.id,
        subtasks: [],
      };
      const saved = syncWriter.write(e, ctx, {coll: "tasks", rid: id, next: value, creating: true});
      if (!saved.applied) return {ok: false, code: "WRITE_CONFLICT", message: "Задача изменилась параллельно, повторите действие"};
      const out = saved.payload;
      recordAudit(e, ctx, {tool: "tasks_create", entityType: "task", entityId: id, organizationId: String(out.organizationId || orgId), ok: true, targetEmployeeId: String(out.assignee || target.id)});
      return {ok: true, result: {task: {id: id, title: String(out.title || title), dueDate: out.dueDate || null, assigneeId: String(out.assignee || target.id), assignee: target.label, organizationId: String(out.organizationId || orgId)}}};
    }

    return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный инструмент Wesi AI"};
  },
};