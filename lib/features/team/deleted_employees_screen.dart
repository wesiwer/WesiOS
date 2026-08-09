import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';
import 'services/employee_admin_service.dart';
import 'services/team_service.dart';

class DeletedEmployeesScreen extends StatefulWidget {
  const DeletedEmployeesScreen({super.key});

  static Future<void> open(BuildContext context) {
    if (!TeamService.isOwnerSession) return Future.value();
    return Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const DeletedEmployeesScreen()),
    );
  }

  @override
  State<DeletedEmployeesScreen> createState() => _DeletedEmployeesScreenState();
}

class _DeletedEmployeesScreenState extends State<DeletedEmployeesScreen> {
  bool get _ru => WesiLocale.isRussian;
  String? _busyId;

  String _date(Object? raw) {
    final value = DateTime.tryParse('$raw')?.toLocal();
    if (value == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}.${two(value.month)}.${value.year} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _restore(Map<String, dynamic> row) async {
    final id = '${row['id']}';
    if (id.isEmpty || _busyId != null) return;

    final name = '${row['fullName']}'.trim().isNotEmpty
        ? '${row['fullName']}'.trim()
        : '${row['nickname']}'.trim().isNotEmpty
            ? '${row['nickname']}'.trim()
            : '${row['login']}';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          _ru ? 'Вернуть сотрудника?' : 'Restore employee?',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          _ru
              ? '$name снова появится в команде. Пароль будет новым — старый из архива не хранится. Права сбросятся к базовым.'
              : '$name will reappear in the team. A new password is generated — the old one is not kept in the archive. Permissions reset to defaults.',
          style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_ru ? 'Отмена' : 'Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_ru ? 'Вернуть' : 'Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyId = id);
    final result = await TeamService.restoreFromArchive(id);
    if (!mounted) return;
    setState(() => _busyId = null);

    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _ru
                ? 'Не удалось вернуть: логин/почта заняты или нет связи с сервером.'
                : 'Restore failed: login/email taken or server unavailable.',
          ),
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          _ru ? 'Сотрудник возвращён' : 'Employee restored',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru
                  ? 'Сохрани логин и пароль — пароль больше нигде не покажется.'
                  : 'Save login and password — the password will not be shown again.',
              style: TextStyle(color: AppTheme.textSecondary, height: 1.4),
            ),
            const SizedBox(height: 12),
            SelectableText(
              '${_ru ? 'Логин' : 'Login'}: ${result.employee.login}\n'
              '${_ru ? 'Пароль' : 'Password'}: ${result.password}',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontFamily: 'monospace',
                height: 1.5,
              ),
            ),
            if (!result.portalProvisioned) ...[
              const SizedBox(height: 10),
              Text(
                _ru
                    ? 'Серверная учётка не создалась — проверь вход владельца и повтори выдачу пароля из карточки.'
                    : 'Server account was not provisioned — check owner session and re-issue password from the card.',
                style: TextStyle(color: AppTheme.accent, fontSize: 12, height: 1.35),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(
                text:
                    '${result.employee.login}\n${result.password}',
              ));
            },
            child: Text(_ru ? 'Скопировать' : 'Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_ru ? 'Готово' : 'Done'),
          ),
        ],
      ),
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!TeamService.isOwnerSession) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        body: Center(
          child: Text(
            _ru ? 'Раздел доступен только владельцу' : 'Owner only',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final rows = EmployeeAdminService.deleted;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                  8, kTitleBarInset + 8, kHasCustomTitleBar ? 148 : 12, 8),
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
                        WesiTitle(
                          _ru ? 'Удалённые сотрудники' : 'Deleted employees',
                          size: 20,
                        ),
                        Text(
                          '${rows.length} ${_ru ? 'записей' : 'records'}',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        _ru ? 'Архив пока пуст' : 'Archive is empty',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                      itemCount: rows.length,
                      itemBuilder: (_, index) => _card(rows[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(Map<String, dynamic> row) {
    final id = '${row['id']}';
    final name = '${row['fullName']}'.trim().isNotEmpty
        ? '${row['fullName']}'.trim()
        : '${row['nickname']}'.trim().isNotEmpty
            ? '${row['nickname']}'.trim()
            : '${row['login']}';
    final reason = '${row['reason']}'.trim();
    final activated = row['wasActivated'] == true;
    final busy = _busyId == id;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (activated ? AppTheme.accentGreen : AppTheme.accent)
                      .withOpacity(0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  activated
                      ? (_ru ? 'был активирован' : 'was activated')
                      : (_ru ? 'не был активирован' : 'not activated'),
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: activated ? AppTheme.accentGreen : AppTheme.accent,
                  ),
                ),
              ),
            ],
          ),
          if ('${row['position']}'.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text('${row['position']}',
                style: TextStyle(fontSize: 12, color: AppTheme.accent)),
          ],
          const SizedBox(height: 10),
          _line(Icons.login, '${_ru ? 'Логин' : 'Login'}: ${row['login']}'),
          _line(Icons.event_busy,
              '${_ru ? 'Удалён' : 'Deleted'}: ${_date(row['deletedAt'])}'),
          _line(
            Icons.notes,
            '${_ru ? 'Причина' : 'Reason'}: '
            '${reason.isEmpty ? (_ru ? 'не указана' : 'not specified') : reason}',
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: busy || _busyId != null ? null : () => _restore(row),
              icon: busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.restart_alt, size: 16),
              label: Text(
                busy
                    ? (_ru ? 'Возвращаю…' : 'Restoring…')
                    : (_ru ? 'Вернуть' : 'Restore'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _line(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: AppTheme.textMuted),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                    fontSize: 12, height: 1.35, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
}
