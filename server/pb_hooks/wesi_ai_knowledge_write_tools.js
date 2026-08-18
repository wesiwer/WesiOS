const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");
const syncWriter = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_sync_writer.js");
function payload(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function permissionsFor(e, ctx) {
  if (ctx.isOwner) return {knowledgeAll: true, knowledgeIds: [], modules: ["knowledge"]};
  const employee = dataAccess.first(
    e.app,
    "wesios_records", "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: ctx.employeeId},
  );
  const p = payload(employee);
  const permissions = p.permissions && typeof p.permissions === "object" ? p.permissions : {};
  return {
    knowledgeAll: permissions.knowledgeAll === true,
    knowledgeIds: Array.isArray(permissions.knowledgeIds) ? permissions.knowledgeIds.map(String) : [],
    modules: Array.isArray(permissions.modules) ? permissions.modules.map(String) : [],
  };
}

function byId(e, ctx, id) {
  return dataAccess.first(
    e.app,
    "wesios_records", "owner={:owner} && coll='articles' && rid={:rid} && deleted=false",
    {owner: ctx.ownerId, rid: id},
  );
}

function canEdit(perms, ctx, id, parentId) {
  return ctx.isOwner || perms.knowledgeAll || perms.knowledgeIds.indexOf(String(id || "")) >= 0 ||
    (!!parentId && perms.knowledgeIds.indexOf(String(parentId)) >= 0);
}

function section(value) {
  const raw = String(value || "playbook");
  return ["about", "playbook", "guide", "finance", "personal"].indexOf(raw) >= 0 ? raw : null;
}

function tags(value) {
  if (!Array.isArray(value)) return [];
  const result = [];
  for (const item of value.slice(0, 30)) {
    const clean = String(item || "").trim().slice(0, 80);
    if (clean && result.indexOf(clean) < 0) result.push(clean);
  }
  return result;
}

module.exports = {
  definitions: function(e, ctx) {
    const perms = permissionsFor(e, ctx);
    if (!ctx.isOwner && perms.modules.indexOf("knowledge") < 0) return [];
    return [
      {name: "knowledge_create", description: "Создать статью/папку Базы знаний WesiOS в разрешённом разделе.", parameters: {type: "object", required: ["title"], properties: {
        title: {type: "string"}, body: {type: "string"}, section: {type: "string", enum: ["about", "playbook", "guide", "finance", "personal"]},
        tags: {type: "array", items: {type: "string"}, maxItems: 30}, parentId: {type: ["string", "null"]}, isFolder: {type: "boolean"}, pinned: {type: "boolean"}, order: {type: "integer"}
      }}},
      {name: "knowledge_update", description: "Изменить доступную статью Базы знаний WesiOS. Меняй только явно указанные поля.", parameters: {type: "object", required: ["articleId"], properties: {
        articleId: {type: "string"}, title: {type: "string"}, body: {type: "string"}, section: {type: "string", enum: ["about", "playbook", "guide", "finance", "personal"]},
        tags: {type: "array", items: {type: "string"}, maxItems: 30}, parentId: {type: ["string", "null"]}, isFolder: {type: "boolean"}, pinned: {type: "boolean"}, order: {type: "integer"}
      }}},
      {name: "knowledge_archive", description: "Удалить пользовательскую статью/папку Базы знаний. DESTRUCTIVE: требуется отдельное подтверждение. Встроенные статьи удалить нельзя.", parameters: {type: "object", required: ["articleId"], properties: {articleId: {type: "string"}}}},
    ];
  },
  context: function() { return {}; },
  execute: function(e, ctx, name, args) {
    const perms = permissionsFor(e, ctx);
    if (!ctx.isOwner && perms.modules.indexOf("knowledge") < 0) return {ok: false, code: "FORBIDDEN", message: "Нет доступа к Базе знаний"};
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    const now = new Date().toISOString();

    if (name === "knowledge_create") {
      const parentId = input.parentId == null ? "" : String(input.parentId).trim();
      if (!ctx.isOwner && !perms.knowledgeAll && (!parentId || perms.knowledgeIds.indexOf(parentId) < 0)) {
        return {ok: false, code: "FORBIDDEN", message: "Создавать статьи можно только внутри разрешённого раздела"};
      }
      if (parentId && !byId(e, ctx, parentId)) return {ok: false, code: "NOT_FOUND", message: "Родительская статья не найдена"};
      const title = String(input.title || "").trim();
      if (!title || title.length > 500) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный заголовок"};
      const sec = section(input.section);
      if (!sec) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный раздел"};
      const body = String(input.body || "");
      if (body.length > 250000) return {ok: false, code: "VALIDATION_ERROR", message: "Статья слишком большая"};
      const id = "wai_article_" + Date.now() + "_" + $security.randomString(8);
      const value = {id, title, body, section: sec, tags: tags(input.tags), createdAt: now, updatedAt: now, builtIn: false,
        pinned: input.pinned === true, parentId: parentId || null, isFolder: input.isFolder === true, orderRaw: Number.isFinite(Number(input.order)) ? Math.trunc(Number(input.order)) : null};
      const saved = syncWriter.write(e, ctx, {coll: "articles", rid: id, next: value, creating: true});
      if (!saved.applied) return {ok: false, code: "WRITE_CONFLICT", message: "Статья изменилась параллельно, повторите действие"};
      const out = saved.payload;
      return {ok: true, result: {article: {id, title: String(out.title || title), parentId: out.parentId || null, isFolder: out.isFolder === true}}};
    }

    const id = String(input.articleId || "").trim();
    if (!id || id.length > 180) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный articleId"};
    const record = byId(e, ctx, id);
    if (!record) return {ok: false, code: "NOT_FOUND", message: "Статья не найдена"};
    const before = payload(record);
    if (!canEdit(perms, ctx, id, before.parentId)) return {ok: false, code: "FORBIDDEN", message: "Нет права изменять эту статью"};
    if (name === "knowledge_archive") {
      if (before.builtIn === true) return {ok: false, code: "FORBIDDEN", message: "Встроенную статью удалить нельзя"};
      const saved = syncWriter.write(e, ctx, {coll: "articles", rid: id, before: before, next: before, deleted: true});
      if (!saved.applied) return {ok: false, code: "WRITE_CONFLICT", message: "Статья уже изменилась, повторите действие"};
      return {ok: true, result: {article: {id, archived: true}}};
    }
    if (name !== "knowledge_update") return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Knowledge-инструмент"};
    const next = Object.assign({}, before); next.id = String(before.id || id);
    if (Object.prototype.hasOwnProperty.call(input, "title")) { const title = String(input.title || "").trim(); if (!title || title.length > 500) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный заголовок"}; next.title = title; }
    if (Object.prototype.hasOwnProperty.call(input, "body")) { const body = String(input.body || ""); if (body.length > 250000) return {ok: false, code: "VALIDATION_ERROR", message: "Статья слишком большая"}; next.body = body; }
    if (Object.prototype.hasOwnProperty.call(input, "section")) { const sec = section(input.section); if (!sec) return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный раздел"}; next.section = sec; }
    if (Object.prototype.hasOwnProperty.call(input, "tags")) next.tags = tags(input.tags);
    if (Object.prototype.hasOwnProperty.call(input, "pinned")) next.pinned = input.pinned === true;
    if (Object.prototype.hasOwnProperty.call(input, "isFolder")) next.isFolder = input.isFolder === true;
    if (Object.prototype.hasOwnProperty.call(input, "order")) next.orderRaw = Number.isFinite(Number(input.order)) ? Math.trunc(Number(input.order)) : next.orderRaw;
    if (Object.prototype.hasOwnProperty.call(input, "parentId")) {
      const parentId = input.parentId == null ? "" : String(input.parentId).trim();
      if (parentId === id) return {ok: false, code: "VALIDATION_ERROR", message: "Статья не может быть родителем самой себе"};
      if (!ctx.isOwner && !perms.knowledgeAll && (!parentId || perms.knowledgeIds.indexOf(parentId) < 0)) return {ok: false, code: "FORBIDDEN", message: "Нет права переместить статью в этот раздел"};
      if (parentId && !byId(e, ctx, parentId)) return {ok: false, code: "NOT_FOUND", message: "Родительская статья не найдена"};
      next.parentId = parentId || null;
    }
    next.updatedAt = now;
    const saved = syncWriter.write(e, ctx, {coll: "articles", rid: id, before: before, next: next});
    if (!saved.applied) return {ok: false, code: "WRITE_CONFLICT", message: "Статья изменилась параллельно, повторите действие"};
    const out = saved.payload;
    return {ok: true, result: {article: {id, title: String(out.title || ""), parentId: out.parentId || null, isFolder: out.isFolder === true}}};
  },
};
