import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const gh = require('../pb_hooks/wesi_ai_github_lib.js');

test('GitHub connector only builds fixed api.github.com URLs', () => {
  assert.equal(
    gh.apiUrl('/repos/wesiwer/WesiOS/branches', {per_page: 20}),
    'https://api.github.com/repos/wesiwer/WesiOS/branches?per_page=20',
  );
  assert.equal(
    gh.repoApiPath('wesiwer', 'WesiOS', '/commits'),
    '/repos/wesiwer/WesiOS/commits',
  );
  assert.throws(() => gh.apiUrl('https://evil.example/a'), /GITHUB_BAD_API_PATH/);
  assert.throws(() => gh.apiUrl('/repos/a/../secret'), /GITHUB_BAD_API_PATH/);
  assert.throws(() => gh.validateOwnerRepo('a/b', 'repo'), /GITHUB_BAD_REPOSITORY/);
});

test('repository file paths and refs reject traversal and control characters', () => {
  assert.equal(gh.validateContentPath('lib/features/ai/file.dart'), 'lib/features/ai/file.dart');
  assert.equal(gh.validateRef('feature/test'), 'feature/test');
  assert.throws(() => gh.validateContentPath('../secret'), /GITHUB_BAD_PATH/);
  assert.throws(() => gh.validateContentPath('a//b'), /GITHUB_BAD_PATH/);
  assert.throws(() => gh.validateRef('../main'), /GITHUB_BAD_REF/);
  assert.throws(() => gh.validateRef('main\nheader'), /GITHUB_BAD_REF/);
});

test('actual granted OAuth scopes are normalized and enforced', () => {
  assert.deepEqual(gh.uniqueScopes('repo, workflow read:user repo'), ['repo', 'workflow', 'read:user']);
  assert.equal(gh.requireScopes(['repo', 'read:user'], ['repo']).ok, true);
  const denied = gh.requireScopes(['read:user'], ['repo']);
  assert.equal(denied.ok, false);
  assert.equal(denied.missing, 'repo');
});

test('authorization header is generated server-side and rejects header injection', () => {
  const token = 'gho_' + 'x'.repeat(40);
  const headers = gh.safeHeaders(token);
  assert.equal(headers.Authorization, `Bearer ${token}`);
  assert.equal(headers['X-GitHub-Api-Version'], '2022-11-28');
  assert.throws(() => gh.safeHeaders('x\r\nInjected: yes'), /GITHUB_BAD_TOKEN/);
});

test('GitHub responses are bounded before entering model context', () => {
  assert.deepEqual(gh.parseJsonResponse({raw: '{"ok":true}'}), {ok: true});
  assert.equal(gh.boundedResult({a: 'ok'}, 1024).a, 'ok');
  assert.throws(() => gh.boundedResult({a: 'x'.repeat(5000)}, 1024), /GITHUB_RESPONSE_TOO_LARGE/);
  assert.throws(() => gh.parseJsonResponse({raw: 'not-json'}), /GITHUB_BAD_RESPONSE/);
});