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
