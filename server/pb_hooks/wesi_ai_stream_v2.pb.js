// Wesi AI streaming v2 routes. Route callbacks intentionally depend only on per-request require() values.
routerAdd("POST", "/api/wesi/ai/stream/prepare-v2", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const runtime = require(`${__hooks}/wesi_ai_stream_runtime_v2.js`);
  const personaRuntime = require(`${__hooks}/wesi_ai_persona_runtime.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = runtime.streamSecret(e, ai);
  const result = runtime.cleanRequest(e, e.requestInfo().body || {}, ctx, ai, personaRuntime, tools, cfg);
  if (result.error) return e.json(result.status, result.error);
  return e.json(200, {ok: true, prepared: result.prepared});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/ai/stream/tool-v2", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const runtime = require(`${__hooks}/wesi_ai_stream_runtime_v2.js`);
  const tools = require(`${__hooks}/wesi_ai_tools.js`);
  const registry = require(`${__hooks}/wesi_ai_capability_registry.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  runtime.streamSecret(e, ai);
  const body = e.requestInfo().body || {};
  const name = String(body.name || "").trim();
  const args = body.arguments && typeof body.arguments === "object" ? body.arguments : {};
  const activeOrganizationId = String(body.activeOrganizationId || "").trim();
  const requestId = String(body.requestId || "").trim().slice(0, 180);
  const conversationId = String(body.conversationId || "").trim().slice(0, 180);
  const persona = String(body.persona || "").trim().toLowerCase().slice(0, 40);
  const actorRole = String(body.actorRole || "lead").trim().toLowerCase();
  const leadPersona = String(body.leadPersona || persona || "").trim().toLowerCase().slice(0, 40);
  const handoffId = String(body.handoffId || "").trim().slice(0, 180);
  const available = tools.definitions(e, ctx);
  const definitionAllowed = available.some(function(item) {
    return String(item.name || "") === name;
  });
  let allowed = definitionAllowed && (actorRole === "lead" || actorRole === "coagent" || actorRole === "subagent");
  if (allowed && actorRole === "coagent") {
    const meta = registry.get(name);
    const validPersonas = ["zane", "nirvana"].indexOf(persona) >= 0 && ["zane", "nirvana"].indexOf(leadPersona) >= 0 && persona !== leadPersona;
    allowed = Boolean(meta) && meta.risk === registry.RISK_READ && validPersonas && handoffId.length > 0;
  }
  if (allowed && actorRole === "subagent") {
    const meta = registry.get(name);
    const validLead = ["zane", "nirvana"].indexOf(leadPersona) >= 0;
    allowed = Boolean(meta) && meta.risk === registry.RISK_READ && validLead && handoffId.length > 0;
  }
  if (!allowed) {
    return e.json(200, {
      ok: true,
      toolResult: {tool: name, verified: true, ok: false, code: "FORBIDDEN", message: actorRole === "coagent" ? "Co-Agent может использовать только разрешённые read-only инструменты" : (actorRole === "subagent" ? "Dynamic Sub-Agent может использовать только scoped read-only инструменты" : "Инструмент недоступен текущему сотруднику")}
    });
  }
  const executed = tools.execute(e, ctx, name, args, activeOrganizationId, {
    requestId: requestId,
    conversationId: conversationId,
    persona: persona,
    actorRole: actorRole,
    leadPersona: leadPersona,
    handoffId: handoffId
  });
  return e.json(200, {
    ok: true,
    toolResult: {
      tool: name,
      verified: true,
      ok: executed.ok === true,
      code: executed.code || null,
      message: executed.message || null,
      alternatives: executed.alternatives || null,
      result: executed.result || null,
      confirmation: executed.confirmation || null
    }
  });
}, $apis.requireAuth("users"));
