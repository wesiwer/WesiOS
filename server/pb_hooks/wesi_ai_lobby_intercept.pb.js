routerUse((e) => {
  const path = String(e.request.url.path || "");
  const method = String(e.request.method || "").toUpperCase();
  if (path !== "/api/wesi/ai/chat" || method !== "POST") return e.next();
  const body = e.requestInfo().body || {};
  if (String(body.persona || "").trim().toLowerCase() !== "lobby") return e.next();
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const lobby = require(`${__hooks}/wesi_ai_lobby_core.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const result = lobby.run(e, body);
  return e.json(result.status, result.body);
});
