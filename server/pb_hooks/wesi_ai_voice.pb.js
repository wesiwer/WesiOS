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
  const payload = {
    requestId: requestId,
    operation: "tts",
    input: {persona: persona, text: text}
  };
  const raw = JSON.stringify(payload);
  const timestamp = String(Math.floor(Date.now() / 1000));
  const signature = $security.hs256(requestId + "." + timestamp + "." + raw, cfg.sharedSecret);

  let relay;
  try {
    relay = $http.send({
      url: cfg.url.replace(/\/$/, "") + "/v1/wesi-ai",
      method: "POST",
      body: raw,
      headers: {
        "Content-Type": "application/json",
        "X-Wesi-Request-Id": requestId,
        "X-Wesi-Timestamp": timestamp,
        "X-Wesi-Signature": signature
      },
      timeout: 120
    });
  } catch (_) {
    return e.json(503, {ok: false, code: "WAI_RELAY_UNAVAILABLE", requestId: requestId});
  }

  if (!relay || relay.statusCode < 200 || relay.statusCode >= 300) {
    const provider = relay && relay.json && typeof relay.json === "object" ? relay.json : {};
    return e.json(relay && relay.statusCode === 429 ? 429 : 502, {
      ok: false,
      code: String(provider.code || "WAI_RELAY_BAD_RESPONSE"),
      requestId: requestId
    });
  }

  const result = relay.json && typeof relay.json === "object" ? relay.json : {};
  const media = result.media && typeof result.media === "object" ? result.media : {};
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
