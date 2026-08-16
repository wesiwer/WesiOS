function basePath() {
  return typeof __hooks !== "undefined" ? __hooks + "/" : "./";
}

function localRequest(workflow, input) {
  const contract = require(basePath() + "wesi_ai_media_contract.js");
  const normalized = contract.normalize(workflow, input);
  if (!normalized.ok) return normalized;
  return {ok: true, result: {localMediaRequest: normalized.request}};
}

module.exports = {
  definitions: function() {
    return [
      {
        name: "generate_image",
        description: "Сгенерировать новое изображение локальным Wesi Image Engine по явной просьбе пользователя. Не вызывай для редактирования уже приложенного изображения.",
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
        description: "Сгенерировать новую музыку локальным Wesi Music Engine по явной просьбе пользователя.",
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
        description: "Сгенерировать новое видео с нуля локальным Wesi Video Engine по явной просьбе пользователя. Не используй для обработки приложенного видео.",
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
      mediaWorkflows: ["imageGenerate", "musicGenerate", "videoGenerate"],
      mediaExecution: "verified_client_engine",
      paidCloudMedia: false
    };
  },

  execute: function(e, ctx, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    if (name === "generate_image") return localRequest("imageGenerate", input);
    if (name === "generate_music") return localRequest("musicGenerate", input);
    if (name === "generate_video") return localRequest("videoGenerate", input);
    return {ok: false, code: "FORBIDDEN", message: "Неизвестный media tool"};
  }
};
