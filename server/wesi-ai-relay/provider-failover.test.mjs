import test from 'node:test';
import assert from 'node:assert/strict';
import {
  assertCandidateAllowed,
  geminiKeySlots,
  providerCooldown,
  resetProviderFailoverState,
  runProviderFailover,
} from './provider-failover.mjs';
import {buildFastCandidates, buildFinalizerCandidates} from './google.mjs';

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
  assert.ok(maximum.filter((item) => item.provider === 'google').every((item) => item.model === 'gemini-3.5-flash'));
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
