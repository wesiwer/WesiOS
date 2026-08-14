routerAdd("GET", "/api/wesi/ai/models", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  const requestId = "wai_models_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "models",
    input: {}
  }, requestId, 35);

  if (!relay.ok) return e.json(relay.status, {ok: false, code: relay.code});
  return e.json(200, {
    ok: true,
    providers: relay.result.providers || {},
    routes: cfg.routes,
    observedAt: new Date().toISOString()
  });
}, $apis.requireAuth("users"));
