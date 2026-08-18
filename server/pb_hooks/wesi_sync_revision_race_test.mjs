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

  set(name, value) {
    this.values[name] = value;
  }
}

globalThis.Record = FakeRecord;
let randomCounter = 0;
globalThis.$security = {
  randomString() {
    randomCounter++;
    return `nonce-${randomCounter}`;
  },
};

const revision = require(path.resolve('server/pb_hooks/wesi_sync_revision.js'));

function businessRow(stamp = '2026-08-18T10:00:00.000Z') {
  const row = new FakeRecord();
  row.id = 'business';
  row.set('owner', 'owner');
  row.set('coll', 'tasks');
  row.set('rid', 'task-1');
  row.set('stamp', stamp);
  row.set('updated', '2026-08-18 10:00:00.000Z');
  row.set('payload', {id: 'task-1'});
  row.set('deleted', false);
  return row;
}

function markerRow(stamp = '2026-08-18T10:00:00.001Z') {
  const row = new FakeRecord();
  row.id = 'marker-from-other-hook';
  row.set('owner', 'owner');
  row.set('org', '__sync_revision__');
  row.set('coll', revision.markerCollection);
  row.set('rid', revision.markerRid);
  row.set('stamp', stamp);
  row.set('payload', {nonce: 'other-hook'});
  row.set('deleted', false);
  return row;
}

function raceApp() {
  const business = businessRow();
  const markers = [];
  let saveCalls = 0;
  let createConflictInjected = false;

  return {
    markers,
    get saveCalls() {
      return saveCalls;
    },
    findCollectionByNameOrId(name) {
      assert.equal(name, 'wesios_records');
      return {name};
    },
    findRecordsByFilter(collection, filter, sort, maxRecords, offset, params) {
      assert.equal(collection, 'wesios_records');
      if (params?.coll === revision.markerCollection && params?.rid === revision.markerRid) {
        return markers.slice(offset, offset + maxRecords);
      }
      if (params?.marker === revision.markerCollection) {
        return offset === 0 ? [business].slice(0, maxRecords) : [];
      }
      return [];
    },
    save(record) {
      saveCalls++;
      const isNewMarker = !record.id &&
        record.getString('coll') === revision.markerCollection;
      if (isNewMarker && !createConflictInjected) {
        createConflictInjected = true;
        // Simulate the competing hook committing the UNIQUE row between our
        // initial markerRows() read and this INSERT.
        markers.push(markerRow());
        throw new Error('UNIQUE constraint failed: wesios_records.owner, coll, rid');
      }
      if (isNewMarker) {
        record.id = `created-${saveCalls}`;
        markers.push(record);
      }
    },
  };
}

test('touch retries as update when another hook wins the first marker create', () => {
  randomCounter = 0;
  const app = raceApp();

  assert.doesNotThrow(() => revision.touch(app, 'owner'));

  assert.equal(app.markers.length, 1,
    'UNIQUE marker race must converge to one physical row');
  assert.equal(app.saveCalls, 2,
    'first INSERT fails, second save updates the row created by the competitor');

  const marker = app.markers[0];
  const payload = marker.get('payload');
  assert.equal(payload.nonce, 'nonce-2',
    'retry must issue a fresh revision token instead of accepting the competitor token');
  assert.ok(
    Date.parse(marker.getString('stamp')) > Date.parse('2026-08-18T10:00:00.001Z'),
    'retry marker stamp must advance beyond the marker that won the create race',
  );
});
