import fs from 'node:fs';
import {prepareGeminiAttachments, deleteGeminiFiles, deleteStagedUploads} from './attachment-preprocessor.mjs';
import {geminiKeySlots, normalizeWesiTier, runProviderFailover} from './provider-failover.mjs';

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

export function buildGoogleCandidates(model, tier, googleKey, secrets = {}, timeoutMs = 30000) {
  const normalized = normalizeWesiTier(tier);
  if (!normalized) return [];
  return geminiKeySlots(googleKey, secrets).map(({slot, key}) => ({
    id: `google:${slot}:${model}`,
    provider: 'google',
    model,
    apiKey: key,
    credentialSlot: slot,
    tier: normalized,
    timeoutMs,
  }));
}

export function buildFastCandidates(googleKey, secrets = {}) {
  const candidates = [
    ...buildGoogleCandidates(
      secrets.WESI_GEMINI_FAST_MODEL || 'gemini-3.5-flash-lite',
      'fast',
      googleKey,
      secrets,
      22000,
    ),
    {
      id: 'groq:fast',
      provider: 'groq',
      model: secrets.WESI_GROQ_FAST_MODEL || 'llama-3.1-8b-instant',
      tier: 'fast',
      timeoutMs: 18000,
    },
    {
      id: 'mistral:fast',
      provider: 'mistral',
      model: secrets.WESI_MISTRAL_FAST_MODEL || 'mistral-small-latest',
      tier: 'fast',
      timeoutMs: 18000,
    },
  ];
  const openRouterModel = String(secrets.WESI_OPENROUTER_FAST_MODEL || '').trim();
  if (openRouterModel) {
    candidates.push({
      id: 'openrouter:fast',
      provider: 'openrouter',
      model: openRouterModel,
      tier: 'fast',
      timeoutMs: 18000,
    });
  }
  return candidates;
}

export function buildFinalizerCandidates(tier, googleKey, secrets = {}) {
  const normalized = normalizeWesiTier(tier);
  if (normalized !== 'pro' && normalized !== 'ultra') return [];
  const googleModel = normalized === 'ultra'
    ? secrets.WESI_GEMINI_ULTRA_MODEL || secrets.WESI_GEMINI_PRO_MODEL || 'gemini-3.5-flash'
    : secrets.WESI_GEMINI_PRO_MODEL || 'gemini-3.5-flash';
  const mistralModel = normalized === 'ultra'
    ? secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest'
    : secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest';
  const groqModel = normalized === 'ultra'
    ? secrets.WESI_GROQ_ULTRA_MODEL || 'openai/gpt-oss-120b'
    : secrets.WESI_GROQ_PRO_MODEL || 'openai/gpt-oss-120b';
  const candidates = [
    ...buildGoogleCandidates(
      googleModel,
      normalized,
      googleKey,
      secrets,
      normalized === 'ultra' ? 58000 : 52000,
    ),
    {
      id: `mistral:${normalized}:final`,
      provider: 'mistral',
      model: mistralModel,
      tier: normalized,
      timeoutMs: 52000,
    },
    {
      id: `groq:${normalized}:final`,
      provider: 'groq',
      model: groqModel,
      tier: normalized,
      timeoutMs: 52000,
    },
  ];
  const openRouterModel = String(
    normalized === 'ultra'
      ? secrets.WESI_OPENROUTER_ULTRA_MODEL || ''
      : secrets.WESI_OPENROUTER_PRO_MODEL || '',
  ).trim();
  if (openRouterModel) {
    candidates.push({
      id: `openrouter:${normalized}:final`,
      provider: 'openrouter',
      model: openRouterModel,
      tier: normalized,
      timeoutMs: 52000,
    });
  }
  return candidates;
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
    if (response.status === 429) return {ok: false, status: 429, code: 'WAI_PROVIDER_RATE_LIMIT'};
    if (response.status === 401 || response.status === 403) {
      return {ok: false, status: 503, code: 'WAI_PROVIDER_AUTH_FAILED'};
    }
    return {ok: false, status: 502, code: 'WAI_PROVIDER_REJECTED'};
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
      if (response.status === 429) return {ok: false, status: 429, code: 'WAI_PROVIDER_RATE_LIMIT'};
      if (response.status === 401 || response.status === 403) {
        return {ok: false, status: 503, code: 'WAI_PROVIDER_AUTH_FAILED'};
      }
      return {
        ok: false,
        status: response.status === 400 ? 400 : 502,
        code: response.status === 400 ? 'WAI_ATTACHMENT_PROVIDER_REJECTED' : 'WAI_PROVIDER_REJECTED',
      };
    }
    const parts = data?.candidates?.[0]?.content?.parts;
    const answer = Array.isArray(parts)
      ? parts.map((part) => typeof part?.text === 'string' ? part.text : '').join('').trim()
      : '';
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
    return callGoogleText(candidate.model, input, candidate.apiKey || googleKey, {timeoutMs, signal});
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
  const tier = normalizeWesiTier(candidates?.[0]?.tier);
  if (!tier) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  return runProviderFailover({
    tier,
    candidates,
    invoke: (candidate) => safeCandidate(candidate, input, googleKey, secrets, options),
  });
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

function proAdvisorCandidates(secrets) {
  const candidates = [
    {
      id: 'groq:pro:advisor',
      provider: 'groq',
      model: secrets.WESI_GROQ_PRO_MODEL || 'openai/gpt-oss-120b',
      tier: 'pro',
      timeoutMs: 28000,
    },
    {
      id: 'mistral:pro:advisor',
      provider: 'mistral',
      model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest',
      tier: 'pro',
      timeoutMs: 28000,
    },
  ];
  const openRouterModel = String(secrets.WESI_OPENROUTER_PRO_MODEL || '').trim();
  if (secrets.OPENROUTER_API_KEY && openRouterModel) {
    candidates.push({
      id: 'openrouter:pro:advisor',
      provider: 'openrouter',
      model: openRouterModel,
      tier: 'pro',
      timeoutMs: 24000,
    });
  }
  return candidates;
}

function maximumAdvisorCandidates(secrets) {
  const candidates = [
    {
      id: 'groq:ultra:advisor',
      provider: 'groq',
      model: secrets.WESI_GROQ_ULTRA_MODEL || 'openai/gpt-oss-120b',
      tier: 'ultra',
      timeoutMs: 32000,
    },
    {
      id: 'mistral:ultra:advisor',
      provider: 'mistral',
      model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest',
      tier: 'ultra',
      timeoutMs: 32000,
    },
  ];
  if (secrets.OPENROUTER_API_KEY) {
    candidates.push({
      id: 'openrouter:ultra:advisor',
      provider: 'openrouter',
      model: secrets.WESI_OPENROUTER_ULTRA_MODEL || 'openrouter/free',
      tier: 'ultra',
      timeoutMs: 32000,
    });
  }
  return candidates;
}

export async function prepareWesiEnsemble(tier, input, googleKey, options = {}) {
  const normalized = String(tier || '').toLowerCase();
  if (normalized !== 'pro' && normalized !== 'ultra') {
    return {ok: false, code: 'WAI_ENSEMBLE_TIER_INVALID'};
  }
  const secrets = options.secrets || providerSecrets();
  const signal = options.signal || null;
  const advisory = advisorInput(input, normalized);
  let advisors = [];

  if (normalized === 'pro') {
    const advisor = await firstAvailable(
      proAdvisorCandidates(secrets),
      advisory,
      googleKey,
      secrets,
      {signal},
    );
    if (advisor.ok) advisors = [advisor];
  } else {
    const results = await Promise.all(
      maximumAdvisorCandidates(secrets).map((candidate) =>
        firstAvailable([candidate], advisory, googleKey, secrets, {signal})
      ),
    );
    advisors = results.filter((item) => item.ok);
  }

  if (!advisors.length) return {ok: false, code: 'WAI_ENSEMBLE_ADVISORS_UNAVAILABLE'};
  return {
    ok: true,
    advisorCount: advisors.length,
    finalizerInput: finalizerInput(normalized, input, advisors),
  };
}

async function callEnsemble(tier, input, googleKey, secrets, options = {}) {
  const prepared = await prepareWesiEnsemble(tier, input, googleKey, {
    secrets,
    signal: options.signal || null,
  });
  const candidates = buildFinalizerCandidates(tier, googleKey, secrets);
  const finalInput = prepared.ok ? prepared.finalizerInput : input;
  const final = await firstAvailable(
    candidates,
    finalInput,
    googleKey,
    secrets,
    {signal: options.signal || null},
  );
  if (final.ok) {
    return {
      ...final,
      provider: tier === 'ultra' ? 'wesi-maximum' : 'wesi-pro',
      model: 'ensemble',
    };
  }
  return final;
}

export async function callTextRoute(route, input, googleKey, options = {}) {
  const direct = parseGoogleRoute(route);
  if (direct) return callGoogleText(direct.model, input, googleKey, options);

  const tier = parseWesiRoute(route);
  if (!tier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  const secrets = options.secrets || providerSecrets();

  if (hasAttachments(input)) {
    const model = tier === 'fast'
      ? secrets.WESI_GEMINI_FAST_MODEL || 'gemini-3.5-flash-lite'
      : tier === 'pro'
        ? secrets.WESI_GEMINI_PRO_MODEL || 'gemini-3.5-flash'
        : secrets.WESI_GEMINI_ULTRA_MODEL || secrets.WESI_GEMINI_PRO_MODEL || 'gemini-3.5-flash';
    const result = await firstAvailable(
      buildGoogleCandidates(model, tier, googleKey, secrets, 60000),
      input,
      googleKey,
      secrets,
      {signal: options.signal || null},
    );
    return result.ok ? {...result, provider: 'google', model} : result;
  }

  if (tier === 'fast') {
    return firstAvailable(
      buildFastCandidates(googleKey, secrets),
      input,
      googleKey,
      secrets,
      {signal: options.signal || null},
    );
  }
  if (tier === 'pro') return callEnsemble('pro', input, googleKey, secrets, options);
  return callEnsemble('ultra', input, googleKey, secrets, options);
}
