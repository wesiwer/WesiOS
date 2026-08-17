const WORKFLOWS = {
  imageGenerate: {mediaType: "image", minInputs: 0, maxInputs: 0, promptMax: 12000},
  imageEdit: {mediaType: "image", minInputs: 1, maxInputs: 1, promptMax: 12000},
  imageReference: {mediaType: "image", minInputs: 1, maxInputs: 1, promptMax: 12000},
  musicGenerate: {mediaType: "music", minInputs: 0, maxInputs: 0, promptMax: 12000},
  musicStems: {mediaType: "music", minInputs: 1, maxInputs: 1, promptMax: 4000, defaultPrompt: "Разделить аудио на отдельные стемы"},
  musicRegenerateStem: {mediaType: "music", minInputs: 1, maxInputs: 1, promptMax: 6000, defaultPrompt: "Перегенерировать выбранный музыкальный стем"},
  musicMix: {mediaType: "music", minInputs: 2, maxInputs: 4, promptMax: 6000, defaultPrompt: "Свести выбранные музыкальные дорожки"},
  musicExport: {mediaType: "music", minInputs: 1, maxInputs: 4, promptMax: 4000, defaultPrompt: "Экспортировать музыкальный результат"},
  videoGenerate: {mediaType: "video", minInputs: 0, maxInputs: 0, promptMax: 6000},
  videoCompose: {mediaType: "video", minInputs: 1, maxInputs: 4, promptMax: 6000},
  videoVoice: {mediaType: "video", minInputs: 2, maxInputs: 2, promptMax: 6000, defaultPrompt: "Добавить голосовую дорожку к видео"},
  videoSfx: {mediaType: "video", minInputs: 1, maxInputs: 1, promptMax: 6000},
  videoSubtitles: {mediaType: "video", minInputs: 1, maxInputs: 1, promptMax: 6000, defaultPrompt: "Добавить субтитры к видео"}
};

function safeText(value, max) {
  const text = String(value == null ? "" : value).trim();
  return text.length <= max ? text : text.slice(0, max);
}

function integerIndex(value) {
  const number = Number(value);
  return Number.isInteger(number) && number >= 0 && number <= 3 ? number : null;
}

function attachmentIndexes(raw) {
  const values = Array.isArray(raw) ? raw : (raw == null ? [] : [raw]);
  const out = [];
  for (const value of values) {
    const index = integerIndex(value);
    if (index == null || out.indexOf(index) >= 0) return null;
    out.push(index);
  }
  return out;
}

function enumValue(value, allowed, fallback) {
  const text = String(value == null ? "" : value).trim();
  return allowed.indexOf(text) >= 0 ? text : fallback;
}

function normalizeOptions(workflow, input) {
  let options = {};
  if (workflow === "imageGenerate" || workflow === "imageEdit" || workflow === "imageReference") {
    options = {
      aspectRatio: enumValue(input.aspectRatio, ["1:1", "2:3", "3:2", "3:4", "4:3", "4:5", "5:4", "9:16", "16:9", "21:9"], "1:1"),
      imageSize: enumValue(input.imageSize, ["0.5K", "1K", "2K", "4K"], "1K")
    };
  } else if (workflow === "musicGenerate") {
    const mode = enumValue(input.mode, ["clip", "pro"], "clip");
    options = {mode: mode, format: mode === "pro" ? enumValue(String(input.format || "").toLowerCase(), ["mp3", "wav"], "mp3") : "mp3"};
  } else if (workflow === "musicStems") {
    options = {format: enumValue(String(input.format || "").toLowerCase(), ["wav", "flac"], "wav")};
  } else if (workflow === "musicRegenerateStem") {
    options = {
      stemName: safeText(input.stemName || "stem", 80) || "stem",
      format: enumValue(String(input.format || "").toLowerCase(), ["wav", "flac"], "wav")
    };
  } else if (workflow === "musicMix") {
    options = {
      format: enumValue(String(input.format || "").toLowerCase(), ["wav", "flac"], "wav"),
      normalize: input.normalize !== false
    };
  } else if (workflow === "musicExport") {
    options = {
      target: enumValue(String(input.target || "").toLowerCase(), ["master", "stems", "package"], "master"),
      format: enumValue(String(input.format || "").toLowerCase(), ["wav", "flac"], "wav")
    };
  } else if (workflow === "videoGenerate" || workflow === "videoCompose") {
    const resolution = enumValue(String(input.resolution || "").toLowerCase(), ["720p", "1080p", "4k"], "720p");
    let durationSeconds = enumValue(String(input.durationSeconds || ""), ["4", "6", "8"], "8");
    if ((resolution === "1080p" || resolution === "4k") && durationSeconds !== "8") durationSeconds = "8";
    options = {
      aspectRatio: enumValue(input.aspectRatio, ["16:9", "9:16"], "16:9"),
      resolution: resolution,
      durationSeconds: durationSeconds,
      quality: enumValue(input.quality, ["fast", "quality"], "quality")
    };
  } else if (workflow === "videoVoice") {
    options = {mix: enumValue(input.mix, ["replace", "duck", "overlay"], "duck")};
  } else if (workflow === "videoSubtitles") {
    options = {language: safeText(input.language || "auto", 24) || "auto"};
  }
  options.workflow = String(workflow);
  return options;
}

function normalize(workflow, input) {
  const spec = WORKFLOWS[String(workflow || "")];
  if (!spec) return {ok: false, code: "WAI_MEDIA_WORKFLOW_FORBIDDEN", message: "Неизвестный media workflow"};
  const source = input && typeof input === "object" && !Array.isArray(input) ? input : {};
  let indexesRaw = source.attachmentIndexes;
  if (indexesRaw == null && source.attachmentIndex != null) indexesRaw = [source.attachmentIndex];
  if (indexesRaw == null && source.videoAttachmentIndex != null) {
    indexesRaw = [source.videoAttachmentIndex];
    if (source.voiceAttachmentIndex != null) indexesRaw.push(source.voiceAttachmentIndex);
  }
  const indexes = attachmentIndexes(indexesRaw);
  if (indexes == null || indexes.length < spec.minInputs || indexes.length > spec.maxInputs) {
    return {ok: false, code: "WAI_MEDIA_INPUT_REQUIRED", message: "Для этого media workflow нужны вложения текущего сообщения"};
  }
  let prompt = safeText(source.prompt, spec.promptMax);
  if (!prompt && spec.defaultPrompt) prompt = spec.defaultPrompt;
  if (!prompt) return {ok: false, code: "WAI_MEDIA_REQUEST_INVALID", message: "Нужно описание media-задачи"};
  return {
    ok: true,
    request: {
      mediaType: spec.mediaType,
      workflow: String(workflow),
      title: safeText(source.title || "Wesi AI Media", 240),
      prompt: prompt,
      attachmentIndexes: indexes,
      options: normalizeOptions(String(workflow), source)
    }
  };
}

module.exports = {
  WORKFLOWS: WORKFLOWS,
  normalize: normalize,
  attachmentIndexes: attachmentIndexes
};
