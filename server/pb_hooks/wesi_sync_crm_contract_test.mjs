import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

class FakeForbiddenError extends Error {}
class FakeBadRequestError extends Error {}
globalThis.ForbiddenError = FakeForbiddenError;
globalThis.BadRequestError = FakeBadRequestError;
globalThis.__hooks = path.resolve('server/pb_hooks');

const runtime = await import(new URL('./wesi_sync_crm_runtime.js', import.meta.url))
  .then((m) => m.default || m);

class FakeRecord {
  constructor({id, coll, payload, deleted = false, stamp = '2026-08-18T10:00:00.000Z'}) {
    this.id = id;
    this.values = {rid: id, coll, payload, deleted, stamp};
  }
  get(name) { return this.values[name]; }
  getString(name) {
    const value = this.values[name];
    return value == null ? '' : String(value);
  }
  getBool(name) { return this.values[name] === true; }
}

function row(coll, id, payload, deleted = false) {
  return new FakeRecord({id, coll, payload: {id, ...payload}, deleted});
}

function ctx(overrides = {}) {
  return {
    ownerId: 'company',
    employeeId: 'e1',
    isOwner: false,
    modules: ['crm'],
    canManageTeam: false,
    canSeeOthersStats: false,
    allowedOrgIds: {'org-a': true},
    ...overrides,
  };
}

function crmState() {
  const clients = [
    row('crm_clients', 'c-own', {organizationId: 'org-a', ownerEmployeeId: 'e1'}),
    row('crm_clients', 'c-deal', {organizationId: 'org-a', ownerEmployeeId: 'e2'}),
    row('crm_clients', 'c-other-org', {organizationId: 'org-b', ownerEmployeeId: 'e2'}),
    row('crm_clients', 'c-deleted-via-deal', {organizationId: 'org-a', ownerEmployeeId: 'e2'}, true),
    row('crm_clients', 'c-live-with-deleted-deal', {organizationId: 'org-a', ownerEmployeeId: 'e2'}),
  ];
  const deals = [
    row('crm_deals', 'd-responsible', {
      organizationId: 'org-a', clientId: 'c-deal', responsibleEmployeeId: 'e1',
    }),
    row('crm_deals', 'd-client-owner', {
      organizationId: 'org-a', clientId: 'c-own', responsibleEmployeeId: 'e2',
    }),
    row('crm_deals', 'd-other-org', {
      organizationId: 'org-b', clientId: 'c-other-org', responsibleEmployeeId: 'e1',
    }),
    row('crm_deals', 'd-deleted-cascade', {
      organizationId: 'org-a', clientId: 'c-deleted-via-deal', responsibleEmployeeId: 'e1',
    }, true),
    row('crm_deals', 'd-deleted-only', {
      organizationId: 'org-a', clientId: 'c-live-with-deleted-deal', responsibleEmployeeId: 'e1',
    }, true),
  ];
  return {
    clients: Object.fromEntries(clients.map((r) => [r.getString('rid'), r])),
    deals: Object.fromEntries(deals.map((r) => [r.getString('rid'), r])),
    clientRows: clients,
    dealRows: deals,
  };
}

test('ordinary employee sees only CRM rows in org + ownership/responsibility scope', () => {
  const c = ctx();
  const crm = crmState();

  assert.equal(runtime.clientVisible(c, crm, crm.clients['c-own'], false), true);
  assert.equal(runtime.clientVisible(c, crm, crm.clients['c-deal'], false), true,
    'assigned deal grants visibility of its client');
  assert.equal(runtime.clientVisible(c, crm, crm.clients['c-other-org'], false), false,
    'responsibility never bypasses organization scope');

  assert.equal(runtime.dealVisible(c, crm, crm.deals['d-responsible'], false), true);
  assert.equal(runtime.dealVisible(c, crm, crm.deals['d-client-owner'], false), true,
    'client owner can see deals of that client');
  assert.equal(runtime.dealVisible(c, crm, crm.deals['d-other-org'], false), false);
});

test('deleted relations propagate tombstones but do not expose live rows forever', () => {
  const c = ctx();
  const crm = crmState();

  assert.equal(
    runtime.clientVisible(c, crm, crm.clients['c-deleted-via-deal'], true),
    true,
    'deleted client remains visible through retained deleted deal so cascade can arrive',
  );
  assert.equal(
    runtime.clientVisible(c, crm, crm.clients['c-live-with-deleted-deal'], false),
    false,
    'a deleted historical deal must not keep a live foreign client visible',
  );
});

test('manager still cannot cross allowed organization boundary', () => {
  const c = ctx({canManageTeam: true});
  const crm = crmState();
  assert.equal(runtime.clientVisible(c, crm, crm.clients['c-deal'], false), true);
  assert.equal(runtime.clientVisible(c, crm, crm.clients['c-other-org'], false), false);
  assert.equal(runtime.dealVisible(c, crm, crm.deals['d-other-org'], false), false);
});

test('ordinary employee cannot edit foreign client even if an assigned deal makes it readable', () => {
  const c = ctx();
  const crm = crmState();
  const existing = crm.clients['c-deal'];
  const input = {
    deleted: false,
    payload: {
      id: 'c-deal',
      organizationId: 'org-a',
      ownerEmployeeId: 'e2',
    },
  };

  assert.throws(
    () => runtime.authorizeClient(null, existing, input, c),
    FakeForbiddenError,
  );
});

test('new ordinary client is normalized to current employee owner', () => {
  const c = ctx();
  const input = {
    deleted: false,
    payload: {id: 'c-new', organizationId: 'org-a'},
  };

  runtime.authorizeClient(null, null, input, c);
  assert.equal(input.payload.ownerEmployeeId, 'e1');
  assert.equal(input.payload.organizationId, 'org-a');
});
