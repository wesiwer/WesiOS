import test from 'node:test';
import assert from 'node:assert/strict';
import {callTextRoute} from './google.mjs';
import {resetProviderFailoverState} from './provider-failover.mjs';

function responseJson(data, status = 200) {
  return {ok: status >= 200 && status < 300, status, async json() { return data; }};
}

function googleAnswer(text) {
  return responseJson({candidates: [{content: {parts: [{text}]}}]});
}

function openAiAnswer(text) {
  return responseJson({choices: [{message: {content: text}}]});
}

test('Fast remains latency-first and does not fan out when Gemini succeeds', async () => {
  resetProviderFailoverState();
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return googleAnswer('FAST_OK');
  };
  try {
    const result = await callTextRoute('wesi/fast', {system: 'persona', history: [], message: 'hi'}, 'g-key', {
      secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'},
    });
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'FAST_OK');
    assert.equal(calls.length, 1);
    assert.match(calls[0], /generativelanguage\.googleapis\.com/);
  } finally {
    globalThis.fetch = original;
  }
});

test('Pro uses one strong advisor seat then a separate finalizer', async () => {
  resetProviderFailoverState();
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    const body = JSON.parse(String(options.body || '{}'));
    calls.push({target, body});
    if (target.includes('api.groq.com')) {
      assert.match(body.messages[0].content, /WESI_AI_ADVISOR_ROLE/);
      return openAiAnswer('groq pro analysis');
    }
    if (target.includes('api.mistral.ai')) {
      throw new Error('Mistral must remain unused when primary Pro advisor succeeds');
    }
    if (target.includes('generativelanguage.googleapis.com')) {
      const system = body.systemInstruction.parts[0].text;
      assert.match(system, /WESI_AI_TOOL_PROTOCOL/);
      assert.match(system, /WESI_AI_ENSEMBLE_FINALIZER/);
      const finalMessage = body.contents.at(-1).parts[0].text;
      assert.match(finalMessage, /groq pro analysis/);
      assert.doesNotMatch(finalMessage, /mistral analysis/);
      return googleAnswer('PRO_FINAL');
    }
    throw new Error(`unexpected provider ${target}`);
  };
  try {
    const result = await callTextRoute('wesi/pro', {
      system: '[WESI_AI_TOOL_PROTOCOL]\nOnly finalizer may select a tool.',
      history: [],
      message: 'analyze this',
    }, 'g-key', {secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'}});
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'PRO_FINAL');
    assert.equal(result.provider, 'wesi-pro');
    assert.equal(calls.filter((c) => c.target.includes('generativelanguage')).length, 1);
    assert.equal(calls.length, 2);
  } finally {
    globalThis.fetch = original;
  }
});

test('Pro advisor seat fails over within Pro before finalization', async () => {
  resetProviderFailoverState();
  const original = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    const body = JSON.parse(String(options.body || '{}'));
    if (target.includes('api.groq.com')) {
      seen.push('groq-rate-limit');
      return responseJson({error: 'rate'}, 429);
    }
    if (target.includes('api.mistral.ai')) {
      seen.push('mistral-advisor');
      assert.match(body.messages[0].content, /WESI_AI_ADVISOR_ROLE/);
      return openAiAnswer('mistral pro analysis');
    }
    if (target.includes('generativelanguage.googleapis.com')) {
      seen.push('gemini-final');
      const finalMessage = body.contents.at(-1).parts[0].text;
      assert.match(finalMessage, /mistral pro analysis/);
      return googleAnswer('PRO_FALLBACK_FINAL');
    }
    throw new Error(`unexpected provider ${target}`);
  };
  try {
    const result = await callTextRoute(
      'wesi/pro',
      {system: 'persona', history: [], message: 'analyze'},
      'g-key',
      {secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm'}},
    );
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'PRO_FALLBACK_FINAL');
    assert.deepEqual(seen, ['groq-rate-limit', 'mistral-advisor', 'gemini-final']);
  } finally {
    globalThis.fetch = original;
  }
});

test('Maximum consults all configured advisors before final synthesis', async () => {
  resetProviderFailoverState();
  const original = globalThis.fetch;
  const seen = [];
  globalThis.fetch = async (url, options = {}) => {
    const target = String(url);
    const body = JSON.parse(String(options.body || '{}'));
    if (target.includes('api.groq.com')) { seen.push('groq'); return openAiAnswer('A'); }
    if (target.includes('api.mistral.ai')) { seen.push('mistral'); return openAiAnswer('B'); }
    if (target.includes('openrouter.ai')) { seen.push('openrouter'); return openAiAnswer('C'); }
    if (target.includes('generativelanguage.googleapis.com')) {
      seen.push('gemini-final');
      const finalMessage = body.contents.at(-1).parts[0].text;
      assert.match(finalMessage, /Аналитик 1/);
      assert.match(finalMessage, /Аналитик 2/);
      assert.match(finalMessage, /Аналитик 3/);
      return googleAnswer('MAX_FINAL');
    }
    throw new Error(`unexpected provider ${target}`);
  };
  try {
    const result = await callTextRoute('wesi/ultra', {system: 'persona', history: [], message: 'hard task'}, 'g-key', {
      secrets: {GROQ_API_KEY: 'g', MISTRAL_API_KEY: 'm', OPENROUTER_API_KEY: 'o'},
    });
    assert.equal(result.answer, 'MAX_FINAL');
    assert.equal(result.provider, 'wesi-maximum');
    assert.deepEqual(new Set(seen.slice(0, 3)), new Set(['groq', 'mistral', 'openrouter']));
    assert.equal(seen.at(-1), 'gemini-final');
  } finally {
    globalThis.fetch = original;
  }
});
