import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../models/employee_model.dart';

/// Скрытая заметка о человеке.
///
/// Открывается долгим нажатием (телефон) или правым кликом (компьютер) и
/// только тем, у кого есть право её видеть. Само наличие пункта в меню тоже
/// скрыто: намёк «здесь что-то есть, но тебе нельзя» — это приглашение
/// поинтересоваться, чего именно.
class EmployeeNotesSheet extends StatelessWidget {
  final EmployeeModel employee;

  const EmployeeNotesSheet({super.key, required this.employee});

  static Future<void> show(BuildContext context, EmployeeModel employee) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => EmployeeNotesSheet(employee: employee),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final notes = employee.notes.trim();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline, size: 17, color: AppTheme.accent),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    ru ? 'Заметка о человеке' : 'Private note',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              ru
                  ? 'Видно только вам и тем, кому вы это открыли. Сам '
                      'сотрудник её не видит.'
                  : 'Visible only to you and those you granted access. The '
                      'person themselves does not see it.',
              style: TextStyle(
                  fontSize: 11, height: 1.4, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 320),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.surfaceLight.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.glassBorder),
              ),
              child: SingleChildScrollView(
                child: Text(
                  notes.isEmpty
                      ? (ru ? 'Заметки нет' : 'No note yet')
                      : notes,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: notes.isEmpty
                        ? AppTheme.textMuted
                        : AppTheme.textPrimary,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _row(ru ? 'Логин' : 'Login', employee.login),
            _row(
              ru ? 'Заведён' : 'Created',
              '${employee.createdAt.day.toString().padLeft(2, '0')}.'
                  '${employee.createdAt.month.toString().padLeft(2, '0')}.'
                  '${employee.createdAt.year}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Text('$label: ',
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted)),
            Expanded(
              child: SelectableText(
                value,
                style:
                    TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          ],
        ),
      );
}
