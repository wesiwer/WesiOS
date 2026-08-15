import assert from 'node:assert/strict';
import test from 'node:test';
import {streamTextRoute} from './text-stream.mjs';

const originalFetch = global.fetch;

test.afterEach(() => {
  global.fetch = originalFetch;
});

test('Gemini SSE chunks are emitted incrementally and reassembled', async () => {
  global.fetch = async (url, options) => {
    assert.match(String(url), /:streamGenerateContent\?alt=sse$/);
    assert.equal(options.method, 'POST');
    return new Response(
      'data: {"candidates":[{"content":{"parts":[{"text":"При"}]}}]}\n\n' +
      'data: {"candidates":[{"content":{"parts":[{"text":"вет"}]}}]}\n\n',
      {status: 200, headers: {'content-type': 'text/event-stream'}},
    );
  };
  const deltas = [];
  const result = await streamTextRoute(
    'google/gemini-test',
    {system: 'system', history: [], message: 'hello', attachments: []},
    'test-key',
    new AbortController().signal,
    (text) => deltas.push(text),
  );
  assert.equal(result.ok, true);
  assert.equal(result.answer, 'Привет');
  assert.deepEqual(deltas, ['При', 'вет']);
});

test('provider rejection happens before any delta and is eligible for fallback', async () => {
  global.fetch = async () => new Response('{"error":"no"}', {status: 429});
  const deltas = [];
  const result = await streamTextRoute(
    'google/gemini-test',
    {system: '', history: [], message: 'hello', attachments: []},
    'test-key',
    new AbortController().signal,
    (text) => deltas.push(text),
  );
  assert.equal(result.ok, false);
  assert.equal(result.code, 'WAI_PROVIDER_RATE_LIMIT');
  assert.equal(result.emitted, false);
  assert.deepEqual(deltas, []);
});
