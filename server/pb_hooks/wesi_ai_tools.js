function adapters() {
  const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
  return [
    require(base + "wesi_ai_task_tools.js"),
    require(base + "wesi_ai_finance_tools.js"),
    require(base + "wesi_ai_workspace_tools.js"),
  ];
}

module.exports = {
  definitions: function(e, ctx) {
    const out = [];
    for (const adapter of adapters()) {
      const items = adapter.definitions(e, ctx);
      if (Array.isArray(items)) out.push(...items);
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
  execute: function(e, ctx, name, args, activeOrganizationId) {
    for (const adapter of adapters()) {
      const definitions = adapter.definitions(e, ctx);
      if (!Array.isArray(definitions) || !definitions.some((item) => String(item.name || "") === name)) continue;
      return adapter.execute(e, ctx, name, args, activeOrganizationId);
    }
    return {ok: false, code: "FORBIDDEN", message: "Инструмент недоступен текущему сотруднику"};
  },
};
