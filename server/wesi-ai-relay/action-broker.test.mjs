import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import crypto from 'node:crypto';

const require = createRequire(import.meta.url);
const registry = require('../pb_hooks/wesi_ai_capability_registry.js');
const policy = require('../pb_hooks/wesi_ai_risk_policy.js');

class FakeRecord {
  constructor() { this.values = {}; }
  set(key, value) { this.values[key] = value; }
  get(key) { return this.values[key]; }
  getString(key) { return String(this.values[key] || ''); }
}

globalThis.Record = FakeRecord;
globalThis.$security = {
  randomString(length) {
    return crypto.randomBytes(Math.max(8, length)).toString('hex').slice(0, length);
  },
};

function harness() {
  const rows = new Map();
  const app = {
    findCollectionByNameOrId() { return {}; },
    save(record) {
      const key = `${record.get('coll')}:${record.get('rid')}`;
      rows.set(key, record);
    },
    delete(record) {
      const key = `${record.get('coll')}:${record.get('rid')}`;
      rows.delete(key);
    },
    findFirstRecordByFilter(_collection, _filter, params) {
      return rows.get(`${params.coll}:${params.rid}`) || null;
    },
    findRecordsByFilter(_collection, _filter, _sort, _limit, _offset, params) {
      return [...rows.values()].filter((record) => record.get('coll') === params.coll);
    },
  };
  return {e: {app}, rows};
}

test('registry is fail-closed and exposes risk classes', () => {
  assert.equal(registry.get('tasks_list').risk, 'READ');
  assert.equal(registry.get('tasks_create').risk, 'WRITE');
  assert.equal(registry.get('tasks_archive').risk, 'DESTRUCTIVE');
  assert.equal(registry.get('not_registered'), null);
  assert.equal(registry.decorateDefinition({name: 'not_registered'}), null);
});

test('risk policy never accepts model-authored destructive confirmation', () => {
  const cap = registry.get('tasks_archive');
  const denied = policy.evaluate(cap, {confirmed: true});
  assert.equal(denied.allowed, false);
  assert.equal(denied.code, 'CONFIRMATION_REQUIRED');
  const internal = policy.evaluate(cap, {confirmedByTicket: true});
  assert.equal(internal.allowed, true);
});

test('broker executes read/write but creates one-time ticket for destructive', () => {
  const {e} = harness();
  const ctx = {ownerId: 'owner-1', employeeId: 'employee-1'};
  let calls = 0;
  const adapter = {
    execute(_e, _ctx, name, args) {
      calls += 1;
      return {ok: true, result: {id: args.taskId || 'created-1', name}};
    },
  };
  const broker = require('../pb_hooks/wesi_ai_action_broker.js');

  const read = broker.execute(e, ctx, adapter, 'tasks_list', {}, 'org_wesi_inc', {});
  assert.equal(read.ok, true);
  const write = broker.execute(e, ctx, adapter, 'tasks_create', {title: 'x'}, 'org_wesi_inc', {});
  assert.equal(write.ok, true);
  assert.equal(calls, 2);

  const pending = broker.execute(
    e,
    ctx,
    adapter,
    'tasks_archive',
    {taskId: 'task-1'},
    'org_wesi_inc',
    {persona: 'zane', conversationId: 'chat-1', requestId: 'req-1'},
  );
  assert.equal(pending.ok, false);
  assert.equal(pending.code, 'CONFIRMATION_REQUIRED');
  assert.ok(pending.confirmation?.id);
  assert.equal(calls, 2);

  const confirmed = broker.confirm(e, ctx, pending.confirmation.id, () => adapter);
  assert.equal(confirmed.ok, true);
  assert.equal(calls, 3);
  const replay = broker.confirm(e, ctx, pending.confirmation.id, () => adapter);
  assert.equal(replay.ok, false);
  assert.equal(replay.code, 'CONFIRMATION_EXPIRED');
});
