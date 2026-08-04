import '../../team/models/employee_model.dart';
import '../../team/services/team_service.dart';

/// Кому принадлежит задача.
///
/// Поле `assignee` в задаче — строка, и это намеренно не менялось: в уже
/// записанных задачах там лежит имя, набранное руками. Теперь туда кладётся
/// **идентификатор человека** из состава, а старые записи продолжают
/// читаться как есть — [displayName] сначала ищет человека, и только не
/// найдя, показывает строку.
///
/// Смена типа поля означала бы новый адаптер Hive и потерю уже введённых
/// имён; выигрыш не стоил бы этого.
class TaskAssignment {
  TaskAssignment._();

  /// Идентификатор того, кто сейчас работает в приложении.
  ///
  /// null — за приложением владелец и состав ещё не заведён. В этом случае
  /// задача остаётся без исполнителя, а не приписывается несуществующему
  /// человеку.
  static String? get currentId => TeamService.current?.id ?? TeamService.owner?.id;

  /// Может ли текущий человек ставить задачи другим.
  static bool get canAssignToOthers =>
      TeamService.currentPermissions.canAssignTasks;

  /// Как показать исполнителя.
  ///
  /// Порядок важен: сначала состав, потом сырая строка. Иначе человек,
  /// которого зовут так же, как называется старая запись, показывался бы
  /// дважды по-разному.
  static String displayName(String? assignee, {String fallback = ''}) {
    if (assignee == null || assignee.trim().isEmpty) return fallback;
    final person = TeamService.byId(assignee);
    if (person != null) return person.displayName;
    return assignee;
  }

  /// Человек из состава, если исполнитель — он. null для старых записей и
  /// для задач без исполнителя.
  static EmployeeModel? personOf(String? assignee) =>
      assignee == null ? null : TeamService.byId(assignee);

  /// Приводит исполнителя к тому, что человеку **разрешено** назначить.
  ///
  /// Вызывается в сервисе, а не только в интерфейсе. Проверка, живущая
  /// исключительно в диалоге, убирает список с экрана, но не мешает задаче
  /// с чужим исполнителем приехать другим путём — например из
  /// синхронизации или из старого экрана, про который забыли.
  ///
  /// Без права: задача достаётся себе. Не «отказать» и не «оставить пустой»
  /// — человек хотел завести задачу, и она у него будет; чужой она просто не
  /// станет.
  static String? coerce(String? requested) {
    if (canAssignToOthers) return requested;
    final me = currentId;
    if (me == null) return null;
    return me;
  }

  /// Кому вообще можно поручать.
  ///
  /// Себя всегда первым: чаще всего задачу заводят себе, и заставлять искать
  /// себя в списке из двадцати человек — лишнее движение на каждую задачу.
  static List<EmployeeModel> candidates() {
    final all = TeamService.all;
    final meId = currentId;
    if (meId == null) return all;
    final me = <EmployeeModel>[];
    final rest = <EmployeeModel>[];
    for (final e in all) {
      (e.id == meId ? me : rest).add(e);
    }
    return [...me, ...rest];
  }
}
