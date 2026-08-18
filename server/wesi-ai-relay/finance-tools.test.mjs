import assert from 'node:assert/strict';
import path from 'node:path';
import test from 'node:test';
import {createRequire} from 'node:module';
import {fileURLToPath} from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
globalThis.__hooks = path.resolve(here, '../pb_hooks');
const require = createRequire(import.meta.url);
const finance = require('../pb_hooks/wesi_ai_finance_tools.js');

function row(payload) {
  return {
    get(name) { return name === 'payload' ? payload : undefined; },
    getString(name) { return name === 'rid' ? String(payload.id || '') : ''; },
  };
}

function event({permissions = ['view'], includeSubtree = false} = {}) {
  const organizations = [
    row({id: 'org_wesi_inc', name: 'Wesi Inc', status: 'active', parentId: null, baseCurrency: 'RUB'}),
    row({id: 'music', name: 'Wesi Music', status: 'active', parentId: 'org_wesi_inc', baseCurrency: 'RUB'}),
    row({id: 'label', name: 'Label', status: 'active', parentId: 'music', baseCurrency: 'RUB'}),
  ];
  const grants = [row({employeeId: 'emp-1', organizationId: 'music', permissions, includeSubtree})];
  const transactions = [
    row({id: 'a', title: 'Продажа', organizationId: 'music', amount: 100000, type: 'income', date: '2026-08-02T12:00:00Z', category: 'Продажи'}),
    row({id: 'b', title: 'Реклама', organizationId: 'music', amount: 25000, type: 'expense', date: '2026-08-03T12:00:00Z', category: 'Маркетинг', isRecurring: true}),
    row({id: 'c', title: 'Чужая операция', organizationId: 'org_wesi_inc', amount: 999999, type: 'income', date: '2026-08-03T12:00:00Z'}),
    row({id: 'd', title: 'Label расход', organizationId: 'label', amount: 10000, type: 'expense', date: '2026-08-04T12:00:00Z'}),
  ];
  return {
    app: {
      findRecordsByFilter(_collection, filter, _sort, _limit, _offset, params) {
        if (filter.includes("coll='organizations'")) return organizations;
        if (filter.includes("coll='organization_grants'")) return grants;
        if (params?.coll === 'transactions' || filter.includes("coll='transactions'")) return transactions;
        return [];
      },
    },
  };
}

const ctx = {isOwner: false, ownerId: 'owner-1', employeeId: 'emp-1', modules: ['ai', 'treasury']};

test('finance tools require view_finance even when finance module is visible', () => {
  const result = finance.execute(event({permissions: ['view']}), ctx, 'finance_summary', {organizationId: 'music', from: '2026-08-01', to: '2026-08-31'}, 'music');
  assert.equal(result.ok, false);
  assert.equal(result.code, 'FORBIDDEN');
});

test('finance summary is calculated on Main from only authorized organization rows', () => {
  const result = finance.execute(event({permissions: ['view', 'view_finance']}), ctx, 'finance_summary', {organizationId: 'music', from: '2026-08-01', to: '2026-08-31'}, 'music');
  assert.equal(result.ok, true);
  assert.equal(result.result.income, 100000);
  assert.equal(result.result.expense, 25000);
  assert.equal(result.result.net, 75000);
  assert.equal(result.result.recurringExpense, 25000);
  assert.equal(result.result.transactionCount, 2);
  assert.equal(result.result.topExpenseCategories[0].category, 'Маркетинг');
});

test('view_finance subtree grant permits child organization but not parent', () => {
  const e = event({permissions: ['view', 'view_finance'], includeSubtree: true});
  const child = finance.execute(e, ctx, 'finance_summary', {organizationId: 'label', from: '2026-08-01', to: '2026-08-31'}, 'label');
  const parent = finance.execute(e, ctx, 'finance_summary', {organizationId: 'org_wesi_inc', from: '2026-08-01', to: '2026-08-31'}, 'org_wesi_inc');
  assert.equal(child.ok, true);
  assert.equal(child.result.expense, 10000);
  assert.equal(parent.ok, false);
  assert.equal(parent.code, 'FORBIDDEN');
});

// «Сколько денег на счету» — вопрос про остаток, а не про оборот за период.
//
// finance_summary считал только доходы и расходы внутри окна и не читал
// счета вообще. Если 500 рублей лежат как начальный остаток счёта, а в
// последние два месяца движений не было, инструмент возвращал нули — и
// Wesi AI уверенно отвечал «0», глядя мимо денег.
//
// Остаток обязан считаться ровно тем же правилом, что показывает экран
// «Казна»: openingBalance счёта плюс его доходы минус расходы, без
// повторяющихся шаблонов и без операций из будущего.
function balanceEvent({accounts, transactions}) {
  const organizations = [row({id: 'org_wesi_inc', name: 'Wesi Inc', status: 'active', parentId: null, baseCurrency: 'RUB'})];
  const grants = [row({employeeId: 'emp-1', organizationId: 'org_wesi_inc', permissions: ['view', 'view_finance'], includeSubtree: false})];
  return {
    app: {
      findRecordsByFilter(_collection, filter, _sort, _limit, _offset, params) {
        if (filter.includes("coll='organizations'")) return organizations;
        if (filter.includes("coll='organization_grants'")) return grants;
        if (params?.coll === 'transactions') return transactions.map(row);
        if (params?.coll === 'accounts') return accounts.map(row);
        return [];
      },
    },
  };
}

test('остаток счёта виден, даже когда за период не было ни одной операции', () => {
  const e = balanceEvent({
    accounts: [{id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500}],
    transactions: [],
  });
  const result = finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc');
  assert.equal(result.ok, true);
  assert.equal(result.result.currentBalance, 500);
  assert.equal(result.result.accounts.length, 1);
  assert.equal(result.result.accounts[0].balance, 500);
});

test('остаток считается как начальный плюс доходы минус расходы', () => {
  const e = balanceEvent({
    accounts: [{id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500}],
    transactions: [
      {id: 'i1', title: 'Продажа', organizationId: 'org_wesi_inc', accountId: 'main', amount: 300, type: 'income', date: '2026-08-02T12:00:00Z'},
      {id: 'e1', title: 'Реклама', organizationId: 'org_wesi_inc', accountId: 'main', amount: 100, type: 'expense', date: '2026-08-03T12:00:00Z'},
    ],
  });
  const result = finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc');
  assert.equal(result.result.currentBalance, 700);
});

test('операция без accountId попадает на основной счёт организации', () => {
  const e = balanceEvent({
    accounts: [{id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 0}],
    transactions: [{id: 'i1', title: 'Продажа', organizationId: 'org_wesi_inc', amount: 500, type: 'income', date: '2026-08-02T12:00:00Z'}],
  });
  assert.equal(finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc').result.currentBalance, 500);
});

test('повторяющийся шаблон не увеличивает остаток', () => {
  const e = balanceEvent({
    accounts: [{id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500}],
    transactions: [{id: 'r1', title: 'Подписка', organizationId: 'org_wesi_inc', accountId: 'main', amount: 900, type: 'income', date: '2026-08-02T12:00:00Z', isRecurring: true}],
  });
  assert.equal(finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc').result.currentBalance, 500);
});

test('операция из будущего в остаток не входит', () => {
  const future = new Date(Date.now() + 30 * 86400000).toISOString();
  const e = balanceEvent({
    accounts: [{id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500}],
    transactions: [{id: 'f1', title: 'Будущее', organizationId: 'org_wesi_inc', accountId: 'main', amount: 1000, type: 'income', date: future}],
  });
  assert.equal(finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc').result.currentBalance, 500);
});

test('архивный счёт в общий остаток не входит', () => {
  const e = balanceEvent({
    accounts: [
      {id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500},
      {id: 'old', name: 'Старый', organizationId: 'org_wesi_inc', openingBalance: 9000, archived: true},
    ],
    transactions: [],
  });
  const result = finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc');
  assert.equal(result.result.currentBalance, 500);
  assert.equal(result.result.accounts.length, 1);
});

test('чужая организация в остаток не подмешивается', () => {
  const e = balanceEvent({
    accounts: [
      {id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 500},
      {id: 'main:other', name: 'Чужой', organizationId: 'other', openingBalance: 100000},
    ],
    transactions: [{id: 'x', title: 'Чужая', organizationId: 'other', accountId: 'main:other', amount: 7000, type: 'income', date: '2026-08-02T12:00:00Z'}],
  });
  assert.equal(finance.execute(e, ctx, 'finance_summary', {}, 'org_wesi_inc').result.currentBalance, 500);
});
