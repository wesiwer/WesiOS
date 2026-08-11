from pathlib import Path


def class_block(text: str, start_marker: str, next_marker: str):
    start = text.index(start_marker)
    end = text.index(next_marker, start)
    return start, end, text[start:end]


def insert_before_close(block: str, addition: str, label: str) -> str:
    close = block.rfind('\n}')
    if close < 0:
        raise SystemExit(f'{label}: closing brace not found')
    return block[:close] + addition + block[close:]


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, got {count}')
    return text.replace(old, new, 1)


# ---- Sync authority and journal integrity ----
p = Path('lib/core/sync/sync_codec.dart')
text = p.read_text(encoding='utf-8')

if 'Generic dataset sync is not an identity authority' not in text:
    start, end, block = class_block(
        text,
        'class EmployeesSync extends SyncCollection<EmployeeModel> {',
        '\nclass OrganizationGrantsSync extends',
    )
    addition = r'''

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    final incoming = decode(fields);
    if (b == null || incoming == null) return false;
    final existing = b.get(incoming.id);
    EmployeeModel? localOwner;
    for (final row in b.values) {
      if (row.isOwner) {
        localOwner = row;
        break;
      }
    }

    // Generic dataset sync is not an identity authority. Trusted server
    // identity bootstrap must establish owner identity locally first.
    if (incoming.isOwner) {
      if (existing?.isOwner != true) return false;
      if (localOwner != null && localOwner.id != incoming.id) return false;
    }
    if (existing?.isOwner == true && !incoming.isOwner) return false;

    await b.put(incoming.id, incoming);
    return true;
  }

  @override
  Future<void> removeById(String id) async {
    final b = box();
    final existing = b?.get(id);
    if (b == null || existing == null || existing.isOwner) return;
    await b.delete(id);
  }
'''
    block = insert_before_close(block, addition, 'EmployeesSync')
    text = text[:start] + block + text[end:]

start, end, block = class_block(
    text,
    'class TransactionsSync extends SyncCollection<TransactionModel> {',
    '\nclass TasksSync extends',
)
if 'linked inter-org leg is part of a journaled logical transfer' not in block:
    addition = r'''

  @override
  Future<void> removeById(String id) async {
    final b = box();
    final existing = b?.get(id);
    if (b == null || existing == null) return;
    // A linked inter-org leg is part of a journaled logical transfer. Remote
    // tombstones cannot delete one side independently; cancellation/recovery
    // must go through InterOrgTransferService.
    if (existing.interOrgTransferId != null ||
        existing.source == TransactionSource.interorg) return;
    await b.delete(id);
  }
'''
    block = insert_before_close(block, addition, 'TransactionsSync')
    text = text[:start] + block + text[end:]

if '_sameImmutableCore(' not in text:
    old = r'''  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    final incoming = decode(fields);
    if (b == null || incoming == null) return false;
    if (!_organizationExistsActive(incoming.fromOrganizationId) ||
        !_organizationExistsActive(incoming.toOrganizationId)) return false;
    final from = _account(incoming.fromAccountId);
    final to = _account(incoming.toAccountId);
    if (from == null ||
        to == null ||
        from.archived ||
        to.archived ||
        from.effectiveOrganizationId != incoming.fromOrganizationId ||
        to.effectiveOrganizationId != incoming.toOrganizationId) return false;
    if (incoming.ownerEmployeeId != null &&
        !_employeeExists(incoming.ownerEmployeeId!)) return false;
    await b.put(incoming.id, incoming);
    await InterOrgTransferService.recoverPending();
    return true;
  }
}

class TransactionAuditsSync extends SyncCollection<TransactionAuditModel> {'''
    new = r'''  bool _sameImmutableCore(
    InterOrgTransferModel a,
    InterOrgTransferModel b,
  ) =>
      a.fromOrganizationId == b.fromOrganizationId &&
      a.toOrganizationId == b.toOrganizationId &&
      a.fromAccountId == b.fromAccountId &&
      a.toAccountId == b.toAccountId &&
      a.amount == b.amount &&
      a.currency == b.currency &&
      a.amountInFromOrgBase == b.amountInFromOrgBase &&
      a.amountInToOrgBase == b.amountInToOrgBase &&
      a.type == b.type &&
      a.note == b.note &&
      a.date == b.date &&
      a.createdBy == b.createdBy &&
      a.createdAt == b.createdAt &&
      a.linkedDebitTransactionId == b.linkedDebitTransactionId &&
      a.linkedCreditTransactionId == b.linkedCreditTransactionId &&
      a.ownerEmployeeId == b.ownerEmployeeId;

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    final incoming = decode(fields);
    if (b == null || incoming == null) return false;
    if (!_organizationExistsActive(incoming.fromOrganizationId) ||
        !_organizationExistsActive(incoming.toOrganizationId)) return false;
    final from = _account(incoming.fromAccountId);
    final to = _account(incoming.toAccountId);
    if (from == null ||
        to == null ||
        from.archived ||
        to.archived ||
        from.effectiveOrganizationId != incoming.fromOrganizationId ||
        to.effectiveOrganizationId != incoming.toOrganizationId) return false;
    if (incoming.ownerEmployeeId != null &&
        !_employeeExists(incoming.ownerEmployeeId!)) return false;

    final existing = b.get(incoming.id);
    if (existing != null) {
      if (!_sameImmutableCore(existing, incoming)) return false;
      if (existing.cancelled) {
        if (!incoming.cancelled ||
            incoming.cancelledAt != existing.cancelledAt ||
            incoming.cancelledBy != existing.cancelledBy) return false;
      } else if (incoming.cancelled) {
        if (incoming.cancelledAt == null ||
            incoming.cancelledBy == null ||
            incoming.cancelledBy!.trim().isEmpty) return false;
      } else if (incoming.cancelledAt != null || incoming.cancelledBy != null) {
        return false;
      }
    } else {
      if (incoming.cancelled) {
        if (incoming.cancelledAt == null ||
            incoming.cancelledBy == null ||
            incoming.cancelledBy!.trim().isEmpty) return false;
      } else if (incoming.cancelledAt != null || incoming.cancelledBy != null) {
        return false;
      }
    }

    await b.put(incoming.id, incoming);
    await InterOrgTransferService.recoverPending();
    return true;
  }
}

class TransactionAuditsSync extends SyncCollection<TransactionAuditModel> {'''
    text = replace_once(text, old, new, 'InterOrgTransfersSync lifecycle')

p.write_text(text, encoding='utf-8')


# ---- Horizon risk aggregation denominator ----
p = Path('lib/features/treasury/services/horizon_engine_competition.dart')
text = p.read_text(encoding='utf-8')
old = 'values.fold<double>(0, (a, b) => a + b) / results.length'
if old in text:
    text = text.replace(
        old,
        'values.fold<double>(0, (a, b) => a + b) / values.length',
        1,
    )
p.write_text(text, encoding='utf-8')


# ---- Async stale-access UI guards ----
def file_replace(path: str, old: str, new: str, label: str):
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    if new in text:
        return
    text = replace_once(text, old, new, label)
    p.write_text(text, encoding='utf-8')


team = 'lib/features/team/team_stats_screen.dart'
file_replace(
    team,
    '  List<EmployeeModel> _people = const [];\n',
    '  List<EmployeeModel> _people = const [];\n  int _loadEpoch = 0;\n',
    'TeamStats epoch field',
)
file_replace(
    team,
    '  Future<void> _load() async {\n    final tasks = await TaskService().getAll();\n',
    '  Future<void> _load() async {\n    final epoch = ++_loadEpoch;\n    final tasks = await TaskService().getAll();\n',
    'TeamStats epoch start',
)
file_replace(
    team,
    '    if (mounted) {\n      setState(() {\n',
    '    if (mounted && epoch == _loadEpoch) {\n      setState(() {\n',
    'TeamStats stale commit',
)

finance = 'lib/features/organizations/my_finance_screen.dart'
file_replace(
    finance,
    '  bool _loading = true;\n',
    '  bool _loading = true;\n  int _loadEpoch = 0;\n',
    'MyFinance epoch field',
)
file_replace(
    finance,
    '  Future<void> _load() async {\n    if (mounted) setState(() => _loading = true);\n',
    '  Future<void> _load() async {\n    final epoch = ++_loadEpoch;\n    if (mounted) setState(() => _loading = true);\n',
    'MyFinance epoch start',
)
file_replace(
    finance,
    '    if (!mounted) return;\n    setState(() {\n',
    '    if (!mounted || epoch != _loadEpoch) return;\n    setState(() {\n',
    'MyFinance stale commit',
)

orgs = 'lib/features/organizations/organizations_screen.dart'
file_replace(
    orgs,
    '  String? _error;\n',
    '  String? _error;\n  int _loadEpoch = 0;\n',
    'Organizations epoch field',
)
file_replace(
    orgs,
    '  Future<void> _load() async {\n    try {\n',
    '  Future<void> _load() async {\n    final epoch = ++_loadEpoch;\n    try {\n',
    'Organizations epoch start',
)
file_replace(
    orgs,
    '      if (!mounted) return;\n      setState(() {\n',
    '      if (!mounted || epoch != _loadEpoch) return;\n      setState(() {\n',
    'Organizations stale success',
)
file_replace(
    orgs,
    '    } catch (e) {\n      if (mounted) {\n',
    '    } catch (e) {\n      if (mounted && epoch == _loadEpoch) {\n',
    'Organizations stale error',
)

switcher = Path('lib/features/organizations/widgets/organization_switcher.dart')
text = switcher.read_text(encoding='utf-8')
if 'OrganizationModel? _current;\n  int _loadEpoch = 0;' not in text:
    text = replace_once(
        text,
        '  OrganizationModel? _current;\n',
        '  OrganizationModel? _current;\n  int _loadEpoch = 0;\n',
        'Switcher epoch field',
    )
    text = replace_once(
        text,
        '  Future<void> _load() async {\n    try {\n      final org = await OrganizationContext.currentOrganization();\n      if (mounted) setState(() => _current = org);\n',
        '  Future<void> _load() async {\n    final epoch = ++_loadEpoch;\n    try {\n      final org = await OrganizationContext.currentOrganization();\n      if (mounted && epoch == _loadEpoch) setState(() => _current = org);\n',
        'Switcher load epoch',
    )
    text = replace_once(
        text,
        '      if (mounted) setState(() => _current = null);\n',
        '      if (mounted && epoch == _loadEpoch) {\n        setState(() => _current = null);\n      }\n',
        'Switcher stale error',
    )

if 'int _pickerLoadEpoch = 0;' not in text:
    text = replace_once(
        text,
        '  bool _loading = true;\n\n  @override\n  void initState() {\n    super.initState();\n    _load();\n  }\n',
        '  bool _loading = true;\n  int _pickerLoadEpoch = 0;\n\n  @override\n  void initState() {\n    super.initState();\n    OrganizationAccessService.revision.addListener(_reload);\n    OrganizationService.revision.addListener(_reload);\n    _load();\n  }\n\n  @override\n  void dispose() {\n    OrganizationAccessService.revision.removeListener(_reload);\n    OrganizationService.revision.removeListener(_reload);\n    super.dispose();\n  }\n\n  void _reload() => _load();\n',
        'Picker listeners',
    )
    text = replace_once(
        text,
        '  Future<void> _load() async {\n    final all = await OrganizationService.all();\n',
        '  Future<void> _load() async {\n    final epoch = ++_pickerLoadEpoch;\n    final all = await OrganizationService.all();\n',
        'Picker epoch start',
    )
    text = replace_once(
        text,
        '    if (!mounted) return;\n    setState(() {\n      _orgs = all;\n',
        '    if (!mounted || epoch != _pickerLoadEpoch) return;\n    setState(() {\n      _orgs = all;\n',
        'Picker stale commit',
    )
    text = replace_once(
        text,
        '  Future<void> _select(String id) async {\n    await OrganizationContext.selectOrganization(id);\n',
        '  Future<void> _select(String id) async {\n    try {\n      await OrganizationContext.selectOrganization(id);\n    } on StateError {\n      await _load();\n      return;\n    }\n',
        'Picker stale selection',
    )
switcher.write_text(text, encoding='utf-8')


# ---- Negative sync regression tests ----
p = Path('test/sync_corruption_guard_test.dart')
text = p.read_text(encoding='utf-8')
additions = ''
if 'employee sync cannot mint, demote or tombstone owner identity' not in text:
    additions += r'''

  test('employee sync cannot mint, demote or tombstone owner identity', () async {
    final employees = Hive.box<EmployeeModel>(TeamService.boxName);
    final owner = EmployeeModel(
      id: 'owner-secure',
      login: 'owner-secure',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      permissions: TeamPermissions.owner,
      isOwner: true,
    );
    final employee = EmployeeModel(
      id: 'ordinary',
      login: 'ordinary',
      fullName: 'Ordinary',
      createdAt: DateTime(2026, 1, 2),
      permissions: const TeamPermissions(),
    );
    await employees.put(owner.id, owner);
    await employees.put(employee.id, employee);
    final sync = EmployeesSync();

    final forgedOwner = sync.encode(employee)..['isOwner'] = true;
    expect(await sync.applyFields(forgedOwner), isFalse);
    expect(TeamService.byId(employee.id)!.isOwner, isFalse);

    final forgedNewOwner = sync.encode(employee)
      ..['id'] = 'remote-owner'
      ..['login'] = 'remote-owner'
      ..['isOwner'] = true;
    expect(await sync.applyFields(forgedNewOwner), isFalse);
    expect(TeamService.byId('remote-owner'), isNull);

    final demotedOwner = sync.encode(owner)..['isOwner'] = false;
    expect(await sync.applyFields(demotedOwner), isFalse);
    expect(TeamService.byId(owner.id)!.isOwner, isTrue);

    await sync.removeById(owner.id);
    expect(TeamService.byId(owner.id), isNotNull);
  });
'''
if 'sync tombstone cannot delete one linked inter-org ledger leg' not in text:
    additions += r'''

  test('sync tombstone cannot delete one linked inter-org ledger leg', () async {
    final account = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final leg = TransactionModel(
      id: 'transfer-1_debit',
      title: 'Inter-org debit',
      amount: 100,
      type: TransactionType.expense,
      date: DateTime(2026, 8, 1),
      accountId: account.id,
      organizationId: OrganizationModel.rootId,
      source: TransactionSource.interorg,
      interOrgTransferId: 'transfer-1',
    );
    await Hive.box<TransactionModel>('wesios_treasury').put(leg.id, leg);
    await TransactionsSync().removeById(leg.id);
    expect(Hive.box<TransactionModel>('wesios_treasury').containsKey(leg.id), isTrue);
  });
'''
if 'inter-org sync cannot rewrite immutable transfer core' not in text:
    additions += r'''

  test('inter-org sync cannot rewrite immutable transfer core', () async {
    final a = await OrganizationService.create(
      name: 'Immutable A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final b = await OrganizationService.create(
      name: 'Immutable B',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final accountA = await AccountService.ensureMain(organizationId: a.id);
    final accountB = await AccountService.ensureMain(organizationId: b.id);
    final now = DateTime(2026, 8, 1);
    final transfer = InterOrgTransferModel(
      id: 'immutable-transfer',
      fromOrganizationId: a.id,
      toOrganizationId: b.id,
      fromAccountId: accountA.id,
      toAccountId: accountB.id,
      amount: 100,
      currency: 'RUB',
      amountInFromOrgBase: 100,
      amountInToOrgBase: 100,
      type: InterOrgTransferType.internalTransfer,
      date: now,
      createdBy: 'owner',
      createdAt: now,
      linkedDebitTransactionId: 'immutable-transfer_debit',
      linkedCreditTransactionId: 'immutable-transfer_credit',
    );
    await Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
        .put(transfer.id, transfer);

    final forged = InterOrgTransfersSync().encode(transfer)..['amount'] = 999;
    expect(await InterOrgTransfersSync().applyFields(forged), isFalse);
    expect(
      Hive.box<InterOrgTransferModel>(InterOrgTransferService.boxName)
          .get(transfer.id)!
          .amount,
      100,
    );
  });
'''
if additions:
    pos = text.rfind('\n}')
    if pos < 0:
        raise SystemExit('sync_corruption_guard closing brace missing')
    text = text[:pos] + additions + text[pos:]
p.write_text(text, encoding='utf-8')


# CRM integrity has already landed as permanent source code. Fail if it regresses.
crm = Path('lib/features/crm/services/crm_service.dart').read_text(encoding='utf-8')
if '_requireInteractionWrite(' not in crm or 'Re-authorize the old parent' not in crm:
    raise SystemExit('CRM interaction integrity hardening is missing')


# ---- Remediation status ----
p = Path('TZ_ORG_HIERARCHY_V1_REMEDIATION_STATUS.md')
text = p.read_text(encoding='utf-8')
if '### I4. Owner identity sync boundary' not in text:
    marker = '\n---\n\n## J. Physical ownership / migration'
    pos = text.index(marker)
    extra = r'''

### I4. Owner identity sync boundary — IMPLEMENTED/PENDING FINAL EVIDENCE
Generic employee dataset sync cannot mint, replace, demote or tombstone owner identity. Trusted server-identity bootstrap remains separate.

### I5. InterOrg sync lifecycle immutability — IMPLEMENTED/PENDING FINAL EVIDENCE
Transfer core is immutable after creation; cancellation is one-way and linked ledger legs cannot be tombstoned independently.

### I6. CRM interaction parent integrity — IMPLEMENTED/PENDING FINAL EVIDENCE
Interaction deal must belong to the same client/org, and an existing hidden interaction cannot be seized by re-parenting its id.

### I7. Stale async UI revoke safety — IMPLEMENTED/PENDING FINAL EVIDENCE
Access-sensitive loaders use generation guards; organization picker refreshes on access changes and rejects stale selection after revoke.
'''
    text = text[:pos] + extra + text[pos:]
    p.write_text(text, encoding='utf-8')


# ---- Remove all temporary patch machinery from the final remediation head ----
verifier = Path('.github/workflows/org-remediation-verification.yml')
workflow = verifier.read_text(encoding='utf-8')
if '  repeat-audit-hardening:' in workflow:
    start = workflow.index('  repeat-audit-hardening:')
    end = workflow.index('  analysis:', start)
    verifier.write_text(workflow[:start] + workflow[end:], encoding='utf-8')

for helper in [
    Path('.github/workflows/run-remediation-finalizer.yml'),
    Path('.github/workflows/org-repeat-audit-fix.yml'),
    Path('.github/repeat-audit-trigger.txt'),
    Path('.github/org-remediation-trigger.txt'),
]:
    if helper.exists():
        helper.unlink()

for marker in Path('.github').glob('finalizer-*.txt'):
    marker.unlink()

# Self-delete: no patch runner remains in the final product branch.
Path(__file__).unlink()
