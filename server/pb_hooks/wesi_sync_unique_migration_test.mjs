import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import vm from 'node:vm';

const migrationPath = path.resolve(
  'server/pb_migrations/1787055000_wesios_records_unique_rid.js',
);
const source = fs.readFileSync(migrationPath, 'utf8');

function loadMigration() {
  let up = null;
  let down = null;
  const context = {
    console,
    Date,
    Number,
    String,
    DynamicModel: class DynamicModel {
      constructor(shape) {
        Object.assign(this, shape);
      }
    },
    arrayOf() {
      return [];
    },
    migrate(upFn, downFn) {
      up = upFn;
      down = downFn;
    },
  };
  vm.runInNewContext(source, context, {filename: migrationPath});
  assert.equal(typeof up, 'function');
  return {up, down};
}

function fakeApp(initialRows, {collectionExists = true} = {}) {
  const rows = initialRows.map((row) => ({...row}));
  const indexCalls = [];
  let saved = false;
  let selectCount = 0;

  const collection = {
    addIndex(name, unique, columns, where) {
      indexCalls.push({name, unique, columns, where});
    },
  };

  const app = {
    rows,
    indexCalls,
    get saved() {
      return saved;
    },
    get selectCount() {
      return selectCount;
    },
    findCollectionByNameOrId(name) {
      assert.equal(name, 'wesios_records');
      if (!collectionExists) throw new Error('missing collection');
      return collection;
    },
    db() {
      return {
        newQuery(sql) {
          const query = {
            params: {},
            bind(params) {
              this.params = params;
              return this;
            },
            all(target) {
              assert.match(sql, /SELECT id, owner, coll, rid, stamp, deleted/);
              selectCount++;
              for (const row of rows) target.push({...row});
            },
            execute() {
              assert.match(sql, /DELETE FROM wesios_records WHERE id=\{:id\}/);
              const id = String(this.params.id);
              const index = rows.findIndex((row) => String(row.id) === id);
              assert.notEqual(index, -1, `migration tried to delete unknown row ${id}`);
              rows.splice(index, 1);
            },
          };
          return query;
        },
      };
    },
    save(value) {
      assert.equal(value, collection);
      saved = true;
    },
  };

  return app;
}

test('clean install exits before querying a missing wesios_records table', () => {
  const {up} = loadMigration();
  const app = fakeApp([], {collectionExists: false});

  up(app);

  assert.equal(app.selectCount, 0);
  assert.equal(app.saved, false);
  assert.deepEqual(app.indexCalls, []);
});

test('migration keeps one deterministic LWW winner per sync identity', () => {
  const {up} = loadMigration();
  const app = fakeApp([
    // Same timestamp: tombstone must beat both live variants.
    {id: 'b', owner: 'o', coll: 'tasks', rid: 'r1', stamp: '2026-08-18T10:00:00.000Z', deleted: false},
    {id: 'a', owner: 'o', coll: 'tasks', rid: 'r1', stamp: '2026-08-18T10:00:00.000Z', deleted: false},
    {id: 'c', owner: 'o', coll: 'tasks', rid: 'r1', stamp: '2026-08-18T10:00:00.000Z', deleted: true},

    // Newer valid stamp beats older/invalid rows.
    {id: 'd', owner: 'o', coll: 'tasks', rid: 'r2', stamp: 'not-a-date', deleted: true},
    {id: 'e', owner: 'o', coll: 'tasks', rid: 'r2', stamp: '2026-08-18T09:00:00.000Z', deleted: false},
    {id: 'f', owner: 'o', coll: 'tasks', rid: 'r2', stamp: '2026-08-18T11:00:00.000Z', deleted: false},

    // Equal live rows use stable record id, independent of scan order.
    {id: 'z', owner: 'other', coll: 'profile', rid: 'me', stamp: '2026-08-18T12:00:00.000Z', deleted: false},
    {id: 'y', owner: 'other', coll: 'profile', rid: 'me', stamp: '2026-08-18T12:00:00.000Z', deleted: false},
  ]);

  up(app);

  assert.deepEqual(
    app.rows.map((row) => row.id).sort(),
    ['c', 'f', 'y'],
  );
  const identities = new Set(
    app.rows.map((row) => `${row.owner}\u0000${row.coll}\u0000${row.rid}`),
  );
  assert.equal(identities.size, app.rows.length);
});

test('migration persists the exact unique owner/coll/rid index', () => {
  const {up} = loadMigration();
  const app = fakeApp([
    {id: 'one', owner: 'o', coll: 'tasks', rid: 'r1', stamp: '2026-08-18T10:00:00.000Z', deleted: false},
  ]);

  up(app);

  assert.equal(app.saved, true);
  assert.deepEqual(app.indexCalls, [{
    name: 'idx_wesios_rid',
    unique: true,
    columns: 'owner, coll, rid',
    where: '',
  }]);
});
