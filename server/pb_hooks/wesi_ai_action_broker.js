const CONFIRMATION_TTL_MS = 5 * 60 * 1000;
const CONFIRMATION_COLL = "wesi_ai_confirmations";

function modulePath(name) {
  const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
  return base + name;
}

function audit(e, ctx, entry) {
  try {
    require(modulePath("wesi_ai_audit.js")).record(e, ctx, entry);
  } catch (_) {}
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

function normalizeInvocation(invocation) {
  const raw = invocation && typeof invocation === "object" && !Array.isArray(invocation) ? invocation : {};
  return {
    persona: String(raw.persona || "").slice(0, 40),
    conversationId: String(raw.conversationId || "").slice(0, 180),
    requestId: String(raw.requestId || "").slice(0, 180),
    confirmedByTicket: raw.confirmedByTicket === true,
    confirmationId: String(raw.confirmationId || "").slice(0, 180),
  };
}

function confirmationBinding(e, ctx) {
  const authId = e && e.auth ? String(e.auth.id || "") : "";
  let sessionId = "";
  try {
    sessionId = String(e.request.header.get("X-WesiOS-Session") || "").trim();
  } catch (_) {}
  return $security.hs256(
    authId + "." + sessionId,
    "wesi-ai-confirm." + String(ctx.ownerId || "") + "." + String(ctx.employeeId || ""),
  );
}

function organizationIdOf(activeOrganizationId, args) {
  const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
  return String(activeOrganizationId || input.organizationId || "org_wesi_inc").slice(0, 180);
}

function entityIdOf(result, args, name) {
  const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
  const direct = input.id || input.taskId || input.eventId || input.articleId || input.clientId || input.dealId || input.transactionId || input.roadmapId || input.beatId || input.audioId || input.notificationId;
  if (direct != null && String(direct).trim()) return String(direct).slice(0, 180);
  if (result && typeof result === "object" && !Array.isArray(result)) {
    for (const key of ["id", "task", "event", "article", "client", "deal", "transaction", "roadmap", "audio", "notification"]) {
      const value = result[key];
      if (value && typeof value === "object" && value.id != null) return String(value.id).slice(0, 180);
      if (key === "id" && value != null) return String(value).slice(0, 180);
    }
  }
  return String(name || "wesi_ai_action").slice(0, 180);
}

function cleanupExpired(e, ctx) {
  let rows = [];
  try {
    rows = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && deleted=false",
      "stamp",
      100,
      0,
      {owner: ctx.ownerId, coll: CONFIRMATION_COLL},
    );
  } catch (_) { rows = []; }
  const now = Date.now();
  for (const row of rows) {
    const payload = payloadOf(row);
    const expires = Date.parse(String(payload.expiresAt || ""));
    if (!Number.isFinite(expires) || expires <= now || payload.usedAt) {
      try { e.app.delete(row); } catch (_) {}
    }
  }
}

function createConfirmation(e, ctx, capability, name, args, activeOrganizationId, invocation) {
  cleanupExpired(e, ctx);
  let encoded = "{}";
  try { encoded = JSON.stringify(args && typeof args === "object" ? args : {}); } catch (_) {
    return {ok: false, code: "VALIDATION_ERROR", message: "Некорректные аргументы действия"};
  }
  if (encoded.length > 24000) {
    return {ok: false, code: "VALIDATION_ERROR", message: "Слишком большой запрос для подтверждения"};
  }
  const now = new Date();
  const expiresAt = new Date(now.getTime() + CONFIRMATION_TTL_MS);
  const id = "wai_confirm_" + Date.now() + "_" + $security.randomString(12);
  const policy = require(modulePath("wesi_ai_risk_policy.js"));
  const payload = {
    id: id,
    employeeId: String(ctx.employeeId || ""),
    authBinding: confirmationBinding(e, ctx),
    tool: String(name || ""),
    args: JSON.parse(encoded),
    activeOrganizationId: String(activeOrganizationId || ""),
    organizationId: organizationIdOf(activeOrganizationId, args),
    persona: invocation.persona,
    conversationId: invocation.conversationId,
    requestId: invocation.requestId,
    risk: String(capability.risk || "DESTRUCTIVE"),
    preview: policy.preview(capability, name, args),
    createdAt: now.toISOString(),
    expiresAt: expiresAt.toISOString(),
    usedAt: null,
  };
  try {
    require(modulePath("wesi_sync_atomic.js")).commit(e.app, {
      owner: ctx.ownerId,
      org: "wesi-inc",
      coll: CONFIRMATION_COLL,
      rid: id,
      payload: payload,
      stamp: now.toISOString(),
      deleted: false,
    });
  } catch (_) {
    return {ok: false, code: "WAI_CONFIRMATION_STORE_FAILED", message: "Не удалось создать безопасное подтверждение"};
  }
  return {
    ok: false,
    code: "CONFIRMATION_REQUIRED",
    message: "Это действие требует явного подтверждения в WesiOS",
    confirmation: {
      id: id,
      expiresAt: expiresAt.toISOString(),
      preview: payload.preview,
    },
  };
}

function recordResult(e, ctx, capability, name, args, activeOrganizationId, invocation, result, policyDecision) {
  audit(e, ctx, {
    tool: name,
    module: capability ? capability.module : "",
    action: capability ? capability.action : "",
    risk: capability ? capability.risk : "",
    policyDecision: policyDecision || "",
    confirmationId: invocation.confirmationId || null,
    persona: invocation.persona,
    conversationId: invocation.conversationId,
    requestId: invocation.requestId,
    entityType: capability ? capability.entityType : "wesi_ai_action",
    entityId: entityIdOf(result && result.result, args, name),
    organizationId: organizationIdOf(activeOrganizationId, args),
    ok: result && result.ok === true,
    code: result && result.code ? String(result.code) : null,
  });
}

function executeAdapter(e, ctx, adapter, capability, name, args, activeOrganizationId, invocation, decision) {
  let result;
  try {
    result = adapter.execute(e, ctx, name, args, activeOrganizationId);
    if (!result || typeof result !== "object" || Array.isArray(result)) {
      result = {ok: false, code: "WAI_TOOL_BAD_RESULT", message: "Инструмент вернул некорректный результат"};
    }
  } catch (error) {
    const taggedCode = error && error.wesiCode ? String(error.wesiCode) : "";
    const taggedMessage = error && error.wesiMessage ? String(error.wesiMessage) : "";
    result = {
      ok: false,
      code: taggedCode || "WAI_TOOL_EXECUTION_FAILED",
      message: taggedMessage || "Не удалось выполнить действие WesiOS",
    };
  }
  recordResult(e, ctx, capability, name, args, activeOrganizationId, invocation, result, decision);
  return result;
}

module.exports = {
  execute: function(e, ctx, adapter, name, args, activeOrganizationId, invocationRaw) {
    const registry = require(modulePath("wesi_ai_capability_registry.js"));
    const policy = require(modulePath("wesi_ai_risk_policy.js"));
    const capability = registry.get(name);
    const invocation = normalizeInvocation(invocationRaw);
    const evaluated = policy.evaluate(capability, invocation);
    if (!evaluated.allowed) {
      if (evaluated.code === "CONFIRMATION_REQUIRED" && capability) {
        const pending = createConfirmation(e, ctx, capability, name, args, activeOrganizationId, invocation);
        recordResult(e, ctx, capability, name, args, activeOrganizationId, invocation, pending, evaluated.decision);
        return pending;
      }
      const denied = {ok: false, code: evaluated.code || "FORBIDDEN", message: evaluated.message || "Действие запрещено политикой Wesi AI"};
      recordResult(e, ctx, capability, name, args, activeOrganizationId, invocation, denied, evaluated.decision);
      return denied;
    }
    return executeAdapter(e, ctx, adapter, capability, name, args, activeOrganizationId, invocation, evaluated.decision);
  },

  confirm: function(e, ctx, ticketId, resolveAdapter) {
    cleanupExpired(e, ctx);
    const id = String(ticketId || "").trim();
    if (!/^wai_confirm_[A-Za-z0-9_-]{16,180}$/.test(id)) {
      return {ok: false, code: "CONFIRMATION_INVALID", message: "Некорректное подтверждение Wesi AI"};
    }
    let record = null;
    try {
      record = require(modulePath("wesi_ai_data_access.js")).first(
        e.app,
        "wesios_records",
        "owner={:owner} && coll={:coll} && rid={:rid} && deleted=false",
        {owner: ctx.ownerId, coll: CONFIRMATION_COLL, rid: id},
      );
    } catch (error) {
      return {
        ok: false,
        code: String((error && error.wesiCode) || "WAI_TOOL_DATA_UNAVAILABLE"),
        message: String((error && error.wesiMessage) || "Не удалось прочитать данные WesiOS"),
      };
    }
    if (!record) return {ok: false, code: "CONFIRMATION_EXPIRED", message: "Подтверждение истекло или уже использовано"};
    const ticket = payloadOf(record);
    const expires = Date.parse(String(ticket.expiresAt || ""));
    const bound = String(ticket.authBinding || "");
    const currentBinding = confirmationBinding(e, ctx);
    if (String(ticket.employeeId || "") !== String(ctx.employeeId || "") ||
        !bound || bound !== currentBinding ||
        !Number.isFinite(expires) || expires <= Date.now() || ticket.usedAt) {
      try { e.app.delete(record); } catch (_) {}
      return {ok: false, code: "CONFIRMATION_EXPIRED", message: "Подтверждение истекло или принадлежит другой сессии"};
    }
    const name = String(ticket.tool || "");
    const adapter = typeof resolveAdapter === "function" ? resolveAdapter(e, ctx, name) : null;
    if (!adapter) {
      try { e.app.delete(record); } catch (_) {}
      return {ok: false, code: "FORBIDDEN", message: "Действие больше недоступно текущему сотруднику"};
    }
    const registry = require(modulePath("wesi_ai_capability_registry.js"));
    const capability = registry.get(name);
    if (!capability || capability.risk !== registry.RISK_DESTRUCTIVE) {
      try { e.app.delete(record); } catch (_) {}
      return {ok: false, code: "CONFIRMATION_INVALID", message: "Действие больше не требует такого подтверждения"};
    }

    // Consume before execution to make replay impossible even if the adapter fails.
    try { e.app.delete(record); } catch (_) {
      return {ok: false, code: "CONFIRMATION_CONSUME_FAILED", message: "Не удалось безопасно использовать подтверждение"};
    }
    const invocation = normalizeInvocation({
      persona: ticket.persona,
      conversationId: ticket.conversationId,
      requestId: ticket.requestId,
      confirmedByTicket: true,
      confirmationId: id,
    });
    const policy = require(modulePath("wesi_ai_risk_policy.js"));
    const evaluated = policy.evaluate(capability, invocation);
    if (!evaluated.allowed) {
      const denied = {ok: false, code: "FORBIDDEN", message: "Политика Wesi AI больше не разрешает действие"};
      recordResult(e, ctx, capability, name, ticket.args || {}, ticket.activeOrganizationId || "", invocation, denied, evaluated.decision);
      return denied;
    }
    const confirmed = executeAdapter(e, ctx, adapter, capability, name, ticket.args || {}, ticket.activeOrganizationId || "", invocation, evaluated.decision);
    if (confirmed && typeof confirmed === "object" && !Array.isArray(confirmed) && !confirmed.tool) {
      confirmed.tool = name;
    }
    return confirmed;
  },
};
