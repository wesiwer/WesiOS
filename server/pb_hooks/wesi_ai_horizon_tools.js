function rows(e, ctx, coll) {
  try {
    return e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll={:coll} && deleted=false",
      "-stamp",
      0,
      0,
      {owner: ctx.ownerId, coll: coll},
    );
  } catch (_) {
    return [];
  }
}

function round(value) {
  return Math.round((Number(value) + Number.EPSILON) * 100) / 100;
}

function date(value) {
  const parsed = new Date(String(value || ""));
  return Number.isFinite(parsed.getTime()) ? parsed : null;
}

module.exports = {
  definitions: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) return [];
    return [{
      name: "horizon_snapshot",
      description: "Прочитать на основном сервере Wesi разрешённый ledger snapshot для Horizon. Требуются view_forecast и view_finance. Результат не выдаётся за полный клиентский Monte-Carlo Horizon.",
      parameters: {
        type: "object",
        properties: {organizationId: {type: "string"}},
      },
    }];
  },

  context: function(e, ctx) {
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) return {horizonOrganizations: []};
    const state = policy.access(e, ctx);
    return {horizonOrganizations: Object.keys(state.forecastOrgIds)
      .filter((id) => state.forecastOrgIds[id] === true && state.orgs[id])
      .map((id) => ({id: id, name: state.orgs[id].name, baseCurrency: state.orgs[id].baseCurrency}))};
  },

  execute: function(e, ctx, name, args, activeOrganizationId) {
    if (name !== "horizon_snapshot") {
      return {ok: false, code: "UNKNOWN_TOOL", message: "Неизвестный Horizon-инструмент"};
    }
    const policy = require(`${__hooks}/wesi_ai_horizon_policy.js`);
    if (!policy.hasForecastModule(ctx)) {
      return {ok: false, code: "FORBIDDEN", message: "Нет доступа к модулю Horizon"};
    }
    const input = args && typeof args === "object" ? args : {};
    const state = policy.access(e, ctx);
    const organizationId = policy.select(
      state,
      String(input.organizationId || activeOrganizationId || ""),
    );
    if (!organizationId) {
      return {ok: false, code: "FORBIDDEN", message: "Для Horizon нужны view_forecast и view_finance этой организации"};
    }

    let balance = 0;
    let income = 0;
    let expense = 0;
    let count = 0;
    const now = new Date();
    const historyStart = new Date(now.getTime() - 90 * 86400000);
    const accounts = rows(e, ctx, "accounts");
    const transactions = rows(e, ctx, "transactions");

    for (const row of accounts) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId || p.archived === true) continue;
      const opening = Number(p.openingBalance || 0);
      if (Number.isFinite(opening)) balance += opening;
    }

    for (const row of transactions) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      if (p.isRecurring === true) continue;
      const amount = Number(p.amount);
      const at = date(p.date);
      if (!Number.isFinite(amount) || amount < 0 || !at || at > now) continue;
      const signed = String(p.type || "expense") === "income" ? amount : -amount;
      balance += signed;
      if (at >= historyStart) {
        count++;
        if (signed >= 0) income += amount;
        else expense += amount;
      }
    }

    const spendPerDay = expense / 90;
    return {ok: true, result: {
      engine: "Wesi Horizon",
      engineScope: "server-ledger",
      fullClientMonteCarlo: false,
      organizationId: organizationId,
      organizationName: state.orgs[organizationId].name,
      reportingCurrency: state.orgs[organizationId].baseCurrency,
      asOf: now.toISOString(),
      currentBalance: round(balance),
      recent90Days: {
        transactionCount: count,
        income: round(income),
        expense: round(expense),
        net: round(income - expense),
        spendPerDay: round(spendPerDay),
      },
      cushionDays: spendPerDay > 0 ? Math.max(0, Math.floor(balance / spendPerDay)) : null,
      caveat: "Full client Horizon Monte-Carlo/calibration/business-context is not reproduced by this server snapshot.",
    }};
  },
};
