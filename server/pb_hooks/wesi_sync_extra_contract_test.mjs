import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const routes = fs.readFileSync(new URL('./wesi_sync_extra.pb.js', import.meta.url), 'utf8');
const runtime = fs.readFileSync(new URL('./wesi_sync_extra_runtime.js', import.meta.url), 'utf8');

test('extended sync helpers live in a request-local runtime module', () => {
  assert.match(runtime, /function\s+read\s*\(/);
  assert.match(runtime, /function\s+write\s*\(/);
  assert.match(runtime, /function\s+revision\s*\(/);
  assert.match(runtime, /module\.exports\s*=\s*\{/);
});

test('route callbacks require the runtime instead of closing over top-level helpers', () => {
  assert.doesNotMatch(routes, /const\s+wesiSyncExtra(Read|Write|Payload)\s*=/);
  assert.doesNotMatch(routes, /for\s*\(const\s+name\s+of/);
  assert.match(routes, /require\(`\$\{__hooks\}\/wesi_sync_extra_runtime\.js`\)/);
});

test('all audited extended collections remain explicitly registered', () => {
  for (const collection of [
    'sandbox_transactions',
    'what_if_presets',
    'profile',
    'shield_private',
    'finance_categories',
    'team_skills',
    'time_center',
    'horizon_predictions',
    'horizon_learning',
    'horizon_competition',
    'horizon_contracts',
    'task_ai_memory',
    'audio_extras',
  ]) {
    assert.match(routes, new RegExp(`/api/wesi/sync/${collection}`));
  }
  assert.match(routes, /\/api\/wesi\/sync\/revision-v2/);
});
