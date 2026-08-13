import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_avatar.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import '../organizations/models/organization_access_grant.dart';
import '../organizations/models/organization_model.dart';
import '../organizations/services/organization_access_service.dart';
import '../organizations/services/organization_context.dart';
import '../organizations/services/organization_service.dart';
import '../organizations/widgets/organization_access_editor.dart';
import '../organizations/widgets/organization_switcher.dart';
import 'deleted_employees_screen.dart';
import 'employee_editor_screen.dart';
import 'models/employee_model.dart';
import 'models/team_permissions.dart';
import 'services/contact_actions.dart';
import 'services/employee_admin_service.dart';
import 'services/team_service.dart';
import 'team_stats_screen.dart';
import 'widgets/employee_notes_sheet.dart';

enum _ContactsSort { name, position, organization }

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  String _search = '';
  final Set<String> _activationBusy = <String>{};
  Timer? _activationTicker;
  Set<String> _contextEmployeeIds = const <String>{};
  List<OrganizationModel> _organizations = const <OrganizationModel>[];
  Map<String, Set<String>> _employeeOrganizationIds =
      const <String, Set<String>>{};
  Set<String> _manageableOrganizationIds = const <String>{};
  String? _organizationFilter;
  String? _positionFilter;
  _ContactsSort _sort = _ContactsSort.name;
  bool _membersLoading = true;
  bool _canManageContext = false;

  bool get _ru => WesiLocale.isRussian;
  bool get _canManage => _canManageContext;
  bool get _canSeeNotes => TeamService.currentPermissions.canSeeNotes;
  bool get _ownerOnly => TeamService.isOwnerSession;
  bool get _localFullAccess => TeamService.current == null || _ownerOnly;

  @override
  void initState() {
    super.initState();
    TeamService.revision.addListener(_refresh);
    OrganizationContext.revision.addListener(_refresh);
    TeamService.ensureOwner();
    if (_localFullAccess) {
      _contextEmployeeIds = TeamService.all.map((e) => e.id).toSet();
      _membersLoading = false;
    }
    _loadContextMembers();
    _activationTicker = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _activationTicker?.cancel();
    TeamService.revision.removeListener(_refresh);
    OrganizationContext.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    _loadContextMembers();
  }

  Future<void> _loadContextMembers() async {
    try {
      final allOrganizations = await OrganizationService.all();
      final current = TeamService.current;
      final allowedOrganizationIds = _localFullAccess
          ? allOrganizations.map((o) => o.id).toSet()
          : await OrganizationAccessService.visibleOrganizationIds();
      // Список людей следует за выбранной организацией, а не показывает
      // сразу всех, к кому есть доступ. Иначе переключатель наверху ни на
      // что не влияет: человек выбирает подразделение, а видит тот же
      // список, что и минуту назад.
      //
      // Контекст сам не расширяет доступ — он уже пересечён с разрешённым,
      // — но при пустом пересечении (организация выбрана, а доступа к ней
      // нет) показываем всё разрешённое: пустой экран контактов выглядел бы
      // как поломка, а не как ограничение.
      final contextIds = await OrganizationContext.effectiveOrganizationIds();
      final scopedIds = _localFullAccess
          ? allowedOrganizationIds
          : (contextIds.intersection(allowedOrganizationIds).isEmpty
              ? allowedOrganizationIds
              : contextIds.intersection(allowedOrganizationIds));
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
            exactIds.intersection(scopedIds).isNotEmpty) {
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

  Future<void> _add() async {
    if (!_canManageContext) return;
    final created = await EmployeeEditorScreen.open(context);
    if (created == null) return;
    final orgId = OrganizationContext.currentOrganizationId;
    final financeVisible = created.permissions.allows(TeamModules.treasury) ||
        created.permissions.allows(TeamModules.forecast) ||
        created.permissions.allows(TeamModules.analytics);
    final permissions = <String>[OrganizationPermissions.view];
    if (financeVisible) {
      permissions.addAll(const [
        OrganizationPermissions.viewFinance,
        OrganizationPermissions.createTransactions,
        OrganizationPermissions.editTransactions,
        OrganizationPermissions.manageAccounts,
        OrganizationPermissions.manageRecurring,
        OrganizationPermissions.viewForecast,
      ]);
    }
    await OrganizationAccessService.grant(
      employeeId: created.id,
      organizationId: orgId,
      includeSubtree: false,
      permissions: permissions,
      canViewSelfFinance: true,
      canViewTeamFinance: created.permissions.canSeeOthersStats,
    );
    await _loadContextMembers();
  }

  Future<void> _edit(EmployeeModel employee) async {
    await EmployeeEditorScreen.open(context, initial: employee);
    if (mounted) setState(() {});
  }

  void _showNotes(EmployeeModel employee) {
    if (_canSeeNotes) EmployeeNotesSheet.show(context, employee);
  }

  Future<void> _retryActivation(EmployeeModel employee) async {
    if (!_ownerOnly ||
        employee.isOwner ||
        _activationBusy.contains(employee.id)) {
      return;
    }

    final alreadyActive = EmployeeAdminService.isActivated(employee.id);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          alreadyActive
              ? (_ru ? 'Переактивировать сотрудника?' : 'Reactivate employee?')
              : (_ru ? 'Повторить активацию?' : 'Retry activation?'),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Text(
          _ru
              ? 'Для ${employee.displayName} будет создан новый пароль. '
                  'Старый пароль перестанет действовать.'
              : 'A new password will be created for ${employee.displayName}. '
                  'The previous password will stop working.',
          style: TextStyle(
            fontSize: 13,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              _ru ? 'Отмена' : 'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _ru ? 'Создать и проверить' : 'Create and verify',
              style: TextStyle(
                color: AppTheme.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _activationBusy.add(employee.id));
    final reset = await TeamService.resetPasswordDetailed(employee.id);
    if (!mounted) return;
    setState(() => _activationBusy.remove(employee.id));

    if (reset == null) {
      _toast(_ru ? 'Сотрудник не найден' : 'Employee not found');
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Row(
          children: [
            Icon(
              reset.portal.ok
                  ? Icons.check_circle_outline
                  : Icons.error_outline,
              color:
                  reset.portal.ok ? AppTheme.accentGreen : AppTheme.accentRed,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                reset.portal.ok
                    ? (_ru ? 'Сотрудник активирован' : 'Employee activated')
                    : (_ru ? 'Активация не завершена' : 'Activation failed'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              reset.portal.message,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color:
                    reset.portal.ok ? AppTheme.accentGreen : AppTheme.accentRed,
              ),
            ),
            const SizedBox(height: 16),
            _credentialLine(_ru ? 'Логин' : 'Login', employee.login),
            const SizedBox(height: 10),
            _credentialLine(
                _ru ? 'Новый пароль' : 'New password', reset.password),
            const SizedBox(height: 12),
            Text(
              _ru
                  ? 'Пароль показывается один раз. Передайте его сотруднику безопасным способом.'
                  : 'The password is shown once. Share it securely.',
              style: TextStyle(
                fontSize: 10.5,
                height: 1.4,
                color: AppTheme.textMuted,
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text: 'Логин: ${employee.login}\nПароль: ${reset.password}',
                ),
              );
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(_ru ? 'Скопировано' : 'Copied'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined, size: 17),
            label: Text(_ru ? 'Копировать' : 'Copy'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(_ru ? 'Готово' : 'Done'),
          ),
        ],
      ),
    );
  }

  Widget _credentialLine(String label, String value) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppTheme.background.withOpacity(.45),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: TextStyle(fontSize: 10, color: AppTheme.textMuted)),
            const SizedBox(height: 4),
            SelectableText(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      );

  Future<void> _removeWithReason(EmployeeModel employee) async {
    if (!_ownerOnly || employee.isOwner) return;
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(
          _ru ? 'Удалить сотрудника?' : 'Delete employee?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? '${employee.displayName} исчезнет из рабочего списка. '
                      'Дата и причина останутся в закрытом архиве.'
                  : '${employee.displayName} will be removed from the active '
                      'list. The date and reason remain in the private archive.',
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              maxLines: 3,
              style: TextStyle(color: AppTheme.textPrimary),
              decoration: InputDecoration(
                labelText: _ru ? 'Причина удаления' : 'Deletion reason',
                hintText: _ru ? 'Можно оставить пустым' : 'Optional',
                filled: true,
                fillColor: AppTheme.background.withOpacity(0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              WesiLocale.get('cancel'),
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              _ru ? 'Удалить' : 'Delete',
              style: TextStyle(color: AppTheme.accentRed),
            ),
          ),
        ],
      ),
    );
    final reason = controller.text;
    controller.dispose();
    if (confirmed != true) return;
    await TeamService.remove(employee.id, reason: reason);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final people = _visible;
    return Scaffold(
      backgroundColor: AppTheme.background,
      floatingActionButton: _canManage
          ? FloatingActionButton.extended(
              onPressed: _add,
              backgroundColor: AppTheme.accent,
              icon: const Icon(Icons.person_add_alt_1, color: Colors.white),
              label: Text(
                _ru ? 'Сотрудник' : 'Employee',
                style: const TextStyle(color: Colors.white),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(people.length),
            _searchField(),
            _filterBar(),
            Expanded(
              child: _membersLoading
                  ? const Center(child: CircularProgressIndicator())
                  : people.isEmpty
                      ? _empty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: people.length,
                          itemBuilder: (context, index) => _card(people[index]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(int count) => Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          kTitleBarInset + 12,
          kHasCustomTitleBar ? 148 : 16,
          0,
        ),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.arrow_back, color: AppTheme.textPrimary),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WesiTitle(_ru ? 'Контакты' : 'Contacts', size: 22),
                  const SizedBox(height: 2),
                  Text(
                    count == 0
                        ? (_ru ? 'Пока никого' : 'Nobody yet')
                        : '$count ${_ru ? 'чел.' : 'people'}',
                    style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const OrganizationSwitcher(compact: true),
            const SizedBox(width: 6),
            if (_ownerOnly)
              IconButton(
                tooltip: _ru ? 'Удалённые сотрудники' : 'Deleted employees',
                icon: Icon(Icons.inventory_2_outlined,
                    color: AppTheme.textPrimary),
                onPressed: () => DeletedEmployeesScreen.open(context),
              ),
            IconButton(
              tooltip: _ru ? 'Показатели' : 'Performance',
              icon: Icon(Icons.insights_outlined, color: AppTheme.textPrimary),
              onPressed: () => TeamStatsScreen.open(context),
            ),
          ],
        ),
      );

  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: SizedBox(
          height: 40,
          child: TextField(
            onChanged: (value) => setState(() => _search = value),
            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              prefixIcon:
                  Icon(Icons.search, size: 18, color: AppTheme.textMuted),
              hintText: _ru ? 'Поиск по людям' : 'Search people',
              hintStyle: TextStyle(fontSize: 13, color: AppTheme.textMuted),
              filled: true,
              fillColor: AppTheme.surface.withOpacity(0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      );

  Widget _filterBar() {
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

  Widget _empty() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.people_outline, size: 40, color: AppTheme.textMuted),
              const SizedBox(height: 12),
              Text(
                _search.isNotEmpty
                    ? (_ru ? 'Никого не нашлось' : 'Nobody found')
                    : _canManage
                        ? (_ru
                            ? 'Добавьте первого человека — кнопка внизу.\n'
                                'Логин и пароль система выдаст сама.'
                            : 'Add the first person with the button below.')
                        : (_ru ? 'Список пуст' : 'The list is empty'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _card(EmployeeModel employee) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: GestureDetector(
          onLongPress: () => _showNotes(employee),
          onSecondaryTap: () => _showNotes(employee),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(0.4),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: employee.isOwner
                    ? AppTheme.accent.withOpacity(0.35)
                    : AppTheme.glassBorder,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    WesiAvatar(
                      size: 42,
                      index: employee.avatarIndex,
                      photo: employee.photo,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: _identity(employee)),
                    if (_canManage)
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
                    if (_ownerOnly && !employee.isOwner)
                      IconButton(
                        tooltip: _ru ? 'Удалить' : 'Delete',
                        icon: Icon(
                          Icons.person_remove_outlined,
                          size: 18,
                          color: AppTheme.accentRed,
                        ),
                        onPressed: () => _removeWithReason(employee),
                      ),
                  ],
                ),
                if (_employeeOrganizations(employee).isNotEmpty) ...[
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
                if (_canSeeNotes && employee.notes.trim().isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.sticky_note_2_outlined,
                          size: 13, color: AppTheme.textMuted),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _ru
                              ? 'Есть заметка — долгое нажатие'
                              : 'Has a note — long press',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _identity(EmployeeModel employee) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text(
                  employee.displayName,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              if (employee.isOwner) ...[
                const SizedBox(width: 8),
                _tag(_ru ? 'владелец' : 'owner'),
              ],
            ],
          ),
          if (employee.position.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              employee.position,
              style: TextStyle(fontSize: 12, color: AppTheme.accent),
            ),
          ],
          if (employee.nickname.trim().isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              '@${employee.nickname}',
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
            ),
          ],
          if (_ownerOnly && !employee.isOwner) ...[
            const SizedBox(height: 7),
            _activationTag(employee),
          ],
        ],
      );

  Widget _activationTag(EmployeeModel employee) {
    final active = EmployeeAdminService.isActivated(employee.id);
    final error = EmployeeAdminService.activationError(employee.id);
    final attempted = EmployeeAdminService.lastActivationAttempt(employee.id);
    final busy = _activationBusy.contains(employee.id);
    final age = attempted == null ? null : DateTime.now().difference(attempted);
    final stalled = !active &&
        attempted != null &&
        age != null &&
        age >= const Duration(seconds: 45);

    final color = active
        ? AppTheme.accentGreen
        : error.isNotEmpty || stalled
            ? AppTheme.accentRed
            : AppTheme.accent;
    final label = busy
        ? (_ru ? 'Проверяю активацию…' : 'Checking activation…')
        : active
            ? (_ru ? 'Активирован' : 'Activated')
            : error.isNotEmpty
                ? (_ru ? 'Ошибка активации' : 'Activation failed')
                : stalled
                    ? (_ru
                        ? 'Активация задержалась'
                        : 'Activation is taking too long')
                    : attempted != null
                        ? (_ru ? 'Активация…' : 'Activating…')
                        : (_ru ? 'Не активирован' : 'Not activated');

    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy ||
              (!active && attempted != null && !stalled && error.isEmpty)) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

    final canRetry = !active && !busy && (error.isNotEmpty || stalled);
    final canActivate = !active && !busy && attempted == null;
    final canReactivate = active && !busy;
    final attemptText = attempted == null
        ? ''
        : '${_ru ? 'Последняя попытка' : 'Last attempt'}: '
            '${attempted.toLocal().toString().split('.').first}';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: error.isNotEmpty
                ? error
                : attemptText.isNotEmpty
                    ? '$label · $attemptText'
                    : label,
            child: tag,
          ),
          if (canReactivate || canRetry || canActivate) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor:
                    canRetry ? AppTheme.accentRed : AppTheme.accent,
              ),
              onPressed: () => _retryActivation(employee),
              icon: Icon(
                canActivate ? Icons.person_add_alt_1 : Icons.refresh_rounded,
                size: 14,
              ),
              label: Text(
                canReactivate
                    ? (_ru ? 'Переактивировать' : 'Reactivate')
                    : canRetry
                        ? (_ru ? 'Повторить активацию' : 'Retry activation')
                        : (_ru ? 'Активировать вручную' : 'Activate manually'),
                style: const TextStyle(
                    fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: AppTheme.accent.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.accent.withOpacity(0.4)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: AppTheme.accent,
          ),
        ),
      );

  Widget _contactChips(EmployeeModel employee) => LayoutBuilder(
        builder: (context, box) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (employee.phone.trim().isNotEmpty)
              _chip(
                icon: Icons.phone,
                label: employee.phone,
                maxWidth: box.maxWidth,
                onTap: () => _tapPhone(employee.phone),
              ),
            if (employee.email.trim().isNotEmpty)
              _chip(
                icon: Icons.alternate_email,
                label: employee.email,
                maxWidth: box.maxWidth,
                onTap: () => _tapEmail(employee.email),
              ),
            for (final entry in employee.socials.entries)
              if (entry.value.trim().isNotEmpty)
                _chip(
                  icon: Icons.link,
                  label: entry.key,
                  maxWidth: box.maxWidth,
                  onTap: () => _tapSocial(entry.key, entry.value),
                ),
          ],
        ),
      );

  Widget _chip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required double maxWidth,
  }) =>
      ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: HoverButton(
          onTap: onTap,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          backgroundColor: AppTheme.surfaceLight.withOpacity(0.6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: AppTheme.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Future<void> _tapPhone(String phone) async {
    final result = await ContactActions.phone(phone);
    if (!mounted) return;
    final text = switch (result) {
      PhoneActionResult.copied => _ru ? 'Номер скопирован' : 'Number copied',
      PhoneActionResult.invalid =>
        _ru ? 'В номере нет цифр' : 'No digits in the number',
      PhoneActionResult.dialed => null,
    };
    if (text != null) _toast(text);
  }

  Future<void> _tapEmail(String email) async {
    final ok = await ContactActions.email(email);
    if (!mounted || ok) return;
    _toast(_ru ? 'Не удалось открыть почту' : 'Could not open mail');
  }

  Future<void> _tapSocial(String network, String value) async {
    final ok = await ContactActions.social(network, value);
    if (!mounted || ok) return;
    _toast(_ru ? 'Ссылка не открылась' : 'Could not open the link');
  }

  void _toast(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

extension _ContactsFirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
