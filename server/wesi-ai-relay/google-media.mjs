const INTERACTIONS_URL = 'https://generativelanguage.googleapis.com/v1beta/interactions';
const GEMINI_BASE = 'https://generativelanguage.googleapis.com/v1beta';

const VOICES = new Set([
  'Zephyr', 'Puck', 'Charon', 'Kore', 'Fenrir', 'Leda', 'Orus', 'Aoede',
  'Callirrhoe', 'Autonoe', 'Enceladus', 'Iapetus', 'Umbriel', 'Algieba',
  'Despina', 'Erinome', 'Algenib', 'Rasalgethi', 'Laomedeia', 'Achernar',
  'Alnilam', 'Schedar', 'Gacrux', 'Pulcherrima', 'Achird', 'Zubenelgenubi',
  'Vindemiatrix', 'Sadachbia', 'Sadaltager', 'Sulafat',
]);

const IMAGE_ASPECTS = new Set([
  '1:1', '2:3', '3:2', '3:4', '4:3', '4:5', '5:4', '9:16', '16:9',
  '21:9', '1:4', '4:1', '1:8', '8:1',
]);
const IMAGE_SIZES = new Set(['0.5K', '1K', '2K', '4K']);
const VIDEO_ASPECTS = new Set(['16:9', '9:16']);
const VIDEO_RESOLUTIONS = new Set(['720p', '1080p', '4k']);
const VIDEO_DURATIONS = new Set(['4', '6', '8']);
const MUSIC_MODES = new Set(['clip', 'pro']);

function boundedText(value, max) {
  const text = String(value || '').trim();
  return text.length <= max ? text : text.slice(0, max);
}

function providerFailure(status) {
  if (status === 429) return {ok: false, status: 429, code: 'WAI_PROVIDER_RATE_LIMIT'};
  if (status === 401 || status === 403) return {ok: false, status: 502, code: 'WAI_PROVIDER_AUTH_FAILED'};
  return {ok: false, status: 502, code: 'WAI_PROVIDER_REJECTED'};
}

async function readJson(response) {
  try { return await response.json(); } catch { return {}; }
}

function contentBlock(data, type) {
  const convenience = type === 'audio' ? data?.output_audio : type === 'image' ? data?.output_image : null;
  if (convenience && typeof convenience.data === 'string' && convenience.data) return convenience;
  const steps = Array.isArray(data?.steps) ? data.steps : [];
  for (let i = steps.length - 1; i >= 0; i--) {
    const step = steps[i];
    if (step?.type !== 'model_output' || !Array.isArray(step.content)) continue;
    for (let j = step.content.length - 1; j >= 0; j--) {
      const block = step.content[j];
      if (block?.type === type && typeof block.data === 'string' && block.data) return block;
    }
  }
  return null;
}

function outputText(data) {
  if (typeof data?.output_text === 'string') return data.output_text.trim();
  const steps = Array.isArray(data?.steps) ? data.steps : [];
  const chunks = [];
  for (const step of steps) {
    if (step?.type !== 'model_output' || !Array.isArray(step.content)) continue;
    for (const block of step.content) {
      if (block?.type === 'text' && typeof block.text === 'string' && block.text.trim()) chunks.push(block.text.trim());
    }
  }
  return chunks.join('\n').trim();
}

export function personaVoice(persona, env = process.env) {
  const requested = String(
    String(persona || '').toLowerCase() === 'nirvana'
      ? env.WESI_NIRVANA_TTS_VOICE || 'Sulafat'
      : env.WESI_ZANE_TTS_VOICE || 'Charon',
  ).trim();
  return VOICES.has(requested) ? requested : (String(persona || '').toLowerCase() === 'nirvana' ? 'Sulafat' : 'Charon');
}

export function personaSpeechStyle(persona) {
  return String(persona || '').toLowerCase() === 'nirvana'
    ? 'Тёпло, живо и естественно, с мягкой уверенностью. Без театральности и без лишней эмоциональной наигранности.'
    : 'Спокойно, точно и уверенно, немного ниже по тону, без спешки и без театральности.';
}

export async function callGoogleTts(input, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const text = boundedText(input?.text, 8000);
  if (!text) return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const persona = String(input?.persona || '').toLowerCase();
  if (persona !== 'zane' && persona !== 'nirvana') return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const voice = personaVoice(persona, options.env || process.env);
  const style = personaSpeechStyle(persona);
  const fetchImpl = options.fetchImpl || fetch;
  const body = {
    model: 'gemini-3.1-flash-tts-preview',
    input: `Синтезируй речь на русском языке. ${style}\nПроизнеси дословно только текст после метки [ТЕКСТ], ничего не добавляя.\n[ТЕКСТ]\n${text}`,
    response_format: {type: 'audio', mime_type: 'audio/wav', sample_rate: 24000, delivery: 'inline'},
    generation_config: {speech_config: [{voice}]},
  };

  for (let attempt = 0; attempt < 2; attempt++) {
    let response;
    try {
      response = await fetchImpl(INTERACTIONS_URL, {
        method: 'POST',
        headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(90000),
      });
    } catch (error) {
      const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
      return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
    }
    const data = await readJson(response);
    if (!response.ok) {
      if (response.status === 500 && attempt === 0) continue;
      return providerFailure(response.status);
    }
    const audio = contentBlock(data, 'audio');
    if (!audio) {
      if (attempt === 0) continue;
      return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
    }
    const bytes = Buffer.from(audio.data, 'base64');
    if (!bytes.length || bytes.length > 20 * 1024 * 1024) return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
    return {
      ok: true,
      media: {
        kind: 'tts',
        mimeType: String(audio.mime_type || 'audio/wav'),
        data: bytes.toString('base64'),
        byteSize: bytes.length,
        sampleRate: Number(audio.sample_rate || 24000),
        voice,
      },
    };
  }
  return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}

export async function callGoogleImage(input, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prompt = boundedText(input?.prompt, 12000);
  if (!prompt) return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const aspectRatio = IMAGE_ASPECTS.has(String(input?.aspectRatio || '')) ? String(input.aspectRatio) : '1:1';
  const imageSize = IMAGE_SIZES.has(String(input?.imageSize || '')) ? String(input.imageSize) : '1K';
  const fetchImpl = options.fetchImpl || fetch;
  let response;
  try {
    response = await fetchImpl(INTERACTIONS_URL, {
      method: 'POST',
      headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
      body: JSON.stringify({
        model: 'gemini-3.1-flash-image',
        input: prompt,
        response_format: {type: 'image', mime_type: 'image/png', aspect_ratio: aspectRatio, image_size: imageSize},
      }),
      signal: AbortSignal.timeout(180000),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
  }
  const data = await readJson(response);
  if (!response.ok) return providerFailure(response.status);
  const image = contentBlock(data, 'image');
  if (!image) return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
  const bytes = Buffer.from(image.data, 'base64');
  if (!bytes.length || bytes.length > 32 * 1024 * 1024) return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
  return {
    ok: true,
    media: {
      kind: 'image',
      mimeType: String(image.mime_type || 'image/png'),
      data: bytes.toString('base64'),
      byteSize: bytes.length,
      aspectRatio,
      imageSize,
    },
  };
}

export async function callGoogleMusic(input, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prompt = boundedText(input?.prompt, 12000);
  if (!prompt) return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const mode = MUSIC_MODES.has(String(input?.mode || '')) ? String(input.mode) : 'clip';
  const model = mode === 'pro' ? 'lyria-3-pro-preview' : 'lyria-3-clip-preview';
  const fetchImpl = options.fetchImpl || fetch;
  let response;
  try {
    response = await fetchImpl(INTERACTIONS_URL, {
      method: 'POST',
      headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
      body: JSON.stringify({
        model,
        input: prompt,
        ...(mode === 'pro' && input?.format === 'wav' ? {response_format: {type: 'audio', mime_type: 'audio/wav'}} : {}),
      }),
      signal: AbortSignal.timeout(mode === 'pro' ? 360000 : 180000),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
  }
  const data = await readJson(response);
  if (!response.ok) return providerFailure(response.status);
  const audio = contentBlock(data, 'audio');
  if (!audio) return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
  const bytes = Buffer.from(audio.data, 'base64');
  if (!bytes.length || bytes.length > 64 * 1024 * 1024) return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
  return {
    ok: true,
    media: {
      kind: 'music',
      mimeType: String(audio.mime_type || (mode === 'pro' && input?.format === 'wav' ? 'audio/wav' : 'audio/mpeg')),
      data: bytes.toString('base64'),
      byteSize: bytes.length,
      model,
      mode,
      lyrics: outputText(data).slice(0, 20000),
    },
  };
}

export async function startGoogleVideo(input, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prompt = boundedText(input?.prompt, 6000);
  if (!prompt) return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const aspectRatio = VIDEO_ASPECTS.has(String(input?.aspectRatio || '')) ? String(input.aspectRatio) : '16:9';
  const resolution = VIDEO_RESOLUTIONS.has(String(input?.resolution || '')) ? String(input.resolution) : '720p';
  let durationSeconds = VIDEO_DURATIONS.has(String(input?.durationSeconds || '')) ? String(input.durationSeconds) : '8';
  if ((resolution === '1080p' || resolution === '4k') && durationSeconds !== '8') durationSeconds = '8';
  const model = input?.quality === 'fast' ? 'veo-3.1-fast-generate-preview' : 'veo-3.1-generate-preview';
  const fetchImpl = options.fetchImpl || fetch;
  let response;
  try {
    response = await fetchImpl(`${GEMINI_BASE}/models/${model}:predictLongRunning`, {
      method: 'POST',
      headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
      body: JSON.stringify({
        instances: [{prompt}],
        parameters: {numberOfVideos: 1, aspectRatio, resolution, durationSeconds},
      }),
      signal: AbortSignal.timeout(120000),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
  }
  const data = await readJson(response);
  if (!response.ok) return providerFailure(response.status);
  const operationName = String(data?.name || '').trim();
  if (!/^[A-Za-z0-9._\/-]{4,300}$/.test(operationName)) return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_RESPONSE'};
  return {ok: true, operationName, model, aspectRatio, resolution, durationSeconds};
}

export async function getGoogleVideoStatus(operationName, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const name = String(operationName || '').trim();
  if (!/^[A-Za-z0-9._\/-]{4,300}$/.test(name) || name.includes('..')) return {ok: false, status: 400, code: 'WAI_BAD_MEDIA_REQUEST'};
  const fetchImpl = options.fetchImpl || fetch;
  let response;
  try {
    response = await fetchImpl(`${GEMINI_BASE}/${name.replace(/^\/+/, '')}`, {
      method: 'GET',
      headers: {'x-goog-api-key': apiKey},
      signal: AbortSignal.timeout(30000),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
  }
  const data = await readJson(response);
  if (!response.ok) return providerFailure(response.status);
  if (data?.done !== true) return {ok: true, done: false};
  if (data?.error) return {ok: true, done: true, failed: true, code: 'WAI_MEDIA_JOB_FAILED'};
  const uri = String(
    data?.response?.generateVideoResponse?.generatedSamples?.[0]?.video?.uri ||
    data?.response?.generatedVideos?.[0]?.video?.uri ||
    '',
  ).trim();
  if (!/^https:\/\//.test(uri)) return {ok: true, done: true, failed: true, code: 'WAI_PROVIDER_BAD_RESPONSE'};
  return {ok: true, done: true, failed: false, providerUri: uri};
}

export const mediaLimits = Object.freeze({
  ttsText: 8000,
  imagePrompt: 12000,
  musicPrompt: 12000,
  videoPrompt: 6000,
});
