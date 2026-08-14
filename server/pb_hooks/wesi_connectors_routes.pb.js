function connectorConfig() {
  try {
    const raw = $os.readFile(__hooks + "/.wesi-connectors.json");
    const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
    const cfg = JSON.parse(text || "{}");
    const url = String(cfg.url || "").replace(/\/$/, "");
    const sharedSecret = String(cfg.sharedSecret || "");
    return {ready: /^http:\/\/127\.0\.0\.1:\d+$/.test(url) && sharedSecret.length >= 32, url: url, sharedSecret: sharedSecret};
  } catch (_) { return {ready: false, url: "", sharedSecret: ""}; }
}

function callBroker(ctx, method, path) {
  const cfg = connectorConfig();
  if (!cfg.ready) return {ok: false, status: 503, code: "CONNECTORS_NOT_CONFIGURED"};
  let response;
  try {
    response = $http.send({
      url: cfg.url + path,
      method: method,
      headers: {
        "Content-Type": "application/json",
        "X-Wesi-Connector-Secret": cfg.sharedSecret,
        "X-Wesi-Owner-Id": String(ctx.ownerId || "")
      },
      timeout: 30
    });
  } catch (_) { return {ok: false, status: 503, code: "CONNECTOR_UNAVAILABLE"}; }
  const json = response && response.json && typeof response.json === "object" ? response.json : {};
  if (!response || response.statusCode < 200 || response.statusCode >= 300 || json.ok !== true) {
    return {ok: false, status: response && response.statusCode >= 400 ? response.statusCode : 502, code: String(json.code || "CONNECTOR_FAILED")};
  }
  return {ok: true, json: json};
}

routerAdd("GET", "/api/wesi/connectors", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  const github = callBroker(ctx, "GET", "/v1/connectors/github/status");
  const value = github.ok ? github.json : {connector: "github", connected: false, unavailable: github.code};
  return e.json(200, {ok: true, connectors: {github: value}});
}, $apis.requireAuth("users"));

routerAdd("POST", "/api/wesi/connectors/github/connect", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  if (!ctx.isOwner) throw new ForbiddenError("Подключать внешние сервисы может только владелец WesiOS");
  const result = callBroker(ctx, "POST", "/v1/connectors/github/connect");
  if (!result.ok) return e.json(result.status, {ok: false, code: result.code});
  return e.json(200, {ok: true, connector: "github", authorizationUrl: String(result.json.authorizationUrl || "")});
}, $apis.requireAuth("users"));

routerAdd("DELETE", "/api/wesi/connectors/github", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);
  if (!ctx.isOwner) throw new ForbiddenError("Отключать внешние сервисы может только владелец WesiOS");
  const result = callBroker(ctx, "DELETE", "/v1/connectors/github");
  if (!result.ok) return e.json(result.status, {ok: false, code: result.code});
  return e.json(200, {ok: true, connector: "github", disconnected: result.json.disconnected === true});
}, $apis.requireAuth("users"));
