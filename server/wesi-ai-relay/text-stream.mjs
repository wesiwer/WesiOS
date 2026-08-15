import fs from 'node:fs';
import {
  prepareGeminiAttachments,
  deleteGeminiFiles,
  deleteStagedUploads,
} from './attachment-preprocessor.mjs';
import {callGoogleText, parseGoogleRoute} from './google.mjs';

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
  } catch {}
  return values;
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

async function* sseData(response) {
  if (!response.body) return;
  const decoder = new TextDecoder();
  let pending = '';
  for await (const chunk of response.body) {
    pending += decoder.decode(chunk, {stream: true});
    for (;;) {
      const split = pending.indexOf('\n\n');
      if (split < 0) break;
      const event = pending.slice(0, split);
      pending = pending.slice(split + 2);
      for (const line of event.split(/\r?\n/)) {
        if (!line.startsWith('data:')) continue;
        yield line.slice(5).trim();
      }
    }
  }
  const tail = pending.trim();
  if (tail) {
    for (const line of tail.split(/\r?\n/)) {
      if (line.startsWith('data:')) yield line.slice(5).trim();
    }
  }
}

async function callOpenAiFull({url, model, apiKey, input, headers = {}, signal}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const response = await fetch(url, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      authorization: `Bearer ${apiKey}`,
      ...headers,
    },
    body: JSON.stringify({model, messages: openAiMessages(input)}),
    signal: signal || AbortSignal.timeout(120000),
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

async function streamOpenAiCompatible({url, model, apiKey, input, headers = {}, signal, onDelta}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED', emitted: false};
  let response;
  try {
    response = await fetch(url, {
      method: 'POST',
      headers: {
        'content-type': 'application/json',
        authorization: `Bearer ${apiKey}`,
        ...headers,
      },
      body: JSON.stringify({model, messages: openAiMessages(input), stream: true}),
      signal,
    });
  } catch (error) {
    if (signal?.aborted) throw error;
    return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE', emitted: false};
  }
  if (!response.ok) {
    return {
      ok: false,
      status: response.status === 429 ? 429 : 502,
      code: response.status === 429 ? 'WAI_PROVIDER_RATE_LIMIT' : 'WAI_PROVIDER_REJECTED',
      emitted: false,
    };
  }
  let emitted = false;
  let answer = '';
  try {
    for await (const raw of sseData(response)) {
      if (!raw || raw === '[DONE]') continue;
      let data;
      try { data = JSON.parse(raw); } catch { continue; }
      const text = String(data?.choices?.[0]?.delta?.content || '');
      if (!text) continue;
      emitted = true;
      answer += text;
      onDelta(text);
    }
  } catch (error) {
    if (signal?.aborted) throw error;
    return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE', emitted};
  }
  return answer.trim()
    ? {ok: true, answer, emitted}
    : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE', emitted};
}

async function streamGoogle(model, input, apiKey, signal, onDelta) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED', emitted: false};
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
    return {ok: false, status: 400, code: String(error?.message || 'WAI_ATTACHMENT_INVALID'), emitted: false};
  }
  if (!userParts.length) userParts.push({text: 'Проанализируй прикреплённые данные.'});
  history.push({role: 'user', parts: userParts});

  let emitted = false;
  let answer = '';
  try {
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:streamGenerateContent?alt=sse`,
      {
        method: 'POST',
        headers: {'content-type': 'application/json', 'x-goog-api-key': apiKey},
        body: JSON.stringify({
          systemInstruction: {parts: [{text: String(input.system || '')}]},
          contents: history,
        }),
        signal,
      },
    );
    if (!response.ok) {
      return {
        ok: false,
        status: response.status === 429 ? 429 : response.status === 400 ? 400 : 502,
        code: response.status === 429
          ? 'WAI_PROVIDER_RATE_LIMIT'
          : response.status === 400
            ? 'WAI_ATTACHMENT_PROVIDER_REJECTED'
            : 'WAI_PROVIDER_REJECTED',
        emitted: false,
      };
    }
    for await (const raw of sseData(response)) {
      if (!raw || raw === '[DONE]') continue;
      let data;
      try { data = JSON.parse(raw); } catch { continue; }
      const parts = data?.candidates?.[0]?.content?.parts;
      const text = Array.isArray(parts)
        ? parts.map((part) => typeof part?.text === 'string' ? part.text : '').join('')
        : '';
      if (!text) continue;
      emitted = true;
      answer += text;
      onDelta(text);
    }
    return answer.trim()
      ? {ok: true, answer, emitted}
      : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE', emitted};
  } catch (error) {
    if (signal?.aborted) throw error;
    return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE', emitted};
  } finally {
    await deleteGeminiFiles(prepared.providerFiles, apiKey);
    deleteStagedUploads(prepared.stagedUploadIds);
  }
}

async function streamCandidate(candidate, input, googleKey, secrets, signal, onDelta) {
  if (candidate.provider === 'google') {
    return streamGoogle(candidate.model, input, googleKey, signal, onDelta);
  }
  if (hasAttachments(input)) {
    return {ok: false, status: 400, code: 'WAI_PROVIDER_NOT_MULTIMODAL', emitted: false};
  }
  if (candidate.provider === 'groq') {
    return streamOpenAiCompatible({
      url: 'https://api.groq.com/openai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.GROQ_API_KEY,
      input,
      signal,
      onDelta,
    });
  }
  if (candidate.provider === 'mistral') {
    return streamOpenAiCompatible({
      url: 'https://api.mistral.ai/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.MISTRAL_API_KEY,
      input,
      signal,
      onDelta,
    });
  }
  if (candidate.provider === 'openrouter') {
    return streamOpenAiCompatible({
      url: 'https://openrouter.ai/api/v1/chat/completions',
      model: candidate.model,
      apiKey: secrets.OPENROUTER_API_KEY,
      input,
      headers: {'HTTP-Referer': 'https://wesi-wf.su', 'X-Title': 'Wesi AI'},
      signal,
      onDelta,
    });
  }
  return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED', emitted: false};
}

async function firstAvailableStream(candidates, input, googleKey, secrets, signal, onDelta) {
  let last = {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED', emitted: false};
  for (const candidate of candidates) {
    const result = await streamCandidate(candidate, input, googleKey, secrets, signal, onDelta);
    if (result.ok) return {...result, provider: candidate.provider, model: candidate.model};
    if (result.emitted) return result;
    last = result;
  }
  return last;
}

async function callUltraStream(input, googleKey, secrets, signal, onDelta) {
  const toolTurn = String(input.system || '').includes('[WESI_AI_TOOL_PROTOCOL]');
  const primaryCandidate = {provider: 'google', model: 'gemini-3.5-flash'};
  const reviewCandidate = {provider: 'groq', model: 'openai/gpt-oss-120b'};

  if (hasAttachments(input) || toolTurn || !googleKey || !secrets.GROQ_API_KEY) {
    return firstAvailableStream([
      primaryCandidate,
      reviewCandidate,
      {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets, signal, onDelta);
  }

  const [primary, review] = await Promise.all([
    callGoogleText(primaryCandidate.model, input, googleKey),
    callOpenAiFull({
      url: 'https://api.groq.com/openai/v1/chat/completions',
      model: reviewCandidate.model,
      apiKey: secrets.GROQ_API_KEY,
      input,
      signal,
    }),
  ]);
  if (!primary.ok && !review.ok) {
    return firstAvailableStream([
      {provider: 'mistral', model: secrets.WESI_MISTRAL_ULTRA_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets, signal, onDelta);
  }
  if (!primary.ok) {
    return streamCandidate(reviewCandidate, input, googleKey, secrets, signal, onDelta);
  }
  if (!review.ok) {
    return streamGoogle(primaryCandidate.model, input, googleKey, signal, onDelta);
  }

  const synthesis = {
    system: 'Ты финальный синтезатор Wesi AI Максимальный. Сформируй один точный ответ пользователю. Используй сильные стороны обоих черновиков, исправляй противоречия и не упоминай внутреннюю маршрутизацию или модели.',
    history: [],
    message: `Исходный запрос:\n${String(input.message || '')}\n\nЧерновик A:\n${primary.answer}\n\nЧерновик B:\n${review.answer}`,
  };
  return streamGoogle('gemini-3.5-flash', synthesis, googleKey, signal, onDelta);
}

export async function streamTextRoute(route, input, googleKey, signal, onDelta) {
  const direct = parseGoogleRoute(route);
  if (direct) return streamGoogle(direct.model, input, googleKey, signal, onDelta);

  const tier = parseWesiRoute(route);
  if (!tier) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE', emitted: false};
  const secrets = providerSecrets();

  if (hasAttachments(input)) {
    const model = tier === 'fast' ? 'gemini-3.5-flash-lite' : 'gemini-3.5-flash';
    const result = await streamGoogle(model, input, googleKey, signal, onDelta);
    return result.ok ? {...result, provider: 'google', model} : result;
  }
  if (tier === 'fast') {
    return firstAvailableStream([
      {provider: 'google', model: 'gemini-3.5-flash-lite'},
      {provider: 'groq', model: 'llama-3.1-8b-instant'},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_FAST_MODEL || 'mistral-small-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets, signal, onDelta);
  }
  if (tier === 'pro') {
    return firstAvailableStream([
      {provider: 'groq', model: 'openai/gpt-oss-120b'},
      {provider: 'google', model: 'gemini-3.5-flash'},
      {provider: 'mistral', model: secrets.WESI_MISTRAL_PRO_MODEL || 'mistral-large-latest'},
      {provider: 'openrouter', model: 'openrouter/free'},
    ], input, googleKey, secrets, signal, onDelta);
  }
  return callUltraStream(input, googleKey, secrets, signal, onDelta);
}
