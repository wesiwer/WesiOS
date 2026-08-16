import test from 'node:test';
import assert from 'node:assert/strict';
import {
  assertCandidateAllowed,
  geminiKeySlots,
  providerCooldown,
  resetProviderFailoverState,
  runProviderFailover,
} from './provider-failover.mjs';
import {buildFastCandidates, buildFinalizerCandidates, callTextRoute} from './google.mjs';

test('Gemini key slots deduplicate credentials without exposing them as ids', () => {
  const slots = geminiKeySlots('key-a', {
    GEMINI_API_KEY_2: 'key-b',
    GEMINI_API_KEY_3: 'key-a',
    GEMINI_API_KEY_4: '',
    GEMINI_API_KEY_5: 'key-c',
  });
  assert.deepEqual(slots.map((item) => item.slot), ['primary', 'secondary-2', 'secondary-5']);
  assert.deepEqual(slots.map((item) => item.key), ['key-a', 'key-b', 'key-c']);
});

test('Fast cannot route through Pro or Maximum candidates', () => {
  assert.equal(assertCandidateAllowed('fast', {tier: 'fast'}), true);
  assert.throws(() => assertCandidateAllowed('fast', {tier: 'pro'}), /WAI_PROVIDER_TIER_VIOLATION/);
  assert.throws(() => assertCandidateAllowed('fast', {tier: 'ultra'}), /WAI_PROVIDER_TIER_VIOLATION/);
});

test('Pro cannot route through Maximum candidates', () => {
  assert.equal(assertCandidateAllowed('pro', {tier: 'pro'}), true);
  assert.throws(() => assertCandidateAllowed('pro', {tier: 'ultra'}), /WAI_PROVIDER_TIER_VIOLATION/);
});

test('actual Fast pool contains only Fast candidates and never dynamic openrouter/free', () => {
  const candidates = buildFastCandidates('g-primary', {
    GEMINI_API_KEY_2: 'g-second',
    GROQ_API_KEY: 'groq',
    MISTRAL_API_KEY: 'mistral',
    OPENROUTER_API_KEY: 'openrouter',
  });
  assert.ok(candidates.length >= 4);
  assert.ok(candidates.every((item) => item.tier === 'fast'));
  assert.equal(candidates.some((item) => item.model === 'openrouter/free'), false);
  assert.equal(candidates.filter((item) => item.provider === 'google').length, 2);
  assert.ok(candidates.filter((item) => item.provider === 'google').every((item) => item.model === 'gemini-3.5-flash-lite'));
});

test('Pro and Maximum finalizer pools stay inside their declared tier', () => {
  const secrets = {GEMINI_API_KEY_2: 'g-second'};
  const pro = buildFinalizerCandidates('pro', 'g-primary', secrets);
  const maximum = buildFinalizerCandidates('ultra', 'g-primary', secrets);
  assert.ok(pro.length >= 4);
  assert.ok(maximum.length >= 4);
  assert.ok(pro.every((item) => item.tier === 'pro'));
  assert.ok(maximum.every((item) => item.tier === 'ultra'));
  assert.ok(pro.filter((item) => item.provider === 'google').every((item) => item.model === 'gemini-3.5-flash'));
  assert.ok(maximum.filter((item) => item.provider === 'google').every((item) => item.model === 'gemini-3.6-flash'));
  assert.notEqual(
    pro.find((item) => item.provider === 'google')?.model,
    maximum.find((item) => item.provider === 'google')?.model,
    'Maximum must default to a stronger model than Pro',
  );
});

test('Fast switches Gemini credentials on 429 without changing Flash Lite model', async () => {
  resetProviderFailoverState();
  const original = globalThis.fetch;
  const calls = [];
  globalThis.fetch = async (url, options = {}) => {
    const key = options.headers?.['x-goog-api-key'];
    calls.push({url: String(url), key});
    if (key === 'primary-key') {
      return {ok: false, status: 429, async json() { return {error: {message: 'quota'}}; }};
    }
    if (key === 'secondary-key') {
      return {
        ok: true,
        status: 200,
        async json() {
          return {candidates: [{content: {parts: [{text: 'FAST_SECONDARY_OK'}]}}]};
        },
      };
    }
    throw new Error(`unexpected key ${key}`);
  };
  try {
    const result = await callTextRoute(
      'wesi/fast',
      {system: 'persona', history: [], message: 'hello'},
      'primary-key',
      {secrets: {GEMINI_API_KEY_2: 'secondary-key'}},
    );
    assert.equal(result.ok, true);
    assert.equal(result.answer, 'FAST_SECONDARY_OK');
    assert.equal(calls.length, 2);
    assert.deepEqual(calls.map((item) => item.key), ['primary-key', 'secondary-key']);
    assert.ok(calls.every((item) => item.url.includes('/gemini-3.5-flash-lite:generateContent')));
  } finally {
    globalThis.fetch = original;
  }
});

test('429 moves to the next same-tier candidate and cools the exhausted one', async () => {
  resetProviderFailoverState();
  let clock = 1_000_000;
  const candidates = [
    {id: 'google:primary:flash-lite', provider: 'google', model: 'flash-lite', tier: 'fast'},
    {id: 'google:secondary-2:flash-lite', provider: 'google', model: 'flash-lite', tier: 'fast'},
  ];
  const calls = [];
  const result = await runProviderFailover({
    tier: 'fast',
    candidates,
    now: () => clock,
    invoke: async (candidate) => {
      calls.push(candidate.id);
      if (candidate.id.includes('primary')) {
        return {ok: false, status: 429, code: 'WAI_PROVIDER_RATE_LIMIT'};
      }
      return {ok: true, answer: 'ok'};
    },
  });
  assert.equal(result.ok, true);
  assert.equal(result.failoverIndex, 1);
  assert.deepEqual(calls, [candidates[0].id, candidates[1].id]);
  assert.equal(providerCooldown(candidates[0], clock).cooling, true);

  calls.length = 0;
  const second = await runProviderFailover({
    tier: 'fast',
    candidates,
    now: () => clock,
    invoke: async (candidate) => {
      calls.push(candidate.id);
      return {ok: true, answer: 'ok'};
    },
  });
  assert.equal(second.ok, true);
  assert.deepEqual(calls, [candidates[1].id], 'cooling primary must be skipped');

  clock += 61_000;
  calls.length = 0;
  const recovered = await runProviderFailover({
    tier: 'fast',
    candidates,
    now: () => clock,
    invoke: async (candidate) => {
      calls.push(candidate.id);
      return {ok: true, answer: 'primary recovered'};
    },
  });
  assert.equal(recovered.ok, true);
  assert.deepEqual(calls, [candidates[0].id], 'primary becomes preferred again after cooldown');
});

test('invalid request does not fan out across providers', async () => {
  resetProviderFailoverState();
  const candidates = [
    {id: 'a', provider: 'google', model: 'm1', tier: 'pro'},
    {id: 'b', provider: 'mistral', model: 'm2', tier: 'pro'},
  ];
  let calls = 0;
  const result = await runProviderFailover({
    tier: 'pro',
    candidates,
    invoke: async () => {
      calls += 1;
      return {ok: false, status: 400, code: 'WAI_ATTACHMENT_PROVIDER_REJECTED'};
    },
  });
  assert.equal(result.ok, false);
  assert.equal(calls, 1);
});

test('partial streaming result never switches provider after bytes were emitted', async () => {
  resetProviderFailoverState();
  const candidates = [
    {id: 'a', provider: 'google', model: 'm1', tier: 'pro'},
    {id: 'b', provider: 'mistral', model: 'm2', tier: 'pro'},
  ];
  let calls = 0;
  const result = await runProviderFailover({
    tier: 'pro',
    candidates,
    invoke: async () => {
      calls += 1;
      return {ok: false, status: 502, code: 'WAI_PROVIDER_UNAVAILABLE', emitted: true};
    },
  });
  assert.equal(result.ok, false);
  assert.equal(calls, 1);
});

test('user cancellation aborts the pool instead of trying another provider', async () => {
  resetProviderFailoverState();
  const candidates = [
    {id: 'a', provider: 'google', model: 'm1', tier: 'fast'},
    {id: 'b', provider: 'mistral', model: 'm2', tier: 'fast'},
  ];
  let calls = 0;
  await assert.rejects(
    runProviderFailover({
      tier: 'fast',
      candidates,
      invoke: async () => {
        calls += 1;
        const error = new Error('cancelled');
        error.name = 'AbortError';
        throw error;
      },
    }),
    (error) => error?.name === 'AbortError',
  );
  assert.equal(calls, 1);
});


test('Gemini slots can group keys by Google project quota scope', () => {
  const slots = geminiKeySlots('key-a', {
    GEMINI_API_PROJECT: 'project-a',
    GEMINI_API_KEY_2: 'key-b',
    GEMINI_API_PROJECT_2: 'project-a',
    GEMINI_API_KEY_3: 'key-c',
    GEMINI_API_PROJECT_3: 'project-b',
  });
  assert.deepEqual(slots.map((item) => item.quotaScope), [
    'project:project-a',
    'project:project-a',
    'project:project-b',
  ]);
});

test('429 on one key skips another key from the same Google project but tries another project', async () => {
  resetProviderFailoverState();
  const candidates = [
    {id: 'g-a-1', provider: 'google', model: 'gemini-3.5-flash-lite', tier: 'fast', quotaScope: 'project:a'},
    {id: 'g-a-2', provider: 'google', model: 'gemini-3.5-flash-lite', tier: 'fast', quotaScope: 'project:a'},
    {id: 'g-b-1', provider: 'google', model: 'gemini-3.5-flash-lite', tier: 'fast', quotaScope: 'project:b'},
  ];
  const calls = [];
  const result = await runProviderFailover({
    tier: 'fast',
    candidates,
    invoke: async (candidate) => {
      calls.push(candidate.id);
      if (candidate.quotaScope === 'project:a') {
        return {ok: false, status: 429, code: 'WAI_PROVIDER_DAILY_QUOTA'};
      }
      return {ok: true, answer: 'project-b-ok'};
    },
  });
  assert.equal(result.ok, true);
  assert.deepEqual(calls, ['g-a-1', 'g-b-1']);
});
