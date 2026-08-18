import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import path from 'node:path';
import test from 'node:test';

const require = createRequire(import.meta.url);

class FakeRecord {
  constructor() {
    this.id = '';
    this.values = {};
  }
  get(name) {
    return this.values[name];
  }
  getString(name) {
    const value = this.values[name];
    return value == null ? '' : String(value);
  }
  getBool(name) {
    return this.values[name] === true;
  }
  set(name, value) {
    this.values[name] = value;
  }
}

globalThis.Record = FakeRecord;
const atomic = require(path.resolve('server/pb_hooks/wesi_sync_atomic.js'));

function row({stamp, deleted = false, payload = {value: 'server'}}) {
  const record = new FakeRecord();
  record.id = 'row-id';
  record.set('owner', 'owner');
  record.set('org', 'wesi-inc');
  record.set('coll', 'tasks');
  record.set('rid', 'task-1');
  record.set('payload', payload);
  record.set('stamp', stamp);
  record.set('deleted', deleted);
  return record;
}

function harness(existing = null) {
  let stored = existing;
  let outerDbUsed = false;
  let transactionCalls = 0;
  let saves = 0;

  const txApp = {
    findRecordsByFilter(collection, filter, sort, maxRecords, offset, params) {
      assert.equal(collection, 'wesios_records');
      if (!stored) return [];
      if (params.owner === stored.getString('owner') &&
          params.coll === stored.getString('coll') &&
          params.rid === stored.getString('rid')) {
        return [stored].slice(offset, offset + maxRecords);
      }
      return [];
    },
    findCollectionByNameOrId(name) {
      assert.equal(name, 'wesios_records');
      return {name};
    },
    save(record) {
      saves++;
      if (!record.id) record.id = 'created';
      stored = record;
    },
  };

  const app = {
    runInTransaction(callback) {
      transactionCalls++;
      callback(txApp);
    },
    findRecordsByFilter() {
      outerDbUsed = true;
      throw new Error('outer app DB must not be used inside atomic commit');
    },
    findCollectionByNameOrId() {
      outerDbUsed = true;
      throw new Error('outer app collection lookup must not be used');
    },
    save() {
      outerDbUsed = true;
      throw new Error('outer app save must not be used');
    },
  };

  return {
    app,
    get stored() {
      return stored;
    },
    get outerDbUsed() {
      return outerDbUsed;
    },
    get transactionCalls() {
      return transactionCalls;
    },
    get saves() {
      return saves;
    },
  };
}

function input(stamp, {deleted = false, payload = {value: 'incoming'}} = {}) {
  return {
    owner: 'owner',
    org: 'wesi-inc',
    coll: 'tasks',
    rid: 'task-1',
    payload,
    stamp,
    deleted,
  };
}

test('commit performs its authoritative read and save through txApp only', () => {
  const h = harness(null);
  const result = atomic.commit(h.app, input('2026-08-18T10:00:00.000Z'));

  assert.equal(result.applied, true);
  assert.equal(result.reason, 'created');
  assert.equal(h.transactionCalls, 1);
  assert.equal(h.saves, 1);
  assert.equal(h.outerDbUsed, false);
  assert.equal(h.stored.getString('stamp'), '2026-08-18T10:00:00.000Z');
});

test('older concurrent request cannot overwrite newer transaction-current row', () => {
  const h = harness(row({stamp: '2026-08-18T11:00:00.000Z'}));
  const result = atomic.commit(h.app, input('2026-08-18T10:00:00.000Z'));

  assert.equal(result.applied, false);
  assert.equal(result.reason, 'stale');
  assert.equal(result.stamp, '2026-08-18T11:00:00.000Z');
  assert.equal(h.saves, 0);
  assert.equal(h.outerDbUsed, false);
});

test('equal-time tombstone wins and preserves current authoritative payload', () => {
  const h = harness(row({
    stamp: '2026-08-18T12:00:00.000Z',
    payload: {organizationId: 'org-a', value: 'current'},
  }));
  const result = atomic.commit(
    h.app,
    input('2026-08-18T12:00:00.000Z', {deleted: true, payload: {}}),
  );

  assert.equal(result.applied, true);
  assert.equal(h.stored.getBool('deleted'), true);
  assert.deepEqual(h.stored.get('payload'), {
    organizationId: 'org-a',
    value: 'current',
  });
});
