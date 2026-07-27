'use strict';

const { filterAnomalies } = require('./anomalyFilter');
const { holtWintersForecast } = require('./holtWinters');
const { expandScheduledRules } = require('./scheduledLayer');
const { runMonteCarlo } = require('./monteCarlo');

function computeForecast(input) {
  const {
    currentBalance,
    transactions,
    scheduledRules = [],
    whatIfScenarios = [],
    horizonDays,
    startDate,
    distribution = 'normal',
    iterations = 5000,
  } = input;

  const { cleaned, statsByCategory } = filterAnomalies(transactions);

  const dailySeries = buildDailySeries(cleaned);
  const baseVariableForecast = holtWintersForecast(dailySeries.values, horizonDays);

  const scheduledTotals = expandScheduledRules(
    [...scheduledRules, ...whatIfScenarios],
    startDate,
    horizonDays
  );
  const dateList = buildDateList(startDate, horizonDays);
  const combinedForecast = dateList.map(
    (date, i) => baseVariableForecast[i] + (scheduledTotals[date] || 0)
  );

  const overallStd = averageCategoryStd(statsByCategory);
  const dailyStd = dateList.map(() => overallStd);

  const mc = runMonteCarlo(currentBalance, combinedForecast, dailyStd, {
    iterations,
    distribution,
  });

  const days_forecast = dateList.map((date, i) => ({
    date,
    p10_balance: round2(mc.p10[i]),
    p50_balance: round2(mc.p50[i]),
    p90_balance: round2(mc.p90[i]),
    cash_gap_probability: round4(mc.cashGapProbability[i]),
  }));

  const metrics = computeMetrics(days_forecast);

  return { days_forecast, metrics };
}

function buildDailySeries(transactions) {
  if (transactions.length === 0) return { dates: [], values: [] };
  const byDate = {};
  for (const t of transactions) {
    byDate[t.date] = (byDate[t.date] || 0) + t.amount;
  }
  const dates = Object.keys(byDate).sort();
  const first = new Date(dates[0] + 'T00:00:00Z');
  const last = new Date(dates[dates.length - 1] + 'T00:00:00Z');
  const values = [];
  const allDates = [];
  for (let d = new Date(first); d <= last; d.setUTCDate(d.getUTCDate() + 1)) {
    const iso = d.toISOString().slice(0, 10);
    allDates.push(iso);
    values.push(byDate[iso] || 0);
  }
  return { dates: allDates, values };
}

function buildDateList(startDateISO, horizonDays) {
  const start = new Date(startDateISO + 'T00:00:00Z');
  const dates = [];
  for (let d = 0; d < horizonDays; d++) {
    const cur = new Date(start);
    cur.setUTCDate(cur.getUTCDate() + d);
    dates.push(cur.toISOString().slice(0, 10));
  }
  return dates;
}

function averageCategoryStd(statsByCategory) {
  const stds = Object.values(statsByCategory).map((s) => s.std);
  if (stds.length === 0) return 0;
  return stds.reduce((a, b) => a + b, 0) / stds.length;
}

function computeMetrics(days_forecast) {
  let runway_days = days_forecast.length;
  let projected_min_balance = Infinity;
  let primary_risk_date = null;

  for (let i = 0; i < days_forecast.length; i++) {
    const day = days_forecast[i];
    if (day.p50_balance < projected_min_balance) {
      projected_min_balance = day.p50_balance;
    }
    if (runway_days === days_forecast.length && day.p50_balance < 0) {
      runway_days = i + 1;
    }
    if (primary_risk_date === null && day.cash_gap_probability > 0.5) {
      primary_risk_date = day.date;
    }
  }

  if (projected_min_balance === Infinity) projected_min_balance = 0;

  return {
    runway_days,
    projected_min_balance: round2(projected_min_balance),
    primary_risk_date,
  };
}

function round2(n) {
  return Math.round(n * 100) / 100;
}
function round4(n) {
  return Math.round(n * 10000) / 10000;
}

module.exports = { computeForecast };
