from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    target = Path(path)
    text = target.read_text()
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one marker, found {count}")
    target.write_text(text.replace(old, new, 1))


rich = "lib/features/ai/widgets/wesi_ai_rich_message.dart"
old_display = r'''  static String displayMarkdown(String markdown) => markdown.replaceAllMapped(
        RegExp(r'^\s{0,3}#{1,6}\s+(.+)$', multiLine: true),
        (match) => '**${match.group(1)?.trim() ?? ''}**',
      );'''
new_display = r'''  static String displayMarkdown(String markdown) {
    var normalized = markdown
        .replaceAllMapped(
          RegExp(r'\$\$([\s\S]*?)\$\$'),
          (match) => _displayInlineMath(match.group(1) ?? ''),
        )
        .replaceAllMapped(
          RegExp(r'(?<!\$)\$([^$\n]+)\$(?!\$)'),
          (match) => _displayInlineMath(match.group(1) ?? ''),
        );
    return normalized.replaceAllMapped(
      RegExp(r'^\s{0,3}#{1,6}\s+(.+)$', multiLine: true),
      (match) => '**${match.group(1)?.trim() ?? ''}**',
    );
  }

  static String _displayInlineMath(String source) {
    var value = source.trim();
    for (var i = 0; i < 4; i++) {
      final next = value.replaceAllMapped(
        RegExp(r'\\(?:mathbf|mathrm|text|operatorname)\{([^{}]*)\}'),
        (match) => match.group(1) ?? '',
      );
      if (next == value) break;
      value = next;
    }
    return value
        .replaceAll(r'\times', '×')
        .replaceAll(r'\cdot', '·')
        .replaceAll(r'\div', '÷')
        .replaceAll(r'\pm', '±')
        .replaceAll(r'\le', '≤')
        .replaceAll(r'\ge', '≥')
        .replaceAll(r'\neq', '≠')
        .replaceAll(r'\,', ' ')
        .replaceAll(r'\ ', ' ')
        .replaceAll(RegExp(r'\s{2,}'), ' ')
        .trim();
  }'''
replace_once(rich, old_display, new_display)
replace_once(
    rich,
    "  static String plainText(String markdown) {\n    return markdown\n",
    "  static String plainText(String markdown) {\n    return displayMarkdown(markdown)\n",
)

api = "lib/features/ai/wesi_ai_api.dart"
replace_once(
    api,
    "    final auth = _auth();\n    final base = Uri.parse(SyncEndpoint.url);\n\n    try {\n",
    "    final auth = _auth();\n"
    "    final base = Uri.parse(SyncEndpoint.url);\n"
    "    var activeOrganizationId = OrganizationContext.currentOrganizationId;\n"
    "    try {\n"
    "      activeOrganizationId =\n"
    "          (await OrganizationContext.currentOrganization()).id;\n"
    "    } catch (_) {\n"
    "      // The server still enforces organization access. Keep Wesi AI usable\n"
    "      // during incomplete local bootstrap, but always prefer the initialized\n"
    "      // organization selected by the user when it is available.\n"
    "    }\n\n"
    "    try {\n",
)
replace_once(
    api,
    "        'activeOrganizationId': OrganizationContext.currentOrganizationId,\n",
    "        'activeOrganizationId': activeOrganizationId,\n",
)

policy = Path("server/pb_hooks/wesi_ai_finance_policy.js")
policy_text = policy.read_text()
zero_limit = '"id", 0, 0, {owner: ctx.ownerId}'
if policy_text.count(zero_limit) != 2:
    raise SystemExit(
        f"finance policy: expected 2 zero-limit reads, found {policy_text.count(zero_limit)}"
    )
policy_text = policy_text.replace(
    zero_limit, '"id", 1000, 0, {owner: ctx.ownerId}'
)
policy_text = policy_text.replace(
    "function access(e, ctx) {\n",
    "function access(e, ctx) {\n"
    "  // PocketBase requires a positive maxRecords value. Never collapse the\n"
    "  // organization/grant scope to an empty set merely because a zero-limit\n"
    "  // backend read failed.\n",
    1,
)
policy.write_text(policy_text)

test_path = Path("test/wesi_ai_rich_message_test.dart")
test_text = test_path.read_text()
marker = "  test('activity model preserves per tool diff and source', () {"
if marker not in test_text:
    raise SystemExit("rich message test marker missing")
regression = r'''  test('display markdown normalizes inline latex without touching currency', () {
    const source =
        r'Счёт: $3 + 4 = 7$. Итог: $10 + 4 = \mathbf{14}$. Цена: $100';
    final display = WesiAiRichParser.displayMarkdown(source);
    expect(display, contains('3 + 4 = 7'));
    expect(display, contains('10 + 4 = 14'));
    expect(display, contains(r'$100'));
    expect(display, isNot(contains(r'$3 + 4 = 7$')));
    expect(display, isNot(contains(r'\mathbf')));
  });

'''
test_path.write_text(test_text.replace(marker, regression + marker, 1))

finance_test = Path("server/pb_hooks/wesi_ai_finance_tools_test.mjs")
finance_test.write_text(r'''import assert from 'node:assert/strict';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const here = path.dirname(fileURLToPath(import.meta.url));
globalThis.__hooks = here;

class Row {
  constructor(payload, rid) {
    this.values = { payload, rid };
  }
  get(name) { return this.values[name]; }
  getString(name) { return String(this.values[name] ?? ''); }
}

const calls = [];
const organizations = [
  new Row({ id: 'org_wesi_inc', name: 'Wesi Inc', baseCurrency: 'RUB' }, 'o1'),
  new Row({ id: 'org_real', name: 'Real Org', baseCurrency: 'RUB' }, 'o2'),
];
const transactions = [
  new Row({ id: 't1', organizationId: 'org_real', title: 'Sale', amount: 2500, type: 'income', date: '2026-08-10T12:00:00Z', category: 'Sales' }, 't1'),
  new Row({ id: 't2', organizationId: 'org_real', title: 'Hosting', amount: 400, type: 'expense', date: '2026-08-11T12:00:00Z', category: 'Infra' }, 't2'),
  new Row({ id: 't3', organizationId: 'org_wesi_inc', title: 'Other org', amount: 9999, type: 'income', date: '2026-08-12T12:00:00Z' }, 't3'),
];

const e = {
  app: {
    findRecordsByFilter(_collection, filter, _sort, maxRecords, _offset, params) {
      calls.push(maxRecords);
      assert.ok(maxRecords > 0, 'maxRecords must stay positive');
      if (filter.includes("coll='organizations'")) return organizations;
      if (filter.includes("coll='organization_grants'")) return [];
      if (params?.coll === 'transactions') return transactions;
      return [];
    },
  },
};
const ctx = { isOwner: true, ownerId: 'owner', employeeId: 'owner', modules: [] };
const tools = require('./wesi_ai_finance_tools.js');
const result = tools.execute(
  e,
  ctx,
  'finance_summary',
  { from: '2026-08-01', to: '2026-08-31' },
  'org_real',
);

assert.equal(result.ok, true);
assert.equal(result.result.organizationId, 'org_real');
assert.equal(result.result.transactionCount, 2);
assert.equal(result.result.income, 2500);
assert.equal(result.result.expense, 400);
assert.equal(result.result.net, 2100);
assert.ok(calls.every((value) => value > 0));
console.log('Wesi AI finance nonzero regression: OK');
''')

print("release 0.22.16 Wesi AI patch applied")
