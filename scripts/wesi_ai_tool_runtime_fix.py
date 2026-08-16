from pathlib import Path

GATEWAY = Path('server/wesi-ai-stream/gateway.mjs')
GATEWAY_TEST = Path('server/wesi-ai-stream/gateway.test.mjs')
FINANCE = Path('server/pb_hooks/wesi_ai_finance_tools.js')
BALANCE = Path('server/pb_hooks/wesi_ai_finance_balance.js')
BALANCE_TEST = Path('server/wesi-ai-stream/finance_balance.test.mjs')


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if new in text:
        return text
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one marker, found {count}')
    return text.replace(old, new, 1)


gateway = GATEWAY.read_text()
gateway = replace_once(
    gateway,
    "export const MAX_TOOL_TURNS = 4;\n",
    "export const MAX_TOOL_TURNS = 4;\nexport const TOOL_STREAM_HOLDBACK_CHARS = 2048;\nexport const MAX_TOOL_ENVELOPE_CHARS = 32 * 1024;\n",
    'gateway constants',
)

old_parser = r'''export function parseToolRequest(answer) {
  let text = String(answer || '').trim();
  if (text.startsWith('```json') && text.lastIndexOf('```') > 6) {
    text = text.slice(7, text.lastIndexOf('```')).trim();
  } else if (text.startsWith('```') && text.lastIndexOf('```') > 3) {
    text = text.slice(3, text.lastIndexOf('```')).trim();
  }
  try {
    const parsed = JSON.parse(text);
    const tool = parsed && typeof parsed.wesiTool === 'object' ? parsed.wesiTool : null;
    if (!tool) return null;
    const name = String(tool.name || '').trim();
    const args = tool.arguments && typeof tool.arguments === 'object' && !Array.isArray(tool.arguments)
      ? tool.arguments
      : {};
    return name ? {name, arguments: args} : null;
  } catch {
    return null;
  }
}

export function shouldRevealBufferedText(buffer) {
  const trimmed = String(buffer || '').trimStart();
  if (!trimmed) return false;
  if (!trimmed.startsWith('{') && !trimmed.startsWith('```')) return true;
  if (trimmed.includes('"wesiTool"') || trimmed.includes("'wesiTool'")) return false;
  return trimmed.length >= 512;
}
'''

new_parser = r'''function normalizeToolEnvelope(parsed, allowedToolNames = null) {
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return null;
  if (!Object.prototype.hasOwnProperty.call(parsed, 'wesiTool')) return null;
  const tool = parsed.wesiTool;
  if (!tool || typeof tool !== 'object' || Array.isArray(tool)) return null;
  const name = String(tool.name || '').trim();
  if (!/^[A-Za-z0-9_.:-]{1,120}$/.test(name)) return null;
  if (Array.isArray(allowedToolNames) && allowedToolNames.length > 0 && !allowedToolNames.includes(name)) {
    return null;
  }
  const args = tool.arguments && typeof tool.arguments === 'object' && !Array.isArray(tool.arguments)
    ? tool.arguments
    : {};
  try {
    if (JSON.stringify(args).length > MAX_TOOL_ENVELOPE_CHARS) return null;
  } catch {
    return null;
  }
  return {name, arguments: args};
}

function parseToolEnvelopeText(text, allowedToolNames) {
  try {
    return normalizeToolEnvelope(JSON.parse(text), allowedToolNames);
  } catch {
    return null;
  }
}

function balancedObjectEnd(text, start) {
  let depth = 0;
  let inString = false;
  let escaped = false;
  for (let index = start; index < text.length; index += 1) {
    const ch = text[index];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch === '\\') {
        escaped = true;
      } else if (ch === '"') {
        inString = false;
      }
      continue;
    }
    if (ch === '"') {
      inString = true;
      continue;
    }
    if (ch === '{') depth += 1;
    if (ch === '}') {
      depth -= 1;
      if (depth === 0) return index;
      if (depth < 0) return -1;
    }
    if (index - start + 1 > MAX_TOOL_ENVELOPE_CHARS) return -1;
  }
  return -1;
}

export function parseToolRequest(answer, allowedToolNames = null) {
  const text = String(answer || '').trim();
  if (!text) return null;

  const exact = parseToolEnvelopeText(text, allowedToolNames);
  if (exact) return exact;

  for (let start = text.indexOf('{'); start >= 0; start = text.indexOf('{', start + 1)) {
    const end = balancedObjectEnd(text, start);
    if (end < 0) continue;
    const candidate = text.slice(start, end + 1);
    const parsed = parseToolEnvelopeText(candidate, allowedToolNames);
    if (parsed) return parsed;
  }
  return null;
}

function hasToolMarker(value) {
  return /["']wesiTool["']\s*:/.test(String(value || ''));
}

export function shouldRevealBufferedText(buffer, holdbackChars = TOOL_STREAM_HOLDBACK_CHARS) {
  const text = String(buffer || '');
  const trimmed = text.trimStart();
  if (!trimmed) return false;
  if (hasToolMarker(text)) return false;
  return text.length > Math.max(0, Number(holdbackChars) || 0);
}
'''

gateway = replace_once(gateway, old_parser, new_parser, 'robust tool parser')

old_stream = r'''async function streamOneTurn({prepared, toolResults, phase, finalOnly, relayUrl, relaySecret, signal, fetchImpl, res}) {
  let full = '';
  let buffer = '';
  let revealed = false;
  const onDelta = (text) => {
    full += text;
    if (finalOnly || revealed) {
      writeNdjson(res, {type: 'delta', text});
      return;
    }
    buffer += text;
    if (shouldRevealBufferedText(buffer)) {
      revealed = true;
      writeNdjson(res, {type: 'delta', text: buffer});
      buffer = '';
    }
  };
  await relayStream({
    relayUrl,
    relaySecret,
    payload: relayPayload(prepared, toolResults, phase, finalOnly),
    signal,
    fetchImpl,
    onDelta,
  });
  return {full, buffer, revealed};
}
'''

new_stream = r'''async function streamOneTurn({prepared, toolResults, phase, finalOnly, relayUrl, relaySecret, signal, fetchImpl, res}) {
  let full = '';
  let buffer = '';
  let revealed = false;
  const guardToolProtocol = Array.isArray(prepared.toolNames) && prepared.toolNames.length > 0;
  const onDelta = (text) => {
    full += text;
    if (!guardToolProtocol) {
      revealed = true;
      writeNdjson(res, {type: 'delta', text});
      return;
    }

    buffer += text;
    if (hasToolMarker(buffer)) return;
    if (shouldRevealBufferedText(buffer)) {
      const safeLength = Math.max(0, buffer.length - TOOL_STREAM_HOLDBACK_CHARS);
      if (safeLength > 0) {
        const safe = buffer.slice(0, safeLength);
        buffer = buffer.slice(safeLength);
        revealed = true;
        writeNdjson(res, {type: 'delta', text: safe});
      }
    }
  };
  await relayStream({
    relayUrl,
    relaySecret,
    payload: relayPayload(prepared, toolResults, phase, finalOnly),
    signal,
    fetchImpl,
    onDelta,
  });
  return {full, buffer, revealed};
}
'''

gateway = replace_once(gateway, old_stream, new_stream, 'stream tool guard')
gateway = replace_once(
    gateway,
    "        const toolRequest = streamed.revealed ? null : parseToolRequest(streamed.full);\n",
    "        const toolRequest = parseToolRequest(streamed.full, prepared.toolNames);\n",
    'parse regardless of reveal',
)

old_final = r'''      const totalDiff = aggregateDiffStats(toolResults);
      writeNdjson(res, {
        type: 'agent',
        phase: 'result',
        name: prepared.persona,
        role: 'lead',
        additions: totalDiff.additions,
        deletions: totalDiff.deletions,
        files: totalDiff.files,
      });
      writeNdjson(res, {
        type: 'done',
        requestId: prepared.requestId,
        answer: finalStream.full,
        toolResults,
      });
'''
new_final = r'''      const refusedFinalTool = parseToolRequest(finalStream.full, prepared.toolNames);
      const finalAnswer = refusedFinalTool
        ? 'Не удалось завершить ответ после нескольких обращений к инструментам. Повтори запрос — внутренний вызов не был показан в чате.'
        : finalStream.full;
      if (refusedFinalTool) {
        writeNdjson(res, {type: 'delta', text: finalAnswer});
      } else if (finalStream.buffer) {
        writeNdjson(res, {type: 'delta', text: finalStream.buffer});
      }
      const totalDiff = aggregateDiffStats(toolResults);
      writeNdjson(res, {
        type: 'agent',
        phase: 'result',
        name: prepared.persona,
        role: 'lead',
        additions: totalDiff.additions,
        deletions: totalDiff.deletions,
        files: totalDiff.files,
      });
      writeNdjson(res, {
        type: 'done',
        requestId: prepared.requestId,
        answer: finalAnswer,
        toolResults,
      });
'''
gateway = replace_once(gateway, old_final, new_final, 'final tool leak guard')
GATEWAY.write_text(gateway)

# Gateway regressions: exact envelope, embedded envelope, screenshot-style trailing prose,
# and holdback semantics.
test_text = GATEWAY_TEST.read_text()
test_text = replace_once(
    test_text,
    "import {createGateway, parseToolRequest, shouldRevealBufferedText, signRelayRequest} from './gateway.mjs';\n",
    "import {createGateway, parseToolRequest, shouldRevealBufferedText, signRelayRequest, TOOL_STREAM_HOLDBACK_CHARS} from './gateway.mjs';\n",
    'gateway test import',
)
old_parser_test = r'''test('tool parser accepts only structured Wesi tool envelope', () => {
  assert.deepEqual(
    parseToolRequest('{"wesiTool":{"name":"tasks_list","arguments":{"limit":3}}}'),
    {name: 'tasks_list', arguments: {limit: 3}},
  );
  assert.equal(parseToolRequest('Обычный ответ'), null);
});

test('stream sniffer reveals normal text but withholds tool JSON', () => {
  assert.equal(shouldRevealBufferedText('Привет'), true);
  assert.equal(shouldRevealBufferedText('{"wesiTool":'), false);
  assert.equal(shouldRevealBufferedText('```json\n{"wesiTool":'), false);
});
'''
new_parser_test = r'''test('tool parser accepts exact and embedded Wesi tool envelopes', () => {
  const expected = {name: 'tasks_list', arguments: {limit: 3}};
  const envelope = '{"wesiTool":{"name":"tasks_list","arguments":{"limit":3}}}';
  assert.deepEqual(parseToolRequest(envelope), expected);
  assert.deepEqual(parseToolRequest(`${envelope}\n\nСейчас глянем результат.`), expected);
  assert.deepEqual(parseToolRequest(`Сейчас проверю.\n${envelope}\nНе используй это как финальный ответ.`), expected);
  assert.equal(parseToolRequest(envelope, ['finance_summary']), null);
  assert.equal(parseToolRequest('Обычный ответ'), null);
});

test('stream sniffer keeps a safe tail and always withholds tool JSON', () => {
  assert.equal(shouldRevealBufferedText('Привет'), false);
  assert.equal(shouldRevealBufferedText('x'.repeat(TOOL_STREAM_HOLDBACK_CHARS + 1)), true);
  assert.equal(shouldRevealBufferedText('{"wesiTool":'), false);
  assert.equal(shouldRevealBufferedText('Сейчас проверю.\n{"wesiTool":'), false);
  assert.equal(shouldRevealBufferedText('```json\n{"wesiTool":'), false);
});
'''
test_text = replace_once(test_text, old_parser_test, new_parser_test, 'gateway parser tests')
old_tool_decl = "  const toolJson = '{\"wesiTool\":{\"name\":\"tasks_list\",\"arguments\":{\"limit\":2}}}';\n"
new_tool_decl = old_tool_decl + "  const malformedToolTurn = `${toolJson}\\n\\n*Сейчас глянем, что вернул инструмент.*`;\n"
test_text = replace_once(test_text, old_tool_decl, new_tool_decl, 'malformed tool fixture')
old_first_turn = r'''        return ndjson([
          {type: 'delta', text: toolJson.slice(0, 20)},
          {type: 'delta', text: toolJson.slice(20)},
          {type: 'done', answer: toolJson},
        ]);
'''
new_first_turn = r'''        return ndjson([
          {type: 'delta', text: malformedToolTurn.slice(0, 20)},
          {type: 'delta', text: malformedToolTurn.slice(20, 60)},
          {type: 'delta', text: malformedToolTurn.slice(60)},
          {type: 'done', answer: malformedToolTurn},
        ]);
'''
test_text = replace_once(test_text, old_first_turn, new_first_turn, 'screenshot tool regression')
GATEWAY_TEST.write_text(test_text)

BALANCE.write_text(r'''function number(value, fallback = 0) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function roundMoney(value) {
  return Math.round((number(value) + Number.EPSILON) * 100) / 100;
}

function truthy(value) {
  return value === true || String(value || '').toLowerCase() === 'true';
}

function calculateFinanceBalances(accounts, transactions, options) {
  const input = options && typeof options === 'object' ? options : {};
  const organizationId = String(input.organizationId || 'org_wesi_inc').trim() || 'org_wesi_inc';
  const requestedAccountId = String(input.accountId || '').trim();
  const asOfMs = Number.isFinite(Number(input.asOfMs)) ? Number(input.asOfMs) : Date.now();
  const rootAccountId = organizationId === 'org_wesi_inc' ? 'main' : `main:${organizationId}`;

  const recurringIncomeIds = (Array.isArray(transactions) ? transactions : [])
    .filter((tx) => truthy(tx?.isRecurring) && String(tx?.type || '') === 'income')
    .map((tx) => String(tx?.id || ''))
    .filter(Boolean);

  const legacyAutoIncome = (tx) => {
    if (truthy(tx?.isRecurring) || String(tx?.type || '') !== 'income') return false;
    const id = String(tx?.id || '');
    return recurringIncomeIds.some((sourceId) => id.startsWith(`${sourceId}_`));
  };

  const rows = [];
  const totals = {};
  for (const account of Array.isArray(accounts) ? accounts : []) {
    const id = String(account?.id || '').trim();
    if (!id || (requestedAccountId && id !== requestedAccountId)) continue;
    const accountOrg = String(account?.organizationId || 'org_wesi_inc');
    if (accountOrg !== organizationId) continue;

    let income = 0;
    let expense = 0;
    let operations = 0;
    for (const tx of Array.isArray(transactions) ? transactions : []) {
      const txOrg = String(tx?.organizationId || 'org_wesi_inc');
      if (txOrg !== organizationId) continue;
      const effectiveAccountId = String(tx?.accountId || rootAccountId);
      if (effectiveAccountId !== id || truthy(tx?.isRecurring) || legacyAutoIncome(tx)) continue;
      const timestamp = Date.parse(String(tx?.date || ''));
      const amount = number(tx?.amount, Number.NaN);
      if (!Number.isFinite(timestamp) || timestamp > asOfMs || !Number.isFinite(amount) || amount < 0) continue;
      if (String(tx?.type || '') === 'income') income += amount;
      else if (String(tx?.type || '') === 'expense') expense += amount;
      else continue;
      operations += 1;
    }

    const balance = roundMoney(number(account?.openingBalance) + income - expense);
    const currency = String(account?.currency || 'RUB').trim().toUpperCase() || 'RUB';
    rows.push({
      id,
      name: String(account?.name || id),
      kind: String(account?.kind || 'other'),
      currency,
      archived: truthy(account?.archived),
      openingBalance: roundMoney(account?.openingBalance),
      balance,
      income: roundMoney(income),
      expense: roundMoney(expense),
      operations,
    });
    totals[currency] = roundMoney(number(totals[currency]) + balance);
  }

  return {
    found: !requestedAccountId || rows.some((account) => account.id === requestedAccountId),
    accounts: rows,
    totalsByCurrency: Object.keys(totals).sort().map((currency) => ({currency, balance: roundMoney(totals[currency])})),
  };
}

module.exports = {calculateFinanceBalances};
''')

BALANCE_TEST.write_text(r'''import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import test from 'node:test';

const require = createRequire(import.meta.url);
const {calculateFinanceBalances} = require('../pb_hooks/wesi_ai_finance_balance.js');

test('finance balances mirror AccountService summaries semantics', () => {
  const asOf = Date.parse('2026-08-16T00:00:00Z');
  const result = calculateFinanceBalances([
    {id: 'main', name: 'Основной', organizationId: 'org_wesi_inc', openingBalance: 1000, currency: 'RUB'},
    {id: 'cash', name: 'Наличные', organizationId: 'org_wesi_inc', openingBalance: 100, currency: 'RUB'},
  ], [
    {id: 'i1', organizationId: 'org_wesi_inc', accountId: 'main', type: 'income', amount: 500, date: '2026-08-10T10:00:00Z'},
    {id: 'e1', organizationId: 'org_wesi_inc', accountId: 'main', type: 'expense', amount: 200, date: '2026-08-11T10:00:00Z'},
    {id: 'future', organizationId: 'org_wesi_inc', accountId: 'main', type: 'expense', amount: 900, date: '2026-09-01T10:00:00Z'},
    {id: 'rent', organizationId: 'org_wesi_inc', accountId: 'main', type: 'expense', amount: 300, date: '2026-08-12T10:00:00Z', isRecurring: true},
    {id: 'salary', organizationId: 'org_wesi_inc', accountId: 'main', type: 'income', amount: 700, date: '2026-08-01T10:00:00Z', isRecurring: true},
    {id: 'salary_202608', organizationId: 'org_wesi_inc', accountId: 'main', type: 'income', amount: 700, date: '2026-08-01T10:00:00Z'},
    {id: 'cash-e', organizationId: 'org_wesi_inc', accountId: 'cash', type: 'expense', amount: 20, date: '2026-08-09T10:00:00Z'},
  ], {organizationId: 'org_wesi_inc', asOfMs: asOf});

  assert.equal(result.found, true);
  assert.deepEqual(result.accounts.map((a) => [a.id, a.balance, a.operations]), [
    ['main', 1300, 2],
    ['cash', 80, 1],
  ]);
  assert.deepEqual(result.totalsByCurrency, [{currency: 'RUB', balance: 1380}]);
});

test('finance balances use effective main account and keep currencies separate', () => {
  const result = calculateFinanceBalances([
    {id: 'main:org_child', name: 'Main', organizationId: 'org_child', openingBalance: 50, currency: 'USD'},
    {id: 'rub', name: 'RUB', organizationId: 'org_child', openingBalance: 100, currency: 'RUB'},
  ], [
    {id: 'i', organizationId: 'org_child', type: 'income', amount: 25, date: '2026-08-10T00:00:00Z'},
  ], {organizationId: 'org_child', asOfMs: Date.parse('2026-08-16T00:00:00Z')});
  assert.deepEqual(result.totalsByCurrency, [
    {currency: 'RUB', balance: 100},
    {currency: 'USD', balance: 75},
  ]);
});
''')

finance = FINANCE.read_text()
finance = replace_once(
    finance,
    '''      {\n        name: "finance_summary",\n        description: "Посчитать на основном сервере Wesi сводку разрешённых финансов организации за период: доходы, расходы, net, категории, recurring и anomalies.",\n        parameters: {type: "object", properties: {organizationId: {type: "string"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}}},\n      },\n''',
    '''      {\n        name: "finance_accounts",\n        description: "Получить текущие остатки по финансовым счетам WesiOS. Используй для вопросов «сколько денег сейчас», «какой баланс/остаток на счёте, карте, в кассе или кошельке». Возвращает фактический balance по каждому счёту и итоги отдельно по валютам.",\n        parameters: {type: "object", properties: {organizationId: {type: "string"}, accountId: {type: "string", description: "Необязательный id конкретного счёта"}}},\n      },\n      {\n        name: "finance_summary",\n        description: "Посчитать cashflow-сводку разрешённых финансов организации за период: доходы, расходы, net, категории, recurring и anomalies. Это НЕ текущий остаток на счетах; для текущего баланса используй finance_accounts.",\n        parameters: {type: "object", properties: {organizationId: {type: "string"}, from: {type: "string", description: "YYYY-MM-DD"}, to: {type: "string", description: "YYYY-MM-DD"}}},\n      },\n''',
    'finance account definition',
)
marker = '''    if (!organizationId) return {ok: false, code: "FORBIDDEN", message: "Нет права просматривать финансы этой организации"};\n\n    const now = new Date();\n'''
insert = '''    if (!organizationId) return {ok: false, code: "FORBIDDEN", message: "Нет права просматривать финансы этой организации"};\n\n    if (name === "finance_accounts") {\n      const engine = require(`${__hooks}/wesi_ai_finance_balance.js`);\n      const accountSource = rows(e, ctx, "accounts");\n      const transactionSource = rows(e, ctx, "transactions");\n      const accounts = [];\n      const transactions = [];\n      for (const row of accountSource) {\n        const p = policy.payload(row);\n        if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;\n        accounts.push({\n          id: String(p.id || row.getString("rid") || ""),\n          name: String(p.name || ""),\n          kind: String(p.kind || "other"),\n          openingBalance: Number(p.openingBalance || 0),\n          archived: p.archived === true,\n          organizationId: String(p.organizationId || policy.ROOT_ORG),\n          currency: String(p.currency || (state.orgs[organizationId] ? state.orgs[organizationId].baseCurrency : "RUB")),\n        });\n      }\n      for (const row of transactionSource) {\n        const p = policy.payload(row);\n        if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;\n        transactions.push({\n          id: String(p.id || row.getString("rid") || ""),\n          type: String(p.type || ""),\n          amount: Number(p.amount),\n          date: String(p.date || ""),\n          isRecurring: p.isRecurring === true,\n          accountId: p.accountId == null ? null : String(p.accountId),\n          organizationId: String(p.organizationId || policy.ROOT_ORG),\n        });\n      }\n      const calculated = engine.calculateFinanceBalances(accounts, transactions, {\n        organizationId: organizationId,\n        accountId: String(input.accountId || ""),\n        asOfMs: Date.now(),\n      });\n      if (!calculated.found) return {ok: false, code: "NOT_FOUND", message: "Финансовый счёт не найден"};\n      return {ok: true, result: {\n        organizationId: organizationId,\n        organizationName: state.orgs[organizationId] ? state.orgs[organizationId].name : organizationId,\n        asOf: new Date().toISOString(),\n        accounts: calculated.accounts,\n        totalsByCurrency: calculated.totalsByCurrency,\n      }};\n    }\n\n    const now = new Date();\n'''
finance = replace_once(finance, marker, insert, 'finance account execution')
FINANCE.write_text(finance)
