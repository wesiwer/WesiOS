import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createDynamicSubagentSpec,
  scopeDynamicCapabilities,
  validateDynamicSubagentResult,
} from './dynamic_subagent.mjs';

function baseSpec(overrides = {}) {
  return createDynamicSubagentSpec({
    parentRequestId: 'req-1',
    role: 'Gradle specialist',
    task: 'Проверь причины ошибки сборки.',
    requestedCapabilities: ['repo.read', 'build.read'],
    grantedCapabilities: ['repo.read', 'build.read'],
    allowlistedCapabilities: ['repo.read', 'build.read'],
    readablePaths: ['android/build.gradle'],
    writablePaths: ['notes/gradle.md'],
    baseRevision: 0,
    ...overrides,
  });
}

test('dynamic subagent forbids recursive depth', () => {
  assert.throws(() => baseSpec({depth: 2}), /WAI_SUBAGENT_RECURSION_FORBIDDEN/);
});

test('capability scope is strict intersection and removes agent/destructive capabilities', () => {
  const scoped = scopeDynamicCapabilities({
    requested: ['repo.read', 'agent.spawn', 'deploy.write', 'connector.secret.read'],
    granted: ['repo.read', 'agent.spawn', 'deploy.write', 'connector.secret.read'],
    allowlisted: ['repo.read', 'agent.spawn', 'deploy.write', 'connector.secret.read'],
    destructiveCapabilities: ['deploy.write'],
  });
  assert.deepEqual(scoped, ['repo.read']);
});

test('result rejects hidden reasoning fields', () => {
  const spec = baseSpec();
  assert.throws(() => validateDynamicSubagentResult({
    summary: 'ok',
    reasoning: 'hidden',
  }, spec), /WAI_SUBAGENT_HIDDEN_REASONING_FORBIDDEN/);
});

test('workspace edits are bounded to declared writable paths', () => {
  const spec = baseSpec({maxWorkspaceEdits: 1});
  const result = validateDynamicSubagentResult({
    summary: 'Проверка завершена',
    workspaceEdits: [
      {path: 'notes/gradle.md', operation: 'create', content: 'safe', baseRevision: 0},
      {path: 'android/build.gradle', operation: 'replace', content: 'unsafe', baseRevision: 0},
    ],
  }, spec);
  assert.equal(result.workspaceEdits.length, 1);
  assert.equal(result.workspaceEdits[0].path, 'notes/gradle.md');
});
