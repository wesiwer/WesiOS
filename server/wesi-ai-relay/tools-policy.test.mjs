import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const tools = require('../pb_hooks/wesi_ai_task_tools.js');

function row(payload, rid = payload.id || '') {
  return {
    get(name) { return name === 'payload' ? payload : undefined; },
    getString(name) { return name === 'rid' ? rid : ''; },
    set(name, value) { this[name] = value; },
  };
}

function fixture({canAssignTasks = false} = {}) {
  const employees = [
    row({id: 'emp-1', login: 'one', fullName: 'Первый', permissions: {canAssignTasks}}),
    row({id: 'emp-2', login: 'ivan', fullName: 'Иван', permissions: {}}),
  ];
  const organizations = [row({id: 'org_wesi_inc', name: 'Wesi Inc', status: 'active', parentId: null})];
  const grants = [row({id: 'emp-1::org_wesi_inc', employeeId: 'emp-1', organizationId: 'org_wesi_inc', permissions: ['view'], includeSubtree: false})];
  const saved = [];
  const app = {
    findFirstRecordByFilter(_collection, filter, params) {
      if (filter.includes("coll='employees'")) return employees.find((x) => x.get('payload').id === params.rid) || null;
      return null;
    },
    findRecordsByFilter(_collection, filter) {
      if (filter.includes("coll='employees'")) return employees;
      if (filter.includes("coll='organizations'")) return organizations;
      if (filter.includes("coll='organization_grants'")) return grants;
      if (filter.includes("coll='tasks'")) return [];
      return [];
    },
    findCollectionByNameOrId() { return {}; },
    save(record) { saved.push(record); },
  };
  return {e: {app}, saved};
}

globalThis.Record = class {
  constructor() { this.values = {}; }
  set(name, value) { this.values[name] = value; }
};
globalThis.$security = {randomString: () => 'ABCDEFGH'};

const ctx = {isOwner: false, ownerId: 'owner-1', employeeId: 'emp-1', modules: ['ai', 'tasks']};

test('tasks tools disappear when module is not granted', () => {
  assert.deepEqual(tools.definitions({}, {...ctx, modules: ['ai']}), []);
});

test('cannot assign a task to another employee without canAssignTasks', () => {
  const {e, saved} = fixture({canAssignTasks: false});
  const result = tools.execute(e, ctx, 'tasks_create', {title: 'Проверить рекламу', assignee: 'Иван'}, 'org_wesi_inc');
  assert.equal(result.ok, false);
  assert.equal(result.code, 'FORBIDDEN');
  assert.equal(saved.length, 0);
  assert.ok(result.alternatives.includes('Создать задачу себе'));
});

test('canAssignTasks permits creating a real server task for another employee', () => {
  const {e, saved} = fixture({canAssignTasks: true});
  const result = tools.execute(e, ctx, 'tasks_create', {title: 'Проверить рекламу', assignee: 'Иван', dueDate: '2026-08-15'}, 'org_wesi_inc');
  assert.equal(result.ok, true);
  assert.equal(result.result.task.assigneeId, 'emp-2');
  assert.equal(saved.length, 1);
  assert.equal(saved[0].values.coll, 'tasks');
  assert.equal(saved[0].values.payload.assignee, 'emp-2');
  assert.equal(saved[0].values.payload.organizationId, 'org_wesi_inc');
});
