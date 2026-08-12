from pathlib import Path
import re

ROOT = Path('.')

editor = r'''import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../team/models/employee_model.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import '../services/organization_access_service.dart';

/// Единый редактор доступа к организации.
///
/// Он намеренно используется и экраном организаций, и контактами: права
/// нельзя настраивать двумя разными наборами переключателей — они неизбежно
/// разъедутся. Сервис остаётся последней границей авторизации, а этот виджет
/// отвечает только за понятную человеку сборку набора прав.
class OrganizationAccessEditor extends StatefulWidget {
  final OrganizationModel organization;
  final EmployeeModel employee;
  final OrganizationAccessGrant? initialGrant;

  const OrganizationAccessEditor({
    super.key,
    required this.organization,
    required this.employee,
    this.initialGrant,
  });

  static Future<bool?> show(
    BuildContext context, {
    required OrganizationModel organization,
    required EmployeeModel employee,
    OrganizationAccessGrant? initialGrant,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => OrganizationAccessEditor(
        organization: organization,
        employee: employee,
        initialGrant: initialGrant,
      ),
    );
  }

  @override
  State<OrganizationAccessEditor> createState() =>
      _OrganizationAccessEditorState();
}

class _OrganizationAccessEditorState extends State<OrganizationAccessEditor> {
  late bool _enabled;
  late Set<String> _permissions;
  late bool _includeSubtree;
  late bool _selfFinance;
  late bool _teamFinance;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final grant = widget.initialGrant;
    _enabled = grant != null;
    _permissions = {...?grant?.permissions};
    _includeSubtree = grant?.includeSubtree ?? false;
    _selfFinance = grant?.canViewSelfFinance ?? true;
    _teamFinance = grant?.canViewTeamFinance ?? false;
    if (_enabled) _normalize();
  }

  static const _financePermissions = <String>{
    OrganizationPermissions.viewFinance,
    OrganizationPermissions.createTransactions,
    OrganizationPermissions.editTransactions,
    OrganizationPermissions.manageAccounts,
    OrganizationPermissions.manageRecurring,
    OrganizationPermissions.viewForecast,
  };

  void _normalize() {
    if (!_enabled) return;
    _permissions.add(OrganizationPermissions.view);
    final needsFinance = _permissions.any(
      (p) => p != OrganizationPermissions.viewFinance &&
          _financePermissions.contains(p),
    );
    if (needsFinance || _teamFinance) {
      _permissions.add(OrganizationPermissions.viewFinance);
    }
    if (!_permissions.contains(OrganizationPermissions.viewFinance)) {
      _permissions.removeAll(_financePermissions);
      _teamFinance = false;
    }
  }

  void _setPermission(String permission, bool value) {
    setState(() {
      if (value) {
        _enabled = true;
        _permissions.add(permission);
      } else {
        _permissions.remove(permission);
        if (permission == OrganizationPermissions.viewFinance) {
          _permissions.removeAll(_financePermissions);
          _teamFinance = false;
        }
      }
      _normalize();
    });
  }

  void _preset(_AccessPreset preset) {
    setState(() {
      _enabled = true;
      _selfFinance = true;
      _teamFinance = false;
      _includeSubtree = false;
      switch (preset) {
        case _AccessPreset.viewOnly:
          _permissions = {OrganizationPermissions.view};
          break;
        case _AccessPreset.finance:
          _permissions = {
            OrganizationPermissions.view,
            OrganizationPermissions.viewFinance,
            OrganizationPermissions.createTransactions,
            OrganizationPermissions.editTransactions,
            OrganizationPermissions.manageAccounts,
            OrganizationPermissions.manageRecurring,
            OrganizationPermissions.viewForecast,
          };
          break;
        case _AccessPreset.teamLead:
          _permissions = {
            OrganizationPermissions.view,
            OrganizationPermissions.viewFinance,
            OrganizationPermissions.createTransactions,
            OrganizationPermissions.editTransactions,
            OrganizationPermissions.manageAccounts,
            OrganizationPermissions.manageRecurring,
            OrganizationPermissions.viewForecast,
            OrganizationPermissions.manageMembers,
          };
          _teamFinance = true;
          break;
        case _AccessPreset.full:
          _permissions = {...OrganizationPermissions.all};
          _includeSubtree = true;
          _teamFinance = true;
          break;
      }
      _normalize();
    });
  }

  Future<void> _save() async {
    if (_saving || widget.employee.isOwner) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_enabled) {
        if (widget.initialGrant != null) {
          await OrganizationAccessService.revoke(
            widget.employee.id,
            widget.organization.id,
          );
        }
      } else {
        _normalize();
        await OrganizationAccessService.grant(
          employeeId: widget.employee.id,
          organizationId: widget.organization.id,
          includeSubtree: _includeSubtree,
          permissions: _permissions.toList()..sort(),
          canViewSelfFinance: _selfFinance,
          canViewTeamFinance: _teamFinance,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = _humanError(e);
      });
    }
  }

  String _humanError(Object error) {
    final text = '$error';
    if (text.contains('manage_members permission required')) {
      return 'У вас нет права менять участников этой организации.';
    }
    if (text.contains('organization does not exist')) {
      return 'Организация больше не существует.';
    }
    if (text.contains('employee does not exist')) {
      return 'Сотрудник больше не существует.';
    }
    return 'Не удалось сохранить доступ. $text';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.employee.isOwner) {
      return AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text('Доступ: ${widget.employee.displayName}'),
        content: const Text(
          'Владелец имеет полный доступ ко всему дереву организаций. '
          'Эти права нельзя урезать.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Готово'),
          ),
        ],
      );
    }

    return AlertDialog(
      backgroundColor: AppTheme.surface,
      titlePadding: const EdgeInsets.fromLTRB(22, 20, 22, 0),
      contentPadding: const EdgeInsets.fromLTRB(22, 12, 22, 0),
      actionsPadding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Доступ: ${widget.employee.displayName}',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontSize: 19,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            widget.organization.name,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
          ),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: MediaQuery.sizeOf(context).height.clamp(480, 720) * .72,
        child: ListView(
          children: [
            _accessSwitch(),
            if (_enabled) ...[
              const SizedBox(height: 14),
              Text(
                'Быстрый выбор',
                style: TextStyle(
                  color: AppTheme.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _presetChip(_AccessPreset.viewOnly, 'Только просмотр'),
                  _presetChip(_AccessPreset.finance, 'Работа с финансами'),
                  _presetChip(_AccessPreset.teamLead, 'Руководитель'),
                  _presetChip(_AccessPreset.full, 'Полный доступ'),
                ],
              ),
              const SizedBox(height: 18),
              _scopeSection(),
              const SizedBox(height: 12),
              _section(
                'Финансы',
                'Что сотрудник может видеть и менять в финансах организации.',
                [
                  _permissionTile(
                    OrganizationPermissions.viewFinance,
                    'Смотреть финансы организации',
                    'Баланс, операции и агрегированные показатели.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.createTransactions,
                    'Создавать операции',
                    'Добавлять доходы, расходы и переводы.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.editTransactions,
                    'Изменять операции',
                    'Редактировать существующие финансовые записи.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.manageAccounts,
                    'Управлять счетами',
                    'Создавать и настраивать счета организации.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.manageRecurring,
                    'Управлять регулярными платежами',
                    'Создавать и изменять повторяющиеся операции.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.viewForecast,
                    'Смотреть прогноз',
                    'Финансовый прогноз и риски организации.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                'Люди и показатели',
                'Личные данные и управление участниками отделены от общих финансов.',
                [
                  _boolTile(
                    value: _selfFinance,
                    onChanged: (v) => setState(() => _selfFinance = v),
                    title: 'Свои финансовые показатели',
                    subtitle: 'Раздел «Мои»: собственная динамика и личные риски.',
                  ),
                  _boolTile(
                    value: _teamFinance,
                    onChanged: (v) => setState(() {
                      _teamFinance = v;
                      if (v) {
                        _enabled = true;
                        _permissions.add(OrganizationPermissions.viewFinance);
                      }
                      _normalize();
                    }),
                    title: 'Персональные финансы команды',
                    subtitle:
                        'Показывает показатели отдельных сотрудников, а не только итог организации.',
                  ),
                  _permissionTile(
                    OrganizationPermissions.manageMembers,
                    'Управлять участниками и их доступом',
                    'Добавлять сотрудников в организацию и менять их права.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _section(
                'Управление организацией',
                'Редкие административные действия.',
                [
                  _permissionTile(
                    OrganizationPermissions.manageOrgSettings,
                    'Менять настройки организации',
                    'Название, структуру, архивирование и другие параметры.',
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _summary(),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: AppTheme.accentRed, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.check_rounded, size: 18),
          label: Text(_enabled ? 'Сохранить' : 'Отключить доступ'),
        ),
      ],
    );
  }

  Widget _accessSwitch() => Container(
        decoration: _boxDecoration(),
        child: SwitchListTile(
          value: _enabled,
          onChanged: (value) => setState(() {
            _enabled = value;
            if (value) {
              _permissions.add(OrganizationPermissions.view);
              _selfFinance = true;
            }
          }),
          title: Text(
            _enabled ? 'Доступ включён' : 'Нет доступа к организации',
            style: TextStyle(
              color: AppTheme.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            _enabled
                ? 'Настройте только то, что действительно нужно сотруднику.'
                : 'Сотрудник не увидит эту организацию.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ),
      );

  Widget _scopeSection() => Container(
        decoration: _boxDecoration(),
        child: _boolTile(
          value: _includeSubtree,
          onChanged: (v) => setState(() => _includeSubtree = v),
          title: 'Также дочерние организации',
          subtitle:
              'Те же права будут действовать на все организации ниже по дереву.',
        ),
      );

  Widget _section(String title, String hint, List<Widget> children) => Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
        decoration: _boxDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 3),
            Text(hint,
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
            const SizedBox(height: 6),
            ...children,
          ],
        ),
      );

  Widget _permissionTile(String permission, String title, String subtitle) =>
      _boolTile(
        value: _permissions.contains(permission),
        onChanged: (v) => _setPermission(permission, v),
        title: title,
        subtitle: subtitle,
      );

  Widget _boolTile({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String title,
    required String subtitle,
  }) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.trailing,
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(title,
            style: TextStyle(color: AppTheme.textPrimary, fontSize: 12.5)),
        subtitle: Text(subtitle,
            style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
      );

  Widget _presetChip(_AccessPreset preset, String label) => ActionChip(
        avatar: Icon(_presetIcon(preset), size: 16, color: AppTheme.accent),
        label: Text(label),
        onPressed: () => _preset(preset),
      );

  IconData _presetIcon(_AccessPreset preset) => switch (preset) {
        _AccessPreset.viewOnly => Icons.visibility_outlined,
        _AccessPreset.finance => Icons.account_balance_wallet_outlined,
        _AccessPreset.teamLead => Icons.groups_2_outlined,
        _AccessPreset.full => Icons.admin_panel_settings_outlined,
      };

  Widget _summary() {
    final parts = <String>['Организация'];
    if (_includeSubtree) parts.add('дочерние организации');
    if (_permissions.contains(OrganizationPermissions.viewFinance)) {
      parts.add('финансы');
    }
    if (_permissions.contains(OrganizationPermissions.manageMembers)) {
      parts.add('управление людьми');
    }
    if (_permissions.contains(OrganizationPermissions.manageOrgSettings)) {
      parts.add('настройки организации');
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.accent.withOpacity(.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.accent.withOpacity(.25)),
      ),
      child: Text(
        'Итого: ${parts.join(' · ')}',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5),
      ),
    );
  }

  BoxDecoration _boxDecoration() => BoxDecoration(
        color: AppTheme.background.withOpacity(.30),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.glassBorder),
      );
}

enum _AccessPreset { viewOnly, finance, teamLead, full }
'''

editor_path = ROOT / 'lib/features/organizations/widgets/organization_access_editor.dart'
editor_path.write_text(editor, encoding='utf-8')

# ------------------------------------------------------------------ Organizations
org_path = ROOT / 'lib/features/organizations/organizations_screen.dart'
org = org_path.read_text(encoding='utf-8')
needle = "import 'services/organization_service.dart';\n"
if "widgets/organization_access_editor.dart" not in org:
    org = org.replace(needle, needle + "import 'widgets/organization_access_editor.dart';\n")

start = org.index('class _OrganizationMembersDialogState')
end = org.index('\nextension _FirstOrNull', start)
replacement = r'''class _OrganizationMembersDialogState extends State<_OrganizationMembersDialog> {
  Map<String, OrganizationAccessGrant> _grants = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final map = <String, OrganizationAccessGrant>{};
    for (final person in TeamService.all) {
      final exact = (await OrganizationAccessService.grantsFor(person.id))
          .where((g) => g.organizationId == widget.organization.id)
          .firstOrNull;
      if (exact != null) map[person.id] = exact;
    }
    if (mounted) {
      setState(() {
        _grants = map;
        _loading = false;
      });
    }
  }

  Future<void> _editAccess(dynamic employee) async {
    final changed = await OrganizationAccessEditor.show(
      context,
      organization: widget.organization,
      employee: employee,
      initialGrant: _grants[employee.id],
    );
    if (changed == true) await _load();
  }

  String _summary(OrganizationAccessGrant? grant) {
    if (grant == null) return 'Нет доступа';
    final labels = <String>[];
    if (grant.includeSubtree) labels.add('с дочерними');
    if (grant.permissions.contains(OrganizationPermissions.viewFinance)) {
      labels.add('финансы');
    }
    if (grant.permissions.contains(OrganizationPermissions.manageMembers)) {
      labels.add('управление людьми');
    }
    if (grant.permissions
        .contains(OrganizationPermissions.manageOrgSettings)) {
      labels.add('настройки');
    }
    if (labels.isEmpty) return 'Только просмотр';
    return labels.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Участники: ${widget.organization.name}'),
          const SizedBox(height: 4),
          Text(
            'Выберите сотрудника — подробные права откроются отдельным экраном.',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
      content: SizedBox(
        width: 610,
        height: 480,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView.separated(
                itemCount: TeamService.all.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final employee = TeamService.all[index];
                  final grant = _grants[employee.id];
                  final enabled = employee.isOwner || grant != null;
                  return Container(
                    decoration: BoxDecoration(
                      color: AppTheme.background.withOpacity(.30),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.glassBorder),
                    ),
                    child: ListTile(
                      leading: Icon(
                        enabled
                            ? Icons.verified_user_outlined
                            : Icons.person_outline,
                        color: enabled ? AppTheme.accent : AppTheme.textMuted,
                      ),
                      title: Text(
                        employee.displayName,
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        employee.isOwner
                            ? 'Владелец · полный доступ'
                            : '${employee.position.isEmpty ? 'Без должности' : employee.position} · ${_summary(grant)}',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _editAccess(employee),
                    ),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
'''
org = org[:start] + replacement + org[end:]
org_path.write_text(org, encoding='utf-8')

# ------------------------------------------------------------------ Contacts
contacts_path = ROOT / 'lib/features/team/contacts_screen.dart'
contacts = contacts_path.read_text(encoding='utf-8')
contacts = contacts.replace(
    "import '../organizations/models/organization_access_grant.dart';\n",
    "import '../organizations/models/organization_access_grant.dart';\n"
    "import '../organizations/models/organization_model.dart';\n")
contacts = contacts.replace(
    "import '../organizations/services/organization_context.dart';\n",
    "import '../organizations/services/organization_context.dart';\n"
    "import '../organizations/services/organization_service.dart';\n")
contacts = contacts.replace(
    "import '../organizations/widgets/organization_switcher.dart';\n",
    "import '../organizations/widgets/organization_access_editor.dart';\n"
    "import '../organizations/widgets/organization_switcher.dart';\n")
if 'enum _ContactSort' not in contacts:
    contacts = contacts.replace(
        'class ContactsScreen extends StatefulWidget {',
        'enum _ContactSort { name, position, organization }\n\nclass ContactsScreen extends StatefulWidget {')

old_fields = '''  Set<String> _contextEmployeeIds = const <String>{};
  bool _membersLoading = true;
  bool _canManageContext = false;

  bool get _ru => WesiLocale.isRussian;
  bool get _canManage => _canManageContext;'''
new_fields = '''  Set<String> _contextEmployeeIds = const <String>{};
  bool _membersLoading = true;
  bool _canManageContext = false;
  List<OrganizationModel> _organizations = const <OrganizationModel>[];
  Map<String, Set<String>> _employeeOrgIds = const <String, Set<String>>{};
  Set<String> _manageableOrgIds = const <String>{};
  String? _selectedOrganizationId;
  String? _selectedPosition;
  _ContactSort _sort = _ContactSort.name;

  bool get _ru => WesiLocale.isRussian;
  bool get _canManage => _manageableOrgIds.isNotEmpty &&
      (_selectedOrganizationId == null ||
          _manageableOrgIds.contains(_selectedOrganizationId));'''
if old_fields not in contacts:
    raise SystemExit('contacts state fields anchor not found')
contacts = contacts.replace(old_fields, new_fields)

load_start = contacts.index('  Future<void> _loadContextMembers() async {')
visible_start = contacts.index('  List<EmployeeModel> get _visible {', load_start)
new_load = r'''  Future<void> _loadContextMembers() async {
    try {
      final allOrganizations = await OrganizationService.all();
      final current = TeamService.current;
      final visibleOrgIds = _localFullAccess
          ? allOrganizations.map((o) => o.id).toSet()
          : await OrganizationAccessService.visibleOrganizationIds();
      final organizations = allOrganizations
          .where((o) => visibleOrgIds.contains(o.id))
          .toList();

      final memberships = <String, Set<String>>{};
      for (final employee in TeamService.all) {
        if (employee.isOwner) {
          memberships[employee.id] = {OrganizationModel.rootId};
          continue;
        }
        final grants = await OrganizationAccessService.grantsFor(employee.id);
        memberships[employee.id] = grants
            .where((g) => g.permissions.contains(OrganizationPermissions.view))
            .map((g) => g.organizationId)
            .where(visibleOrgIds.contains)
            .toSet();
      }

      final manageable = <String>{};
      for (final organization in organizations) {
        if (current?.isOwner == true ||
            (current != null &&
                await OrganizationAccessService.can(
                  organization.id,
                  OrganizationPermissions.manageMembers,
                ))) {
          manageable.add(organization.id);
        }
      }

      var selected = _selectedOrganizationId;
      if (selected != null && !visibleOrgIds.contains(selected)) selected = null;
      if (selected == null &&
          visibleOrgIds.contains(OrganizationContext.currentOrganizationId)) {
        selected = OrganizationContext.currentOrganizationId;
      }

      final contextEmployeeIds = <String>{};
      for (final employee in TeamService.all) {
        final memberOf = memberships[employee.id] ?? const <String>{};
        if (selected == null || memberOf.contains(selected)) {
          contextEmployeeIds.add(employee.id);
        }
      }

      if (!mounted) return;
      setState(() {
        _organizations = organizations;
        _employeeOrgIds = memberships;
        _manageableOrgIds = manageable;
        _selectedOrganizationId = selected;
        _contextEmployeeIds = contextEmployeeIds;
        _canManageContext = selected != null && manageable.contains(selected);
        _membersLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _organizations = const [];
        _employeeOrgIds = const {};
        _manageableOrgIds = const {};
        _contextEmployeeIds = const <String>{};
        _canManageContext = false;
        _membersLoading = false;
      });
    }
  }

  void _applyOrganizationFilter(String? organizationId) {
    setState(() {
      _selectedOrganizationId = organizationId;
      _selectedPosition = null;
      _contextEmployeeIds = TeamService.all.where((employee) {
        if (organizationId == null) return true;
        return (_employeeOrgIds[employee.id] ?? const <String>{})
            .contains(organizationId);
      }).map((e) => e.id).toSet();
      _canManageContext = organizationId != null &&
          _manageableOrgIds.contains(organizationId);
    });
  }

  String _organizationName(String id) {
    for (final organization in _organizations) {
      if (organization.id == id) return organization.name;
    }
    return id;
  }

  String _employeeOrganizationLabel(EmployeeModel employee) {
    final names = (_employeeOrgIds[employee.id] ?? const <String>{})
        .map(_organizationName)
        .toList()
      ..sort();
    return names.isEmpty ? 'Без организации' : names.join(', ');
  }

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

'''
contacts = contacts[:load_start] + new_load + contacts[visible_start:]

old_visible = re.search(
    r'  List<EmployeeModel> get _visible \{.*?\n  \}\n\n  Future<void> _add\(\) async \{',
    contacts,
    re.S,
)
if not old_visible:
    raise SystemExit('visible/_add anchor not found')
new_visible = r'''  List<EmployeeModel> get _visible {
    final query = _search.trim().toLowerCase();
    final result = TeamService.all.where((employee) {
      if (!_contextEmployeeIds.contains(employee.id)) return false;
      if (_selectedPosition != null && employee.position != _selectedPosition) {
        return false;
      }
      if (query.isEmpty) return true;
      return employee.displayName.toLowerCase().contains(query) ||
          employee.position.toLowerCase().contains(query) ||
          employee.login.contains(query) ||
          employee.email.toLowerCase().contains(query) ||
          employee.phone.contains(query) ||
          _employeeOrganizationLabel(employee).toLowerCase().contains(query);
    }).toList();

    int byName(EmployeeModel a, EmployeeModel b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase());
    result.sort((a, b) {
      switch (_sort) {
        case _ContactSort.name:
          return byName(a, b);
        case _ContactSort.position:
          final position = a.position
              .toLowerCase()
              .compareTo(b.position.toLowerCase());
          return position == 0 ? byName(a, b) : position;
        case _ContactSort.organization:
          final organization = _employeeOrganizationLabel(a)
              .toLowerCase()
              .compareTo(_employeeOrganizationLabel(b).toLowerCase());
          return organization == 0 ? byName(a, b) : organization;
      }
    });
    return result;
  }

  Future<OrganizationModel?> _chooseOrganization({
    required Set<String> candidates,
    String title = 'Организация',
  }) async {
    final available = _organizations.where((o) => candidates.contains(o.id)).toList();
    if (available.isEmpty) return null;
    if (available.length == 1) return available.single;
    return showDialog<OrganizationModel>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          for (final organization in available)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialogContext, organization),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(organization.name),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openOrganizationAccess(EmployeeModel employee) async {
    if (employee.isOwner) return;
    final memberships = _employeeOrgIds[employee.id] ?? const <String>{};
    final candidates = memberships.intersection(_manageableOrgIds);
    OrganizationModel? organization;
    final selected = _selectedOrganizationId;
    if (selected != null && candidates.contains(selected)) {
      organization = _organizations.where((o) => o.id == selected).firstOrNull;
    }
    organization ??= await _chooseOrganization(
      candidates: candidates,
      title: 'Настроить доступ: ${employee.displayName}',
    );
    if (organization == null || !mounted) return;
    final grant = (await OrganizationAccessService.grantsFor(employee.id))
        .where((g) => g.organizationId == organization!.id)
        .firstOrNull;
    if (!mounted) return;
    final changed = await OrganizationAccessEditor.show(
      context,
      organization: organization,
      employee: employee,
      initialGrant: grant,
    );
    if (changed == true) await _loadContextMembers();
  }

  Future<void> _add() async {'''
contacts = contacts[:old_visible.start()] + new_visible + contacts[old_visible.end():]

# Replace beginning of _add so selected org is used, and all-org view asks which org.
old_add_head = '''  Future<void> _add() async {
    if (!_canManageContext) return;
    final created = await EmployeeEditorScreen.open(context);
    if (created == null) return;
    final orgId = OrganizationContext.currentOrganizationId;'''
new_add_head = '''  Future<void> _add() async {
    if (!_canManage) return;
    OrganizationModel? target;
    final selected = _selectedOrganizationId;
    if (selected != null && _manageableOrgIds.contains(selected)) {
      target = _organizations.where((o) => o.id == selected).firstOrNull;
    }
    target ??= await _chooseOrganization(
      candidates: _manageableOrgIds,
      title: 'В какую организацию добавить сотрудника?',
    );
    if (target == null || !mounted) return;
    final created = await EmployeeEditorScreen.open(context);
    if (created == null) return;
    final orgId = target.id;'''
contacts = contacts.replace(old_add_head, new_add_head)

# Insert filter row after search field in main build.
contacts = contacts.replace(
    '''            _header(people.length),
            _searchField(),
            Expanded(''',
    '''            _header(people.length),
            _searchField(),
            _filters(),
            Expanded(''')

# Insert filter widgets before _empty.
empty_anchor = '  Widget _empty() => Center('
filter_code = r'''  Widget _filters() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _filterDropdown<String?>(
              value: _selectedOrganizationId,
              hint: 'Все организации',
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Все организации'),
                ),
                for (final organization in _organizations)
                  DropdownMenuItem<String?>(
                    value: organization.id,
                    child: Text(organization.name),
                  ),
              ],
              onChanged: _applyOrganizationFilter,
            ),
            _filterDropdown<String?>(
              value: _selectedPosition,
              hint: 'Все должности',
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('Все должности'),
                ),
                for (final position in _positions)
                  DropdownMenuItem<String?>(
                    value: position,
                    child: Text(position),
                  ),
              ],
              onChanged: (value) => setState(() => _selectedPosition = value),
            ),
            _filterDropdown<_ContactSort>(
              value: _sort,
              hint: 'Сортировка',
              items: const [
                DropdownMenuItem(
                  value: _ContactSort.name,
                  child: Text('По имени'),
                ),
                DropdownMenuItem(
                  value: _ContactSort.position,
                  child: Text('По должности'),
                ),
                DropdownMenuItem(
                  value: _ContactSort.organization,
                  child: Text('По организации'),
                ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _sort = value);
              },
            ),
          ],
        ),
      );

  Widget _filterDropdown<T>({
    required T value,
    required String hint,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) => Container(
        constraints: const BoxConstraints(minWidth: 150, maxWidth: 220),
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.5),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            hint: Text(hint),
            isExpanded: true,
            dropdownColor: AppTheme.surface,
            style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            items: items,
            onChanged: onChanged,
          ),
        ),
      );

'''
if empty_anchor not in contacts:
    raise SystemExit('empty anchor missing')
contacts = contacts.replace(empty_anchor, filter_code + empty_anchor)

# Add access action to cards before generic edit action.
card_anchor = '''                    if (_canManage)
                      IconButton(
                        tooltip: _ru ? 'Изменить' : 'Edit','''
card_repl = '''                    if (!employee.isOwner &&
                        (_employeeOrgIds[employee.id] ?? const <String>{})
                            .intersection(_manageableOrgIds)
                            .isNotEmpty)
                      IconButton(
                        tooltip: _ru ? 'Доступ к организациям' : 'Organization access',
                        icon: Icon(Icons.admin_panel_settings_outlined,
                            size: 18, color: AppTheme.accent),
                        onPressed: () => _openOrganizationAccess(employee),
                      ),
                    if (_canManage)
                      IconButton(
                        tooltip: _ru ? 'Изменить' : 'Edit','''
if card_anchor not in contacts:
    raise SystemExit('card action anchor missing')
contacts = contacts.replace(card_anchor, card_repl)

# Show organization chips in employee identity.
position_anchor = '''          if (employee.position.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              employee.position,
              style: TextStyle(fontSize: 12, color: AppTheme.accent),
            ),
          ],'''
position_repl = position_anchor + r'''
          if ((_employeeOrgIds[employee.id] ?? const <String>{}).isNotEmpty) ...[
            const SizedBox(height: 5),
            Wrap(
              spacing: 5,
              runSpacing: 4,
              children: [
                for (final orgId in _employeeOrgIds[employee.id]!)
                  _tag(_organizationName(orgId)),
              ],
            ),
          ],'''
if position_anchor not in contacts:
    raise SystemExit('identity position anchor missing')
contacts = contacts.replace(position_anchor, position_repl)

# _empty should acknowledge active filters, not only search.
contacts = contacts.replace(
    '''                _search.isNotEmpty
                    ? (_ru ? 'Никого не нашлось' : 'Nobody found')''',
    '''                _search.isNotEmpty || _selectedPosition != null
                    ? (_ru ? 'Никого не нашлось' : 'Nobody found')''')

# Add firstOrNull extension if absent.
if 'extension _FirstOrNull' not in contacts:
    contacts += r'''

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
'''

contacts_path.write_text(contacts, encoding='utf-8')

# ------------------------------------------------------------------ Contract tests
contract_path = ROOT / 'test/organization_ui_contract_test.dart'
contract = contract_path.read_text(encoding='utf-8')
insert_before = '\n}\n'
extra = r'''

  test('organization access editor uses human labels and presets', () {
    final editor = source(
      'lib/features/organizations/widgets/organization_access_editor.dart',
    );
    expect(editor, contains('Только просмотр'));
    expect(editor, contains('Работа с финансами'));
    expect(editor, contains('Руководитель'));
    expect(editor, contains('Полный доступ'));
    expect(editor, contains('Смотреть финансы организации'));
    expect(editor, contains('Управлять участниками и их доступом'));
  });

  test('Contacts can filter and sort by organization and position', () {
    final screen = source('lib/features/team/contacts_screen.dart');
    expect(screen, contains('Все организации'));
    expect(screen, contains('Все должности'));
    expect(screen, contains('По должности'));
    expect(screen, contains('По организации'));
    expect(screen, contains('OrganizationAccessEditor.show'));
  });
'''
pos = contract.rfind(insert_before)
if pos == -1:
    raise SystemExit('contract end missing')
contract = contract[:pos] + extra + contract[pos:]
contract_path.write_text(contract, encoding='utf-8')

print('organization access + contacts UX patch applied')
