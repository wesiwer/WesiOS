import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../team/services/team_service.dart';
import '../treasury/models/account_model.dart';
import '../treasury/services/account_service.dart';
import '../treasury/services/treasury_service.dart';
import 'models/organization_access_grant.dart';
import 'models/organization_model.dart';
import 'services/organization_access_service.dart';
import 'services/organization_context.dart';
import 'services/organization_service.dart';
import 'widgets/organization_access_editor.dart';

class OrganizationsScreen extends StatefulWidget {
  const OrganizationsScreen({super.key});

  @override
  State<OrganizationsScreen> createState() => _OrganizationsScreenState();
}

class _OrganizationsScreenState extends State<OrganizationsScreen> {
  List<OrganizationModel> _orgs = const [];
  Set<String> _allowed = const {};
  Set<String> _manageSettings = const {};
  Set<String> _manageMembers = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final orgs = await OrganizationService.all(includeArchived: true);
      final allowed = TeamService.current == null
          ? orgs.map((e) => e.id).toSet()
          : await OrganizationAccessService.visibleOrganizationIds();
      final manageSettings = <String>{};
      final manageMembers = <String>{};
      final employee = TeamService.current;
      for (final org in orgs) {
        if (employee == null ||
            employee.isOwner ||
            await OrganizationAccessService.can(
              org.id,
              OrganizationPermissions.manageOrgSettings,
            )) {
          manageSettings.add(org.id);
        }
        if (employee == null ||
            employee.isOwner ||
            await OrganizationAccessService.can(
              org.id,
              OrganizationPermissions.manageMembers,
            )) {
          manageMembers.add(org.id);
        }
      }
      if (!mounted) return;
      setState(() {
        _orgs = orgs;
        _allowed = allowed;
        _manageSettings = manageSettings;
        _manageMembers = manageMembers;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = '$e';
        });
    }
  }

  int _depth(OrganizationModel org) {
    final byId = {for (final o in _orgs) o.id: o};
    var parent = org.parentId;
    var result = 0;
    final seen = <String>{org.id};
    while (parent != null && seen.add(parent)) {
      result++;
      parent = byId[parent]?.parentId;
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.background,
        title: const Text('Организации'),
        actions: [
          IconButton(
            tooltip: 'Межорганизационный перевод',
            onPressed: () =>
                Navigator.pushNamed(context, '/organizations/transfer'),
            icon: const Icon(Icons.swap_horiz_rounded),
          ),
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      floatingActionButton: _manageSettings.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_business_outlined),
              label: const Text('Создать'),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                  children: [
                    _intro(),
                    const SizedBox(height: 12),
                    for (final org in _orgs)
                      if (_allowed.contains(org.id) ||
                          TeamService.current?.isOwner == true)
                        _orgTile(org),
                  ],
                ),
    );
  }

  Widget _intro() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Text(
          'Каждый узел — отдельная организация со своими счетами, операциями, прогнозом и людьми. '
          'Режим «С дочерними» только консолидирует поддерево и не смешивает ownership.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.35),
        ),
      );

  Widget _orgTile(OrganizationModel org) {
    final selected = org.id == OrganizationContext.currentOrganizationId;
    return Padding(
      padding: EdgeInsets.only(left: _depth(org) * 18.0, bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.accent.withOpacity(.10)
              : AppTheme.surface.withOpacity(.35),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(
            color: selected
                ? AppTheme.accent.withOpacity(.55)
                : AppTheme.glassBorder,
          ),
        ),
        child: ListTile(
          leading: Icon(
            org.isRoot ? Icons.hub_outlined : Icons.business_outlined,
            color: org.archived ? AppTheme.textSecondary : AppTheme.accent,
          ),
          title: Row(
            children: [
              Flexible(
                child: Text(org.name,
                    style: TextStyle(
                        color: AppTheme.textPrimary,
                        fontWeight: FontWeight.w800)),
              ),
              if (org.archived) ...[
                const SizedBox(width: 7),
                const Chip(label: Text('Архив')),
              ],
            ],
          ),
          subtitle: Text(
            '${org.baseCurrency}${org.code == null ? '' : ' • ${org.code}'}',
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          trailing: PopupMenuButton<String>(
            onSelected: (action) => _action(org, action),
            itemBuilder: (_) => [
              if (!org.archived)
                const PopupMenuItem(
                    value: 'open', child: Text('Открыть Treasury')),
              if (!org.archived && _manageSettings.contains(org.id))
                const PopupMenuItem(
                    value: 'edit', child: Text('Редактировать')),
              if (!org.archived && _manageSettings.contains(org.id))
                const PopupMenuItem(
                    value: 'child', child: Text('Создать дочернюю')),
              if (_manageMembers.contains(org.id))
                const PopupMenuItem(
                    value: 'members', child: Text('Участники и права')),
              if (!org.isRoot && _manageSettings.contains(org.id))
                PopupMenuItem(
                  value: org.archived ? 'restore' : 'archive',
                  child: Text(org.archived ? 'Восстановить' : 'Архивировать'),
                ),
            ],
          ),
          onTap: org.archived ? null : () => _openOrg(org),
        ),
      ),
    );
  }

  Future<void> _action(OrganizationModel org, String action) async {
    switch (action) {
      case 'open':
        await _openOrg(org);
        break;
      case 'edit':
        if (_manageSettings.contains(org.id)) await _edit(org);
        break;
      case 'child':
        if (_manageSettings.contains(org.id)) await _create(parent: org);
        break;
      case 'members':
        if (_manageMembers.contains(org.id)) await _members(org);
        break;
      case 'archive':
        if (!_manageSettings.contains(org.id)) return;
        final ok = await OrganizationService.archive(org.id);
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text(
                    'Нельзя архивировать root или узел с активными дочерними организациями.')),
          );
        }
        await _load();
        break;
      case 'restore':
        if (!_manageSettings.contains(org.id)) return;
        await OrganizationService.restore(org.id);
        await _load();
        break;
    }
  }

  Future<void> _openOrg(OrganizationModel org) async {
    await OrganizationContext.selectOrganization(org.id);
    await OrganizationContext.setScope(OrganizationScope.only);
    AccountService.revision.value++;
    TreasuryService.revision.value++;
    if (mounted) Navigator.pushNamed(context, '/treasury/dashboard');
  }

  Future<void> _create({OrganizationModel? parent}) async {
    final parentCandidates = _orgs
        .where((o) => !o.archived && _manageSettings.contains(o.id))
        .toList();
    final defaultParent = parent ??
        parentCandidates
            .where((o) => o.id == OrganizationContext.currentOrganizationId)
            .firstOrNull ??
        parentCandidates.firstOrNull;
    if (defaultParent == null) return;

    final name = TextEditingController();
    final currency = TextEditingController(text: defaultParent.baseCurrency);
    var parentId = defaultParent.id;
    var reserve = false;
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Новая организация'),
          content: SizedBox(
            width: 430,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Название')),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: parentId,
                  decoration: const InputDecoration(labelText: 'Родитель'),
                  items: [
                    for (final item in parentCandidates)
                      DropdownMenuItem(value: item.id, child: Text(item.name)),
                  ],
                  onChanged: (v) => setLocal(() => parentId = v ?? parentId),
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: currency,
                    decoration:
                        const InputDecoration(labelText: 'Базовая валюта')),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: reserve,
                  onChanged: (v) => setLocal(() => reserve = v ?? false),
                  title: const Text('Создать резервный счёт'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Создать')),
          ],
        ),
      ),
    );
    if (result != true || name.text.trim().isEmpty) return;
    try {
      final employee = TeamService.current;
      final org = await OrganizationService.create(
        name: name.text,
        parentId: parentId,
        baseCurrency: currency.text,
        createdBy: employee?.id ?? 'local',
      );
      if (employee != null && !employee.isOwner) {
        final grants = await OrganizationAccessService.grantsFor(employee.id);
        OrganizationAccessGrant? template;
        for (final grant in grants) {
          if (grant.organizationId == parentId) {
            template = grant;
            break;
          }
          if (grant.includeSubtree &&
              (grant.organizationId == parentId ||
                  await OrganizationService.isDescendant(
                    parentId,
                    grant.organizationId,
                  ))) {
            template = grant;
          }
        }
        if (template != null && !template.includeSubtree) {
          await OrganizationAccessService.grant(
            employeeId: employee.id,
            organizationId: org.id,
            includeSubtree: false,
            permissions: template.permissions,
            canViewTeamFinance: template.canViewTeamFinance,
            canViewSelfFinance: template.canViewSelfFinance,
            createdBy: employee.id,
            enforceActor: false,
          );
        }
      }
      await AccountService.ensureMain(organizationId: org.id);
      if (reserve) {
        await AccountService.create(
          name: 'Резерв',
          kind: AccountKind.reserve,
          organizationId: org.id,
          currency: org.baseCurrency,
        );
      }
      await _load();
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Future<void> _edit(OrganizationModel org) async {
    if (!_manageSettings.contains(org.id)) return;
    final name = TextEditingController(text: org.name);
    final currency = TextEditingController(text: org.baseCurrency);
    final code = TextEditingController(text: org.code ?? '');
    final description = TextEditingController(text: org.description ?? '');
    var parentId = org.parentId;
    final candidates =
        _orgs.where((o) => !o.archived && o.id != org.id).toList();
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text('Редактировать ${org.name}'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: name,
                    decoration: const InputDecoration(labelText: 'Название')),
                const SizedBox(height: 10),
                if (!org.isRoot)
                  DropdownButtonFormField<String>(
                    value: parentId,
                    decoration: const InputDecoration(labelText: 'Родитель'),
                    items: [
                      for (final item in candidates)
                        DropdownMenuItem(
                            value: item.id, child: Text(item.name)),
                    ],
                    onChanged: (value) => setLocal(() => parentId = value),
                  ),
                const SizedBox(height: 10),
                TextField(
                    controller: currency,
                    decoration:
                        const InputDecoration(labelText: 'Базовая валюта')),
                const SizedBox(height: 10),
                TextField(
                    controller: code,
                    decoration: const InputDecoration(labelText: 'Код')),
                const SizedBox(height: 10),
                TextField(
                    controller: description,
                    decoration: const InputDecoration(labelText: 'Описание')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Отмена')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Сохранить')),
          ],
        ),
      ),
    );
    if (save != true || name.text.trim().isEmpty) return;
    try {
      await OrganizationService.update(
        org,
        name: name.text,
        parentId: org.isRoot ? null : parentId,
        baseCurrency: currency.text,
        code: code.text.trim().isEmpty ? null : code.text.trim(),
        description:
            description.text.trim().isEmpty ? null : description.text.trim(),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  Future<void> _members(OrganizationModel org) async {
    final people = TeamService.all;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _OrganizationMembersDialog(
        organization: org,
        people: people,
      ),
    );
  }
}

class _OrganizationMembersDialog extends StatefulWidget {
  final OrganizationModel organization;
  final List<dynamic> people;
  const _OrganizationMembersDialog(
      {required this.organization, required this.people});

  @override
  State<_OrganizationMembersDialog> createState() =>
      _OrganizationMembersDialogState();
}

class _OrganizationMembersDialogState
    extends State<_OrganizationMembersDialog> {
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
    if (grant.permissions.contains(OrganizationPermissions.manageOrgSettings)) {
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

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
