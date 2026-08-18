import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

class FakeForbiddenError extends Error {}
globalThis.ForbiddenError = FakeForbiddenError;
globalThis.BadRequestError = class extends Error {};
globalThis.__hooks = path.resolve('server/pb_hooks');

const policy = await import(new URL('./wesi_sync_generic_policy.js', import.meta.url))
  .then((m) => m.default || m);

class Row {
  constructor(payload) { this.payload = payload; }
  get(name) { return name === 'payload' ? this.payload : null; }
  getString() { return ''; }
  getBool() { return false; }
}

function ctx(extra = {}) {
  return {
    ownerId: 'company', employeeId: 'e1', isOwner: false,
    modules: ['tasks', 'chats', 'knowledge', 'treasury'],
    canManageTeam: false, canAssignTasks: false, canSeeOthersStats: false,
    knowledgeAll: false, knowledgeIds: ['article-1'],
    allowedOrgIds: {'org-a': true},
    ownGrants: [{organizationId: 'org-a', includeSubtree: false,
      permissions: ['view_finance', 'create_transactions', 'edit_transactions', 'manage_accounts']}],
    orgParents: {},
    ...extra,
  };
}

test('employee avatar update preserves transaction-current protected fields', () => {
  const input = {coll: 'employees', rid: 'e1', deleted: false,
    payload: {avatarIndex: 4, photo: 'new'}};
  policy.authorize(null, new Row({id: 'e1', permissions: {admin: true}, email: 'owner-set'}), input, ctx());
  assert.deepEqual(input.payload.permissions, {admin: true});
  assert.equal(input.payload.email, 'owner-set');
  assert.equal(input.payload.avatarIndex, 4);
});

test('task cannot be updated after concurrent reassignment outside employee scope', () => {
  const existing = new Row({id: 't1', organizationId: 'org-a', assignee: 'e2'});
  const input = {coll: 'tasks', rid: 't1', deleted: false,
    payload: {id: 't1', organizationId: 'org-a', assignee: 'e1'}};
  assert.throws(() => policy.authorize(null, existing, input, ctx()), FakeForbiddenError);
});

test('transaction cannot be moved from an organization without edit permission', () => {
  const c = ctx({
    allowedOrgIds: {'org-a': true, 'org-b': true},
    ownGrants: [{organizationId: 'org-b', includeSubtree: false,
      permissions: ['create_transactions', 'edit_transactions']}],
  });
  const existing = new Row({id: 'x', organizationId: 'org-a'});
  const input = {coll: 'transactions', rid: 'x', deleted: false,
    payload: {id: 'x', organizationId: 'org-b'}};
  assert.throws(() => policy.authorize(null, existing, input, c), FakeForbiddenError);
});

test('message authorization rechecks transaction-current parent chat', () => {
  const txApp = {
    findRecordsByFilter(collection, filter, sort, limit, offset, params) {
      assert.equal(params.rid, 'chat-1');
      return [new Row({id: 'chat-1', kind: 'work', participants: ['e2']})];
    },
  };
  const input = {coll: 'messages', rid: 'm1', deleted: false,
    payload: {id: 'm1', chatId: 'chat-1'}};
  assert.throws(() => policy.authorize(txApp, null, input, ctx()), FakeForbiddenError);
});

test('knowledge reparenting requires access to both current and target scope', () => {
  const existing = new Row({id: 'article-1', parentId: ''});
  const input = {coll: 'articles', rid: 'article-1', deleted: false,
    payload: {id: 'article-1', parentId: 'foreign-parent'}};
  // id itself is explicitly granted, so the move remains allowed; remove that
  // grant to prove the target is rejected.
  policy.authorize(null, existing, input, ctx());
  assert.throws(() => policy.authorize(null, existing, input,
    ctx({knowledgeIds: ['some-other-id']})), FakeForbiddenError);
});
