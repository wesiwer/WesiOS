import test from 'node:test';
import assert from 'node:assert/strict';
import {Permission, requirePermission, assertSafeGitHubWrite} from './policy.mjs';

test('read is allowed by default for GitHub', () => {
  assert.doesNotThrow(() => requirePermission('github', Permission.READ, {}));
});

test('destructive GitHub action is denied by default', () => {
  assert.throws(() => requirePermission('github', Permission.DESTRUCTIVE, {}), error => error.code === 'CONNECTOR_FORBIDDEN');
});

test('direct main branch ref write requires explicit policy', () => {
  assert.throws(
    () => assertSafeGitHubWrite({method: 'PATCH', path: '/repos/wesiwer/WesiOS/git/refs/heads/main', policy: {write: true}}),
    error => error.code === 'PROTECTED_BRANCH_WRITE_REQUIRES_APPROVAL',
  );
});
