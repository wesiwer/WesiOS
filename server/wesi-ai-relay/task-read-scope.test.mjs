import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);
const tools = require('../pb_hooks/wesi_ai_task_tools.js');

function row(payload) {
  return {
    get(name) { return name === 'payload' ? payload : undefined; },
    getString(name) { return name === 'rid' ? String(payload.id || '') : ''; },
  };
}

function makeEvent({canSeeOthersStats = false, canAssignTasks = false, canManageTeam = false} = {}) {
  const employee = row({
    id: 'emp-1',
    permissions: {canSeeOthersStats, canAssignTasks, canManageTeam},
  });
  const org = row({id: 'org_wesi_inc', name: 'Wesi Inc', status: 'active', parentId: null});
  const grant = row({employeeId: 'emp-1', organizationId: 'org_wesi_inc', permissions: ['view'], includeSubtree: false});
  const tasks = [
    row({id: 'own', title: 'Своя', organizationId: 'org_wesi_inc', assignee: 'emp-1', responsibleEmployeeId: 'emp-1', status: 'backlog'}),
    row({id: 'other', title: 'Чужая', organizationId: 'org_wesi_inc', assignee: 'emp-2', responsibleEmployeeId: 'emp-2', status: 'backlog'}),
  ];
  return {
    app: {
      findFirstRecordByFilter(_collection, filter) {
        if (filter.includes("coll='employees'")) return employee;
        return null;
      },
      findRecordsByFilter(_collection, filter) {
        if (filter.includes("coll='organizations'")) return [org];
        if (filter.includes("coll='organization_grants'")) return [grant];
        if (filter.includes("coll='tasks'")) return tasks;
        if (filter.includes("coll='employees'")) return [employee];
        return [];
      },
    },
  };
}

const ctx = {isOwner: false, ownerId: 'owner-1', employeeId: 'emp-1', modules: ['ai', 'tasks']};

test('canSeeOthersStats alone does not expose other employees tasks to Wesi AI', () => {
  const result = tools.execute(makeEvent({canSeeOthersStats: true}), ctx, 'tasks_list', {}, 'org_wesi_inc');
  assert.equal(result.ok, true);
  assert.deepEqual(result.result.tasks.map((x) => x.id), ['own']);
});

test('canAssignTasks follows server task policy and permits reading team tasks', () => {
  const result = tools.execute(makeEvent({canAssignTasks: true}), ctx, 'tasks_list', {}, 'org_wesi_inc');
  assert.equal(result.ok, true);
  assert.deepEqual(result.result.tasks.map((x) => x.id), ['own', 'other']);
});
