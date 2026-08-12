from pathlib import Path
import re


def one(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, got {count}')
    return text.replace(old, new, 1)


def regex_one(text: str, pattern: str, replacement: str, label: str) -> str:
    result, count = re.subn(pattern, replacement, text, count=1, flags=re.S | re.M)
    if count != 1:
        raise SystemExit(f'{label}: expected one match, got {count}')
    return result


org_path = Path('lib/features/organizations/organizations_screen.dart')
org = org_path.read_text()
if "widgets/organization_access_editor.dart" not in org:
    org = one(
        org,
        "import 'services/organization_service.dart';\n",
        "import 'services/organization_service.dart';\nimport 'widgets/organization_access_editor.dart';\n",
        'organization editor import',
    )
org = org.replace(
    'Интерфейс показывает только права, которые текущая роль сама может делегировать. Service layer повторно проверяет это при сохранении.',
    'Показываются только сотрудники и права, которыми ваша роль может управлять. Сервер повторно проверит доступ при сохранении.',
)
org = regex_one(
    org,
    r"^                      if \(_grants\[employee\.id\] case final grant\?\) \.\.\.\[\n.*?^                      \],\n",
    """                      if (_grants[employee.id] case final grant?) ...[\n                        ListTile(\n                          leading: Icon(\n                            Icons.tune_rounded,\n                            color: AppTheme.accent,\n                          ),\n                          title: const Text('Настроить доступ'),\n                          subtitle: Text(\n                            OrganizationAccessEditor.shortSummary(grant),\n                          ),\n                          trailing: const Icon(Icons.chevron_right),\n                          onTap: () async {\n                            final changed = await OrganizationAccessEditor.open(\n                              context,\n                              employee: employee,\n                              organization: widget.organization,\n                            );\n                            if (changed == true) await _load();\n                          },\n                        ),\n                      ],\n""",
    'organization access details',
)
org_path.write_text(org)

contacts_path = Path('lib/features/team/contacts_screen.dart')
contacts = contacts_path.read_text()
if "models/organization_model.dart" not in contacts:
    contacts = one(
        contacts,
        "import '../organizations/models/organization_access_grant.dart';\n",
        "import '../organizations/models/organization_access_grant.dart';\nimport '../organizations/models/organization_model.dart';\n",
        'organization model import',
    )
if "services/organization_service.dart" not in contacts:
    contacts = one(
        contacts,
        "import '../organizations/services/organization_context.dart';\n",
        "import '../organizations/services/organization_context.dart';\nimport '../organizations/services/organization_service.dart';\n",
        'organization service import',
    )
if "widgets/organization_access_editor.dart" not in contacts:
    contacts = one(
        contacts,
        "import '../organizations/widgets/organization_switcher.dart';\n",
        "import '../organizations/widgets/organization_access_editor.dart';\nimport '../organizations/widgets/organization_switcher.dart';\n",
        'organization editor import',
    )
if 'enum _ContactsSort' not in contacts:
    contacts = one(
        contacts,
        'class ContactsScreen extends StatefulWidget {',
        'enum _ContactsSort { name, position, organization }\n\nclass ContactsScreen extends StatefulWidget {',
        'sort enum',
    )
contacts = one(
    contacts,
    """  Set<String> _contextEmployeeIds = const <String>{};
  bool _membersLoading = true;
  bool _canManageContext = false;
""",
    """  Set<String> _contextEmployeeIds = const <String>{};
  List<OrganizationModel> _organizations = const <OrganizationModel>[];
  Map<String, Set<String>> _employeeOrganizationIds =
      const <String, Set<String>>{};
  Set<String> _manageableOrganizationIds = const <String>{};
  String? _organizationFilter;
  String? _positionFilter;
  _ContactsSort _sort = _ContactsSort.name;
  bool _membersLoading = true;
  bool _canManageContext = false;
""",
    'contacts state fields',
)
contacts = regex_one(
    contacts,
    r"^  Future<void> _loadContextMembers\(\) async \{.*?^  \}\n\n  List<EmployeeModel> get _visible \{.*?^  \}\n\n  Future<void> _add\(\) async \{",
    """  Future<void> _loadContextMembers() async {
    try {
      final allOrganizations = await OrganizationService.all();
      final current = TeamService.current;
      final allowedOrganizationIds = _localFullAccess
          ? allOrganizations.map((o) => o.id).toSet()
          : await OrganizationAccessService.visibleOrganizationIds();
      final visibleOrganizations = allOrganizations
          .where((o) => allowedOrganizationIds.contains(o.id))
          .toList();

      final manageable = <String>{};
      if (_localFullAccess || current?.isOwner == true) {
        manageable.addAll(allowedOrganizationIds);
      } else if (current != null) {
        for (final organization in visibleOrganizations) {
          if (await OrganizationAccessService.can(
            organization.id,
            OrganizationPermissions.manageMembers,
          )) {
            manageable.add(organization.id);
          }
        }
      }

      final employeeIds = <String>{};
      final memberships = <String, Set<String>>{};
      for (final employee in TeamService.all) {
        final grants = await OrganizationAccessService.grantsFor(employee.id);
        final exactIds = grants.map((g) => g.organizationId).toSet();
        if (employee.isOwner && exactIds.isEmpty) {
          exactIds.add(OrganizationModel.rootId);
        }
        memberships[employee.id] = exactIds;
        if (_localFullAccess ||
            employee.isOwner ||
            exactIds.intersection(allowedOrganizationIds).isNotEmpty) {
          employeeIds.add(employee.id);
        }
      }

      final canManage = current?.isOwner == true ||
          (current != null &&
              manageable.contains(OrganizationContext.currentOrganizationId));
      if (!mounted) return;
      setState(() {
        _contextEmployeeIds = employeeIds;
        _organizations = visibleOrganizations;
        _employeeOrganizationIds = memberships;
        _manageableOrganizationIds = manageable;
        if (_organizationFilter != null &&
            !allowedOrganizationIds.contains(_organizationFilter)) {
          _organizationFilter = null;
        }
        _canManageContext = canManage;
        _membersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _contextEmployeeIds = _localFullAccess
            ? TeamService.all.map((e) => e.id).toSet()
            : const <String>{};
        _canManageContext = TeamService.isOwnerSession;
        _membersLoading = false;
      });
    }
  }

  List<EmployeeModel> get _visible {
    final query = _search.trim().toLowerCase();
    final result = TeamService.all
        .where((employee) => _contextEmployeeIds.contains(employee.id))
        .where((employee) => _organizationFilter == null ||
            (_employeeOrganizationIds[employee.id] ?? const <String>{})
                .contains(_organizationFilter))
        .where((employee) => _positionFilter == null ||
            employee.position.trim() == _positionFilter)
        .where((employee) {
          if (query.isEmpty) return true;
          return employee.displayName.toLowerCase().contains(query) ||
              employee.position.toLowerCase().contains(query) ||
              employee.login.contains(query) ||
              employee.email.toLowerCase().contains(query) ||
              employee.phone.contains(query) ||
              _organizationNames(employee).toLowerCase().contains(query);
        })
        .toList();

    int compare(EmployeeModel a, EmployeeModel b) {
      switch (_sort) {
        case _ContactsSort.position:
          final byPosition =
              a.position.toLowerCase().compareTo(b.position.toLowerCase());
          return byPosition != 0
              ? byPosition
              : a.displayName
                  .toLowerCase()
                  .compareTo(b.displayName.toLowerCase());
        case _ContactsSort.organization:
          final byOrganization = _organizationNames(a)
              .toLowerCase()
              .compareTo(_organizationNames(b).toLowerCase());
          return byOrganization != 0
              ? byOrganization
              : a.displayName
                  .toLowerCase()
                  .compareTo(b.displayName.toLowerCase());
        case _ContactsSort.name:
          return a.displayName
              .toLowerCase()
              .compareTo(b.displayName.toLowerCase());
      }
    }

    result.sort(compare);
    return result;
  }

  List<OrganizationModel> _employeeOrganizations(EmployeeModel employee) {
    final ids = _employeeOrganizationIds[employee.id] ?? const <String>{};
    return _organizations.where((o) => ids.contains(o.id)).toList();
  }

  String _organizationNames(EmployeeModel employee) =>
      _employeeOrganizations(employee).map((o) => o.name).join(', ');

  List<String> get _positions {
    final result = TeamService.all
        .where((e) => _contextEmployeeIds.contains(e.id))
        .map((e) => e.position.trim())
        .where((p) => p.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  Future<void> _openAccess(EmployeeModel employee) async {
    if (employee.isOwner || _manageableOrganizationIds.isEmpty) return;
    OrganizationModel? organization;
    if (_organizationFilter != null &&
        _manageableOrganizationIds.contains(_organizationFilter)) {
      organization = _organizations
          .where((o) => o.id == _organizationFilter)
          .firstOrNull;
    }

    if (organization == null) {
      final candidates = _organizations
          .where((o) => _manageableOrganizationIds.contains(o.id))
          .toList();
      if (candidates.length == 1) {
        organization = candidates.single;
      } else {
        final selectedId = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: Text('Организация для ${employee.displayName}'),
            children: [
              for (final item in candidates)
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, item.id),
                  child: Row(
                    children: [
                      const Icon(Icons.business_outlined, size: 18),
                      const SizedBox(width: 10),
                      Expanded(child: Text(item.name)),
                      if ((_employeeOrganizationIds[employee.id] ??
                              const <String>{})
                          .contains(item.id))
                        Icon(
                          Icons.check_circle,
                          size: 17,
                          color: AppTheme.accentGreen,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
        if (selectedId == null || !mounted) return;
        organization =
            candidates.where((o) => o.id == selectedId).firstOrNull;
      }
    }
    if (organization == null || !mounted) return;
    final changed = await OrganizationAccessEditor.open(
      context,
      employee: employee,
      organization: organization,
    );
    if (changed == true) await _loadContextMembers();
  }

  Future<void> _add() async {""",
    'contacts loading/filtering methods',
)
contacts = one(
    contacts,
    """            _header(people.length),
            _searchField(),
            Expanded(
""",
    """            _header(people.length),
            _searchField(),
            _filterBar(),
            Expanded(
""",
    'filter bar placement',
)
filter_bar = r'''  Widget _filterBar() {
    final positions = _positions;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      child: Row(
        children: [
          _filterMenu(
            icon: Icons.business_outlined,
            label: _organizationFilter == null
                ? 'Все организации'
                : _organizations
                        .where((o) => o.id == _organizationFilter)
                        .map((o) => o.name)
                        .firstOrNull ??
                    'Организация',
            items: [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('Все организации'),
              ),
              for (final organization in _organizations)
                PopupMenuItem<String?>(
                  value: organization.id,
                  child: Text(organization.name),
                ),
            ],
            onSelected: (value) =>
                setState(() => _organizationFilter = value),
          ),
          const SizedBox(width: 8),
          _filterMenu(
            icon: Icons.badge_outlined,
            label: _positionFilter ?? 'Все должности',
            items: [
              const PopupMenuItem<String?>(
                value: null,
                child: Text('Все должности'),
              ),
              for (final position in positions)
                PopupMenuItem<String?>(
                  value: position,
                  child: Text(position),
                ),
            ],
            onSelected: (value) => setState(() => _positionFilter = value),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<_ContactsSort>(
            initialValue: _sort,
            onSelected: (value) => setState(() => _sort = value),
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: _ContactsSort.name,
                child: Text('По имени'),
              ),
              PopupMenuItem(
                value: _ContactsSort.position,
                child: Text('По должности'),
              ),
              PopupMenuItem(
                value: _ContactsSort.organization,
                child: Text('По организации'),
              ),
            ],
            child: _filterChip(
              Icons.sort_rounded,
              _sort == _ContactsSort.name
                  ? 'По имени'
                  : _sort == _ContactsSort.position
                      ? 'По должности'
                      : 'По организации',
            ),
          ),
          if (_organizationFilter != null || _positionFilter != null) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => setState(() {
                _organizationFilter = null;
                _positionFilter = null;
              }),
              icon: const Icon(Icons.filter_alt_off_outlined, size: 17),
              label: const Text('Сбросить'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _filterMenu({
    required IconData icon,
    required String label,
    required List<PopupMenuEntry<String?>> items,
    required ValueChanged<String?> onSelected,
  }) =>
      PopupMenuButton<String?>(
        onSelected: onSelected,
        itemBuilder: (_) => items,
        child: _filterChip(icon, label),
      );

  Widget _filterChip(IconData icon, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.55),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: AppTheme.accent),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more, size: 16, color: AppTheme.textMuted),
          ],
        ),
      );

'''
contacts = one(contacts, '  Widget _empty() => Center(', filter_bar + '  Widget _empty() => Center(', 'filter widgets')
contacts = one(
    contacts,
    """                    if (_canManage)
                      IconButton(
                        tooltip: _ru ? 'Изменить' : 'Edit',
                        icon: Icon(Icons.tune,
                            size: 18, color: AppTheme.textMuted),
                        onPressed: () => _edit(employee),
                      ),
""",
    """                    if (_canManage)
                      IconButton(
                        tooltip: _ru ? 'Изменить' : 'Edit',
                        icon: Icon(Icons.tune,
                            size: 18, color: AppTheme.textMuted),
                        onPressed: () => _edit(employee),
                      ),
                    if (!employee.isOwner &&
                        _manageableOrganizationIds.isNotEmpty)
                      IconButton(
                        tooltip: 'Доступ к организациям',
                        icon: Icon(
                          Icons.admin_panel_settings_outlined,
                          size: 19,
                          color: AppTheme.accent,
                        ),
                        onPressed: () => _openAccess(employee),
                      ),
""",
    'access card action',
)
contacts = one(
    contacts,
    """                if (employee.hasContacts) ...[
                  const SizedBox(height: 10),
                  _contactChips(employee),
                ],
""",
    """                if (_employeeOrganizations(employee).isNotEmpty) ...[
                  const SizedBox(height: 9),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final organization
                          in _employeeOrganizations(employee))
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withOpacity(.09),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppTheme.accent.withOpacity(.22),
                            ),
                          ),
                          child: Text(
                            organization.name,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
                if (employee.hasContacts) ...[
                  const SizedBox(height: 10),
                  _contactChips(employee),
                ],
""",
    'organization chips',
)
if 'extension _ContactsFirstOrNull' not in contacts:
    contacts = contacts.rstrip() + """

extension _ContactsFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
"""
contacts_path.write_text(contacts)
