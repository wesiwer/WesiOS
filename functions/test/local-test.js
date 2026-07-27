'use strict';

const { computeForecast } = require('../src/forecastEngine');

function generateHistory() {
  const transactions = [];
  const start = new Date('2026-05-28T00:00:00Z');
  for (let d = 0; d < 60; d++) {
    const date = new Date(start);
    date.setUTCDate(date.getUTCDate() + d);
    const iso = date.toISOString().slice(0, 10);
    const dow = date.getUTCDay();

    const isWeekday = dow >= 1 && dow <= 5;
    const income = isWeekday ? 3000 + Math.random() * 1500 : 300 + Math.random() * 400;
    transactions.push({ date: iso, category: 'Продажи', amount: Math.round(income) });

    const expense = 1200 + Math.random() * 300;
    transactions.push({ date: iso, category: 'Операционные', amount: -Math.round(expense) });
  }

  transactions.push({ date: '2026-06-15', category: 'Операционные', amount: -45000 });

  return transactions;
}

const transactions = generateHistory();

const scheduledRules = [
  {
    id: 'rent',
    amount: -25000,
    category: 'Аренда',
    rule: { type: 'monthly', dayOfMonth: 1 },
    startDate: '2026-01-01',
  },
  {
    id: 'salary-5',
    amount: -60000,
    category: 'Зарплата',
    rule: { type: 'monthly', dayOfMonth: 5 },
    startDate: '2026-01-01',
  },
  {
    id: 'salary-20',
    amount: -60000,
    category: 'Зарплата',
    rule: { type: 'monthly', dayOfMonth: 20 },
    startDate: '2026-01-01',
  },
];

const whatIfScenarios = [
  {
    id: 'whatif-mic',
    amount: -18000,
    category: 'Оборудование',
    rule: { type: 'once', date: '2026-08-06' },
  },
];

const result = computeForecast({
  currentBalance: 50000,
  transactions,
  scheduledRules,
  whatIfScenarios,
  horizonDays: 30,
  startDate: '2026-07-28',
  distribution: 'normal',
  iterations: 5000,
});

console.log('=== Первые 5 дней прогноза ===');
console.table(result.days_forecast.slice(0, 5));

console.log('
=== Последние 5 дней прогноза ===');
console.table(result.days_forecast.slice(-5));

console.log('
=== Metrics ===');
console.log(result.metrics);

const assert = require('assert');

assert.strictEqual(result.days_forecast.length, 30, 'Должно быть 30 дней прогноза');

for (const day of result.days_forecast) {
  assert.ok(day.p10_balance <= day.p50_balance + 0.01, `P10 не должен быть больше P50 (${day.date})`);
  assert.ok(day.p50_balance <= day.p90_balance + 0.01, `P50 не должен быть больше P90 (${day.date})`);
  assert.ok(
    day.cash_gap_probability >= 0 && day.cash_gap_probability <= 1,
    'cash_gap_probability должен быть в [0,1]'
  );
}

assert.ok(
  result.metrics.runway_days >= 1 && result.metrics.runway_days <= 30,
  'runway_days должен быть в пределах горизонта'
);

console.log('
✅ Все базовые проверки пройдены. Движок работает корректно.');
