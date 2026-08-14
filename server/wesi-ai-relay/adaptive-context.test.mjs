import test from 'node:test';
import assert from 'node:assert/strict';

import {
  estimateTokens,
  modelContextWindow,
  prepareAdaptiveContext,
} from './adaptive-context.mjs';

test('token estimator is conservative for Russian and code', () => {
  assert.ok(estimateTokens('Привет, это длинная русская фраза для проверки.') > 10);
  assert.ok(estimateTokens('const value = JSON.stringify({hello: "world"});') > 8);
});

test('frontier providers receive large model-aware default windows', () => {
  assert.ok(modelContextWindow('google', 'gemini-test') >= 1_000_000);
  assert.ok(modelContextWindow('openai', 'gpt-test') >= 200_000);
  assert.ok(modelContextWindow('anthropic', 'claude-test') >= 200_000);
  assert.ok(modelContextWindow('xai', 'grok-test') >= 200_000);
});

test('recent dialogue stays verbatim while relevant old turns are recovered', () => {
  const history = [];
  for (let i = 0; i < 140; i++) {
    history.push({
      author: i % 2 === 0 ? 'user' : 'zane',
      text: i === 8
        ? 'Кодовое решение проекта называется ORBIT-739 и относится к серверному релизу.'
        : `Обычная реплика номер ${i} без важной информации.`,
    });
  }
  const result = prepareAdaptiveContext(
    {provider: 'anthropic', model: 'claude-test'},
    {
      system: 'Ты Зейн.',
      history,
      message: 'Напомни кодовое решение проекта ORBIT и серверный релиз.',
    },
  );
  const combined = result.messages.map((item) => item.content).join('\n');
  assert.match(combined, /ORBIT-739/);
  assert.match(combined, /реплика номер 139/);
  assert.equal(result.messages.at(-1).role, 'user');
});

test('context manager stays below its safe input budget for huge histories', () => {
  const history = Array.from({length: 900}, (_, i) => ({
    author: i % 2 ? 'zane' : 'user',
    text: `Сообщение ${i}: ` + 'длинный технический контекст '.repeat(120),
  }));
  const result = prepareAdaptiveContext(
    {provider: 'anthropic', model: 'claude-test'},
    {system: 'system '.repeat(1000), history, message: 'Продолжай анализ.'},
  );
  assert.ok(result.meta.estimatedInputTokens < result.meta.windowTokens);
  assert.ok(result.meta.outputReserveTokens >= 8192);
  assert.ok(result.meta.historySelected < result.meta.historyAvailable);
  assert.ok(result.meta.historyOmitted > 0);
});
