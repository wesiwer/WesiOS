import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';

const require = createRequire(import.meta.url);

// Хуки резолвят соседние модули через глобальный __hooks, который под node
// никто не выставляет.
globalThis.__hooks = new URL('../pb_hooks', import.meta.url).pathname;
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
    // Модули перечислены и в записи сотрудника: writer перечитывает права из
    // базы внутри транзакции, а не доверяет контексту вызова. Без них проверка
    // отклоняет запись как «раздел больше не открыт».
    row({id: 'emp-1', login: 'one', fullName: 'Первый', permissions: {modules: ['ai', 'tasks'], canAssignTasks}}),
    row({id: 'emp-2', login: 'ivan', fullName: 'Иван', permissions: {}}),
  ];
  const organizations = [row({id: 'org_wesi_inc', name: 'Wesi Inc', status: 'active', parentId: null})];
  const grants = [row({id: 'emp-1::org_wesi_inc', employeeId: 'emp-1', organizationId: 'org_wesi_inc', permissions: ['view'], includeSubtree: false})];
  const saved = [];
  const app = {
    // PocketBase пишет через транзакцию и передаёт обработчику транзакционный
    // app. Фикстура одиночная, изоляции здесь не проверяется — достаточно
    // вызвать обработчик с тем же app.
    runInTransaction(handler) { return handler(app); },
    findFirstRecordByFilter(_collection, filter, params) {
      // Часть запросов подставляет коллекцию параметром ({:coll}), а не
      // литералом в фильтре. Фикстура смотрела только на литерал и на
      // параметризованный запрос отвечала «не найдено» — writer честно решал,
      // что назначенный сотрудник исчез.
      const coll = params?.coll || (filter.includes("coll='employees'") ? 'employees' : '');
      if (coll === 'employees') return employees.find((x) => x.get('payload').id === params.rid) || null;
      return null;
    },
    findRecordsByFilter(_collection, filter, _sort, _limit, _offset, params) {
      // Коллекция приходит и литералом в фильтре, и параметром {:coll}.
      // Учитываются оба, иначе параметризованная проверка «сотрудник ещё
      // существует» не находит никого и запись отклоняется.
      const named = params?.coll || '';
      const literal = ["employees", "organizations", "organization_grants", "tasks"]
        .find((coll) => filter.includes(`coll='${coll}'`)) || '';
      const coll = named || literal;
      const pool = coll === 'employees' ? employees
        : coll === 'organizations' ? organizations
        : coll === 'organization_grants' ? grants
        : [];
      const rid = params?.rid;
      return rid ? pool.filter((x) => String(x.get('payload').id || '') === String(rid)) : pool;
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

// Классы ошибок PocketBase живут в JSVM как глобальные. Под node их надо
// объявить, иначе первый же отказ writer'а падает с ReferenceError и тест
// сообщает не о том, что проверяет.
globalThis.BadRequestError = class BadRequestError extends Error {};
globalThis.ForbiddenError = class ForbiddenError extends Error {};
globalThis.NotFoundError = class NotFoundError extends Error {};
globalThis.UnauthorizedError = class UnauthorizedError extends Error {};

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
