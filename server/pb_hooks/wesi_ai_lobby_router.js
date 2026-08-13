module.exports = {
  choose: function(ai, cfg, route, requestId, message, history) {
    const payload = {requestId, route, operation: "route", input: {
      system: "WESI_AI_LOBBY_ROUTER\nChoose ZANE for technical/finance/work tasks, NIRVANA for creative/media tasks, and both for mixed requests. Return only ZANE, NIRVANA, ZANE_NIRVANA or NIRVANA_ZANE.",
      history, message
    }};
    const result = ai.callRelay(cfg, payload, requestId);
    if (!result.ok) return ["zane", "nirvana"];
    const token = result.answer.toUpperCase().replace(/[^A-Z_]/g, "");
    if (token === "ZANE") return ["zane"];
    if (token === "NIRVANA") return ["nirvana"];
    if (token === "NIRVANA_ZANE") return ["nirvana", "zane"];
    return ["zane", "nirvana"];
  }
};
