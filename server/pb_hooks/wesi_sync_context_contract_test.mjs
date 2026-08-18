import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('./wesi_sync_context.pb.js', import.meta.url), 'utf8');

test('employee sync authorization never falls back to portal snapshot', () => {
  assert.match(source, /coll='employees' && rid=\{:rid\} && deleted=false/);
  assert.doesNotMatch(source, /linkPayload\.snapshot\s*&&/);
  assert.doesNotMatch(source, /snapshot\s*=\s*employee\s*\?\s*payloadOf\(employee\)/);
});

test('missing live employee terminates session with UnauthorizedError', () => {
  const marker = source.indexOf('if (!employee)');
  assert.ok(marker >= 0);
  const block = source.slice(marker, marker + 260);
  assert.match(block, /UnauthorizedError/);
  assert.doesNotMatch(block, /ForbiddenError/);
});
