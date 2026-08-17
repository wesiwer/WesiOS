function basePath() {
  return typeof __hooks !== "undefined" ? __hooks + "/" : "./";
}

function localRequest(workflow, input) {
  const contract = require(basePath() + "wesi_ai_media_contract.js");
  const normalized = contract.normalize(workflow, input);
  if (!normalized.ok) return normalized;
  return {ok: true, result: {localMediaRequest: normalized.request}};
}

const attachmentIndex = {type: "integer", enum: [0, 1, 2, 3]};
const attachmentIndexes = {type: "array", minItems: 1, maxItems: 4, items: attachmentIndex};

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
            prompt: {type: "string"}, title: {type: "string"},
            aspectRatio: {type: "string", enum: ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]},
            imageSize: {type: "string", enum: ["0.5K", "1K", "2K", "4K"]}
          }
        }
      },
      {
        name: "edit_image",
        description: "Изменить изображение из вложений текущего сообщения. attachmentIndex — номер вложения начиная с 0.",
        parameters: {
          type: "object", required: ["prompt", "attachmentIndex"],
          properties: {
            prompt: {type: "string"}, attachmentIndex: attachmentIndex, title: {type: "string"},
            aspectRatio: {type: "string", enum: ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]},
            imageSize: {type: "string", enum: ["0.5K", "1K", "2K", "4K"]}
          }
        }
      },
      {
        name: "reference_image",
        description: "Создать новое изображение с опорой на изображение из вложений текущего сообщения. attachmentIndex — номер вложения начиная с 0.",
        parameters: {
          type: "object", required: ["prompt", "attachmentIndex"],
          properties: {
            prompt: {type: "string"}, attachmentIndex: attachmentIndex, title: {type: "string"},
            aspectRatio: {type: "string", enum: ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"]},
            imageSize: {type: "string", enum: ["0.5K", "1K", "2K", "4K"]}
          }
        }
      },
      {
        name: "generate_music",
        description: "Сгенерировать новую музыку локальным Wesi Music Engine по явной просьбе пользователя.",
        parameters: {
          type: "object", required: ["prompt"],
          properties: {
            prompt: {type: "string"}, title: {type: "string"},
            mode: {type: "string", enum: ["clip", "pro"]},
            format: {type: "string", enum: ["mp3", "wav"]}
          }
        }
      },
      {
        name: "separate_music_stems",
        description: "Разделить аудиофайл из вложений текущего сообщения на стемы.",
        parameters: {
          type: "object", required: ["attachmentIndex"],
          properties: {attachmentIndex: attachmentIndex, prompt: {type: "string"}, title: {type: "string"}, format: {type: "string", enum: ["wav", "flac"]}}
        }
      },
      {
        name: "regenerate_music_stem",
        description: "Перегенерировать один выбранный музыкальный стем из текущего вложения. Не принимает filesystem path.",
        parameters: {
          type: "object", required: ["attachmentIndex", "prompt"],
          properties: {
            attachmentIndex: attachmentIndex, prompt: {type: "string"}, title: {type: "string"},
            stemName: {type: "string"}, format: {type: "string", enum: ["wav", "flac"]}
          }
        }
      },
      {
        name: "mix_music",
        description: "Свести 2–4 музыкальных дорожки/стема из вложений текущего сообщения.",
        parameters: {
          type: "object", required: ["attachmentIndexes"],
          properties: {
            attachmentIndexes: {type: "array", minItems: 2, maxItems: 4, items: attachmentIndex},
            prompt: {type: "string"}, title: {type: "string"}, format: {type: "string", enum: ["wav", "flac"]}, normalize: {type: "boolean"}
          }
        }
      },
      {
        name: "export_music",
        description: "Экспортировать мастер, стемы или пакет из 1–4 музыкальных вложений текущего сообщения.",
        parameters: {
          type: "object", required: ["attachmentIndexes"],
          properties: {
            attachmentIndexes: attachmentIndexes, prompt: {type: "string"}, title: {type: "string"},
            target: {type: "string", enum: ["master", "stems", "package"]}, format: {type: "string", enum: ["wav", "flac"]}
          }
        }
      },
      {
        name: "generate_video",
        description: "Сгенерировать новое видео с нуля локальным Wesi Video Engine по явной просьбе пользователя.",
        parameters: {
          type: "object", required: ["prompt"],
          properties: {
            prompt: {type: "string"}, title: {type: "string"}, aspectRatio: {type: "string", enum: ["16:9", "9:16"]},
            resolution: {type: "string", enum: ["720p", "1080p", "4k"]}, durationSeconds: {type: "string", enum: ["4", "6", "8"]},
            quality: {type: "string", enum: ["fast", "quality"]}
          }
        }
      },
      {
        name: "compose_video",
        description: "Собрать видео из 1–4 вложений текущего сообщения. Произвольные пути запрещены.",
        parameters: {
          type: "object", required: ["prompt", "attachmentIndexes"],
          properties: {
            prompt: {type: "string"}, attachmentIndexes: attachmentIndexes, title: {type: "string"},
            aspectRatio: {type: "string", enum: ["16:9", "9:16"]}, resolution: {type: "string", enum: ["720p", "1080p", "4k"]},
            durationSeconds: {type: "string", enum: ["4", "6", "8"]}, quality: {type: "string", enum: ["fast", "quality"]}
          }
        }
      },
      {
        name: "add_video_voice",
        description: "Добавить голосовую дорожку из вложения к видео из другого вложения текущего сообщения.",
        parameters: {
          type: "object", required: ["videoAttachmentIndex", "voiceAttachmentIndex"],
          properties: {
            videoAttachmentIndex: attachmentIndex, voiceAttachmentIndex: attachmentIndex, prompt: {type: "string"}, title: {type: "string"},
            mix: {type: "string", enum: ["replace", "duck", "overlay"]}
          }
        }
      },
      {
        name: "add_video_sfx",
        description: "Добавить или сгенерировать звуковые эффекты для видео из вложения текущего сообщения.",
        parameters: {type: "object", required: ["videoAttachmentIndex", "prompt"], properties: {videoAttachmentIndex: attachmentIndex, prompt: {type: "string"}, title: {type: "string"}}}
      },
      {
        name: "add_video_subtitles",
        description: "Добавить субтитры к видео из вложения текущего сообщения.",
        parameters: {type: "object", required: ["videoAttachmentIndex"], properties: {videoAttachmentIndex: attachmentIndex, prompt: {type: "string"}, language: {type: "string"}, title: {type: "string"}}}
      }
    ];
  },

  context: function() {
    return {
      mediaGeneration: ["image", "music", "video"],
      mediaWorkflows: [
        "imageGenerate", "imageEdit", "imageReference",
        "musicGenerate", "musicStems", "musicRegenerateStem", "musicMix", "musicExport",
        "videoGenerate", "videoCompose", "videoVoice", "videoSfx", "videoSubtitles"
      ],
      mediaAttachmentSelection: "current_turn_indexes_0_to_3",
      mediaExecution: "verified_client_engine",
      mediaValidation: "wesi-media-v1",
      paidCloudMedia: false
    };
  },

  execute: function(e, ctx, name, args) {
    const input = args && typeof args === "object" && !Array.isArray(args) ? args : {};
    if (name === "generate_image") return localRequest("imageGenerate", input);
    if (name === "edit_image") return localRequest("imageEdit", input);
    if (name === "reference_image") return localRequest("imageReference", input);
    if (name === "generate_music") return localRequest("musicGenerate", input);
    if (name === "separate_music_stems") return localRequest("musicStems", input);
    if (name === "regenerate_music_stem") return localRequest("musicRegenerateStem", input);
    if (name === "mix_music") return localRequest("musicMix", input);
    if (name === "export_music") return localRequest("musicExport", input);
    if (name === "generate_video") return localRequest("videoGenerate", input);
    if (name === "compose_video") return localRequest("videoCompose", input);
    if (name === "add_video_voice") return localRequest("videoVoice", input);
    if (name === "add_video_sfx") return localRequest("videoSfx", input);
    if (name === "add_video_subtitles") return localRequest("videoSubtitles", input);
    return {ok: false, code: "FORBIDDEN", message: "Неизвестный media tool"};
  }
};
