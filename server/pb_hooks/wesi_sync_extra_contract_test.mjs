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

test('legacy profile_private is migrated before canonical profile or shield access', () => {
  assert.match(runtime, /function\s+migrateLegacyProfilePrivate\s*\(/);
  assert.match(runtime, /coll='profile_private'\s*&&\s*deleted=false/);
  assert.match(runtime, /coll='profile'\s*&&\s*rid='me'/);
  assert.match(runtime, /coll='shield_private'/);

  const readStart = runtime.indexOf('function read(e, collection');
  const writeStart = runtime.indexOf('function write(e, collection');
  const revisionStart = runtime.indexOf('function revision(e)');
  assert.ok(readStart >= 0 && writeStart > readStart && revisionStart > writeStart);
  const readBody = runtime.slice(readStart, writeStart);
  const writeBody = runtime.slice(writeStart, revisionStart);
  assert.match(readBody, /collection === "profile" \|\| collection === "shield_private"/);
  assert.match(readBody, /migrateLegacyProfilePrivate\(e\)/);
  assert.match(writeBody, /collection === "profile" \|\| collection === "shield_private"/);
  assert.match(writeBody, /migrateLegacyProfilePrivate\(e\)/);
});

test('migration never overwrites canonical targets and converts avatar bytes', () => {
  assert.match(runtime, /if\s*\(!existingShield\)/);
  assert.match(runtime, /if\s*\(existingProfile\) return;/);
  assert.match(runtime, /legacyBytesToBase64/);
  assert.match(runtime, /__wesios_bytes_v1/);
  assert.match(runtime, /Math\.min\(parsed, now\)/,
    'legacy future stamps must be clamped during migration');
});
