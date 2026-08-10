from pathlib import Path


def once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f'missing marker {path}: {old[:120]!r}')
    p.write_text(text.replace(old, new, 1))


# Generic permission -> organization resolution.
path = 'lib/features/organizations/services/organization_access_service.dart'
once(
    path,
    """  static Future<bool> can(\n    String organizationId,\n    String permission, {\n""",
    """  static Future<Set<String>> organizationIdsFor(\n    String permission, {\n    String? employeeId,\n  }) async {\n    final employee = employeeId == null\n        ? TeamService.current\n        : TeamService.byId(employeeId);\n    if (employee == null) return <String>{};\n    if (employee.isOwner) {\n      final root = await OrganizationService.root();\n      return OrganizationService.subtreeIds(root.id);\n    }\n    final result = <String>{};\n    for (final grant in await grantsFor(employee.id)) {\n      if (!grant.allows(permission)) continue;\n      if (grant.includeSubtree) {\n        result.addAll(await OrganizationService.subtreeIds(grant.organizationId));\n      } else {\n        result.add(grant.organizationId);\n      }\n    }\n    return result;\n  }\n\n  static Future<bool> can(\n    String organizationId,\n    String permission, {\n""",
)

# Treasury read layer must require aggregate finance permission.
path = 'lib/features/treasury/services/treasury_service.dart'
once(
    path,
    """  Future<List<TransactionModel>> getAllTransactions() async {\n    final ids = await OrganizationContext.effectiveOrganizationIds();\n    final all = await getAllTransactionsRaw();\n    return all.where((t) => ids.contains(t.effectiveOrganizationId)).toList();\n  }\n""",
    """  Future<List<TransactionModel>> getAllTransactions() async {\n    var ids = await OrganizationContext.effectiveOrganizationIds();\n    if (TeamService.current != null) {\n      final financeIds = await OrganizationAccessService.organizationIdsFor(\n        OrganizationPermissions.viewFinance,\n      );\n      ids = ids.intersection(financeIds);\n    }\n    final all = await getAllTransactionsRaw();\n    return all.where((t) => ids.contains(t.effectiveOrganizationId)).toList();\n  }\n""",
)
once(
    path,
    """  Future<ForecastResult> generateForecast({\n    int days = 30,\n    WhatIfScenario whatIf = WhatIfScenario.none,\n    double annualDiscountRate = 0.0,\n  }) async {\n    final scoped = await getAllTransactions();\n""",
    """  Future<ForecastResult> generateForecast({\n    int days = 30,\n    WhatIfScenario whatIf = WhatIfScenario.none,\n    double annualDiscountRate = 0.0,\n  }) async {\n    if (TeamService.current != null &&\n        !await OrganizationAccessService.can(\n          OrganizationContext.currentOrganizationId,\n          OrganizationPermissions.viewForecast,\n        )) {\n      throw StateError('view_forecast permission required');\n    }\n    final scoped = await getAllTransactions();\n""",
)

# Account lists are aggregate finance too.
path = 'lib/features/treasury/services/account_service.dart'
once(
    path,
    """  static Future<List<AccountModel>> getAll({bool includeArchived = true}) async {\n    final ids = await OrganizationContext.effectiveOrganizationIds();\n    for (final id in ids) {\n""",
    """  static Future<List<AccountModel>> getAll({bool includeArchived = true}) async {\n    var ids = await OrganizationContext.effectiveOrganizationIds();\n    if (TeamService.current != null) {\n      final financeIds = await OrganizationAccessService.organizationIdsFor(\n        OrganizationPermissions.viewFinance,\n      );\n      ids = ids.intersection(financeIds);\n    }\n    for (final id in ids) {\n""",
)
once(
    path,
    """  }) async {\n    await ensureMain(organizationId: organizationId);\n    final box = await _accountsBox;\n""",
    """  }) async {\n    if (TeamService.current != null &&\n        !await OrganizationAccessService.canViewOrganizationFinance(organizationId)) {\n      return const <AccountModel>[];\n    }\n    await ensureMain(organizationId: organizationId);\n    final box = await _accountsBox;\n""",
)

# Organization management UI gets explicit manage_settings/manage_members gating.
path = 'lib/features/organizations/organizations_screen.dart'
once(
    path,
    """  List<OrganizationModel> _orgs = const [];\n  Set<String> _allowed = const {};\n  bool _loading = true;\n""",
    """  List<OrganizationModel> _orgs = const [];\n  Set<String> _allowed = const {};\n  Set<String> _manageSettings = const {};\n  Set<String> _manageMembers = const {};\n  bool _loading = true;\n""",
)
once(
    path,
    """      final allowed = TeamService.current == null\n          ? orgs.map((e) => e.id).toSet()\n          : await OrganizationAccessService.visibleOrganizationIds();\n      if (!mounted) return;\n      setState(() {\n        _orgs = orgs;\n        _allowed = allowed;\n""",
    """      final allowed = TeamService.current == null\n          ? orgs.map((e) => e.id).toSet()\n          : await OrganizationAccessService.visibleOrganizationIds();\n      final manageSettings = <String>{};\n      final manageMembers = <String>{};\n      final employee = TeamService.current;\n      for (final org in orgs) {\n        if (employee == null || employee.isOwner ||\n            await OrganizationAccessService.can(\n              org.id,\n              OrganizationPermissions.manageOrgSettings,\n            )) {\n          manageSettings.add(org.id);\n        }\n        if (employee == null || employee.isOwner ||\n            await OrganizationAccessService.can(\n              org.id,\n              OrganizationPermissions.manageMembers,\n            )) {\n          manageMembers.add(org.id);\n        }\n      }\n      if (!mounted) return;\n      setState(() {\n        _orgs = orgs;\n        _allowed = allowed;\n        _manageSettings = manageSettings;\n        _manageMembers = manageMembers;\n""",
)
once(
    path,
    """      floatingActionButton: FloatingActionButton.extended(\n        onPressed: _create,\n        icon: const Icon(Icons.add_business_outlined),\n        label: const Text('Создать'),\n      ),\n""",
    """      floatingActionButton: _manageSettings.isEmpty\n          ? null\n          : FloatingActionButton.extended(\n              onPressed: _create,\n              icon: const Icon(Icons.add_business_outlined),\n              label: const Text('Создать'),\n            ),\n""",
)
once(
    path,
    """              if (!org.archived)\n                const PopupMenuItem(value: 'child', child: Text('Создать дочернюю')),\n              const PopupMenuItem(value: 'members', child: Text('Участники и права')),\n              if (!org.isRoot)\n""",
    """              if (!org.archived && _manageSettings.contains(org.id))\n                const PopupMenuItem(value: 'edit', child: Text('Редактировать')),\n              if (!org.archived && _manageSettings.contains(org.id))\n                const PopupMenuItem(value: 'child', child: Text('Создать дочернюю')),\n              if (_manageMembers.contains(org.id))\n                const PopupMenuItem(value: 'members', child: Text('Участники и права')),\n              if (!org.isRoot && _manageSettings.contains(org.id))\n""",
)
once(
    path,
    """      case 'open': await _openOrg(org); break;\n      case 'child': await _create(parent: org); break;\n      case 'members': await _members(org); break;\n""",
    """      case 'open': await _openOrg(org); break;\n      case 'edit':\n        if (_manageSettings.contains(org.id)) await _edit(org);\n        break;\n      case 'child':\n        if (_manageSettings.contains(org.id)) await _create(parent: org);\n        break;\n      case 'members':\n        if (_manageMembers.contains(org.id)) await _members(org);\n        break;\n""",
)
once(
    path,
    """      case 'archive':\n        final ok = await OrganizationService.archive(org.id);\n""",
    """      case 'archive':\n        if (!_manageSettings.contains(org.id)) return;\n        final ok = await OrganizationService.archive(org.id);\n""",
)
once(
    path,
    """      case 'restore':\n        await OrganizationService.restore(org.id);\n""",
    """      case 'restore':\n        if (!_manageSettings.contains(org.id)) return;\n        await OrganizationService.restore(org.id);\n""",
)
once(
    path,
    """    final parentCandidates = _orgs.where((o) => !o.archived).toList();\n""",
    """    final parentCandidates = _orgs\n        .where((o) => !o.archived && _manageSettings.contains(o.id))\n        .toList();\n""",
)

# Never escalate a manager to full rights on a newly-created child. Exact
# parent grants are copied as-is; subtree grants already cover the new child.
once(
    path,
    """      if (employee != null && !employee.isOwner) {\n        await OrganizationAccessService.grant(\n          employeeId: employee.id,\n          organizationId: org.id,\n          includeSubtree: true,\n          permissions: OrganizationPermissions.all,\n          canViewTeamFinance: true,\n          createdBy: employee.id,\n          enforceActor: false,\n        );\n      }\n""",
    """      if (employee != null && !employee.isOwner) {\n        final grants = await OrganizationAccessService.grantsFor(employee.id);\n        OrganizationAccessGrant? template;\n        for (final grant in grants) {\n          if (grant.organizationId == parentId) {\n            template = grant;\n            break;\n          }\n          if (grant.includeSubtree &&\n              (grant.organizationId == parentId ||\n                  await OrganizationService.isDescendant(\n                    parentId,\n                    grant.organizationId,\n                  ))) {\n            template = grant;\n          }\n        }\n        if (template != null && !template.includeSubtree) {\n          await OrganizationAccessService.grant(\n            employeeId: employee.id,\n            organizationId: org.id,\n            includeSubtree: false,\n            permissions: template.permissions,\n            canViewTeamFinance: template.canViewTeamFinance,\n            canViewSelfFinance: template.canViewSelfFinance,\n            createdBy: employee.id,\n            enforceActor: false,\n          );\n        }\n      }\n""",
)

# Complete the specified edit flow.
once(
    path,
    """  Future<void> _members(OrganizationModel org) async {\n""",
    """  Future<void> _edit(OrganizationModel org) async {\n    if (!_manageSettings.contains(org.id)) return;\n    final name = TextEditingController(text: org.name);\n    final currency = TextEditingController(text: org.baseCurrency);\n    final code = TextEditingController(text: org.code ?? '');\n    final description = TextEditingController(text: org.description ?? '');\n    var parentId = org.parentId;\n    final candidates = _orgs.where((o) => !o.archived && o.id != org.id).toList();\n    final save = await showDialog<bool>(\n      context: context,\n      builder: (dialogContext) => StatefulBuilder(\n        builder: (context, setLocal) => AlertDialog(\n          title: Text('Редактировать ${org.name}'),\n          content: SizedBox(\n            width: 440,\n            child: Column(\n              mainAxisSize: MainAxisSize.min,\n              children: [\n                TextField(controller: name, decoration: const InputDecoration(labelText: 'Название')),\n                const SizedBox(height: 10),\n                if (!org.isRoot)\n                  DropdownButtonFormField<String>(\n                    value: parentId,\n                    decoration: const InputDecoration(labelText: 'Родитель'),\n                    items: [\n                      for (final item in candidates)\n                        DropdownMenuItem(value: item.id, child: Text(item.name)),\n                    ],\n                    onChanged: (value) => setLocal(() => parentId = value),\n                  ),\n                const SizedBox(height: 10),\n                TextField(controller: currency, decoration: const InputDecoration(labelText: 'Базовая валюта')),\n                const SizedBox(height: 10),\n                TextField(controller: code, decoration: const InputDecoration(labelText: 'Код')),\n                const SizedBox(height: 10),\n                TextField(controller: description, decoration: const InputDecoration(labelText: 'Описание')),\n              ],\n            ),\n          ),\n          actions: [\n            TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Отмена')),\n            FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Сохранить')),\n          ],\n        ),\n      ),\n    );\n    if (save != true || name.text.trim().isEmpty) return;\n    try {\n      await OrganizationService.update(\n        org,\n        name: name.text,\n        parentId: org.isRoot ? null : parentId,\n        baseCurrency: currency.text,\n        code: code.text.trim().isEmpty ? null : code.text.trim(),\n        description: description.text.trim().isEmpty ? null : description.text.trim(),\n      );\n      await _load();\n    } catch (e) {\n      if (mounted) {\n        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));\n      }\n    }\n  }\n\n  Future<void> _members(OrganizationModel org) async {\n""",
)
