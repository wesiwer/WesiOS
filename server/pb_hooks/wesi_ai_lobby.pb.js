routerAdd("POST", "/api/wesi/ai/lobby", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const lobby = require(`${__hooks}/wesi_ai_lobby_core.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const body = e.requestInfo().body || {};
  const result = lobby.run(e, body);
  return e.json(result.status, result.body);
}, $apis.requireAuth("users"));
