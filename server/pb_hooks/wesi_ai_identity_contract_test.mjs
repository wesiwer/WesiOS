import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const source = fs.readFileSync(new URL('./wesi_ai_lib.js', import.meta.url), 'utf8');

test('Wesi AI identity never authorizes from portal-account snapshot', () => {
  assert.match(source, /coll='employees' && rid=\{:rid\} && deleted=false/);
  assert.doesNotMatch(source, /lp\.snapshot/);
  assert.doesNotMatch(source, /employee\s*\?\s*payloadOf\(employee\)/);
});

test('missing live employee terminates Wesi AI identity session', () => {
  const marker = source.indexOf('if (!employee)');
  assert.ok(marker >= 0, 'missing employee guard is required');
  const block = source.slice(marker, marker + 260);
  assert.match(block, /UnauthorizedError/);
  assert.doesNotMatch(block, /ForbiddenError/);
});
