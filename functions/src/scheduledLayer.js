'use strict';

function expandScheduledRules(rules, startDateISO, horizonDays) {
  const dailyTotals = {};
  const start = new Date(startDateISO + 'T00:00:00Z');

  for (let d = 0; d < horizonDays; d++) {
    const current = addDays(start, d);
    const iso = toISO(current);
    let dayTotal = 0;

    for (const rule of rules) {
      if (!isRuleActiveOn(rule, current)) continue;
      if (matchesRule(rule.rule, current)) {
        dayTotal += rule.amount;
      }
    }
    if (dayTotal !== 0) dailyTotals[iso] = (dailyTotals[iso] || 0) + dayTotal;
  }

  return dailyTotals;
}

function isRuleActiveOn(rule, date) {
  const start = rule.startDate ? new Date(rule.startDate + 'T00:00:00Z') : null;
  const end = rule.endDate ? new Date(rule.endDate + 'T00:00:00Z') : null;
  if (start && date < start) return false;
  if (end && date > end) return false;
  return true;
}

function matchesRule(rule, date) {
  switch (rule.type) {
    case 'once':
      return toISO(date) === rule.date;
    case 'daily':
      return true;
    case 'weekly':
      return (rule.daysOfWeek || []).includes(date.getUTCDay());
    case 'monthly': {
      const day = date.getUTCDate();
      const lastDayOfMonth = new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0)).getUTCDate();
      const targetDay = Math.min(rule.dayOfMonth, lastDayOfMonth);
      return day === targetDay;
    }
    default:
      return false;
  }
}

function addDays(date, n) {
  const copy = new Date(date);
  copy.setUTCDate(copy.getUTCDate() + n);
  return copy;
}

function toISO(date) {
  return date.toISOString().slice(0, 10);
}

module.exports = { expandScheduledRules, matchesRule, isRuleActiveOn };
