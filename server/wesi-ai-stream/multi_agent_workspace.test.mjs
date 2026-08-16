import test from 'node:test';
import assert from 'node:assert/strict';
import {
  createConflictSafeWorkspace,
  workspaceSnapshot,
  applySubagentWorkspaceEdits,
} from './multi_agent_workspace.mjs';

test('stale overlapping edit is rejected instead of last-write-wins', () => {
  const workspace = createConflictSafeWorkspace({
    workspaceId: 'ws-1',
    files: [{path: 'plan.md', content: 'base', revision: 0}],
  });
  const first = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a1',
    allowedPaths: ['plan.md'],
    edits: [{path: 'plan.md', operation: 'replace', content: 'first', baseRevision: 0}],
  });
  assert.equal(first.applied.length, 1);
  const second = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a2',
    allowedPaths: ['plan.md'],
    edits: [{path: 'plan.md', operation: 'replace', content: 'second', baseRevision: 0}],
  });
  assert.equal(second.applied.length, 0);
  assert.equal(second.conflicts[0].code, 'REVISION_CONFLICT');
  assert.equal(workspaceSnapshot(workspace).files[0].content, 'first');
});

test('path outside subagent scope is rejected', () => {
  const workspace = createConflictSafeWorkspace({workspaceId: 'ws-2'});
  const result = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a1',
    allowedPaths: ['notes/a.md'],
    edits: [{path: 'secret.txt', operation: 'create', content: 'x', baseRevision: 0}],
  });
  assert.equal(result.applied.length, 0);
  assert.equal(result.rejected[0].code, 'PATH_NOT_ALLOWED');
});

test('create and replace require conflict-safe file state', () => {
  const workspace = createConflictSafeWorkspace({workspaceId: 'ws-3'});
  const created = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a1',
    allowedPaths: ['notes/a.md'],
    edits: [{path: 'notes/a.md', operation: 'create', content: 'v1', baseRevision: 0}],
  });
  assert.equal(created.applied.length, 1);
  const duplicateCreate = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a2',
    allowedPaths: ['notes/a.md'],
    edits: [{path: 'notes/a.md', operation: 'create', content: 'v2', baseRevision: 1}],
  });
  assert.equal(duplicateCreate.conflicts[0].code, 'ALREADY_EXISTS');
  const missingReplace = applySubagentWorkspaceEdits(workspace, {
    agentId: 'a3',
    allowedPaths: ['notes/missing.md'],
    edits: [{path: 'notes/missing.md', operation: 'replace', content: 'x', baseRevision: 0}],
  });
  assert.equal(missingReplace.conflicts[0].code, 'MISSING_FILE');
});
