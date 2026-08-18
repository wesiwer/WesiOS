routerAdd("POST", "/api/wesi/ai/tts", (e) => {
  const ai = require(`${__hooks}/wesi_ai_lib.js`);
  const ctx = ai.resolveIdentity(e);
  ai.requireAiModule(ctx);

  const body = e.requestInfo().body || {};
  const persona = String(body.persona || "").trim().toLowerCase();
  const text = String(body.text || "").trim();
  if (["zane", "nirvana"].indexOf(persona) < 0) {
    throw new BadRequestError("Некорректный голос Wesi AI");
  }
  if (!text || text.length > 8000) {
    throw new BadRequestError("Некорректный текст для озвучки Wesi AI");
  }

  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return e.json(503, {ok: false, code: "WAI_RELAY_NOT_CONFIGURED"});

  const requestId = "wai_tts_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "tts",
    input: {persona: persona, text: text}
  }, requestId, 120);
  if (!relay.ok) {
    return e.json(relay.status || 502, {
      ok: false,
      code: relay.code || "WAI_RELAY_BAD_RESPONSE",
      requestId: requestId
    });
  }

  const media = relay.result && relay.result.media && typeof relay.result.media === "object"
    ? relay.result.media : {};
  const data = String(media.data || "");
  const mimeType = String(media.mimeType || "");
  const byteSize = Number(media.byteSize || 0);
  if (String(media.kind || "") !== "tts" ||
      !/^audio\/(wav|mpeg|mp3|ogg|opus|aac|flac|l16)$/i.test(mimeType) ||
      !/^[A-Za-z0-9+/=]+$/.test(data) ||
      data.length > 28 * 1024 * 1024 ||
      !Number.isFinite(byteSize) || byteSize <= 0 || byteSize > 20 * 1024 * 1024) {
    return e.json(502, {ok: false, code: "WAI_RELAY_BAD_RESPONSE", requestId: requestId});
  }

  return e.json(200, {
    ok: true,
    requestId: requestId,
    mimeType: mimeType,
    audioBase64: data,
    byteSize: byteSize
  });
}, $apis.requireAuth("users"));
