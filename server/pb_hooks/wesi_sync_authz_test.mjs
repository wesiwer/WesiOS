import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

class FakeUnauthorizedError extends Error {}
globalThis.UnauthorizedError = FakeUnauthorizedError;
globalThis.__hooks = path.resolve('server/pb_hooks');

const authz = await import(new URL('./wesi_sync_authz.js', import.meta.url))
  .then((m) => m.default || m);

class Row {
  constructor({rid = '', payload = {}} = {}) { this.rid = rid; this.payload = payload; }
  get(name) { return name === 'payload' ? this.payload : null; }
  getString(name) { return name === 'rid' ? this.rid : ''; }
}

function app({employee = null, organizations = [], grants = []} = {}) {
  return {
    findRecordsByFilter(collection, filter, sort, limit, offset, params) {
      if (filter.includes("coll='employees'")) return employee ? [employee] : [];
      if (filter.includes("coll='organizations'")) return organizations;
      if (filter.includes("coll='organization_grants'")) return grants;
      return [];
    },
  };
}

const base = {ownerId: 'company', employeeId: 'e1', isOwner: false};

test('missing live employee invalidates transaction authorization', () => {
  assert.throws(() => authz.refresh(app(), base), FakeUnauthorizedError);
});

test('refresh uses current employee modules rather than request snapshot', () => {
  const employee = new Row({payload: {permissions: {modules: ['tasks'], canAssignTasks: true}}});
  const fresh = authz.refresh(app({employee}), {...base, modules: ['crm', 'audio']});
  assert.deepEqual(fresh.modules, ['tasks']);
  assert.equal(fresh.canAssignTasks, true);
});

test('revoked org grant disappears from transaction scope', () => {
  const employee = new Row({payload: {permissions: {modules: ['treasury']}}});
  const org = new Row({rid: 'org-a', payload: {id: 'org-a'}});
  const fresh = authz.refresh(app({employee, organizations: [org], grants: []}), {
    ...base,
    allowedOrgIds: {'org-a': true},
    ownGrants: [{organizationId: 'org-a', permissions: ['view_finance']}],
  });
  assert.deepEqual(fresh.allowedOrgIds, {});
  assert.deepEqual(fresh.ownGrants, []);
});
