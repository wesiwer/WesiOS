import fs from 'node:fs';
import {prepareGeminiAttachments, deleteGeminiFiles} from './attachment-preprocessor.mjs';

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

async function callOpenAiCompatible({url, model, apiKey, input, headers = {}}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`,
      ...headers,
    },
    body: JSON.stringify({model, messages: openAiMessages(input)}),
    signal: AbortSignal.timeout(120000),
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

export async function callGoogleText(model, input, apiKey) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const history = [];
  for (const item of Array.isArray(input.history) ? input.history : []) {
    const text = String(item?.text || '');
    if (text) history.push({role: String(item?.author || '') === 'user' ? 'user' : 'model', parts: [{text}]});
  }

  const userParts = [];
  const message = String(input.message || '').trim();
  if (message) userParts.push({text: message});
  let prepared = {parts: [], providerFiles: []};
  try {
    prepared = await prepareGeminiAttachments(input.attachments, apiKey);
    userParts.push(...prepared.parts);
  } catch (error) {
    await deleteGeminiFiles(prepared?.providerFiles, apiKey);
    return {ok: false, status: 400, code: String(error?.message || 'WAI_ATTACHMENT_INVALID')};
  }
  if (!userParts.length) userParts.push({text: 'Проанализируй прикреплённые данные.'});
  history.push({role: 'user', parts: userParts});

  try {
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
      method: 'POST',
      headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
      body: JSON.stringify({systemInstruction: {parts: [{text: String(input.system || '')}]}, contents: history}),
      signal: AbortSignal.timeout(180000),
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
  }
}

async function callCandidate(candidate, input, googleKey, secrets) {
  if (candidate.provider === 'google') return callGoogleText(candidate.model, input, googleKey);
  if (hasAttachments(input)) return {ok: false, status: 400, code: 'WAI_PROVIDER_NOT_MULTIMODAL'};
  if (candidate.provider === 'groq') {
    return callOpenAiCompatible({
      url: 'https://api.groq.com/openai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.GROQ_API_KEY,
      input,
    });
  }
  if (candidate.provider === 'mistral') {
    return callOpenAiCompatible({
      url: 'https://api.mistral.ai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.MISTRAL_API_KEY,
      input,
    });
  }
  if (candidate.provider === 'openrouter') {
    return callOpenAiCompatible({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.OPENROUTER_API_KEY,
      input,
      headers: {'HTTP-Referer': 'https://wesi-wf.su', 'X-Title': 'Wesi AI'},
    });
  }
  return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
}

async function firstAvailable(candidates, input, googleKey, secrets) {
  let last = {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  for (const candidate of candidates) {
    const result = await callCandidate(candidate, input, googleKey, secrets);
    if (result.ok) return {...result, provider: candidate.provider, model: candidate.model};
    last = result;
  }
  return last;
}

async function callUltra(input, googleKey, secrets) {
  const toolTurn = String(input.system || '').includes('[WESI_AI_TOOL_PROTOCOL]');
  const primaryCandidate = {provider: 'google', model: 'gemini-3.5-flash'};
  const reviewCandidate = {provider: 'groq', model: 'openai/gpt-oss-120b'};

  // Attachments must remain intact. The current free review providers are
  // text-only in our adapter, so multimodal Ultra uses the strongest Gemini
  // route directly instead of silently dropping the file content.
  if (hasAttachments(input)) {
    const result = await callCandidate(primaryCandidate, input, googleKey, secrets);
    return result.ok ? {...result, provider: primaryCandidate.provider, model: primaryCandidate.model} : result;
  }

  if (toolTurn || !googleKey || !secrets.GROQ_API_KEY) {
    return firstAvailable([
      primaryCandidate,
      reviewCandidate,
      {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets);
  }

  const [primary, review] = await Promise.all([
    callCandidate(primaryCandidate, input, googleKey, secrets),
    callCandidate(reviewCandidate, input, googleKey, secrets),
  ]);
  if (!primary.ok && !review.ok) {
    return firstAvailable([
      {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets);
  }
  if (!primary.ok) return {...review, provider: reviewCandidate.provider, model: reviewCandidate.model};
  if (!review.ok) return {...primary, provider: primaryCandidate.provider, model: primaryCandidate.model};

  const synthesis = {
    system: 'Ты финальный синтезатор Wesi AI Ultra. Сформируй один точный ответ пользователю. Используй сильные стороны обоих черновиков, исправляй противоречия и не упоминай внутреннюю маршрутизацию или модели.',
    history: [],
    message: `Исходный запрос:\n${String(input.message || '')}\n\nЧерновик A:\n${primary.answer}\n\nЧерновик B:\n${review.answer}`,
  };
  const final = await callGoogleText('gemini-3.5-flash', synthesis, googleKey);
  return final.ok ? {...final, provider: 'wesi-ultra', model: 'ensemble'} : {...primary, provider: primaryCandidate.provider, model: primaryCandidate.model};
}

export async function callTextRoute(route, input, googleKey) {
  const direct = parseGoogleRoute(route);
  if (direct) return callGoogleText(direct.model, input, googleKey);

  const tier = parseWesiRoute(route);
  if (!tier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  const secrets = providerSecrets();

  if (hasAttachments(input)) {
    const model = tier === 'fast' ? 'gemini-3.5-flash-lite' : 'gemini-3.5-flash';
    const result = await callGoogleText(model, input, googleKey);
    return result.ok ? {...result, provider: 'google', model} : result;
  }

  if (tier === 'fast') {
    return firstAvailable([
      {provider: 'google', model: 'gemini-3.5-flash-lite'},
      {provider: 'groq', model: 'llama-3.1-8b-instant'},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_FAST_MODEL || 'mistral-small-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets);
  }
  if (tier === 'pro') {
    return firstAvailable([
      {provider: 'groq', model: 'openai/gpt-oss-120b'},
      {provider: 'google', model: 'gemini-3.5-flash'},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets);
  }
  return callUltra(input, googleKey, secrets);
}
