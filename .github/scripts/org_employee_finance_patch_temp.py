from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'missing marker {path}: {old[:140]!r}')
    p.write_text(text.replace(old, new, 1))


# CRM editor must persist stable employee IDs instead of only display names.
path = 'lib/features/crm/crm_screen.dart'
once(
    path,
    "import '../team/widgets/employee_or_custom_field.dart';\n",
    "import '../team/widgets/employee_or_custom_field.dart';\n"
    "import '../team/services/team_service.dart';\n",
)
once(
    path,
    "    _owner = TextEditingController(text: value?.owner ?? '');\n",
    "    _owner = TextEditingController(\n"
    "      text: value?.ownerEmployeeId ?? value?.owner ?? TeamService.current?.id ?? '',\n"
    "    );\n",
)
once(
    path,
    """              storeEmployeeId: false,\n              allowCustom: true,\n""",
    """              storeEmployeeId: true,\n              allowCustom: true,\n""",
)
once(
    path,
    """    final now = DateTime.now();\n    final existing = widget.existing;\n    Navigator.pop(\n""",
    """    final now = DateTime.now();\n    final existing = widget.existing;\n    final ownerValue = _owner.text.trim();\n    final ownerEmployee = TeamService.byId(ownerValue);\n    Navigator.pop(\n""",
)
once(
    path,
    """        owner: _owner.text.trim(),\n        notes: _notes.text.trim(),\n""",
    """        owner: ownerEmployee?.displayName ?? ownerValue,\n        ownerEmployeeId: ownerEmployee?.id,\n        notes: _notes.text.trim(),\n""",
)
# Deal responsibility state + selector.
once(
    path,
    """  late double _probability;\n  DateTime? _expectedClose;\n""",
    """  late double _probability;\n  String? _responsibleEmployeeId;\n  DateTime? _expectedClose;\n""",
)
once(
    path,
    """    _probability =\n        (value?.probability ?? _defaultProbability(_stage)).toDouble();\n    _expectedClose = value?.expectedCloseAt;\n""",
    """    _probability =\n        (value?.probability ?? _defaultProbability(_stage)).toDouble();\n    _responsibleEmployeeId =\n        value?.responsibleEmployeeId ?? TeamService.current?.id;\n    _expectedClose = value?.expectedCloseAt;\n""",
)
once(
    path,
    """            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n""",
    """            const SizedBox(height: 10),\n            EmployeeOrCustomField(\n              label: _ru ? 'Ответственный сотрудник' : 'Responsible employee',\n              value: _responsibleEmployeeId,\n              storeEmployeeId: true,\n              allowCustom: false,\n              onChanged: (value) =>\n                  setState(() => _responsibleEmployeeId = value),\n            ),\n            const SizedBox(height: 10),\n            _field(_tags, _ru ? 'Теги через запятую' : 'Comma-separated tags'),\n""",
)
once(
    path,
    """        expectedCloseAt: _expectedClose,\n        closedAt: existing?.closedAt,\n""",
    """        expectedCloseAt: _expectedClose,\n        closedAt: existing?.closedAt,\n        organizationId: existing?.organizationId ??\n            widget.clients\n                .where((client) => client.id == _clientId)\n                .map((client) => client.organizationId)\n                .firstOrNull ??\n            '',\n        responsibleEmployeeId: _responsibleEmployeeId,\n""",
)
# crm_screen already has a private firstOrNull extension only if current code
# supplies one? Add a local safe helper to avoid depending on another library.
p = Path(path)
s = p.read_text()
if 'extension _CrmFirstOrNull<T>' not in s:
    s += "\n\nextension _CrmFirstOrNull<T> on Iterable<T> {\n  T? get firstOrNull => isEmpty ? null : first;\n}\n"
p.write_text(s)

# Saving must preserve existing org and explicit responsibility; never silently
# reattribute a custom/unassigned record to the current user.
path = 'lib/features/crm/services/crm_service.dart'
once(path, "import '../../team/services/team_service.dart';\n", '')
once(
    path,
    """  static Future<void> saveClient(CrmClient client) async {\n    final all = await clients();\n    final now = DateTime.now();\n    final normalized = client.copyWith(\n      updatedAt: now,\n      organizationId: client.organizationId.isEmpty\n          ? OrganizationContext.currentOrganizationId\n          : client.organizationId,\n      ownerEmployeeId: client.ownerEmployeeId ?? TeamService.current?.id,\n    );\n    final index = all.indexWhere((value) => value.id == client.id);\n""",
    """  static Future<void> saveClient(CrmClient client) async {\n    final all = await clients();\n    final now = DateTime.now();\n    final index = all.indexWhere((value) => value.id == client.id);\n    final previous = index < 0 ? null : all[index];\n    final normalized = client.copyWith(\n      updatedAt: now,\n      organizationId: client.organizationId.isEmpty\n          ? (previous?.organizationId ?? OrganizationContext.currentOrganizationId)\n          : client.organizationId,\n      ownerEmployeeId: client.ownerEmployeeId,\n      clearOwnerEmployee: client.ownerEmployeeId == null,\n    );\n""",
)
once(
    path,
    """  static Future<void> saveDeal(CrmDeal deal) async {\n    final all = await deals();\n    final now = DateTime.now();\n    var next = deal.copyWith(\n      updatedAt: now,\n      organizationId: deal.organizationId.isEmpty\n          ? OrganizationContext.currentOrganizationId\n          : deal.organizationId,\n      responsibleEmployeeId:\n          deal.responsibleEmployeeId ?? TeamService.current?.id,\n    );\n""",
    """  static Future<void> saveDeal(CrmDeal deal) async {\n    final all = await deals();\n    final now = DateTime.now();\n    final index = all.indexWhere((value) => value.id == deal.id);\n    final previous = index < 0 ? null : all[index];\n    var next = deal.copyWith(\n      updatedAt: now,\n      organizationId: deal.organizationId.isEmpty\n          ? (previous?.organizationId ?? OrganizationContext.currentOrganizationId)\n          : deal.organizationId,\n      responsibleEmployeeId: deal.responsibleEmployeeId,\n      clearResponsibleEmployee: deal.responsibleEmployeeId == null,\n    );\n""",
)
# Remove the second declaration of index in saveDeal after normalization.
once(
    path,
    """    final index = all.indexWhere((value) => value.id == deal.id);\n    if (index < 0) {\n      all.add(next);\n""",
    """    if (index < 0) {\n      all.add(next);\n""",
)

# Employee finance gets risk counters and same-length previous-period comparison.
path = 'lib/features/organizations/services/employee_finance_service.dart'
once(
    path,
    "import '../../treasury/services/forecast_engine.dart';\n",
    "import '../../treasury/services/forecast_engine.dart';\n"
    "import '../../treasury/services/anomaly_engine.dart';\n",
)
once(
    path,
    """  final int overdueEvents;\n  final List<TransactionModel> upcoming;\n""",
    """  final int overdueEvents;\n  final int missedDealExpectations;\n  final int anomalousExpenses;\n  final List<TransactionModel> upcoming;\n""",
)
once(
    path,
    """    required this.overdueEvents,\n    required this.upcoming,\n""",
    """    required this.overdueEvents,\n    required this.missedDealExpectations,\n    required this.anomalousExpenses,\n    required this.upcoming,\n""",
)
once(
    path,
    """        overdueEvents: 0,\n        upcoming: const [],\n""",
    """        overdueEvents: 0,\n        missedDealExpectations: 0,\n        anomalousExpenses: 0,\n        upcoming: const [],\n""",
)
# Add comparison value object before row.
once(
    path,
    """class EmployeeFinanceRow {\n""",
    """class EmployeeFinanceComparison {\n  final EmployeeFinanceMetrics current;\n  final EmployeeFinanceMetrics previous;\n\n  const EmployeeFinanceComparison({\n    required this.current,\n    required this.previous,\n  });\n}\n\nclass EmployeeFinanceRow {\n""",
)
once(
    path,
    """    var recurring = 0.0;\n    var overdue = 0;\n    final now = DateTime.now();\n""",
    """    var recurring = 0.0;\n    var overdue = 0;\n    var missedDeals = 0;\n    var anomalousExpenses = 0;\n    final anomalyIds = AnomalyEngine.detect(transactions).map((e) => e.id).toSet();\n    final now = DateTime.now();\n""",
)
once(
    path,
    """        if (tx.type == TransactionType.income) {\n          income += tx.amount;\n        } else {\n          expense += tx.amount;\n        }\n""",
    """        if (tx.type == TransactionType.income) {\n          income += tx.amount;\n        } else {\n          expense += tx.amount;\n          if (anomalyIds.contains(tx.id)) anomalousExpenses++;\n        }\n""",
)
once(
    path,
    """    for (final deal in deals) {\n      if (deal.responsibleEmployeeId != employeeId ||\n          deal.stage != DealStage.won) {\n        continue;\n      }\n""",
    """    for (final deal in deals) {\n      if (deal.responsibleEmployeeId != employeeId) continue;\n      if (deal.isOpen &&\n          deal.expectedCloseAt != null &&\n          deal.expectedCloseAt!.isBefore(now)) {\n        missedDeals++;\n      }\n      if (deal.stage != DealStage.won) continue;\n""",
)
once(
    path,
    """      overdueEvents: overdue,\n      upcoming: upcoming,\n""",
    """      overdueEvents: overdue,\n      missedDealExpectations: missedDeals,\n      anomalousExpenses: anomalousExpenses,\n      upcoming: upcoming,\n""",
)
# Replace self() with comparison-backed implementation.
start = """  static Future<EmployeeFinanceMetrics> self({int periodDays = 30}) async {\n"""
end = """  /// Aggregate finance for the selected organization or authorized subtree.\n"""
p = Path(path)
s = p.read_text()
i = s.find(start)
j = s.find(end, i)
if i < 0 or j < 0:
    raise SystemExit('self block markers missing')
new_block = """  static Future<EmployeeFinanceComparison> selfComparison({\n    int periodDays = 30,\n  }) async {\n    final employee = TeamService.current;\n    final now = DateTime.now();\n    final currentFrom = now.subtract(Duration(days: periodDays - 1));\n    final previousTo = currentFrom.subtract(const Duration(microseconds: 1));\n    final previousFrom = previousTo.subtract(Duration(days: periodDays - 1));\n    if (employee == null) {\n      return EmployeeFinanceComparison(\n        current: EmployeeFinanceMetrics.empty('', currentFrom, now),\n        previous: EmployeeFinanceMetrics.empty('', previousFrom, previousTo),\n      );\n    }\n    final orgId = OrganizationContext.currentOrganizationId;\n    if (!await OrganizationAccessService.canViewSelfFinance(orgId)) {\n      return EmployeeFinanceComparison(\n        current: EmployeeFinanceMetrics.empty(employee.id, currentFrom, now),\n        previous: EmployeeFinanceMetrics.empty(employee.id, previousFrom, previousTo),\n      );\n    }\n    final ids = await OrganizationContext.effectiveOrganizationIds();\n    final all = (await TreasuryService().getAllTransactionsRaw())\n        .where((t) => ids.contains(t.effectiveOrganizationId))\n        .toList();\n    final deals = await CrmService.dealsForOrganizations(ids);\n    final tasks = await TaskService().getForOrganizations(ids);\n    return EmployeeFinanceComparison(\n      current: _calculate(\n        employeeId: employee.id,\n        transactions: all,\n        deals: deals,\n        tasks: tasks,\n        from: currentFrom,\n        to: now,\n      ),\n      previous: _calculate(\n        employeeId: employee.id,\n        transactions: all,\n        deals: deals,\n        tasks: tasks,\n        from: previousFrom,\n        to: previousTo,\n      ),\n    );\n  }\n\n  static Future<EmployeeFinanceMetrics> self({int periodDays = 30}) async =>\n      (await selfComparison(periodDays: periodDays)).current;\n\n"""
s = s[:i] + new_block + s[j:]
p.write_text(s)

# My Finance: period switching, previous-period dynamics, explicit risk block.
path = 'lib/features/organizations/my_finance_screen.dart'
once(
    path,
    """  EmployeeFinanceView _view = EmployeeFinanceView.self;\n  EmployeeFinanceMetrics? _self;\n""",
    """  EmployeeFinanceView _view = EmployeeFinanceView.self;\n  int _periodDays = 30;\n  EmployeeFinanceMetrics? _self;\n  EmployeeFinanceMetrics? _previousSelf;\n""",
)
once(
    path,
    """    final self = await EmployeeFinanceService.self(periodDays: 30);\n    final forecast = await EmployeeFinanceService.selfForecast(days: 30);\n""",
    """    final comparison = await EmployeeFinanceService.selfComparison(\n      periodDays: _periodDays,\n    );\n    final self = comparison.current;\n    final previousSelf = comparison.previous;\n    final forecast = await EmployeeFinanceService.selfForecast(days: 30);\n""",
)
once(
    path,
    """        periodDays: 30,\n""",
    """        periodDays: _periodDays,\n""",
)
once(
    path,
    """          periodDays: 30,\n""",
    """          periodDays: _periodDays,\n""",
)
once(
    path,
    """      _self = self;\n      _organization = organization;\n""",
    """      _self = self;\n      _previousSelf = previousSelf;\n      _organization = organization;\n""",
)
once(
    path,
    """                  _viewSelector(),\n                  const SizedBox(height: 16),\n""",
    """                  _periodSelector(),\n                  const SizedBox(height: 12),\n                  _viewSelector(),\n                  const SizedBox(height: 16),\n""",
)
# Add period selector before view selector.
once(
    path,
    """  Widget _viewSelector() {\n""",
    """  Widget _periodSelector() => Wrap(\n        spacing: 8,\n        children: [\n          for (final days in const [7, 30, 90])\n            ChoiceChip(\n              label: Text('$days дн.'),\n              selected: _periodDays == days,\n              onSelected: (_) async {\n                if (_periodDays == days) return;\n                setState(() => _periodDays = days);\n                await _load();\n              },\n            ),\n        ],\n      );\n\n  Widget _viewSelector() {\n""",
)
# Add dynamics and risk sections in self view before forecast.
once(
    path,
    """        const SizedBox(height: 18),\n        _section(\n          'Личный прогноз вклада',\n""",
    """        const SizedBox(height: 18),\n        _section(\n          'Динамика к предыдущим $_periodDays дням',\n          _comparisonText(m, _previousSelf),\n        ),\n        const SizedBox(height: 12),\n        _section(\n          'Личные риски',\n          _riskText(m),\n        ),\n        const SizedBox(height: 18),\n        _section(\n          'Личный прогноз вклада',\n""",
)
# Add helpers before metric widget.
once(
    path,
    """  Widget _metric(String label, String value, IconData icon, Color color) =>\n""",
    """  String _delta(double current, double previous) {\n    if (previous == 0) {\n      if (current == 0) return '0%';\n      return current > 0 ? '+новое' : '-новое';\n    }\n    final value = (current - previous) / previous.abs() * 100;\n    final sign = value > 0 ? '+' : '';\n    return '$sign${value.toStringAsFixed(0)}%';\n  }\n\n  String _comparisonText(\n    EmployeeFinanceMetrics current,\n    EmployeeFinanceMetrics? previous,\n  ) {\n    if (previous == null) return 'Нет базы для сравнения.';\n    return 'Вклад ${_delta(current.contribution, previous.contribution)} • '\n        'расходы ${_delta(current.expenses, previous.expenses)} • '\n        'net ${_delta(current.net, previous.net)}.';\n  }\n\n  String _riskText(EmployeeFinanceMetrics metrics) {\n    final risks = <String>[];\n    if (metrics.overdueEvents > 0) {\n      risks.add('просроченные денежные задачи: ${metrics.overdueEvents}');\n    }\n    if (metrics.missedDealExpectations > 0) {\n      risks.add('сделки позже ожидаемой даты: ${metrics.missedDealExpectations}');\n    }\n    if (metrics.anomalousExpenses > 0) {\n      risks.add('аномальные расходы: ${metrics.anomalousExpenses}');\n    }\n    return risks.isEmpty ? 'Активных персональных финансовых рисков не найдено.' : risks.join(' • ');\n  }\n\n  Widget _metric(String label, String value, IconData icon, Color color) =>\n""",
)
