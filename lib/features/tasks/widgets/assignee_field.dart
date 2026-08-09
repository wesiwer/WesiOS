import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wesi_avatar.dart';
import '../../team/models/employee_model.dart';
import '../../team/widgets/employee_or_custom_field.dart';
import '../services/task_assignment.dart';

/// Выбор исполнителя.
///
/// Раньше здесь было поле со свободным вводом: имя, набранное руками,
/// никуда не вело и ничего не значило — задача не появлялась у человека, он
/// о ней не узнавал. Теперь исполнитель выбирается из состава.
///
/// **Если права раздавать поручения нет**, поле не исчезает, а показывает
/// самого человека и объясняет почему. Исчезнувшее поле читается как
/// «сломалось»; закрытое с объяснением — как решение владельца, которое
/// можно попросить изменить.
class AssigneeField extends StatelessWidget {
  final String? value;
  final ValueChanged<String?> onChanged;

  const AssigneeField(
      {super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    final people = TaskAssignment.candidates();
    final canAssign = TaskAssignment.canAssignToOthers;

    if (people.isEmpty) {
      return _hint(ru
          ? 'Состав пуст — заведите людей в контактах, и их можно будет '
              'выбирать исполнителями.'
          : 'No people yet — add them in contacts to assign tasks.');
    }

    if (!canAssign) {
      final me = TaskAssignment.personOf(TaskAssignment.currentId);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(ru ? 'Исполнитель' : 'Assignee'),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight.withOpacity(0.3),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppTheme.glassBorder),
            ),
            child: Row(
              children: [
                if (me != null) ...[
                  WesiAvatar(
                      size: 22,
                      index: me.avatarIndex,
                      photo: me.photo,
                      showBorder: false),
                  const SizedBox(width: 9),
                ],
                Expanded(
                  child: Text(
                    me?.displayName ?? (ru ? 'Вы' : 'You'),
                    style:
                        TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                  ),
                ),
                Icon(Icons.lock_outline, size: 15, color: AppTheme.textMuted),
              ],
            ),
          ),
          const SizedBox(height: 5),
          _hint(ru
              ? 'Ставить задачи другим вам не открыто — задача останется за вами.'
              : 'You cannot assign to others — the task stays with you.'),
        ],
      );
    }

    return EmployeeOrCustomField(
      label: ru ? 'Исполнитель' : 'Assignee',
      value: value,
      storeEmployeeId: true,
      allowCustom: true,
      allowEmpty: true,
      customLabel: ru ? 'Другой исполнитель' : 'Other assignee',
      onChanged: onChanged,
    );
  }

  /// Исполнитель из старой записи — имя строкой — в списке отсутствует.
  /// Подставлять его в value нельзя: DropdownButton падает на значении,
  /// которого нет среди пунктов.
  bool _valueInList(List<EmployeeModel> people) =>
      value != null && people.any((p) => p.id == value);

  Widget _person(EmployeeModel p, bool ru) {
    final isMe = p.id == TaskAssignment.currentId;
    return Row(
      children: [
        WesiAvatar(
            size: 20, index: p.avatarIndex, photo: p.photo, showBorder: false),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            isMe ? '${p.displayName} · ${ru ? 'вы' : 'you'}' : p.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _label(String text) =>
      Text(text, style: TextStyle(fontSize: 11, color: AppTheme.textMuted));

  Widget _hint(String text) => Text(
        text,
        style:
            TextStyle(fontSize: 10.5, height: 1.35, color: AppTheme.textMuted),
      );
}
