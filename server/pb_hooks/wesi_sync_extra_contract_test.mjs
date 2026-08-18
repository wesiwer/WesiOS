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
  const migrationStart = runtime.indexOf('function migrateLegacyProfilePrivate(e)');
  const readStart = runtime.indexOf('function read(e, collection');
  assert.ok(migrationStart >= 0 && readStart > migrationStart);
  const migrationBody = runtime.slice(migrationStart, readStart);

  assert.match(migrationBody, /wesi_sync_atomic\.js/);
  assert.match(migrationBody, /atomic\.createIfAbsent\(e\.app/);
  assert.match(migrationBody, /coll:\s*"shield_private"/);
  assert.match(migrationBody, /coll:\s*"profile"/);
  assert.match(migrationBody, /rid:\s*"me"/);
  assert.doesNotMatch(migrationBody, /e\.app\.save\(/,
    'legacy migration must not use non-atomic check-then-save');
  assert.match(runtime, /legacyBytesToBase64/);
  assert.match(runtime, /__wesios_bytes_v1/);
  assert.match(runtime, /Math\.min\(parsed, now\)/,
    'legacy future stamps must be clamped during migration');
});

test('extended normal writes use transactional authoritative commit', () => {
  const writeStart = runtime.indexOf('function write(e, collection');
  const revisionStart = runtime.indexOf('function revision(e)');
  const writeBody = runtime.slice(writeStart, revisionStart);

  assert.match(writeBody, /wesi_sync_atomic\.js/);
  assert.match(writeBody, /\.commit\(e\.app/);
  assert.doesNotMatch(writeBody, /wesi_sync_lww\.js/,
    'outer preflight LWW is not the authoritative write boundary anymore');
  assert.doesNotMatch(writeBody, /e\.app\.save\(/);
});
