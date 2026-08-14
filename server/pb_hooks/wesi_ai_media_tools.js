function text(value, max) {
  const raw = String(value == null ? "" : value).trim();
  return raw.length <= max ? raw : raw.slice(0, max);
}

function configReady() {
  try {
    const ai = require((typeof __hooks !== "undefined" ? __hooks + "/" : "./") + "wesi_ai_lib.js");
    return ai.readRelayConfig().ready === true;
  } catch (_) {
    return false;
  }
}

function generateImage(ctx, input) {
  const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
  const ai = require(base + "wesi_ai_lib.js");
  const media = require(base + "wesi_ai_media_lib.js");
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return {ok: false, code: "WAI_RELAY_NOT_CONFIGURED", message: "Генерация изображений пока не подключена"};

  const prompt = text(input.prompt, 12000);
  if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание изображения"};
  const aspect = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"].indexOf(String(input.aspectRatio || "")) >= 0
    ? String(input.aspectRatio) : "1:1";
  const size = ["0.5K", "1K", "2K", "4K"].indexOf(String(input.imageSize || "")) >= 0
    ? String(input.imageSize) : "1K";
  const title = text(input.title || "Изображение Wesi AI", 240);
  const record = media.createJob(ctx, "image", prompt, title, {aspectRatio: aspect, imageSize: size});
  const payload = media.payloadOf(record);
  payload.status = "running";
  media.savePayload(record, payload);

  const requestId = "wai_img_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "image",
    input: {prompt: prompt, aspectRatio: aspect, imageSize: size}
  }, requestId, 240);
  if (!relay.ok) {
    media.failJob(record, relay.code);
    return {ok: false, code: relay.code, message: "Не удалось сгенерировать изображение"};
  }
  const relayMedia = relay.result && relay.result.media && typeof relay.result.media === "object" ? relay.result.media : null;
  const saved = media.persistRelayArtifact(ai, cfg, record, relayMedia);
  if (!saved.ok) {
    media.failJob(record, saved.code);
    return {ok: false, code: saved.code, message: "Изображение получено, но не удалось сохранить его в WesiOS"};
  }
  return {ok: true, result: {jobId: saved.payload.jobId, contentBlock: saved.contentBlock}};
}

function generateMusic(ctx, input) {
  const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
  const ai = require(base + "wesi_ai_lib.js");
  const media = require(base + "wesi_ai_media_lib.js");
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return {ok: false, code: "WAI_RELAY_NOT_CONFIGURED", message: "Генерация музыки пока не подключена"};

  const prompt = text(input.prompt, 12000);
  if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание музыки"};
  const mode = String(input.mode || "clip") === "pro" ? "pro" : "clip";
  const format = mode === "pro" && String(input.format || "").toLowerCase() === "wav" ? "wav" : "mp3";
  const title = text(input.title || "Музыка Wesi AI", 240);
  const record = media.createJob(ctx, "music", prompt, title, {mode: mode, format: format});
  const payload = media.payloadOf(record);
  payload.status = "running";
  media.savePayload(record, payload);

  const requestId = "wai_music_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "music",
    input: {prompt: prompt, mode: mode, format: format}
  }, requestId, mode === "pro" ? 420 : 240);
  if (!relay.ok) {
    media.failJob(record, relay.code);
    return {ok: false, code: relay.code, message: "Не удалось сгенерировать музыку"};
  }
  const relayMedia = relay.result && relay.result.media && typeof relay.result.media === "object" ? relay.result.media : null;
  const saved = media.persistRelayArtifact(ai, cfg, record, relayMedia);
  if (!saved.ok) {
    media.failJob(record, saved.code);
    return {ok: false, code: saved.code, message: "Музыка получена, но не удалось сохранить её в WesiOS"};
  }
  if (relayMedia && relayMedia.lyrics) {
    const latest = media.payloadOf(record);
    latest.lyrics = text(relayMedia.lyrics, 20000);
    media.savePayload(record, latest);
  }
  return {ok: true, result: {jobId: saved.payload.jobId, contentBlock: saved.contentBlock}};
}

function generateVideo(ctx, input) {
  const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
  const ai = require(base + "wesi_ai_lib.js");
  const media = require(base + "wesi_ai_media_lib.js");
  const cfg = ai.readRelayConfig();
  if (!cfg.ready) return {ok: false, code: "WAI_RELAY_NOT_CONFIGURED", message: "Генерация видео пока не подключена"};

  const prompt = text(input.prompt, 6000);
  if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание видео"};
  const aspect = ["16:9", "9:16"].indexOf(String(input.aspectRatio || "")) >= 0 ? String(input.aspectRatio) : "16:9";
  const resolution = ["720p", "1080p", "4k"].indexOf(String(input.resolution || "")) >= 0 ? String(input.resolution) : "720p";
  let durationSeconds = ["4", "6", "8"].indexOf(String(input.durationSeconds || "")) >= 0 ? String(input.durationSeconds) : "8";
  if ((resolution === "1080p" || resolution === "4k") && durationSeconds !== "8") durationSeconds = "8";
  const quality = String(input.quality || "") === "fast" ? "fast" : "quality";
  const title = text(input.title || "Видео Wesi AI", 240);
  const record = media.createJob(ctx, "video", prompt, title, {
    aspectRatio: aspect,
    resolution: resolution,
    durationSeconds: durationSeconds,
    quality: quality
  });

  const requestId = "wai_video_" + Date.now() + "_" + $security.randomString(12);
  const relay = ai.callRelayJson(cfg, {
    requestId: requestId,
    operation: "video.start",
    input: {
      prompt: prompt,
      aspectRatio: aspect,
      resolution: resolution,
      durationSeconds: durationSeconds,
      quality: quality
    }
  }, requestId, 180);
  if (!relay.ok) {
    media.failJob(record, relay.code);
    return {ok: false, code: relay.code, message: "Не удалось запустить генерацию видео"};
  }
  const job = relay.result && relay.result.job && typeof relay.result.job === "object" ? relay.result.job : {};
  const operationName = String(job.operationName || "");
  if (!/^[A-Za-z0-9._\/-]{4,300}$/.test(operationName) || operationName.indexOf("..") >= 0) {
    media.failJob(record, "WAI_PROVIDER_BAD_RESPONSE");
    return {ok: false, code: "WAI_PROVIDER_BAD_RESPONSE", message: "Провайдер не вернул корректную задачу видео"};
  }
  const payload = media.payloadOf(record);
  payload.status = "running";
  payload.providerOperationName = operationName;
  payload.providerModel = text(job.model, 120);
  payload.startedAt = new Date().toISOString();
  media.savePayload(record, payload);

  const statusUrl = "https://api.wesi-inc.ru/api/wesi/ai/media/jobs/" + encodeURIComponent(payload.jobId);
  return {
    ok: true,
    result: {
      jobId: payload.jobId,
      contentBlock: {
        type: "media",
        data: {
          mediaType: "video",
          title: title,
          prompt: text(prompt, 2000),
          status: "pending",
          url: statusUrl
        }
      }
    }
  };
}

module.exports = {
  definitions: function() {
    if (!configReady()) return [];
    return [
      {
        name: "generate_image",
        description: "Сгенерировать изображение по явной просьбе пользователя и показать готовый WesiOS-артефакт в чате. Не вызывай для иллюстрации обычного ответа без прямой просьбы создать изображение.",
        parameters: {
          type: "object",
          required: ["prompt"],
          properties: {
            prompt: {type: "string"},
            title: {type: "string"},
            aspectRatio: {type: "string", enum: ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]},
            imageSize: {type: "string", enum: ["0.5K", "1K", "2K", "4K"]}
          }
        }
      },
      {
        name: "generate_music",
        description: "Сгенерировать музыку по явной просьбе пользователя. clip подходит для быстрого 30-секундного результата, pro — для длинной композиции. Не вызывай без прямой просьбы создать музыку/бит/трек.",
        parameters: {
          type: "object",
          required: ["prompt"],
          properties: {
            prompt: {type: "string"},
            title: {type: "string"},
            mode: {type: "string", enum: ["clip", "pro"]},
            format: {type: "string", enum: ["mp3", "wav"]}
          }
        }
      },
      {
        name: "generate_video",
        description: "Запустить асинхронную генерацию видео по явной просьбе пользователя. Возвращает pending-карточку; WesiOS сам отслеживает задачу и заменяет её готовым видео. Не вызывай без прямой просьбы создать видео.",
        parameters: {
          type: "object",
          required: ["prompt"],
          properties: {
            prompt: {type: "string"},
            title: {type: "string"},
            aspectRatio: {type: "string", enum: ["16:9", "9:16"]},
            resolution: {type: "string", enum: ["720p", "1080p", "4k"]},
            durationSeconds: {type: "string", enum: ["4", "6", "8"]},
            quality: {type: "string", enum: ["fast", "quality"]}
          }
        }
      }
    ];
  },

  context: function() {
    return configReady() ? {mediaGeneration: ["image", "music", "video"]} : {};
  },

  execute: function(e, ctx, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    if (name === "generate_image") return generateImage(ctx, input);
    if (name === "generate_music") return generateMusic(ctx, input);
    if (name === "generate_video") return generateVideo(ctx, input);
    return {ok: false, code: "FORBIDDEN", message: "Неизвестный media tool"};
  }
};
