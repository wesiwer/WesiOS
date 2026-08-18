// Каждый инструмент Wesi AI должен реально работать, а не только существовать.
//
// Реестр уже проверяется на полноту (tools-registry.test.mjs), но досягаемость
// — не работоспособность. Инструмент может значиться в списке и падать на
// первом же вызове, возвращать пустоту при живых данных или молча ничего не
// сохранять. Ровно так вышло с деньгами: finance_summary отвечал «0», потому
// что не читал счета вовсе.
//
// Здесь каждый объявленный инструмент вызывается: читающие — на данных той же
// формы, что пишет приложение; пишущие — с проверкой, что строка сохранена;
// разрушающие — через полный цикл подтверждения.
import assert from 'node:assert/strict';
import test from 'node:test';
import {createRequire} from 'node:module';
import {readdirSync, readFileSync} from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';

const hooks = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../pb_hooks');
globalThis.__hooks = hooks;
globalThis.$security = {
  randomString: (n) => 'X'.repeat(Number(n) || 24),
  sha256: (s) => 'sha' + String(s).length,
  hs256: () => 'sig',
  equal: (a, b) => a === b,
};
globalThis.Record = class {
  constructor() { this.values = {}; }
  set(k, v) { this.values[k] = v; }
  get(k) { return this.values[k]; }
  getString(k) { return String(this.values[k] ?? ''); }
  getBool(k) { return this.values[k] === true; }
};
class PbError extends Error {}
for (const n of ['BadRequestError', 'ForbiddenError', 'NotFoundError', 'UnauthorizedError']) {
  globalThis[n] = class extends PbError {};
}
globalThis.$os = {getenv: () => '', dirFS: () => ({})};
globalThis.$http = {send: () => ({statusCode: 503, json: {ok: false}})};

const require = createRequire(import.meta.url);
const registry = require(path.join(hooks, 'wesi_ai_tools.js'));
const ORG = 'org_wesi_inc';
const OWNER = {isOwner: true, ownerId: 'owner-1', employeeId: 'owner', modules: ['ai']};

// Записи PocketBase, а не голые объекты: инструменты зовут getString/getBool.
function row(payload, coll) {
  const fields = {payload, coll, rid: String(payload.id || ''), org: String(payload.organizationId || ''), deleted: false, stamp: ''};
  return {
    get: (k) => fields[k],
    getString: (k) => String(fields[k] ?? ''),
    getBool: (k) => fields[k] === true,
    getDateTime: (k) => fields[k] || '',
    set(k, v) { fields[k] = v; },
  };
}

const now = new Date();
const iso = (ms) => new Date(ms).toISOString();
const day = 86400000;

// Формы полей взяты из toJson() клиентских моделей. Если сервер начнёт читать
// поле, которого приложение не пишет, соответствующая проверка опустеет.
function freshData() {
  return {
    organizations: [row({id: ORG, name: 'Wesi Inc', status: 'active', parentId: null, baseCurrency: 'RUB'}, 'organizations')],
    organization_grants: [],
    employees: [row({id: 'emp-1', login: 'one', fullName: 'Иван', position: 'Менеджер', permissions: {modules: ['ai']}}, 'employees')],
    accounts: [row({id: 'main', name: 'Основной', organizationId: ORG, openingBalance: 500}, 'accounts')],
    transactions: [
      row({id: 't1', title: 'Продажа', organizationId: ORG, accountId: 'main', amount: 300, type: 'income', date: iso(now.getTime() - 5 * day), category: 'Продажи'}, 'transactions'),
      row({id: 't2', title: 'Реклама', organizationId: ORG, accountId: 'main', amount: 100, type: 'expense', date: iso(now.getTime() - 3 * day), category: 'Маркетинг'}, 'transactions'),
    ],
    tasks: [row({id: 'task-1', title: 'Проверить рекламу', organizationId: ORG, stage: 'todo', dueDate: iso(now.getTime() + 3 * day)}, 'tasks')],
    articles: [row({id: 'a1', title: 'Регламент', body: 'Текст регламента про отпуск', organizationId: ORG, parentId: null, section: 'playbook'}, 'articles')],
    calendar_events: [row({id: 'ev1', title: 'Встреча', notes: 'обсудить рекламу', startAt: iso(now.getTime() + day), durationMinutes: 60, allDay: false, repeat: 'none', reminderMinutesBefore: 15, enabled: true}, 'calendar_events')],
    crm_clients: [row({id: 'c1', name: 'ООО Ромашка', company: 'Ромашка', phone: '+70000000000', email: 'a@b.c', source: 'сайт', status: 'active', notes: '', tags: [], organizationId: ORG, ownerEmployeeId: 'emp-1', nextContactAt: null, createdAt: iso(now.getTime() - 30 * day), updatedAt: iso(now.getTime())}, 'crm_clients')],
    crm_deals: [row({id: 'd1', clientId: 'c1', title: 'Поставка', amount: 50000, currency: 'RUB', stage: 'newLead', probability: 30, notes: '', tags: [], organizationId: ORG, responsibleEmployeeId: 'emp-1', expectedCloseAt: iso(now.getTime() + 20 * day), createdAt: iso(now.getTime() - 10 * day), updatedAt: iso(now.getTime())}, 'crm_deals')],
    crm_interactions: [],
    roadmap_projects: [row({id: 'p1', title: 'Проект', description: '', owner: '', tags: [], startDate: iso(now.getTime() - 30 * day), endDate: iso(now.getTime() + 60 * day), archived: false}, 'roadmap_projects')],
    roadmap_items: [row({id: 'r1', projectId: 'p1', title: 'Веха', description: '', kind: 'phase', status: 'planned', assignee: '', startDate: iso(now.getTime() - 7 * day), endDate: iso(now.getTime() + 7 * day), progress: 0, order: 0}, 'roadmap_items')],
    audio_beats: [row({id: 'au1', title: 'Трек', organizationId: ORG}, 'audio_beats')],
  };
}

function harness() {
  let data = freshData();
  const saved = [];
  const app = {
    findRecordsByFilter(_c, filter, _s, _l, _o, params) {
      const named = params?.coll;
      const literal = Object.keys(data).find((k) => filter.includes(`coll='${k}'`));
      const pool = data[named || literal] || [];
      const rid = params?.rid;
      return rid ? pool.filter((r) => r.getString('rid') === String(rid)) : pool;
    },
    findFirstRecordByFilter(c, f, p) {
      const r = app.findRecordsByFilter(c, f, '', 1, 0, p);
      return r.length ? r[0] : null;
    },
    findCollectionByNameOrId: () => ({}),
    runInTransaction: (fn) => fn(app),
    save(rec) {
      saved.push(rec);
      // Сохранённое обязано стать видимым для последующих чтений, иначе
      // подтверждение действия не найдёт собственный билет.
      const coll = rec.getString ? rec.getString('coll') : '';
      if (!coll) return;
      if (!data[coll]) data[coll] = [];
      const rid = String(rec.getString('rid') || '');
      const idx = data[coll].findIndex((r) => r.getString('rid') === rid);
      if (idx >= 0) data[coll][idx] = rec; else data[coll].push(rec);
    },
    delete() {},
  };
  const e = {app, auth: {id: 'auth-1'}, request: {header: {get: () => 'session-1'}}, requestInfo: () => ({body: {}})};
  return {e, saved};
}

function declaredNames() {
  const names = new Map();
  for (const file of readdirSync(hooks).filter((f) => /^wesi_ai_.*(_tools|connector)\.js$/.test(f))) {
    const src = readFileSync(path.join(hooks, file), 'utf8');
    for (const m of src.matchAll(/name:\s*"([a-z][a-z0-9_]*)"/g)) {
      if (!names.has(m[1])) names.set(m[1], file);
    }
  }
  return names;
}

test('ни один инструмент не падает с программной ошибкой', () => {
  const {e} = harness();
  const crashed = [];
  for (const [name, file] of declaredNames()) {
    try {
      const out = registry.execute(e, OWNER, name, {}, ORG, {});
      if (!out || typeof out !== 'object' || !('ok' in out)) crashed.push(`${name} (${file}): вернул не результат`);
    } catch (err) {
      // Отказ политики — нормальный ответ. Программная ошибка — нет.
      if (!(err instanceof PbError)) crashed.push(`${name} (${file}): ${err.constructor.name}: ${err.message}`);
    }
  }
  assert.deepEqual(crashed, [], `инструменты падают на пустых аргументах:\n${crashed.join('\n')}`);
});

const READS = [
  ['tasks_list', {}, (r) => r.tasks.length === 1],
  ['finance_summary', {}, (r) => r.currentBalance === 700 && r.accounts.length === 1],
  ['finance_transactions', {limit: 10}, (r) => r.transactionCount === 2],
  ['horizon_snapshot', {}, (r) => r.currentBalance === 700],
  ['organizations_list', {}, (r) => r.organizations.length === 1],
  ['calendar_events', {}, (r) => r.events.length === 1],
  ['knowledge_search', {query: 'отпуск'}, (r) => r.articles.length === 1],
  ['knowledge_article', {articleId: 'a1'}, (r) => r.article.title === 'Регламент'],
  ['crm_clients', {}, (r) => r.clients.length === 1],
  ['crm_deals', {}, (r) => r.deals.length === 1],
  ['crm_pipeline_summary', {}, (r) => r.openCount === 1 && r.openAmount === 50000],
  ['roadmap_list', {}, (r) => r.projects.length === 1 && r.items.length === 1],
  ['audio_vault_list', {}, (r) => r.beats.length === 1],
  ['team_list', {}, (r) => r.employees.length === 1],
];

for (const [name, args, check] of READS) {
  test(`${name} возвращает живые данные`, () => {
    const {e} = harness();
    const out = registry.execute(e, OWNER, name, args, ORG, {});
    assert.equal(out.ok, true, `${name}: ${out.code} ${out.message || ''}`);
    assert.ok(check(out.result), `${name} отработал, но вернул не те данные: ${JSON.stringify(out.result).slice(0, 300)}`);
  });
}

const RENDERS = [
  ['render_table', {title: 'Итоги', columns: ['Месяц', 'Сумма'], rows: [['Июль', '100']]}, 'table'],
  ['render_chart', {title: 'Динамика', chartType: 'line', labels: ['Июль'], series: [{name: 'Доход', values: [100]}]}, 'chart'],
  ['render_diagram', {title: 'Схема', nodes: [{id: 'a', label: 'Старт'}], edges: []}, 'diagram'],
];

for (const [name, args, kind] of RENDERS) {
  test(`${name} собирает блок для сообщения`, () => {
    const {e} = harness();
    const out = registry.execute(e, OWNER, name, args, ORG, {});
    assert.equal(out.ok, true, `${name}: ${out.code} ${out.message || ''}`);
    assert.equal(out.result.contentBlock.type, kind);
  });
}

const WRITES = [
  ['tasks_create', {title: 'Новая задача', description: 'Проверить рекламу', priority: 'normal'}],
  ['tasks_update', {taskId: 'task-1', title: 'Переименованная задача'}],
  ['finance_transaction_create', {title: 'Аренда', amount: 1000, type: 'expense', date: iso(now.getTime()), accountId: 'main', category: 'Офис'}],
  ['finance_transaction_update', {transactionId: 't1', title: 'Продажа (уточнено)'}],
  ['calendar_create', {title: 'Планёрка', startAt: iso(now.getTime() + 2 * day), durationMinutes: 30}],
  ['calendar_update', {eventId: 'ev1', title: 'Встреча перенесена'}],
  ['crm_client_create', {name: 'ООО Новый', phone: '+79990000000'}],
  ['crm_client_update', {clientId: 'c1', company: 'Ромашка Плюс'}],
  ['crm_deal_create', {clientId: 'c1', title: 'Новая сделка', amount: 1000, stage: 'newLead'}],
  ['crm_deal_update', {dealId: 'd1', amount: 60000}],
  ['crm_interaction_create', {clientId: 'c1', kind: 'call', title: 'Созвон', details: 'Обсудили поставку'}],
  ['knowledge_create', {title: 'Новая статья', text: 'Тело статьи'}],
  ['knowledge_update', {articleId: 'a1', title: 'Регламент 2'}],
  ['roadmap_create', {entityType: 'item', projectId: 'p1', title: 'Новая веха', kind: 'phase', status: 'planned', startDate: iso(now.getTime()), endDate: iso(now.getTime() + 14 * day)}],
  ['roadmap_update', {entityType: 'item', id: 'r1', status: 'inProgress'}],
  ['audio_vault_update', {beatId: 'au1', stage: 'production'}],
];

for (const [name, args] of WRITES) {
  test(`${name} действительно сохраняет строку`, () => {
    const {e, saved} = harness();
    const out = registry.execute(e, OWNER, name, args, ORG, {});
    assert.equal(out.ok, true, `${name}: ${out.code} ${out.message || ''}`);
    assert.ok(saved.length > 0, `${name} ответил ok, но ничего не сохранил`);
  });
}

const DESTRUCTIVE = [
  ['tasks_archive', {taskId: 'task-1'}],
  ['finance_transaction_delete', {transactionId: 't2'}],
  ['calendar_delete', {eventId: 'ev1'}],
  ['crm_client_archive', {clientId: 'c1'}],
  ['crm_deal_archive', {dealId: 'd1'}],
  ['knowledge_archive', {articleId: 'a1'}],
  ['roadmap_archive', {entityType: 'item', id: 'r1'}],
];

for (const [name, args] of DESTRUCTIVE) {
  test(`${name} требует подтверждения и выполняется после него`, () => {
    const {e, saved} = harness();
    const pending = registry.execute(e, OWNER, name, args, ORG, {});
    assert.equal(pending.ok, false);
    assert.equal(pending.code, 'CONFIRMATION_REQUIRED', `${name} выполнил разрушающее действие без подтверждения`);
    assert.ok(pending.confirmation?.id, `${name}: подтверждение без идентификатора`);
    const done = registry.confirm(e, OWNER, pending.confirmation.id);
    assert.equal(done.ok, true, `${name}: подтверждение не сработало (${done.code})`);
    assert.ok(saved.length > 0, `${name} подтверждён, но ничего не изменил`);
  });
}

// Медиа выполняется на устройстве: сервер отдаёт разобранный запрос, а не
// зовёт провайдера сам. Проверяется, что запрос собирается и несёт workflow.
const MEDIA = [
  ['generate_image', {prompt: 'Обложка для трека', title: 'Обложка', aspectRatio: '1:1'}, 'image'],
  ['generate_music', {prompt: 'Тёмный трэп бит', title: 'Бит', mode: 'clip', format: 'mp3'}, 'music'],
  ['generate_video', {prompt: 'Клип: город ночью', title: 'Клип'}, 'video'],
  ['edit_image', {prompt: 'Убрать фон', attachmentIndex: 0}, 'image'],
  ['export_music', {attachmentIndexes: [0], target: 'master', format: 'wav'}, 'music'],
  ['add_video_subtitles', {attachmentIndex: 0, text: 'Субтитры'}, 'video'],
];

for (const [name, args, mediaType] of MEDIA) {
  test(`${name} собирает корректный медиазапрос`, () => {
    const {e} = harness();
    const out = registry.execute(e, OWNER, name, args, ORG, {});
    assert.equal(out.ok, true, `${name}: ${out.code} ${out.message || ''}`);
    const request = out.result.localMediaRequest;
    assert.ok(request, `${name} не вернул медиазапрос`);
    assert.equal(request.mediaType, mediaType);
    assert.ok(String(request.workflow || '').length > 0, `${name}: пустой workflow`);
  });
}

test('производные медиаинструменты не работают без вложений', () => {
  const {e} = harness();
  const out = registry.execute(e, OWNER, 'edit_image', {prompt: 'Убрать фон'}, ORG, {});
  assert.equal(out.ok, false);
  assert.equal(out.code, 'WAI_MEDIA_INPUT_REQUIRED');
});

test('каждый GitHub-инструмент имеет обработчик, а не проваливается в общий отказ', () => {
  const src = readFileSync(path.join(hooks, 'wesi_ai_github_connector.js'), 'utf8');
  const declared = [...new Set([...src.matchAll(/name:\s*"(github_[a-z_]+)"/g)].map((m) => m[1]))];
  assert.ok(declared.length >= 15, `объявлено всего ${declared.length} GitHub-инструментов`);
  const missing = declared.filter((name) => !src.includes(`"${name}"`, src.indexOf('execute')));
  assert.deepEqual(missing, [], `GitHub-инструменты без обработчика: ${missing.join(', ')}`);
});

test('GitHub закрыт, пока аккаунт не подключён', () => {
  const {e} = harness();
  const out = registry.execute(e, OWNER, 'github_repositories_list', {}, ORG, {});
  assert.equal(out.ok, false);
  assert.equal(out.code, 'FORBIDDEN');
});
