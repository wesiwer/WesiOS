import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';

/// Кому принадлежит задача.
///
/// Поле `assignee` в задаче — строка, и это намеренно не менялось: в уже
/// записанных задачах там лежит имя, набранное руками. Теперь туда кладётся
/// **идентификатор человека** из состава, а старые записи продолжают
/// читаться как есть — [displayName] сначала ищет человека, и только не
/// найдя, показывает строку.
class TaskAssignment {
  TaskAssignment._();

  /// Идентификатор подтверждённого пользователя.
  ///
  /// Без входа — null. Раньше здесь подставлялся локальный владелец, и любая
  /// бизнес-логика, использующая currentId, снова получала fail-open обход.
  static String? get currentId => TeamService.current?.id;

  /// Может ли текущий человек ставить задачи другим.
  static bool get canAssignToOthers =>
      TeamService.currentPermissions.canAssignTasks;

  static String displayName(String? assignee, {String fallback = ''}) {
    if (assignee == null || assignee.trim().isEmpty) return fallback;
    final person = TeamService.byId(assignee);
    if (person != null) return person.displayName;
    return assignee;
  }

  static EmployeeModel? personOf(String? assignee) =>
      assignee == null ? null : TeamService.byId(assignee);

  static String? coerce(String? requested) {
    if (canAssignToOthers) {
      final value = requested?.trim();
      return value == null || value.isEmpty ? null : value;
    }
    final me = currentId;
    if (me == null) return null;
    return me;
  }

  static List<EmployeeModel> candidates() {
    final all = TeamService.all;
    final meId = currentId;
    if (meId == null) return const [];
    final me = <EmployeeModel>[];
    final rest = <EmployeeModel>[];
    for (final e in all) {
      (e.id == meId ? me : rest).add(e);
    }
    return [...me, ...rest];
  }
}
