import 'package:flutter/material.dart';

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
      (p) =>
          p != OrganizationPermissions.viewFinance &&
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
                    subtitle:
                        'Раздел «Мои»: собственная динамика и личные риски.',
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

  Widget _section(String title, String hint, List<Widget> children) =>
      Container(
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
  }) =>
      CheckboxListTile(
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
