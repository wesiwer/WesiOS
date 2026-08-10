from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'missing marker {path}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1))


# Subtree breakdown itself must only enumerate organizations with aggregate
# finance permission.
path = 'lib/features/organizations/widgets/subtree_finance_breakdown.dart'
once(
    path,
    "import '../../treasury/services/treasury_service.dart';\n",
    "import '../../treasury/services/treasury_service.dart';\n"
    "import '../../team/services/team_service.dart';\n"
    "import '../models/organization_access_grant.dart';\n"
    "import '../services/organization_access_service.dart';\n",
)
once(
    path,
    """    final ids = await OrganizationContext.effectiveOrganizationIds();\n    if (ids.length <= 1) return const [];\n""",
    """    var ids = await OrganizationContext.effectiveOrganizationIds();\n    if (TeamService.current != null) {\n      final financeIds = await OrganizationAccessService.organizationIdsFor(\n        OrganizationPermissions.viewFinance,\n      );\n      ids = ids.intersection(financeIds);\n    }\n    if (ids.length <= 1) return const [];\n""",
)

# Treasury must visibly expose the mandatory subtree organization breakdown.
path = 'lib/features/treasury/treasury_screen.dart'
once(
    path,
    "import '../organizations/widgets/organization_switcher.dart';\n",
    "import '../organizations/widgets/organization_switcher.dart';\n"
    "import '../organizations/widgets/subtree_finance_breakdown.dart';\n",
)
once(
    path,
    """          _balanceCard(),\n          const SizedBox(height: 20),\n""",
    """          _balanceCard(),\n          if (OrganizationContext.scope == OrganizationScope.subtree) ...[\n            const SizedBox(height: 16),\n            const SubtreeFinanceBreakdown(),\n          ],\n          const SizedBox(height: 20),\n""",
)

# Analytics must refresh when organization context changes and show the same
# mandatory subtree breakdown.
path = 'lib/features/analytics/analytics_screen.dart'
once(
    path,
    "import '../tasks/services/task_service.dart';\n",
    "import '../tasks/services/task_service.dart';\n"
    "import '../organizations/services/organization_context.dart';\n"
    "import '../organizations/widgets/subtree_finance_breakdown.dart';\n",
)
once(
    path,
    """    TreasuryService.revision.addListener(_load);\n    TaskService.revision.addListener(_load);\n""",
    """    TreasuryService.revision.addListener(_load);\n    TaskService.revision.addListener(_load);\n    OrganizationContext.revision.addListener(_load);\n""",
)
once(
    path,
    """    TreasuryService.revision.removeListener(_load);\n    TaskService.revision.removeListener(_load);\n""",
    """    TreasuryService.revision.removeListener(_load);\n    TaskService.revision.removeListener(_load);\n    OrganizationContext.revision.removeListener(_load);\n""",
)
once(
    path,
    """                    _kpiGrid(d),\n                    const SizedBox(height: 18),\n                    _trendCard(d),\n""",
    """                    _kpiGrid(d),\n                    if (OrganizationContext.scope == OrganizationScope.subtree) ...[\n                      const SizedBox(height: 18),\n                      const SubtreeFinanceBreakdown(),\n                    ],\n                    const SizedBox(height: 18),\n                    _trendCard(d),\n""",
)

# Member management must expose the actual permission list, not just a single
# coarse toggle.
path = 'lib/features/organizations/organizations_screen.dart'
once(
    path,
    """  Future<void> _subtree(String employeeId, bool value) async {\n""",
    """  Future<void> _selfFinance(String employeeId, bool value) async {\n    final grant = _grants[employeeId];\n    if (grant == null) return;\n    await OrganizationAccessService.grant(\n      employeeId: employeeId,\n      organizationId: grant.organizationId,\n      includeSubtree: grant.includeSubtree,\n      permissions: grant.permissions,\n      canViewSelfFinance: value,\n      canViewTeamFinance: grant.canViewTeamFinance,\n    );\n    await _load();\n  }\n\n  Future<void> _permission(\n    String employeeId,\n    String permission,\n    bool value,\n  ) async {\n    final grant = _grants[employeeId];\n    if (grant == null) return;\n    final permissions = grant.permissions.toSet();\n    if (value) {\n      permissions.add(permission);\n      permissions.add(OrganizationPermissions.view);\n    } else {\n      permissions.remove(permission);\n    }\n    await OrganizationAccessService.grant(\n      employeeId: employeeId,\n      organizationId: grant.organizationId,\n      includeSubtree: grant.includeSubtree,\n      permissions: permissions.toList(),\n      canViewSelfFinance: grant.canViewSelfFinance,\n      canViewTeamFinance: grant.canViewTeamFinance,\n    );\n    await _load();\n  }\n\n  Future<void> _subtree(String employeeId, bool value) async {\n""",
)
once(
    path,
    """                        CheckboxListTile(\n                          value: grant.includeSubtree,\n                          onChanged: (v) => _subtree(employee.id, v ?? false),\n                          title: const Text('Доступ к поддереву'),\n                        ),\n                        CheckboxListTile(\n                          value: grant.canViewTeamFinance,\n                          onChanged: (v) => _teamFinance(employee.id, v ?? false),\n                          title: const Text('Видит финансы команды'),\n                        ),\n""",
    """                        CheckboxListTile(\n                          value: grant.canViewSelfFinance,\n                          onChanged: (v) => _selfFinance(employee.id, v ?? true),\n                          title: const Text('Личные показатели (Мои)'),\n                        ),\n                        CheckboxListTile(\n                          value: grant.includeSubtree,\n                          onChanged: (v) => _subtree(employee.id, v ?? false),\n                          title: const Text('Доступ к поддереву'),\n                        ),\n                        CheckboxListTile(\n                          value: grant.canViewTeamFinance,\n                          onChanged: (v) => _teamFinance(employee.id, v ?? false),\n                          title: const Text('Персональные финансы команды'),\n                        ),\n                        const Divider(),\n                        for (final permission in const [\n                          OrganizationPermissions.viewFinance,\n                          OrganizationPermissions.createTransactions,\n                          OrganizationPermissions.editTransactions,\n                          OrganizationPermissions.manageAccounts,\n                          OrganizationPermissions.manageRecurring,\n                          OrganizationPermissions.viewForecast,\n                          OrganizationPermissions.manageOrgSettings,\n                          OrganizationPermissions.manageMembers,\n                        ])\n                          CheckboxListTile(\n                            dense: true,\n                            value: grant.permissions.contains(permission),\n                            onChanged: (v) => _permission(\n                              employee.id,\n                              permission,\n                              v ?? false,\n                            ),\n                            title: Text(permission),\n                          ),\n""",
)
