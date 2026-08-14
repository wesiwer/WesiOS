const TIMEOUT_MS = 20000;

async function readJson(response) {
  try { return await response.json(); } catch { return {}; }
}

function normalize(provider, raw) {
  const id = String(raw?.id || raw?.name || '').replace(/^models\//, '').trim();
  if (!id) return null;
  const context = Number(
    raw?.context_length ?? raw?.max_input_tokens ?? raw?.inputTokenLimit ?? raw?.input_token_limit,
  );
  const output = Number(raw?.max_tokens ?? raw?.outputTokenLimit ?? raw?.output_token_limit);
  return {
    id,
    route: `${provider}/${id}`,
    displayName: String(raw?.display_name || raw?.displayName || id),
    contextTokens: Number.isFinite(context) && context > 0 ? context : null,
    maxOutputTokens: Number.isFinite(output) && output > 0 ? output : null,
  };
}

async function listGoogle(apiKey) {
  if (!apiKey) return {configured: false, models: []};
  const response = await fetch('https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000', {
    headers: {'x-goog-api-key': apiKey}, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const data = await readJson(response);
  if (!response.ok) return {configured: true, ok: false, status: response.status, models: []};
  const models = (Array.isArray(data?.models) ? data.models : [])
    .filter((m) => Array.isArray(m?.supportedGenerationMethods) ? m.supportedGenerationMethods.includes('generateContent') : true)
    .map((m) => normalize('google', m)).filter(Boolean);
  return {configured: true, ok: true, models};
}

async function listOpenAi(apiKey) {
  if (!apiKey) return {configured: false, models: []};
  const response = await fetch('https://api.openai.com/v1/models', {
    headers: {authorization: `Bearer ${apiKey}`}, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const data = await readJson(response);
  if (!response.ok) return {configured: true, ok: false, status: response.status, models: []};
  return {configured: true, ok: true, models: (Array.isArray(data?.data) ? data.data : []).map((m) => normalize('openai', m)).filter(Boolean)};
}

async function listAnthropic(apiKey) {
  if (!apiKey) return {configured: false, models: []};
  const response = await fetch('https://api.anthropic.com/v1/models?limit=1000', {
    headers: {'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
    signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const data = await readJson(response);
  if (!response.ok) return {configured: true, ok: false, status: response.status, models: []};
  return {configured: true, ok: true, models: (Array.isArray(data?.data) ? data.data : []).map((m) => normalize('anthropic', m)).filter(Boolean)};
}

async function listXai(apiKey) {
  if (!apiKey) return {configured: false, models: []};
  const response = await fetch('https://api.x.ai/v1/models', {
    headers: {authorization: `Bearer ${apiKey}`}, signal: AbortSignal.timeout(TIMEOUT_MS),
  });
  const data = await readJson(response);
  if (!response.ok) return {configured: true, ok: false, status: response.status, models: []};
  return {configured: true, ok: true, models: (Array.isArray(data?.data) ? data.data : []).map((m) => normalize('xai', m)).filter(Boolean)};
}

export async function listProviderModels(keys = {}) {
  const settled = await Promise.allSettled([
    listGoogle(keys.google), listOpenAi(keys.openai), listAnthropic(keys.anthropic), listXai(keys.xai),
  ]);
  const names = ['google', 'openai', 'anthropic', 'xai'];
  const providers = {};
  for (let i = 0; i < names.length; i++) {
    providers[names[i]] = settled[i].status === 'fulfilled'
      ? settled[i].value
      : {configured: Boolean(keys[names[i]]), ok: false, error: 'unavailable', models: []};
  }
  return providers;
}
