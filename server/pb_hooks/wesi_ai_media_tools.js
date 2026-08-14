function text(value, max) {
  const raw = String(value == null ? "" : value).trim();
  return raw.length <= max ? raw : raw.slice(0, max);
}

function localRequest(kind, input) {
  if (kind === "image") {
    const prompt = text(input.prompt, 12000);
    if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание изображения"};
    const aspect = ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"].indexOf(String(input.aspectRatio || "")) >= 0
      ? String(input.aspectRatio) : "1:1";
    const size = ["0.5K", "1K", "2K", "4K"].indexOf(String(input.imageSize || "")) >= 0
      ? String(input.imageSize) : "1K";
    return {
      ok: true,
      result: {
        localMediaRequest: {
          mediaType: "image",
          title: text(input.title || "Изображение Wesi AI", 240),
          prompt: prompt,
          options: {aspectRatio: aspect, imageSize: size}
        }
      }
    };
  }

  if (kind === "music") {
    const prompt = text(input.prompt, 12000);
    if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание музыки"};
    const mode = String(input.mode || "clip") === "pro" ? "pro" : "clip";
    const format = mode === "pro" && String(input.format || "").toLowerCase() === "wav" ? "wav" : "mp3";
    return {
      ok: true,
      result: {
        localMediaRequest: {
          mediaType: "music",
          title: text(input.title || "Музыка Wesi AI", 240),
          prompt: prompt,
          options: {mode: mode, format: format}
        }
      }
    };
  }

  if (kind === "video") {
    const prompt = text(input.prompt, 6000);
    if (!prompt) return {ok: false, code: "VALIDATION_ERROR", message: "Нужно описание видео"};
    const aspect = ["16:9", "9:16"].indexOf(String(input.aspectRatio || "")) >= 0 ? String(input.aspectRatio) : "16:9";
    const resolution = ["720p", "1080p", "4k"].indexOf(String(input.resolution || "")) >= 0 ? String(input.resolution) : "720p";
    let durationSeconds = ["4", "6", "8"].indexOf(String(input.durationSeconds || "")) >= 0 ? String(input.durationSeconds) : "8";
    if ((resolution === "1080p" || resolution === "4k") && durationSeconds !== "8") durationSeconds = "8";
    const quality = String(input.quality || "") === "fast" ? "fast" : "quality";
    return {
      ok: true,
      result: {
        localMediaRequest: {
          mediaType: "video",
          title: text(input.title || "Видео Wesi AI", 240),
          prompt: prompt,
          options: {
            aspectRatio: aspect,
            resolution: resolution,
            durationSeconds: durationSeconds,
            quality: quality
          }
        }
      }
    };
  }

  return {ok: false, code: "FORBIDDEN", message: "Неизвестный media tool"};
}

module.exports = {
  definitions: function() {
    return [
      {
        name: "generate_image",
        description: "Сгенерировать изображение локальным Wesi Image Engine по явной просьбе пользователя. Если движок не установлен на устройстве, приложение предложит его установить. Не вызывай без прямой просьбы создать изображение.",
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
        description: "Сгенерировать музыку локальным Wesi Music Engine по явной просьбе пользователя. Если движок не установлен, приложение предложит установку.",
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
        description: "Сгенерировать видео локальным Wesi Video Engine по явной просьбе пользователя. Если движок не установлен, приложение предложит установку.",
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
    return {
      mediaGeneration: ["image", "music", "video"],
      mediaExecution: "verified_client_engine",
      paidCloudMedia: false
    };
  },

  execute: function(e, ctx, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    if (name === "generate_image") return localRequest("image", input);
    if (name === "generate_music") return localRequest("music", input);
    if (name === "generate_video") return localRequest("video", input);
    return {ok: false, code: "FORBIDDEN", message: "Неизвестный media tool"};
  }
};
