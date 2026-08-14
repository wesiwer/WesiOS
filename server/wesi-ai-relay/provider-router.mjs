import {prepareAdaptiveContext} from './adaptive-context.mjs';

const quotaSnapshots = new Map();

function routeOf(raw) {
  const match = /^(google|openai|anthropic|xai)\/([A-Za-z0-9._:-]{2,120})$/.exec(String(raw || '').trim());
  return match ? {provider: match[1], model: match[2], route: `${match[1]}/${match[2]}`} : null;
}

function numberHeader(headers, name) {
  const raw = headers?.get?.(name);
  if (raw == null || raw === '') return null;
  const value = Number(raw);
  return Number.isFinite(value) && value >= 0 ? value : null;
}

function durationMs(raw) {
  const value = String(raw || '').trim().toLowerCase();
  if (!value) return null;
  if (/^\d+(\.\d+)?$/.test(value)) return Number(value) * 1000;
  let total = 0;
  let matched = false;
  for (const match of value.matchAll(/(\d+(?:\.\d+)?)(ms|s|m|h)/g)) {
    matched = true;
    const n = Number(match[1]);
    total += match[2] === 'ms' ? n : match[2] === 's' ? n * 1000 : match[2] === 'm' ? n * 60000 : n * 3600000;
  }
  return matched ? total : null;
}

function resetAtFrom(headers, names) {
  for (const name of names) {
    const raw = headers?.get?.(name);
    if (!raw) continue;
    const absolute = Date.parse(raw);
    if (Number.isFinite(absolute)) return new Date(absolute).toISOString();
    const delta = durationMs(raw);
    if (delta != null) return new Date(Date.now() + delta).toISOString();
  }
  return null;
}

function dimension(limit, remaining, resetAt) {
  if (limit == null || remaining == null || limit <= 0) return null;
  return {limit, remaining: Math.max(0, remaining), remainingPercent: Math.max(0, Math.min(100, (remaining / limit) * 100)), resetAt: resetAt || null};
}

function captureQuota(route, response, provider) {
  if (!route || !response?.headers) return;
  const h = response.headers;
  const dimensions = [];
  if (provider === 'anthropic') {
    const reqReset = resetAtFrom(h, ['anthropic-ratelimit-requests-reset', 'retry-after']);
    const tokReset = resetAtFrom(h, ['anthropic-ratelimit-tokens-reset', 'retry-after']);
    dimensions.push(dimension(numberHeader(h, 'anthropic-ratelimit-requests-limit'), numberHeader(h, 'anthropic-ratelimit-requests-remaining'), reqReset));
    dimensions.push(dimension(numberHeader(h, 'anthropic-ratelimit-tokens-limit'), numberHeader(h, 'anthropic-ratelimit-tokens-remaining'), tokReset));
  } else {
    const reqReset = resetAtFrom(h, ['x-ratelimit-reset-requests', 'retry-after']);
    const tokReset = resetAtFrom(h, ['x-ratelimit-reset-tokens', 'retry-after']);
    dimensions.push(dimension(numberHeader(h, 'x-ratelimit-limit-requests'), numberHeader(h, 'x-ratelimit-remaining-requests'), reqReset));
    dimensions.push(dimension(numberHeader(h, 'x-ratelimit-limit-tokens'), numberHeader(h, 'x-ratelimit-remaining-tokens'), tokReset));
  }
  const known = dimensions.filter(Boolean);
  if (!known.length) return;
  known.sort((a, b) => a.remainingPercent - b.remainingPercent);
  quotaSnapshots.set(route, {remainingPercent: known[0].remainingPercent, resetAt: known[0].resetAt, observedAt: new Date().toISOString(), dimensions: known});
}

async function jsonResponse(response) {
  try { return await response.json(); } catch { return {}; }
}

function providerError(response) {
  if (response.status === 429) return {ok: false, status: 429, code: 'WAI_PROVIDER_RATE_LIMIT'};
  if (response.status === 401 || response.status === 403) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  return {ok: false, status: response.status >= 400 && response.status < 500 ? response.status : 502, code: 'WAI_PROVIDER_REJECTED'};
}

async function callOpenAi(parsed, input, apiKey) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prepared = prepareAdaptiveContext(parsed, input);
  const response = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {'content-type': 'application/json', authorization: `Bearer ${apiKey}`},
    body: JSON.stringify({model: parsed.model, messages: [{role: 'system', content: String(input?.system || '')}, ...prepared.messages]}),
    signal: AbortSignal.timeout(120000),
  });
  captureQuota(parsed.route, response, 'openai');
  const data = await jsonResponse(response);
  if (!response.ok) return providerError(response);
  const answer = String(data?.choices?.[0]?.message?.content || '').trim();
  return answer ? {ok: true, answer, context: prepared.meta} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}

async function callXai(parsed, input, apiKey) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prepared = prepareAdaptiveContext(parsed, input);
  const response = await fetch('https://api.x.ai/v1/chat/completions', {
    method: 'POST',
    headers: {'content-type': 'application/json', authorization: `Bearer ${apiKey}`},
    body: JSON.stringify({model: parsed.model, messages: [{role: 'system', content: String(input?.system || '')}, ...prepared.messages]}),
    signal: AbortSignal.timeout(120000),
  });
  captureQuota(parsed.route, response, 'xai');
  const data = await jsonResponse(response);
  if (!response.ok) return providerError(response);
  const answer = String(data?.choices?.[0]?.message?.content || '').trim();
  return answer ? {ok: true, answer, context: prepared.meta} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}

async function callAnthropic(parsed, input, apiKey) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const prepared = prepareAdaptiveContext(parsed, input);
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {'content-type': 'application/json', 'x-api-key': apiKey, 'anthropic-version': '2023-06-01'},
    body: JSON.stringify({model: parsed.model, max_tokens: Math.min(16384, prepared.meta.outputReserveTokens), system: String(input?.system || ''), messages: prepared.messages}),
    signal: AbortSignal.timeout(120000),
  });
  captureQuota(parsed.route, response, 'anthropic');
  const data = await jsonResponse(response);
  if (!response.ok) return providerError(response);
  const answer = Array.isArray(data?.content) ? data.content.map((part) => part?.type === 'text' ? String(part.text || '') : '').join('').trim() : '';
  return answer ? {ok: true, answer, context: prepared.meta} : {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
}

export function describeRoute(raw, keys = {}) {
  const parsed = routeOf(raw);
  if (!parsed) return null;
  const configured = parsed.provider === 'google' ? Boolean(keys.google) : parsed.provider === 'openai' ? Boolean(keys.openai) : parsed.provider === 'anthropic' ? Boolean(keys.anthropic) : Boolean(keys.xai);
  const quota = quotaSnapshots.get(parsed.route) || null;
  return {route: parsed.route, provider: parsed.provider, model: parsed.model, configured, remainingPercent: quota?.remainingPercent ?? null, resetAt: quota?.resetAt ?? null, observedAt: quota?.observedAt ?? null};
}

export function quotaForRoutes(routes, keys = {}) {
  const result = {};
  for (const [key, route] of Object.entries(routes || {})) result[key] = describeRoute(route, keys);
  return result;
}

export async function callProviderText(rawRoute, input, keys = {}, callGoogleText) {
  const parsed = routeOf(rawRoute);
  if (!parsed) return {ok: false, status: 400, code: 'WAI_ROUTE_UNAVAILABLE'};
  if (parsed.provider === 'google') {
    const prepared = prepareAdaptiveContext(parsed, input);
    const googleInput = {...input, history: prepared.messages.slice(0, -1).map((item) => ({author: item.role === 'user' ? 'user' : 'assistant', text: item.content})), message: String(input?.message || '')};
    const result = await callGoogleText(parsed.model, googleInput, keys.google);
    return result?.ok ? {...result, context: prepared.meta} : result;
  }
  if (parsed.provider === 'openai') return callOpenAi(parsed, input, keys.openai);
  if (parsed.provider === 'anthropic') return callAnthropic(parsed, input, keys.anthropic);
  return callXai(parsed, input, keys.xai);
}
