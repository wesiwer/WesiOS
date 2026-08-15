function basePath() {
  return typeof __hooks !== "undefined" ? __hooks + "/" : "./";
}

function adapters() {
  const base = basePath();
  return [
    require(base + "wesi_ai_task_tools.js"),
    require(base + "wesi_ai_task_write_tools.js"),
    require(base + "wesi_ai_finance_tools.js"),
    require(base + "wesi_ai_finance_write_tools.js"),
    require(base + "wesi_ai_workspace_tools.js"),
    require(base + "wesi_ai_calendar_write_tools.js"),
    require(base + "wesi_ai_crm_write_tools.js"),
    require(base + "wesi_ai_knowledge_tools.js"),
    require(base + "wesi_ai_knowledge_write_tools.js"),
    require(base + "wesi_ai_roadmap_tools.js"),
    require(base + "wesi_ai_audio_tools.js"),
    require(base + "wesi_ai_team_tools.js"),
    require(base + "wesi_ai_github_tools.js"),
    require(base + "wesi_ai_horizon_tools.js"),
    require(base + "wesi_ai_presentation_tools.js"),
    require(base + "wesi_ai_media_tools.js"),
    require(base + "wesi_ai_github_connector.js"),
  ];
}

function adapterFor(e, ctx, name) {
  const target = String(name || "");
  for (const adapter of adapters()) {
    const definitions = adapter.definitions(e, ctx);
    if (!Array.isArray(definitions)) continue;
    if (definitions.some(function(item) { return String(item && item.name || "") === target; })) {
      return adapter;
    }
  }
  return null;
}

module.exports = {
  definitions: function(e, ctx) {
    const registry = require(basePath() + "wesi_ai_capability_registry.js");
    const out = [];
    for (const adapter of adapters()) {
      const items = adapter.definitions(e, ctx);
      if (!Array.isArray(items)) continue;
      for (const item of items) {
        const decorated = registry.decorateDefinition(item);
        if (decorated) out.push(decorated);
      }
    }
    return out;
  },

  context: function(e, ctx, activeOrganizationId) {
    const result = {};
    for (const adapter of adapters()) {
      if (typeof adapter.context !== "function") continue;
      const part = adapter.context(e, ctx, activeOrganizationId);
      if (part && typeof part === "object") Object.assign(result, part);
    }
    return result;
  },

  execute: function(e, ctx, name, args, activeOrganizationId, invocation) {
    const adapter = adapterFor(e, ctx, name);
    if (!adapter) {
      return {ok: false, code: "FORBIDDEN", message: "Инструмент недоступен текущему сотруднику"};
    }
    const broker = require(basePath() + "wesi_ai_action_broker.js");
    return broker.execute(e, ctx, adapter, name, args, activeOrganizationId, invocation || {});
  },

  confirm: function(e, ctx, ticketId) {
    const broker = require(basePath() + "wesi_ai_action_broker.js");
    return broker.confirm(e, ctx, ticketId, adapterFor);
  },
};
