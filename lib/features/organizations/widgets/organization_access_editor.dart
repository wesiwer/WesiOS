import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';
import '../models/organization_access_grant.dart';
import '../models/organization_model.dart';
import '../services/organization_access_service.dart';
import '../services/organization_service.dart';

class OrganizationAccessEditor extends StatefulWidget {
  final EmployeeModel employee;
  final OrganizationModel organization;

  const OrganizationAccessEditor({
    super.key,
    required this.employee,
    required this.organization,
  });

  static Future<bool?> open(
    BuildContext context, {
    required EmployeeModel employee,
    required OrganizationModel organization,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.background,
      builder: (_) => OrganizationAccessEditor(
        employee: employee,
        organization: organization,
      ),
    );
  }

  static String permissionLabel(String permission) {
    switch (permission) {
      case OrganizationPermissions.view:
        return 'Доступ к организации';
      case OrganizationPermissions.viewFinance:
        return 'Просмотр финансов';
      case OrganizationPermissions.createTransactions:
        return 'Добавление операций';
      case OrganizationPermissions.editTransactions:
        return 'Изменение и удаление операций';
      case OrganizationPermissions.manageAccounts:
        return 'Управление счетами';
      case OrganizationPermissions.manageRecurring:
        return 'Регулярные платежи';
      case OrganizationPermissions.viewForecast:
        return 'Финансовый прогноз';
      case OrganizationPermissions.manageOrgSettings:
        return 'Настройки организации';
      case OrganizationPermissions.manageMembers:
        return 'Управление сотрудниками';
      default:
        return permission;
    }
  }

  static String shortSummary(OrganizationAccessGrant? grant) {
    if (grant == null) return 'Нет доступа';
    final parts = <String>[];
    if (grant.permissions.contains(OrganizationPermissions.viewFinance)) {
      parts.add('финансы');
    }
    if (grant.permissions.contains(OrganizationPermissions.manageMembers)) {
      parts.add('сотрудники');
    }
    if (grant.permissions.contains(OrganizationPermissions.manageOrgSettings)) {
      parts.add('настройки');
    }
    if (grant.includeSubtree) parts.add('дочерние организации');
    if (parts.isEmpty) return 'Только просмотр';
    return parts.join(' · ');
  }

  @override
  State<OrganizationAccessEditor> createState() =>
      _OrganizationAccessEditorState();
}

class _OrganizationAccessEditorState extends State<OrganizationAccessEditor> {
  OrganizationAccessGrant? _existing;
  Set<String> _permissions = <String>{};
  Set<String> _actorPermissions = <String>{};
  bool _enabled = false;
  bool _includeSubtree = false;
  bool _selfFinance = true;
  bool _teamFinance = false;
  bool _actorSubtree = false;
  bool _actorTeamFinance = false;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final exact = (await OrganizationAccessService.grantsFor(widget.employee.id))
          .where((g) => g.organizationId == widget.organization.id)
          .firstOrNull;
      final actor = TeamService.current;
      final actorPermissions = <String>{};
      var actorSubtree = actor?.isOwner == true || actor == null;
      var actorTeamFinance = actor?.isOwner == true || actor == null;

      if (actor == null || actor.isOwner) {
        actorPermissions.addAll(OrganizationPermissions.all);
      } else {
        for (final permission in OrganizationPermissions.all) {
          if (await OrganizationAccessService.can(
            widget.organization.id,
            permission,
            employeeId: actor.id,
          )) {
            actorPermissions.add(permission);
          }
        }
        for (final grant in await OrganizationAccessService.grantsFor(actor.id)) {
          final covers = grant.organizationId == widget.organization.id ||
              (grant.includeSubtree &&
                  await OrganizationService.isDescendant(
                    widget.organization.id,
                    grant.organizationId,
                  ));
          if (!covers) continue;
          actorSubtree = actorSubtree || grant.includeSubtree;
          actorTeamFinance = actorTeamFinance ||
              (grant.canViewTeamFinance &&
                  grant.permissions.contains(OrganizationPermissions.viewFinance));
        }
      }

      if (!mounted) return;
      setState(() {
        _existing = exact;
        _enabled = exact != null;
        _permissions = exact?.permissions.toSet() ?? <String>{OrganizationPermissions.view};
        _includeSubtree = exact?.includeSubtree ?? false;
        _selfFinance = exact?.canViewSelfFinance ?? true;
        _teamFinance = exact?.canViewTeamFinance ?? false;
        _actorPermissions = actorPermissions;
        _actorSubtree = actorSubtree;
        _actorTeamFinance = actorTeamFinance;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  bool _canDelegate(String permission) => _actorPermissions.contains(permission);

  void _normalize() {
    if (!_enabled) return;
    _permissions.add(OrganizationPermissions.view);
    final financeDependent = <String>{
      OrganizationPermissions.createTransactions,
      OrganizationPermissions.editTransactions,
      OrganizationPermissions.manageAccounts,
      OrganizationPermissions.manageRecurring,
      OrganizationPermissions.viewForecast,
    };
    if (_permissions.any(financeDependent.contains) || _teamFinance) {
      _permissions.add(OrganizationPermissions.viewFinance);
    }
    if (!_permissions.contains(OrganizationPermissions.viewFinance)) {
      _permissions.removeAll(financeDependent);
      _teamFinance = false;
    }
  }

  void _setPermission(String permission, bool value) {
    setState(() {
      if (value) {
        _permissions.add(permission);
      } else {
        _permissions.remove(permission);
        if (permission == OrganizationPermissions.viewFinance) {
          _permissions.removeAll({
            OrganizationPermissions.createTransactions,
            OrganizationPermissions.editTransactions,
            OrganizationPermissions.manageAccounts,
            OrganizationPermissions.manageRecurring,
            OrganizationPermissions.viewForecast,
          });
          _teamFinance = false;
        }
      }
      _normalize();
    });
  }

  void _preset(Set<String> requested, {bool subtree = false, bool teamFinance = false}) {
    setState(() {
      _enabled = true;
      _permissions = requested.where(_canDelegate).toSet();
      if (_canDelegate(OrganizationPermissions.view)) {
        _permissions.add(OrganizationPermissions.view);
      }
      _includeSubtree = subtree && _actorSubtree;
      _teamFinance = teamFinance &&
          _actorTeamFinance &&
          _canDelegate(OrganizationPermissions.viewFinance);
      _selfFinance = true;
      _normalize();
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (!_enabled) {
        if (_existing != null) {
          await OrganizationAccessService.revoke(
            widget.employee.id,
            widget.organization.id,
          );
        }
      } else {
        _normalize();
        if (!_permissions.contains(OrganizationPermissions.view)) {
          throw StateError('Текущая роль не может выдать доступ к этой организации.');
        }
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
        _error = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object error) {
    final text = '$error';
    if (text.contains('cannot grant permission not held by actor')) {
      return 'Нельзя выдать право, которого нет у вашей роли.';
    }
    if (text.contains('manage_members permission required')) {
      return 'У вашей роли нет права управлять сотрудниками этой организации.';
    }
    if (text.contains('cannot grant subtree')) {
      return 'Нельзя открыть дочерние организации шире вашего собственного доступа.';
    }
    return text.replaceFirst('Bad state: ', '');
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.sizeOf(context).height * .92;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          _handle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Доступ сотрудника',
                        style: TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${widget.employee.displayName} · ${widget.organization.name}',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppTheme.glassBorder),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 22),
                    children: [
                      if (_error != null) _errorCard(),
                      _accessMaster(),
                      if (_enabled) ...[
                        const SizedBox(height: 14),
                        _presets(),
                        const SizedBox(height: 18),
                        _section(
                          title: 'Область доступа',
                          icon: Icons.account_tree_outlined,
                          children: [
                            _toggle(
                              title: 'Дочерние организации',
                              subtitle: 'Распространить выбранные права на все организации ниже этой.',
                              value: _includeSubtree,
                              enabled: _actorSubtree,
                              onChanged: (v) => setState(() => _includeSubtree = v),
                            ),
                          ],
                        ),
                        _section(
                          title: 'Финансы',
                          icon: Icons.account_balance_wallet_outlined,
                          children: [
                            _permission(
                              OrganizationPermissions.viewFinance,
                              'Просмотр финансов',
                              'Баланс, операции и сводные показатели организации.',
                            ),
                            _permission(
                              OrganizationPermissions.createTransactions,
                              'Добавление операций',
                              'Создавать доходы и расходы.',
                            ),
                            _permission(
                              OrganizationPermissions.editTransactions,
                              'Изменение и удаление операций',
                              'Исправлять и удалять существующие операции.',
                            ),
                            _permission(
                              OrganizationPermissions.manageAccounts,
                              'Управление счетами',
                              'Создавать и настраивать финансовые счета.',
                            ),
                            _permission(
                              OrganizationPermissions.manageRecurring,
                              'Регулярные платежи',
                              'Создавать и менять повторяющиеся операции.',
                            ),
                            _permission(
                              OrganizationPermissions.viewForecast,
                              'Финансовый прогноз',
                              'Просматривать прогнозы и риски по доступным финансам.',
                            ),
                            _toggle(
                              title: 'Свои финансовые показатели',
                              subtitle: 'Показывать сотруднику его личные показатели в разделе «Мои».',
                              value: _selfFinance,
                              enabled: true,
                              onChanged: (v) => setState(() => _selfFinance = v),
                            ),
                            _toggle(
                              title: 'Финансы других сотрудников',
                              subtitle: 'Показывать персональную финансовую статистику команды. Это более чувствительный доступ.',
                              value: _teamFinance,
                              enabled: _actorTeamFinance &&
                                  _canDelegate(OrganizationPermissions.viewFinance),
                              onChanged: (v) => setState(() {
                                _teamFinance = v;
                                _normalize();
                              }),
                            ),
                          ],
                        ),
                        _section(
                          title: 'Управление',
                          icon: Icons.admin_panel_settings_outlined,
                          children: [
                            _permission(
                              OrganizationPermissions.manageOrgSettings,
                              'Настройки организации',
                              'Менять название, структуру и параметры организации.',
                            ),
                            _permission(
                              OrganizationPermissions.manageMembers,
                              'Управление сотрудниками',
                              'Добавлять сотрудников и настраивать их доступ в пределах своих прав.',
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            decoration: BoxDecoration(
              color: AppTheme.surface.withOpacity(.65),
              border: Border(top: BorderSide(color: AppTheme.glassBorder)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('Отмена'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_enabled ? 'Сохранить доступ' : 'Снять доступ'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle() => Center(
        child: Container(
          width: 42,
          height: 4,
          margin: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: AppTheme.textMuted.withOpacity(.35),
            borderRadius: BorderRadius.circular(20),
          ),
        ),
      );

  Widget _errorCard() => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.accentRed.withOpacity(.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.accentRed.withOpacity(.25)),
        ),
        child: Text(_error!, style: TextStyle(color: AppTheme.accentRed)),
      );

  Widget _accessMaster() => Container(
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.55),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: SwitchListTile(
          value: _enabled,
          onChanged: _canDelegate(OrganizationPermissions.view)
              ? (v) => setState(() {
                    _enabled = v;
                    if (v) _normalize();
                  })
              : null,
          title: Text(
            'Доступ к ${widget.organization.name}',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            _enabled
                ? 'Доступ включён. Ниже можно выбрать, что именно разрешено.'
                : 'Сотрудник не видит данные этой организации.',
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
        ),
      );

  Widget _presets() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Быстрая настройка',
            style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ActionChip(
                avatar: const Icon(Icons.visibility_outlined, size: 16),
                label: const Text('Только просмотр'),
                onPressed: () => _preset({OrganizationPermissions.view}),
              ),
              ActionChip(
                avatar: const Icon(Icons.payments_outlined, size: 16),
                label: const Text('Работа с финансами'),
                onPressed: () => _preset({
                  OrganizationPermissions.view,
                  OrganizationPermissions.viewFinance,
                  OrganizationPermissions.createTransactions,
                  OrganizationPermissions.editTransactions,
                  OrganizationPermissions.manageAccounts,
                  OrganizationPermissions.manageRecurring,
                  OrganizationPermissions.viewForecast,
                }),
              ),
              ActionChip(
                avatar: const Icon(Icons.groups_outlined, size: 16),
                label: const Text('Управление командой'),
                onPressed: () => _preset({
                  OrganizationPermissions.view,
                  OrganizationPermissions.manageMembers,
                }),
              ),
              ActionChip(
                avatar: const Icon(Icons.admin_panel_settings_outlined, size: 16),
                label: const Text('Полный доступ'),
                onPressed: () => _preset(
                  OrganizationPermissions.all.toSet(),
                  subtree: true,
                  teamFinance: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Text(
            'Пресеты никогда не выдают больше прав, чем есть у вашей собственной роли.',
            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
          ),
        ],
      );

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) =>
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(.42),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 6),
              child: Row(
                children: [
                  Icon(icon, size: 18, color: AppTheme.accent),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: TextStyle(
                      color: AppTheme.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      );

  Widget _permission(String permission, String title, String subtitle) => _toggle(
        title: title,
        subtitle: subtitle,
        value: _permissions.contains(permission),
        enabled: _canDelegate(permission),
        onChanged: (v) => _setPermission(permission, v),
      );

  Widget _toggle({
    required String title,
    required String subtitle,
    required bool value,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) =>
      SwitchListTile.adaptive(
        contentPadding: const EdgeInsets.symmetric(horizontal: 4),
        value: value,
        onChanged: enabled ? onChanged : null,
        title: Text(
          title,
          style: TextStyle(
            color: enabled ? AppTheme.textPrimary : AppTheme.textMuted,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          enabled ? subtitle : '$subtitle\nНедоступно для вашей роли.',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 11.5, height: 1.35),
        ),
      );
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
