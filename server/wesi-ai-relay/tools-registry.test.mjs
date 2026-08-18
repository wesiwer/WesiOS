// Каждый написанный Wesi AI tool должен быть реально досягаем.
//
// Инструмент живёт в двух местах: в собственном адаптере и в списке adapters()
// внутри wesi_ai_tools.js. Забыть второе место нечем: код адаптера полностью
// корректен, тесты адаптера зелёные, ревью видит готовый файл — а модель при
// этом не получает инструмент вообще, потому что реестр о нём не знает.
//
// Так и случилось с horizon_snapshot: файл, политика доступа и проверка прав
// были написаны, но require() в реестр никто не дописал.
//
// Тест сверяет не один инструмент, а инвариант: объединение определений всех
// адаптеров на диске равно тому, что отдаёт реестр.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {readdirSync} from 'node:fs';
import {fileURLToPath} from 'node:url';
import path from 'node:path';

const require = createRequire(import.meta.url);
const hooks = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../pb_hooks');
globalThis.__hooks = hooks;

const e = {
  app: {
    findRecordsByFilter() { return []; },
    findFirstRecordByFilter() { return null; },
    findCollectionByNameOrId() { return {}; },
  },
};

// Владелец видит максимум: любой инструмент, скрытый только правами, тут
// раскрывается. Инструмент, не появившийся даже здесь, недосягаем никому.
const owner = {isOwner: true, ownerId: 'owner-1', employeeId: 'owner', modules: ['ai']};

function names(definitions) {
  return (Array.isArray(definitions) ? definitions : []).map((item) => String(item.name || '')).sort();
}

function adapterFiles() {
  return readdirSync(hooks)
    .filter((file) => /^wesi_ai_.*_tools\.js$/.test(file))
    .sort();
}

test('реестр знает каждый адаптер инструментов, лежащий в pb_hooks', () => {
  const registry = require(`${hooks}/wesi_ai_tools.js`);
  const exposed = new Set(names(registry.definitions(e, owner)));

  const missing = [];
  for (const file of adapterFiles()) {
    const adapter = require(`${hooks}/${file}`);
    for (const name of names(adapter.definitions(e, owner))) {
      if (!exposed.has(name)) missing.push(`${file}:${name}`);
    }
  }

  assert.deepEqual(missing, [], `инструменты написаны, но не подключены к реестру: ${missing.join(', ')}`);
});

test('реестр не выдумывает инструментов сверх адаптеров', () => {
  const registry = require(`${hooks}/wesi_ai_tools.js`);
  const declared = new Set();
  for (const file of adapterFiles()) {
    for (const name of names(require(`${hooks}/${file}`).definitions(e, owner))) declared.add(name);
  }
  for (const name of names(registry.definitions(e, owner))) {
    assert.ok(declared.has(name), `реестр отдаёт ${name}, которого нет ни в одном адаптере`);
  }
});

test('horizon_snapshot доступен владельцу', () => {
  const registry = require(`${hooks}/wesi_ai_tools.js`);
  assert.ok(names(registry.definitions(e, owner)).includes('horizon_snapshot'));
});

test('horizon_snapshot скрыт без модуля forecast', () => {
  const registry = require(`${hooks}/wesi_ai_tools.js`);
  const employee = {isOwner: false, ownerId: 'owner-1', employeeId: 'emp-1', modules: ['ai']};
  assert.ok(!names(registry.definitions(e, employee)).includes('horizon_snapshot'));
});

test('execute отказывает по правам, а не по имени инструмента', () => {
  const registry = require(`${hooks}/wesi_ai_tools.js`);
  const employee = {isOwner: false, ownerId: 'owner-1', employeeId: 'emp-1', modules: ['ai']};
  const result = registry.execute(e, employee, 'horizon_snapshot', {}, 'org_wesi_inc');
  assert.equal(result.ok, false);
  assert.equal(result.code, 'FORBIDDEN');
});
