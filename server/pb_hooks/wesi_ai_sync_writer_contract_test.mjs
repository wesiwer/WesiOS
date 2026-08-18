import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const root = new URL('./', import.meta.url);
const helper = fs.readFileSync(new URL('./wesi_ai_sync_writer.js', root), 'utf8');
const atomic = fs.readFileSync(new URL('./wesi_sync_atomic.js', root), 'utf8');

const mutationTools = [
  'wesi_ai_task_tools.js',
  'wesi_ai_calendar_write_tools.js',
  'wesi_ai_task_write_tools.js',
  'wesi_ai_knowledge_write_tools.js',
  'wesi_ai_finance_write_tools.js',
  'wesi_ai_crm_write_tools.js',
  'wesi_ai_roadmap_tools.js',
  'wesi_ai_audio_tools.js',
];

test('atomic boundary supports transaction-time AI payload rebase', () => {
  assert.match(atomic, /typeof rawInput\.rebase === "function"/);
  assert.match(atomic, /if \(rebase\) rebase\(txApp, existing, input\)/);
  const rebaseAt = atomic.indexOf('if (rebase) rebase(txApp, existing, input)');
  const authAt = atomic.indexOf('if (authorize) authorize(txApp, existing, input)');
  const lwwAt = atomic.indexOf('const decision = lww.decide');
  assert.ok(rebaseAt >= 0 && authAt > rebaseAt && lwwAt > authAt,
    'rebase and live authorization must happen before LWW/save');
});

test('Wesi AI writer rebases deltas and reuses live sync authorization', () => {
  assert.match(helper, /wesi_sync_atomic\.js/);
  assert.match(helper, /wesi_sync_authz\.js/);
  assert.match(helper, /wesi_sync_generic_policy\.js/);
  assert.match(helper, /wesi_sync_crm_runtime\.js/);
  assert.match(helper, /rebase:\s*function/);
  assert.match(helper, /authz\.refresh\(txApp, requestCtx\)/);
  assert.match(helper, /Object\.assign\(\{\}, current, patch\)/);
  assert.match(helper, /genericPolicy\.authorize\(txApp, existing, input, fresh\)/);
  assert.match(helper, /crmPolicy\.authorize(Client|Deal|Interaction)/);
});

for (const file of mutationTools) {
  test(`${file} cannot bypass atomic sync writer`, () => {
    const source = fs.readFileSync(new URL(`./${file}`, root), 'utf8');
    assert.match(source, /wesi_ai_sync_writer\.js/);
    assert.match(source, /syncWriter\.write\(/);
    assert.doesNotMatch(source, /\be\.app\.save\s*\(/);
    assert.doesNotMatch(source, /\bnew\s+Record\s*\(/);
    assert.doesNotMatch(source, /function\s+saveNew\s*\(/);
  });
}
