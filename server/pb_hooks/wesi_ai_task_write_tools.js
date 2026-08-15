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

function rows(e, ctx, coll) {
  try {
    return e.app.findRecordsByFilter(
      "wesios_records", "owner={:owner} && coll={:coll} && deleted=false",
      "id", 0, 0, {owner: ctx.ownerId, coll: coll},
    );
  } catch (_) { return []; }
}

function loadAccess(e, ctx) {
  let permissions = {};
  if (ctx.isOwner) {
    permissions = {canManageTeam: true, canAssignTasks: true};
  } else {
    let employee = null;
    try {
      employee = e.app.findFirstRecordByFilter(
        "wesios_records",
        "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, rid: ctx.employeeId},
      );
    } catch (_) { employee = null; }
    const p = payloadOf(employee);
    permissions = p.permissions && typeof p.permissions === "object" ? p.permissions : {};
  }

  const orgs = {};
  const parents = {};
  for (const row of rows(e, ctx, "organizations")) {
    const p = payloadOf(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    orgs[id] = p;
    parents[id] = p.parentId == null ? null : String(p.parentId);
  }
  const grants = rows(e, ctx, "organization_grants").map(payloadOf).filter(function(g) {
    return String(g.employeeId || "") === ctx.employeeId;
  });
  const allowed = {};
  if (ctx.isOwner) {
    for (const id of Object.keys(orgs)) allowed[id] = true;
  } else {
    for (const id of Object.keys(orgs)) {
      let cursor = id;
      let first = true;
      while (cursor) {
        const hit = grants.some(function(g) {
          if (String(g.organizationId || "") !== cursor) return false;
          if (!first && g.includeSubtree !== true) return false;
          const perms = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
          return perms.indexOf("view") >= 0;
        });
        if (hit) { allowed[id] = true; break; }
        first = false;
        cursor = parents[cursor];
      }
    }
  }
  return {
    allowedOrgIds: allowed,
    canManageTeam: ctx.isOwner || permissions.canManageTeam === true,
    canAssignOthers: ctx.isOwner || permissions.canManageTeam === true || permissions.canAssignTasks === true,
  };
}

function taskRecord(e, ctx, id) {
  try {
    return e.app.findFirstRecordByFilter(
      "wesios_records",
      "owner={:owner} && coll='tasks' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: id},
    );
  } catch (_) { return null; }
}

function taskOwned(access, ctx, p) {
  const orgId = String(p.organizationId || ROOT_ORG);
  if (access.allowedOrgIds[orgId] !== true) return false;
  if (ctx.isOwner || access.canManageTeam || access.canAssignOthers) return true;
  const tags = Array.isArray(p.tags) ? p.tags.map(String) : [];
  return String(p.assignee || "") === ctx.employeeId ||
    String(p.responsibleEmployeeId || "") === ctx.employeeId ||
    tags.indexOf("wesios:employee:" + ctx.employeeId) >= 0;
}

function employees(e, ctx) {
  return rows(e, ctx, "employees").map(function(row) {
    const p = payloadOf(row);
    return {
      id: String(p.id || row.getString("rid") || ""),
      login: String(p.login || ""), fullName: String(p.fullName || ""), nickname: String(p.nickname || ""),
    };
  }).filter(function(item) { return !!item.id; });
}

function resolveEmployee(e, ctx, raw) {
  const query = String(raw || "").trim().toLowerCase();
  if (!query) return null;
  const all = employees(e, ctx);
  const exact = all.filter(function(item) {
    return [item.id, item.login, item.fullName, item.nickname].some(function(v) { return v && v.toLowerCase() === query; });
  });
  if (exact.length === 1) return exact[0];
  const partial = all.filter(function(item) {
    return [item.login, item.fullName, item.nickname].some(function(v) { return v && v.toLowerCase().indexOf(query) >= 0; });
  });
  if (partial.length === 1) return partial[0];
  return {error: exact.length > 1 || partial.length > 1 ? "AMBIGUOUS_EMPLOYEE" : "EMPLOYEE_NOT_FOUND"};
}

function validDueDate(value) {
  if (value == null || String(value).trim() === "") return {ok: true, value: null};
  const raw = String(value).trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(raw) || !Number.isFinite(Date.parse(raw + "T12:00:00Z"))) {
    return {ok: false};
  }
  return {ok: true, value: raw + "T12:00:00.000Z"};
}

module.exports = {
  definitions: function(e, ctx) {
    if (!ctx.isOwner && ctx.modules.indexOf("tasks") < 0) return [];
    return [
      {
        name: "tasks_update",
        description: "Изменить доступную реальную задачу WesiOS: название, описание, статус, приоритет, срок или ответственного. Меняй только явно указанные поля.",
        parameters: {type: "object", required: ["taskId"], properties: {
          taskId: {type: "string"}, title: {type: "string"}, description: {type: "string"},
          status: {type: "string", enum: ["backlog", "inProgress", "review", "done"]},
          priority: {type: "string", enum: ["low", "normal", "high", "urgent"]},
          dueDate: {type: ["string", "null"], description: "YYYY-MM-DD или null, чтобы убрать срок"},
          assignee: {type: "string", description: "Имя, login или id сотрудника"}
        }},
      },
      {
        name: "tasks_archive",
        description: "Архивировать/удалить доступную задачу WesiOS. DESTRUCTIVE: сервер всегда потребует отдельное подтверждение пользователя в WesiOS.",
        parameters: {type: "object", required: ["taskId"], properties: {taskId: {type: "string"}}},
      },
    ];
  },

  context: function() { return {}; },

  execute: function(e, ctx, name, args) {
    if (!ctx.isOwner && ctx.modules.indexOf("tasks") < 0) {
      return {ok: false, code: "FORBIDDEN", message: "Нет доступа к модулю задач"};
    }
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    const id = String(input.taskId || "").trim();
    if (!id || id.length > 180) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный taskId"};
    const record = taskRecord(e, ctx, id);
    if (!record) return {ok: false, code: "NOT_FOUND", message: "Задача не найдена"};
    const before = payloadOf(record);
    const access = loadAccess(e, ctx);
    if (!taskOwned(access, ctx, before)) return {ok: false, code: "FORBIDDEN", message: "Нет права изменять эту задачу"};

    if (name === "tasks_archive") {
      record.set("deleted", true);
      record.set("stamp", new Date().toISOString());
      e.app.save(record);
      return {ok: true, result: {task: {id: id, archived: true}}};
    }
    if (name !== "tasks_update") return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Task-инструмент"};

    const next = {};
    for (const key of Object.keys(before)) next[key] = before[key];
    if (Object.prototype.hasOwnProperty.call(input, "title")) {
      const title = String(input.title || "").trim();
      if (!title || title.length > 500) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректное название задачи"};
      next.title = title;
    }
    if (Object.prototype.hasOwnProperty.call(input, "description")) next.description = String(input.description || "").slice(0, 10000);
    if (Object.prototype.hasOwnProperty.call(input, "status")) {
      const value = String(input.status || "");
      if (["backlog", "inProgress", "review", "done"].indexOf(value) < 0) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный статус задачи"};
      next.status = value;
    }
    if (Object.prototype.hasOwnProperty.call(input, "priority")) {
      const value = String(input.priority || "");
      if (["low", "normal", "high", "urgent"].indexOf(value) < 0) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный приоритет задачи"};
      next.priority = value;
    }
    if (Object.prototype.hasOwnProperty.call(input, "dueDate")) {
      const due = validDueDate(input.dueDate);
      if (!due.ok) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный срок задачи"};
      next.dueDate = due.value;
    }
    if (Object.prototype.hasOwnProperty.call(input, "assignee")) {
      const target = resolveEmployee(e, ctx, input.assignee);
      if (!target || target.error) return {ok: false, code: target && target.error || "EMPLOYEE_NOT_FOUND", message: target && target.error === "AMBIGUOUS_EMPLOYEE" ? "Найдено несколько сотрудников" : "Сотрудник не найден"};
      if (target.id !== ctx.employeeId && !access.canAssignOthers) {
        return {ok: false, code: "FORBIDDEN", message: "Нет права назначать задачи другим сотрудникам"};
      }
      next.assignee = target.id;
      next.responsibleEmployeeId = target.id;
      const tags = Array.isArray(next.tags) ? next.tags.map(String).filter(function(tag) { return tag.indexOf("wesios:employee:") !== 0; }) : [];
      tags.push("wesios:employee:" + target.id);
      next.tags = tags;
    }
    next.id = String(before.id || id);
    record.set("payload", next);
    record.set("stamp", new Date().toISOString());
    record.set("deleted", false);
    e.app.save(record);
    return {ok: true, result: {task: {
      id: id, title: String(next.title || ""), status: String(next.status || "backlog"),
      priority: String(next.priority || "normal"), dueDate: next.dueDate || null,
      assigneeId: next.assignee || next.responsibleEmployeeId || null,
      organizationId: String(next.organizationId || ROOT_ORG)
    }}};
  },
};
