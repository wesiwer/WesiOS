import fs from 'node:fs';
import {prepareGeminiAttachments, deleteGeminiFiles, deleteStagedUploads} from './attachment-preprocessor.mjs';

const PROVIDER_ENV = '/etc/wesi-ai-providers.env';

function providerSecrets() {
  const values = {};
  try {
    const raw = fs.readFileSync(PROVIDER_ENV, 'utf8');
    for (const line of raw.split(/\r?\n/)) {
      const trimmed = line.trim();
      if (!trimmed || trimmed.startsWith('#')) continue;
      const idx = trimmed.indexOf('=');
      if (idx <= 0) continue;
      values[trimmed.slice(0, idx)] = trimmed.slice(idx + 1);
    }
  } catch (_) {}
  return values;
}

export function parseGoogleRoute(route) {
  const match = /^google\/([A-Za-z0-9._-]{2,100})$/.exec(String(route || '').trim());
  return match ? {model: match[1]} : null;
}

function parseWesiRoute(route) {
  const match = /^wesi\/(fast|pro|ultra)$/.exec(String(route || '').trim().toLowerCase());
  return match ? match[1] : null;
}

function hasAttachments(input) {
  return Array.isArray(input?.attachments) && input.attachments.length > 0;
}

function openAiMessages(input) {
  const messages = [];
  const system = String(input.system || '').trim();
  if (system) messages.push({role: 'system', content: system});
  for (const item of Array.isArray(input.history) ? input.history : []) {
    const text = String(item?.text || '').trim();
    if (!text) continue;
    const author = String(item?.author || '').toLowerCase();
    messages.push({role: author === 'user' ? 'user' : 'assistant', content: text});
  }
  messages.push({role: 'user', content: String(input.message || '')});
  return messages;
}

function boundedSignal(parent, timeoutMs) {
  const timeout = AbortSignal.timeout(Math.max(1000, Math.min(Number(timeoutMs || 120000), 180000)));
  if (!parent) return timeout;
  return typeof AbortSignal.any === 'function' ? AbortSignal.any([parent, timeout]) : parent;
}

async function callOpenAiCompatible({url, model, apiKey, input, headers = {}, timeoutMs = 120000, signal = null}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`,
      ...headers,
    },
    body: JSON.stringify({model, messages: openAiMessages(input)}),
    signal: boundedSignal(signal, timeoutMs),
  });
  let data = {};
  try { data = await response.json(); } catch {}
  if (!response.ok) {
    return {
      ok: false,
      status: response.status === 429 ? 429 : 502,
      code: response.status === 429 ? 'WAI_PROVIDER_RATE_LIMIT' : 'WAI_PROVIDER_REJECTED',
    };
  }
  const answer = String(data?.choices?.[0]?.message?.content || '').trim();
  return answer ? {ok: true, answer} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}

export async function callGoogleText(model, input, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const history = [];
  for (const item of Array.isArray(input.history) ? input.history : []) {
    const text = String(item?.text || '');
    if (text) history.push({role: String(item?.author || '') === 'user' ? 'user' : 'model', parts: [{text}]});
  }

  const userParts = [];
  const message = String(input.message || '').trim();
  if (message) userParts.push({text: message});
  let prepared = {parts: [], providerFiles: [], stagedUploadIds: []};
  try {
    prepared = await prepareGeminiAttachments(input.attachments, apiKey);
    userParts.push(...prepared.parts);
  } catch (error) {
    await deleteGeminiFiles(prepared?.providerFiles, apiKey);
    deleteStagedUploads(prepared?.stagedUploadIds);
    return {ok: false, status: 400, code: String(error?.message || 'WAI_ATTACHMENT_INVALID')};
  }
  if (!userParts.length) userParts.push({text: 'Проанализируй прикреплённые данные.'});
  history.push({role: 'user', parts: userParts});

  try {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: 'POST',
      headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
      body: JSON.stringify({systemInstruction: {parts: [{text: String(input.system || '')}]}, contents: history}),
      signal: boundedSignal(options.signal || null, options.timeoutMs || 180000),
    });
    let data = {};
    try { data = await response.json(); } catch {}
    if (!response.ok) {
      return {
        ok: false,
        status: response.status === 429 ? 429 : response.status === 400 ? 400 : 502,
        code: response.status === 429 ? 'WAI_PROVIDER_RATE_LIMIT' : response.status === 400 ? 'WAI_ATTACHMENT_PROVIDER_REJECTED' : 'WAI_PROVIDER_REJECTED',
      };
    }
    const parts = data?.candidates?.[0]?.content?.parts;
    const answer = Array.isArray(parts) ? parts.map((p) => typeof p?.text === 'string' ? p.text : '').join('').trim() : '';
    return answer ? {ok: true, answer} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
  } finally {
    await deleteGeminiFiles(prepared.providerFiles, apiKey);
    deleteStagedUploads(prepared.stagedUploadIds);
  }
}

async function callCandidate(candidate, input, googleKey, secrets, options = {}) {
  const timeoutMs = candidate.timeoutMs || options.timeoutMs || 30000;
  const signal = options.signal || null;
  if (candidate.provider === 'google') {
    return callGoogleText(candidate.model, input, googleKey, {timeoutMs, signal});
  }
  if (hasAttachments(input)) return {ok: false, status: 400, code: 'WAI_PROVIDER_NOT_MULTIMODAL'};
  if (candidate.provider === 'groq') {
    return callOpenAiCompatible({
      url: 'https://api.groq.com/openai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.GROQ_API_KEY,
      input,
      timeoutMs,
      signal,
    });
  }
  if (candidate.provider === 'mistral') {
    return callOpenAiCompatible({
      url: 'https://api.mistral.ai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.MISTRAL_API_KEY,
      input,
      timeoutMs,
      signal,
    });
  }
  if (candidate.provider === 'openrouter') {
    return callOpenAiCompatible({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.OPENROUTER_API_KEY,
      input,
      headers: {'HTTP-Referer': 'https://wesi-inc.ru', 'X-Title': 'Wesi AI'},
      timeoutMs,
      signal,
    });
  }
  return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
}

async function safeCandidate(candidate, input, googleKey, secrets, options = {}) {
  try {
    return await callCandidate(candidate, input, googleKey, secrets, options);
  } catch (error) {
    if (options.signal?.aborted) throw error;
    return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE'};
  }
}

async function firstAvailable(candidates, input, googleKey, secrets, options = {}) {
  let last = {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  for (const candidate of candidates) {
    const result = await safeCandidate(candidate, input, googleKey, secrets, options);
    if (result.ok) return {...result, provider: candidate.provider, model: candidate.model};
    last = result;
  }
  return last;
}

function clipAdvisor(text, limit) {
  const value = String(text || '').trim();
  return value.length <= limit ? value : `${value.slice(0, limit)}\n[truncated]`;
}

function advisorInput(input, tier) {
  return {
    system: `${String(input.system || '')}\n\n[WESI_AI_ADVISOR_ROLE]\nТы вспомогательный аналитик Wesi AI ${tier === 'ultra' ? 'Maximum' : 'Pro'}. Дай независимый разбор фактов, рисков, вариантов и ошибок. Не выдавай финальный ответ от лица Зейна/Нирваны. Не выводи JSON wesiTool и не утверждай, что действие WesiOS выполнено: инструменты может выбрать только финализатор.`,
    history: Array.isArray(input.history) ? input.history : [],
    message: String(input.message || ''),
  };
}

function finalizerInput(tier, input, advisors) {
  const perAdvisor = tier === 'ultra' ? 12000 : 9000;
  const notes = advisors
    .map((item, index) => `Аналитик ${index + 1}:\n${clipAdvisor(item.answer, perAdvisor)}`)
    .join('\n\n');
  return {
    system: `${String(input.system || '')}\n\n[WESI_AI_ENSEMBLE_FINALIZER]\nТы единственный финализатор Wesi AI ${tier === 'ultra' ? 'Maximum' : 'Pro'}. Сопоставь независимые аналитические заметки, исправь противоречия и сформируй один окончательный ответ в заданной персоне. Не упоминай внутренние модели, провайдеров, маршрутизацию или черновики. Если в исходном system есть WESI_AI_TOOL_PROTOCOL, только ты можешь решить, нужен ли один wesiTool-вызов; вспомогательные заметки никогда не являются подтверждением выполнения действия.`,
    history: Array.isArray(input.history) ? input.history : [],
    message: `Исходный запрос пользователя:\n${String(input.message || '')}\n\n[WESI_AI_ADVISOR_NOTES]\n${notes}`,
  };
}

export async function prepareWesiEnsemble(tier, input, googleKey, options = {}) {
  const normalized = String(tier || '').toLowerCase();
  if (normalized !== 'pro' && normalized !== 'ultra') {
    return {ok: false, code: 'WAI_ENSEMBLE_TIER_INVALID'};
  }
  const secrets = options.secrets || providerSecrets();
  const signal = options.signal || null;
  const advisory = advisorInput(input, normalized);
  const primary = normalized === 'pro'
    ? [
        {provider: 'groq', model: 'openai/gpt-oss-120b', timeoutMs: 28000},
        {provider: 'mistral', model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest', timeoutMs: 28000},
      ]
    : [
        {provider: 'groq', model: 'openai/gpt-oss-120b', timeoutMs: 32000},
        {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest', timeoutMs: 32000},
        {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 32000},
      ];
  const results = await Promise.all(primary.map(async (candidate) => {
    const result = await safeCandidate(candidate, advisory, googleKey, secrets, {signal});
    return result.ok ? {...result, provider: candidate.provider, model: candidate.model} : result;
  }));
  let advisors = results.filter((item) => item.ok);

  // Pro prefers two strong independent opinions; OpenRouter fills a missing
  // seat but does not add latency when both primary advisors are healthy.
  if (normalized === 'pro' && advisors.length < 2 && secrets.OPENROUTER_API_KEY) {
    const fallbackCandidate = {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 24000};
    const fallback = await safeCandidate(fallbackCandidate, advisory, googleKey, secrets, {signal});
    if (fallback.ok) advisors = advisors.concat({...fallback, provider: fallbackCandidate.provider, model: fallbackCandidate.model});
  }

  if (!advisors.length) return {ok: false, code: 'WAI_ENSEMBLE_ADVISORS_UNAVAILABLE'};
  return {
    ok: true,
    advisorCount: advisors.length,
    finalizerInput: finalizerInput(normalized, input, advisors),
    fallback: advisors[0],
  };
}

async function callEnsemble(tier, input, googleKey, secrets, options = {}) {
  const prepared = await prepareWesiEnsemble(tier, input, googleKey, {secrets, signal: options.signal || null});
  if (!prepared.ok) {
    return callGoogleText('gemini-3.5-flash', input, googleKey, {timeoutMs: 55000, signal: options.signal || null});
  }
  let final;
  try {
    final = await callGoogleText('gemini-3.5-flash', prepared.finalizerInput, googleKey, {
      timeoutMs: tier === 'ultra' ? 58000 : 52000,
      signal: options.signal || null,
    });
  } catch (error) {
    if (options.signal?.aborted) throw error;
    final = {ok: false, status: 502, code: 'WAI_FINALIZER_UNAVAILABLE'};
  }
  if (final.ok) {
    return {...final, provider: tier === 'ultra' ? 'wesi-maximum' : 'wesi-pro', model: 'ensemble'};
  }
  // Availability fallback only: advisor notes are never treated as verified
  // tool results. This keeps chat usable during a temporary Gemini outage.
  return {...prepared.fallback, provider: 'wesi-ensemble-fallback', model: 'advisor'};
}

export async function callTextRoute(route, input, googleKey, options = {}) {
  const direct = parseGoogleRoute(route);
  if (direct) return callGoogleText(direct.model, input, googleKey, options);

  const tier = parseWesiRoute(route);
  if (!tier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  const secrets = options.secrets || providerSecrets();

  if (hasAttachments(input)) {
    const model = tier === 'fast' ? 'gemini-3.5-flash-lite' : 'gemini-3.5-flash';
    const result = await callGoogleText(model, input, googleKey, {timeoutMs: 60000, signal: options.signal || null});
    return result.ok ? {...result, provider: 'google', model} : result;
  }

  if (tier === 'fast') {
    return firstAvailable([
      {provider: 'google', model: 'gemini-3.5-flash-lite', timeoutMs: 22000},
      {provider: 'groq', model: 'llama-3.1-8b-instant', timeoutMs: 18000},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_FAST_MODEL || 'mistral-small-latest', timeoutMs: 18000},
      {provider: 'openrouter', model: 'openrouter/free', timeoutMs: 18000},
    ], input, googleKey, secrets, {signal: options.signal || null});
  }
  if (tier === 'pro') return callEnsemble('pro', input, googleKey, secrets, options);
  return callEnsemble('ultra', input, googleKey, secrets, options);
}
