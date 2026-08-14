const DEFAULT_WINDOWS = Object.freeze({
  google: 1_048_576,
  openai: 400_000,
  anthropic: 200_000,
  xai: 256_000,
});

const MIN_OUTPUT_RESERVE = 8_192;
const MAX_OUTPUT_RESERVE = 32_768;
const MIN_RECENT_MESSAGES = 32;
const MAX_CONTEXT_MESSAGES = 1_200;

function finitePositive(value) {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? Math.floor(n) : null;
}

function envWindow(provider, model) {
  const normalized = String(model || '').toUpperCase().replace(/[^A-Z0-9]+/g, '_');
  return finitePositive(process.env[`WESI_CONTEXT_WINDOW_${provider.toUpperCase()}_${normalized}`])
    || finitePositive(process.env[`WESI_CONTEXT_WINDOW_${provider.toUpperCase()}`]);
}

export function modelContextWindow(provider, model) {
  const override = envWindow(provider, model);
  if (override) return override;
  return DEFAULT_WINDOWS[provider] || 128_000;
}

// Conservative multilingual estimate. It deliberately overestimates Russian,
// code and JSON so a provider never receives a context close to its hard cap.
export function estimateTokens(text) {
  const value = String(text || '');
  if (!value) return 0;
  let ascii = 0;
  let nonAscii = 0;
  let whitespace = 0;
  for (const ch of value) {
    if (/\s/.test(ch)) whitespace++;
    else if (ch.charCodeAt(0) <= 0x7f) ascii++;
    else nonAscii++;
  }
  return Math.ceil(ascii / 3.6 + nonAscii / 1.9 + whitespace / 5 + 4);
}

function messageTokens(item) {
  return estimateTokens(item?.content ?? item?.text ?? '') + 6;
}

function normalizeHistory(input) {
  const result = [];
  for (const item of Array.isArray(input?.history) ? input.history : []) {
    const text = String(item?.text || '').trim();
    if (!text) continue;
    result.push({
      role: String(item?.author || '') === 'user' ? 'user' : 'assistant',
      content: text,
    });
    if (result.length >= MAX_CONTEXT_MESSAGES) break;
  }
  return result;
}

function keywords(text) {
  const words = String(text || '')
    .toLowerCase()
    .match(/[a-zа-яё0-9_]{4,}/gi) || [];
  const ignored = new Set([
    'который', 'которая', 'которые', 'этого', 'этот', 'тогда', 'также', 'чтобы',
    'просто', 'можно', 'нужно', 'будет', 'have', 'that', 'this', 'with', 'from',
    'your', 'about', 'what', 'when', 'then', 'into', 'should', 'would',
  ]);
  return new Set(words.filter((word) => !ignored.has(word)).slice(0, 80));
}

function relevance(item, queryWords, index, total) {
  if (!queryWords.size) return 0;
  const words = keywords(item.content);
  let overlap = 0;
  for (const word of words) if (queryWords.has(word)) overlap++;
  const recency = total <= 1 ? 0 : index / (total - 1);
  return overlap * 10 + recency;
}

export function prepareAdaptiveContext(parsed, input) {
  const windowTokens = modelContextWindow(parsed.provider, parsed.model);
  const system = String(input?.system || '');
  const message = String(input?.message || '');
  const history = normalizeHistory(input);
  const systemTokens = estimateTokens(system) + 12;
  const messageTokenCount = estimateTokens(message) + 8;
  const outputReserve = Math.min(
    MAX_OUTPUT_RESERVE,
    Math.max(MIN_OUTPUT_RESERVE, Math.floor(windowTokens * 0.08)),
  );
  // Keep a safety margin for provider framing, tool turns and tokenizer error.
  const usable = Math.max(
    8_192,
    Math.floor(windowTokens * 0.86) - systemTokens - messageTokenCount - outputReserve,
  );

  const selected = new Set();
  let used = 0;

  // Preserve the latest conversation verbatim first.
  for (let i = history.length - 1; i >= 0; i--) {
    const cost = messageTokens(history[i]);
    if (selected.size >= MIN_RECENT_MESSAGES && used + cost > usable * 0.62) break;
    if (used + cost > usable) break;
    selected.add(i);
    used += cost;
  }

  // Spend the rest on older messages relevant to the current request. This
  // prevents a huge window from being filled only by chronological noise.
  const queryWords = keywords(`${message}\n${history.slice(-8).map((x) => x.content).join('\n')}`);
  const candidates = [];
  for (let i = 0; i < history.length; i++) {
    if (selected.has(i)) continue;
    candidates.push({index: i, score: relevance(history[i], queryWords, i, history.length)});
  }
  candidates.sort((a, b) => b.score - a.score || b.index - a.index);
  for (const candidate of candidates) {
    const cost = messageTokens(history[candidate.index]);
    if (used + cost > usable) continue;
    selected.add(candidate.index);
    used += cost;
  }

  const messages = [...selected]
    .sort((a, b) => a - b)
    .map((index) => history[index]);
  messages.push({role: 'user', content: message});

  return {
    messages,
    meta: {
      provider: parsed.provider,
      model: parsed.model,
      windowTokens,
      estimatedInputTokens: systemTokens + used + messageTokenCount,
      outputReserveTokens: outputReserve,
      historyAvailable: history.length,
      historySelected: selected.size,
      historyOmitted: Math.max(0, history.length - selected.size),
    },
  };
}
