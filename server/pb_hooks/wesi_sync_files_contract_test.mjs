import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';

class FakeForbiddenError extends Error {}
class FakeBadRequestError extends Error {}
globalThis.ForbiddenError = FakeForbiddenError;
globalThis.BadRequestError = FakeBadRequestError;
globalThis.__hooks = path.resolve('server/pb_hooks');

const runtime = await import(new URL('./wesi_sync_files_runtime.js', import.meta.url))
  .then((m) => m.default || m);

class FakeRecord {
  constructor(payload, deleted = false) { this.payload = payload; this.deleted = deleted; }
  get(name) { return name === 'payload' ? this.payload : null; }
  getBool(name) { return name === 'deleted' && this.deleted; }
  getString(name) { return name === 'stamp' ? '2026-08-18T10:00:00.000Z' : ''; }
}

const ctx = (extra = {}) => ({
  employeeId: 'e1',
  isOwner: false,
  canManageTeam: false,
  modules: ['audio'],
  ...extra,
});

const row = (payload) => new FakeRecord(payload);

test('ordinary employee sees only participant-scoped file metadata', () => {
  const c = ctx();
  assert.equal(runtime.visible(c, 'file_requests', row({requesterId: 'e1'})), true);
  assert.equal(runtime.visible(c, 'file_requests', row({requesterId: 'e2', holderId: 'e1'})), true);
  assert.equal(runtime.visible(c, 'file_requests', row({requesterId: 'e2', holderId: ''})), true);
  assert.equal(runtime.visible(c, 'file_requests', row({requesterId: 'e2', holderId: 'e3'})), false);
  assert.equal(runtime.visible(c, 'file_grants', row({employeeId: 'e1', grantedBy: 'e2'})), true);
  assert.equal(runtime.visible(c, 'file_grants', row({employeeId: 'e2', grantedBy: 'e1'})), true);
  assert.equal(runtime.visible(c, 'file_grants', row({employeeId: 'e2', grantedBy: 'e3'})), false);
  assert.equal(runtime.visible(c, 'file_handovers', row({fromEmployeeId: 'e1', toEmployeeId: 'e2'})), true);
  assert.equal(runtime.visible(c, 'file_handovers', row({fromEmployeeId: 'e2', toEmployeeId: 'e3'})), false);
});

test('manager can see all file metadata rows', () => {
  const c = ctx({canManageTeam: true});
  assert.equal(runtime.visible(c, 'file_grants', row({employeeId: 'e2', grantedBy: 'e3'})), true);
  assert.equal(runtime.visible(c, 'file_handovers', row({fromEmployeeId: 'e2', toEmployeeId: 'e3'})), true);
});

test('ordinary employee cannot create request for another employee', () => {
  assert.throws(() => runtime.authorizeRequest(null, null, {
    deleted: false,
    payload: {id: 'r1', requesterId: 'e2'},
  }, ctx()), FakeForbiddenError);
});

test('request participants are immutable after creation', () => {
  const existing = row({
    id: 'r1', subjectKind: 'beat', subjectId: 'b1', fileKind: 'wav',
    attachmentId: '', requesterId: 'e1', holderId: 'e2', createdAt: '2026-08-18T10:00:00Z',
  });
  const input = {deleted: false, payload: {id: 'r1', requesterId: 'evil', holderId: 'evil', status: 'cancelled'}};
  runtime.authorizeRequest(null, existing, input, ctx());
  assert.equal(input.payload.requesterId, 'e1');
  assert.equal(input.payload.holderId, 'e2');
  assert.equal(input.payload.subjectId, 'b1');
});

test('ordinary employee cannot mutate grants', () => {
  assert.throws(() => runtime.authorizeGrant(null, null, {deleted: false, payload: {}}, ctx()), FakeForbiddenError);
});

test('ordinary employee may only record a handover from self', () => {
  runtime.authorizeHandover(null, null, {deleted: false, payload: {fromEmployeeId: 'e1'}}, ctx());
  assert.throws(() => runtime.authorizeHandover(null, null, {
    deleted: false, payload: {fromEmployeeId: 'e2'},
  }, ctx()), FakeForbiddenError);
});
