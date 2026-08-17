const dataAccess = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_data_access.js");
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

function permissionsFor(e, ctx) {
  if (ctx.isOwner) return {knowledgeAll: true, knowledgeIds: [], modules: ["knowledge"]};
  let employee = null;
  employee = dataAccess.first(e.app,
      "wesios_records",
      "owner={:owner} && coll='employees' && rid={:rid} && deleted=false",
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

function articleById(e, ctx, articleId) {
  let record = null;
  record = dataAccess.first(e.app,
      "wesios_records",
      "owner={:owner} && coll='articles' && rid={:rid} && deleted=false",
      {owner: ctx.ownerId, rid: articleId},
    );
  if (record) return record;

  // Legacy records should normally use article id as rid, but keep a bounded
  // compatibility fallback for older imports where payload.id differs.
  let rows = [];
  rows = dataAccess.records(e.app,
      "wesios_records",
      "owner={:owner} && coll='articles' && deleted=false",
      "-stamp,-id", 200, 0,
      {owner: ctx.ownerId},
    );
  for (const row of rows) {
    if (String(payload(row).id || "") === articleId) return row;
  }
  return null;
}

module.exports = {
  definitions: function(e, ctx) {
    const permissions = permissionsFor(e, ctx);
    if (!ctx.isOwner && permissions.modules.indexOf("knowledge") < 0) return [];
    return [{
      name: "knowledge_article",
      description: "Прочитать конкретную разрешённую сотруднику статью Базы знаний WesiOS по articleId из verified knowledge_search. Используй для подробного объяснения, резюме, вопросов по статье и сравнения её содержания. Не выдумывай articleId.",
      parameters: {
        type: "object",
        required: ["articleId"],
        properties: {
          articleId: {type: "string", minLength: 1, maxLength: 160},
        },
      },
    }];
  },

  context: function(e, ctx) {
    const permissions = permissionsFor(e, ctx);
    return {
      knowledgeArticleRead: ctx.isOwner || permissions.modules.indexOf("knowledge") >= 0,
    };
  },

  execute: function(e, ctx, name, args) {
    if (name !== "knowledge_article") {
      return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Knowledge-инструмент"};
    }
    const permissions = permissionsFor(e, ctx);
    if (!ctx.isOwner && permissions.modules.indexOf("knowledge") < 0) {
      return {ok: false, code: "FORBIDDEN", message: "Нет доступа к Базе знаний"};
    }
    const articleId = String((args && args.articleId) || "").trim();
    if (!articleId || articleId.length > 160) {
      return {ok: false, code: "VALIDATION_ERROR", message: "Некорректный articleId"};
    }
    const row = articleById(e, ctx, articleId);
    if (!row) return {ok: false, code: "NOT_FOUND", message: "Статья не найдена"};
    const p = payload(row);
    const id = String(p.id || row.getString("rid") || articleId);
    const parentId = String(p.parentId || "");
    const allowed = ctx.isOwner || permissions.knowledgeAll ||
      permissions.knowledgeIds.indexOf(id) >= 0 ||
      (parentId && permissions.knowledgeIds.indexOf(parentId) >= 0);
    if (!allowed) {
      return {ok: false, code: "FORBIDDEN", message: "Нет доступа к этой статье"};
    }

    const body = plainKnowledgeBody(p.body);
    const text = body.length <= 20000 ? body : body.slice(0, 20000) + "\n[Статья обрезана до лимита Wesi AI]";
    const title = String(p.title || "").slice(0, 240);
    const section = String(p.section || "playbook").slice(0, 80);
    const tags = Array.isArray(p.tags) ? p.tags.map(String).slice(0, 30) : [];
    return {
      ok: true,
      result: {
        article: {
          id: id,
          title: title,
          parentId: parentId || null,
          section: section,
          tags: tags,
          text: text,
          updatedAt: String(p.updatedAt || ""),
        },
        contentBlock: {
          type: "knowledge",
          data: {
            articleId: id,
            title: title,
            section: section,
            excerpt: body.slice(0, 800),
          },
        },
      },
    };
  },
};
