from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'missing marker {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))


path = 'lib/features/team/contacts_screen.dart'
once(
    path,
    "import '../../core/widgets/window_controls.dart';\n",
    "import '../../core/widgets/window_controls.dart';\n"
    "import '../organizations/models/organization_access_grant.dart';\n"
    "import '../organizations/services/organization_access_service.dart';\n"
    "import '../organizations/services/organization_context.dart';\n"
    "import '../organizations/widgets/organization_switcher.dart';\n",
)
once(
    path,
    """  Timer? _activationTicker;\n\n  bool get _ru => WesiLocale.isRussian;\n  bool get _canManage => TeamService.currentPermissions.canManageTeam;\n""",
    """  Timer? _activationTicker;\n  Set<String> _contextEmployeeIds = const <String>{};\n  bool _membersLoading = true;\n  bool _canManageContext = false;\n\n  bool get _ru => WesiLocale.isRussian;\n  bool get _canManage => _canManageContext;\n""",
)
once(
    path,
    """    TeamService.revision.addListener(_refresh);\n    TeamService.ensureOwner();\n""",
    """    TeamService.revision.addListener(_refresh);\n    OrganizationContext.revision.addListener(_refresh);\n    TeamService.ensureOwner();\n    _loadContextMembers();\n""",
)
once(
    path,
    """    TeamService.revision.removeListener(_refresh);\n    super.dispose();\n""",
    """    TeamService.revision.removeListener(_refresh);\n    OrganizationContext.revision.removeListener(_refresh);\n    super.dispose();\n""",
)
once(
    path,
    """  void _refresh() {\n    if (mounted) setState(() {});\n  }\n\n  List<EmployeeModel> get _visible {\n    final query = _search.trim().toLowerCase();\n    if (query.isEmpty) return TeamService.all;\n    return TeamService.all.where((employee) {\n""",
    """  void _refresh() {\n    _loadContextMembers();\n  }\n\n  Future<void> _loadContextMembers() async {\n    final orgIds = await OrganizationContext.effectiveOrganizationIds();\n    final employeeIds = <String>{};\n    for (final employee in TeamService.all) {\n      if (employee.isOwner) {\n        employeeIds.add(employee.id);\n        continue;\n      }\n      final visible = await OrganizationAccessService.visibleOrganizationIds(\n        employeeId: employee.id,\n      );\n      if (visible.intersection(orgIds).isNotEmpty) employeeIds.add(employee.id);\n    }\n    final current = TeamService.current;\n    final canManage = current?.isOwner == true ||\n        (current != null &&\n            await OrganizationAccessService.can(\n              OrganizationContext.currentOrganizationId,\n              OrganizationPermissions.manageMembers,\n            ));\n    if (!mounted) return;\n    setState(() {\n      _contextEmployeeIds = employeeIds;\n      _canManageContext = canManage;\n      _membersLoading = false;\n    });\n  }\n\n  List<EmployeeModel> get _visible {\n    final query = _search.trim().toLowerCase();\n    final contextual = TeamService.all\n        .where((employee) => _contextEmployeeIds.contains(employee.id))\n        .toList();\n    if (query.isEmpty) return contextual;\n    return contextual.where((employee) {\n""",
)
once(
    path,
    """  Future<void> _add() async {\n    final created = await EmployeeEditorScreen.open(context);\n    if (created != null && mounted) setState(() {});\n  }\n""",
    """  Future<void> _add() async {\n    if (!_canManageContext) return;\n    final created = await EmployeeEditorScreen.open(context);\n    if (created == null) return;\n    final orgId = OrganizationContext.currentOrganizationId;\n    final financeVisible = created.permissions.allows(TeamModules.treasury) ||\n        created.permissions.allows(TeamModules.forecast) ||\n        created.permissions.allows(TeamModules.analytics);\n    final permissions = <String>[OrganizationPermissions.view];\n    if (financeVisible) {\n      permissions.addAll(const [\n        OrganizationPermissions.viewFinance,\n        OrganizationPermissions.createTransactions,\n        OrganizationPermissions.editTransactions,\n        OrganizationPermissions.manageAccounts,\n        OrganizationPermissions.manageRecurring,\n        OrganizationPermissions.viewForecast,\n      ]);\n    }\n    await OrganizationAccessService.grant(\n      employeeId: created.id,\n      organizationId: orgId,\n      includeSubtree: false,\n      permissions: permissions,\n      canViewSelfFinance: true,\n      canViewTeamFinance: created.permissions.canSeeOthersStats,\n    );\n    await _loadContextMembers();\n  }\n""",
)
once(
    path,
    """    final people = _visible;\n    return Scaffold(\n""",
    """    final people = _visible;\n    return Scaffold(\n""",
)
once(
    path,
    """            Expanded(\n              child: people.isEmpty\n                  ? _empty()\n                  : ListView.builder(\n""",
    """            Expanded(\n              child: _membersLoading\n                  ? const Center(child: CircularProgressIndicator())\n                  : people.isEmpty\n                      ? _empty()\n                      : ListView.builder(\n""",
)
# Header gets global context switcher so Team membership is visibly scoped.
once(
    path,
    """            if (_ownerOnly)\n              IconButton(\n""",
    """            const OrganizationSwitcher(compact: true),\n            const SizedBox(width: 6),\n            if (_ownerOnly)\n              IconButton(\n""",
)
