module.exports = {
  run: function(e, body) {
    const ai = require(`${__hooks}/wesi_ai_lib.js`);
    const personas = require(`${__hooks}/wesi_ai_persona_runtime.js`);
    const router = require(`${__hooks}/wesi_ai_lobby_router.js`);
    const turn = require(`${__hooks}/wesi_ai_lobby_turn.js`);
    const tier = String(body.tier || "fast").trim().toLowerCase();
    const mode = String(body.lobbyMode || "smart").trim().toLowerCase();
    const message = String(body.message || "").trim();
    if (["fast", "pro", "maximum"].indexOf(tier) < 0 || ["both", "smart"].indexOf(mode) < 0 || !message) return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}};
    const zane = personas.load("zane");
    const nirvana = personas.load("nirvana");
    if (!zane.ready || !nirvana.ready) return {status: 503, body: {ok: false, code: "WAI_PERSONA_ENGINE_NOT_READY"}};
    const cfg = ai.readRelayConfig();
    const route = cfg.routes[tier] || "";
    if (!cfg.ready || !route) return {status: 503, body: {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"}};
    const history = [];
    for (const item of Array.isArray(body.messages) ? body.messages : []) {
      if (!item || typeof item !== "object") continue;
      const author = String(item.author || "").toLowerCase();
      const text = String(item.text || "");
      if (["user", "zane", "nirvana", "tool"].indexOf(author) >= 0 && text.length <= 32000) history.push({author, text});
    }
    const memory = ai.sanitizeMemory(body.memory && typeof body.memory === "object" ? body.memory : {});
    const projectContext = String(body.projectContext || "").trim();
    const taskState = body.taskState && typeof body.taskState === "object" && !Array.isArray(body.taskState) ? body.taskState : {};
    let taskStateJson = "{}";
    try { taskStateJson = JSON.stringify(taskState); } catch (_) { return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}}; }
    if (projectContext.length > 64000 || taskStateJson.length > 12000) return {status: 400, body: {ok: false, code: "WAI_BAD_LOBBY_REQUEST"}};
    const rootId = "wai_lobby_" + Date.now() + "_" + $security.randomString(10);
    const order = mode === "both" ? ["zane", "nirvana"] : router.choose(ai, cfg, route, rootId + "_route", message, history);
    const messages = [];
    for (const name of order) {
      const profile = name === "zane" ? zane : nirvana;
      const personaMemory = name === "zane" ? memory.zane : memory.nirvana;
      const result = turn.run(ai, cfg, route, rootId + "_" + name, name, profile, message, history, memory.shared, personaMemory, memory.project, messages, String(body.summary || ""), projectContext, taskStateJson);
      if (!result.ok) {
        if (!messages.length) return {status: result.status || 503, body: {ok: false, code: result.code, requestId: rootId}};
        continue;
      }
      messages.push({author: name, text: result.answer});
    }
    return {status: 200, body: {ok: true, requestId: rootId, persona: "lobby", tier, lobbyMode: mode, participants: order, messages, answer: "__WESI_LOBBY_V1__" + JSON.stringify(messages)}};
  }
};
