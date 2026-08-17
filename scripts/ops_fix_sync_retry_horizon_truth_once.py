from pathlib import Path


# 1) SyncEngine: retry dependency-blocked rows until no progress,
# then fail closed instead of uploading while local state is incomplete.
p = Path('lib/core/sync/sync_engine.dart')
s = p.read_text(encoding='utf-8')
start = s.index(
    '    var applied = 0;\n',
    s.index('static Future<SyncCollectionReport> _runOne'),
)
end = s.index('    if (applied > 0) c.notifyChanged();\n', start)
replacement = r'''    var applied = 0;
    SyncFailure? applyFailure;
    var pending = List<SyncRecord>.from(plan.toApplyLocally);

    Future<void> resetIncompleteStamp(String id) async {
      SyncJournal.forget(c.name, id);
      await SyncJournal.record(
        c.name,
        id,
        SyncStamp(DateTime.fromMillisecondsSinceEpoch(0)),
      );
    }

    // Some valid server rows depend on another row in the same collection.
    // Organizations are the obvious case: a child can sort before its parent.
    // Grants may also depend on an actor grant. One-pass application therefore
    // turns a harmless wire order into a permanent sync failure. Retry only
    // rows that were not accepted, and stop as soon as a full pass makes no
    // progress. This is bounded by the number of rows because every continuing
    // pass must apply at least one row.
    while (pending.isNotEmpty) {
      var progressed = false;
      final deferred = <SyncRecord>[];

      for (final r in pending) {
        SyncJournal.expect(
          c.name,
          r.id,
          SyncStamp(r.updatedAt, deleted: r.deleted),
        );
        await SyncJournal.record(
          c.name,
          r.id,
          SyncStamp(r.updatedAt, deleted: r.deleted),
        );

        var accepted = false;
        try {
          if (r.deleted) {
            await c.removeById(r.id);
            accepted = true;
          } else {
            accepted = await c.applyFields(r.fields);
          }
        } catch (_) {
          accepted = false;
        }

        if (accepted) {
          applied++;
          progressed = true;
        } else {
          // The expected Hive event will never arrive for a rejected row.
          // Do not let the expectation consume a later real user edit.
          SyncJournal.forget(c.name, r.id);
          deferred.add(r);
        }
      }

      if (deferred.isEmpty) {
        pending = const <SyncRecord>[];
        break;
      }
      pending = deferred;
      if (!progressed) break;
    }

    if (pending.isNotEmpty) {
      for (final r in pending) {
        await resetIncompleteStamp(r.id);
      }
      final first = pending.first.id;
      final suffix = pending.length > 1 ? ' (+${pending.length - 1})' : '';
      applyFailure = SyncFailure(
        'REMOTE_APPLY_INCOMPLETE',
        'Не удалось применить ${c.name}:$first$suffix',
      );
    }

'''
s = s[:start] + replacement + s[end:]
needle = '''    if (applied > 0) c.notifyChanged();

    if (plan.toUpload.isEmpty) {'''
repl = '''    if (applied > 0) c.notifyChanged();

    // Never push a merge plan derived from a state that we failed to apply.
    // Retrying later is safe; uploading while incomplete can overwrite a valid
    // server row with stale local state.
    if (applyFailure != null) {
      return SyncCollectionReport(
        collection: c.name,
        applied: applied,
        failure: applyFailure,
      );
    }

    if (plan.toUpload.isEmpty) {'''
if needle not in s:
    raise SystemExit('SyncEngine post-apply anchor missing')
s = s.replace(needle, repl, 1)
p.write_text(s, encoding='utf-8')


# 2) Horizon: mirror AccountService.summaries actual-balance semantics while
# preserving the already hardened source-read diagnostics around the formula.
p = Path('server/pb_hooks/wesi_ai_horizon_tools.js')
s = p.read_text(encoding='utf-8')
calc_start = s.index('    let balance = 0;\n', s.index('execute: function'))
calc_end = s.index('    const spendPerDay = expense / 90;\n', calc_start)
calculation = '''    let balance = 0;
    let income = 0;
    let expense = 0;
    let count = 0;
    const now = new Date();
    const historyStart = new Date(now.getTime() - 90 * 86400000);

    for (const row of accounts) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId || p.archived === true) continue;
      const opening = Number(p.openingBalance || 0);
      if (Number.isFinite(opening)) balance += opening;
    }

    // Keep this exactly aligned with AccountService.summaries(): recurring
    // templates do not affect actual balance, future operations do not count,
    // and legacy materialized recurring-income rows are excluded to prevent a
    // historical double count. Actual Treasury balance is in reporting amount
    // (`amount`), not organizationBaseAmount.
    const recurringIncomeIds = [];
    for (const row of transactions) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      if (p.isRecurring === true && String(p.type || "expense") === "income") {
        recurringIncomeIds.push(String(p.id || row.getString("rid") || ""));
      }
    }
    const legacyAutoIncome = (p, row) => {
      if (p.isRecurring === true || String(p.type || "expense") !== "income") return false;
      const id = String(p.id || row.getString("rid") || "");
      return recurringIncomeIds.some((recurringId) => recurringId && id.indexOf(recurringId + "_") === 0);
    };

    for (const row of transactions) {
      const p = policy.payload(row);
      if (String(p.organizationId || policy.ROOT_ORG) !== organizationId) continue;
      if (p.isRecurring === true || legacyAutoIncome(p, row)) continue;
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

'''
s = s[:calc_start] + calculation + s[calc_end:]
p.write_text(s, encoding='utf-8')


# 3) Client receive regression coverage.
p = Path('test/sync_receive_regression_test.dart')
s = p.read_text(encoding='utf-8')
main_idx = s.index('\nvoid main() {')
dependency = r'''

class _DependencyReceiveCollection extends SyncCollection<dynamic> {
  final Set<String> accepted = <String>{};

  @override
  String get name => 'dependency_probe';

  @override
  String get boxName => 'wesios_dependency_probe';

  @override
  String idOf(dynamic value) => value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) =>
      value is Map ? Map<String, dynamic>.from(value) : const {};

  @override
  dynamic decode(Map<String, dynamic> fields) => fields;

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final id = '${fields['id'] ?? ''}';
    final parent = '${fields['parent'] ?? ''}';
    if (id.isEmpty) return false;
    if (parent.isNotEmpty && !accepted.contains(parent)) return false;
    accepted.add(id);
    return true;
  }
}
'''
if '_DependencyReceiveCollection' not in s:
    s = s[:main_idx] + dependency + s[main_idx:]
s = s.replace(
    '  late _RejectingReceiveCollection probe;\n',
    '  late _RejectingReceiveCollection probe;\n'
    '  late _DependencyReceiveCollection dependencyProbe;\n',
    1,
)
s = s.replace(
    '    probe = _RejectingReceiveCollection();\n'
    '    SyncCodec.collections.add(probe);\n',
    '    probe = _RejectingReceiveCollection();\n'
    '    dependencyProbe = _DependencyReceiveCollection();\n'
    '    SyncCodec.collections.add(probe);\n'
    '    SyncCodec.collections.add(dependencyProbe);\n',
    1,
)
s = s.replace(
    '    SyncCodec.collections.remove(probe);\n',
    '    SyncCodec.collections.remove(probe);\n'
    '    SyncCodec.collections.remove(dependencyProbe);\n',
    1,
)
existing_expect = (
    "    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');\n"
    '    expect(report.applied, 0);\n'
)
replacement_expect = (
    "    expect(report.firstFailure?.code, 'REMOTE_APPLY_INCOMPLETE');\n"
    "    expect(report.firstFailure?.message, contains('receive_probe:remote-1'));\n"
    '    expect(report.applied, 0);\n'
)
if existing_expect not in s:
    raise SystemExit('receive regression expectation anchor missing')
s = s.replace(existing_expect, replacement_expect, 1)
test_anchor = "  test('fresh interactive login starts receive polling for every employee', () {"
dependency_test = r'''  test('dependency-blocked rows are retried within the same collection pass', () async {
    dependencyProbe.accepted.clear();
    final transport = FakeSyncTransport()
      ..seed(
        dependencyProbe.name,
        'child',
        {'id': 'child', 'parent': 'parent'},
        base.add(const Duration(minutes: 2)),
      )
      ..seed(
        dependencyProbe.name,
        'parent',
        {'id': 'parent'},
        base.add(const Duration(minutes: 1)),
      );

    final report = await SyncEngine.run(
      transport: transport,
      now: base.add(const Duration(minutes: 3)),
      only: {dependencyProbe.name},
    );

    expect(report.ok, isTrue, reason: report.describe());
    expect(dependencyProbe.accepted, containsAll(<String>{'parent', 'child'}));
    expect(report.applied, 2);
  });

'''
if dependency_test not in s:
    if test_anchor not in s:
        raise SystemExit('receive regression insertion anchor missing')
    s = s.replace(test_anchor, dependency_test + test_anchor, 1)
p.write_text(s, encoding='utf-8')


# 4) Executable Node test for server Horizon truth semantics.
p = Path('server/pb_hooks/wesi_ai_horizon_truth_test.mjs')
p.write_text(r'''import assert from "node:assert/strict";
import path from "node:path";
import {createRequire} from "node:module";
import {test} from "node:test";

const require = createRequire(import.meta.url);
globalThis.__hooks = path.resolve("server/pb_hooks");
const tool = require(path.resolve("server/pb_hooks/wesi_ai_horizon_tools.js"));

function row(rid, payload) {
  return {
    get(name) { return name === "payload" ? payload : null; },
    getString(name) { return name === "rid" ? rid : ""; },
  };
}

function appFixture({throwLedger = false} = {}) {
  const now = Date.now();
  const yesterday = new Date(now - 86400000).toISOString();
  const future = new Date(now + 86400000).toISOString();
  const org = row("org_wesi_inc", {
    id: "org_wesi_inc", name: "Wesi Inc", isRoot: true,
    parentId: null, status: "active", baseCurrency: "RUB",
  });
  const account = row("main", {
    id: "main", organizationId: "org_wesi_inc", archived: false,
    openingBalance: 1000,
  });
  const transactions = [
    row("recurring-income", {id: "recurring-income", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 5000, organizationBaseAmount: 50, isRecurring: true, date: yesterday}),
    row("recurring-income_legacy", {id: "recurring-income_legacy", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 5000, organizationBaseAmount: 50, isRecurring: false, date: yesterday}),
    row("income", {id: "income", organizationId: "org_wesi_inc", accountId: "main", type: "income", amount: 200, organizationBaseAmount: 2, isRecurring: false, date: yesterday}),
    row("expense", {id: "expense", organizationId: "org_wesi_inc", accountId: "main", type: "expense", amount: 50, organizationBaseAmount: 0.5, isRecurring: false, date: yesterday}),
    row("future", {id: "future", organizationId: "org_wesi_inc", accountId: "main", type: "expense", amount: 900, organizationBaseAmount: 9, isRecurring: false, date: future}),
  ];
  return {
    findRecordsByFilter(_collection, filter, _sort, _max, _offset, params) {
      if (filter.includes("coll='organizations'")) return [org];
      if (filter.includes("coll='organization_grants'")) return [];
      if (params?.coll === "accounts") {
        if (throwLedger) throw new Error("ledger down");
        return [account];
      }
      if (params?.coll === "transactions") {
        if (throwLedger) throw new Error("ledger down");
        return transactions;
      }
      return [];
    },
  };
}

const ctx = {isOwner: true, modules: ["forecast"], ownerId: "owner", employeeId: "owner"};

test("horizon snapshot mirrors canonical Treasury actual-balance semantics", () => {
  const e = {app: appFixture()};
  const result = tool.execute(e, ctx, "horizon_snapshot", {}, "org_wesi_inc");
  assert.equal(result.ok, true);
  assert.equal(result.result.currentBalance, 1150);
  assert.equal(result.result.recent90Days.transactionCount, 2);
  assert.equal(result.result.recent90Days.income, 200);
  assert.equal(result.result.recent90Days.expense, 50);
  assert.equal(result.result.recent90Days.net, 150);
});

test("horizon does not convert a backend read failure into financial zeros", () => {
  const e = {app: appFixture({throwLedger: true})};
  const result = tool.execute(e, ctx, "horizon_snapshot", {}, "org_wesi_inc");
  assert.equal(result.ok, false);
  assert.equal(result.code, "HORIZON_DATA_UNAVAILABLE");
});
''', encoding='utf-8')
