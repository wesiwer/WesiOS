import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/security/shield_service.dart';
import '../models/employee_model.dart';
import '../models/team_permissions.dart';
import 'credentials_generator.dart';
import 'login_pool_service.dart';

/// Результат создания сотрудника.
///
/// Пароль возвращается ЗДЕСЬ и только здесь — это единственный момент, когда
/// он существует в открытом виде. Дальше в базе лежит его хеш, и показать
/// пароль повторно нельзя ни владельцу, ни кому-либо ещё: можно лишь выдать
/// новый.
class CreatedEmployee {
  final EmployeeModel employee;
  final String password;

  const CreatedEmployee(this.employee, this.password);
}

/// Сотрудники: кто есть, кто чем может пользоваться, кто под каким логином
/// входит.
///
/// Пока всё лежит на устройстве. Устроено так, чтобы переезд на сервер был
/// заменой хранилища, а не переписыванием: наружу отдаются готовые модели, а
/// не строки Hive, и проверка пароля уже сейчас идёт через хеш — ровно так,
/// как её будет делать сервер.
class TeamService {
  TeamService._();

  static const String boxName = 'wesios_team';
  static const String _settingsBox = 'wesios_settings';
  static const String _currentKey = 'team_current_employee';

  /// Итераций для хеша пароля сотрудника.
  ///
  /// Меньше, чем у пароля Wesi Shield (120 000): тот защищает ключ
  /// шифрования на устройстве и подбирается офлайн, а этот скоро переедет на
  /// сервер, где перебор ограничен ещё и сетью. 60 000 держат вход быстрым
  /// на телефоне и остаются дорогими для перебора.
  static const int _iterations = 60000;

  /// Меняется при любой правке состава — экраны перечитывают список.
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Box<EmployeeModel>? _open() {
    try {
      return Hive.box<EmployeeModel>(boxName);
    } catch (_) {
      return null;
    }
  }

  static Box<dynamic>? _settings() {
    try {
      return Hive.box(_settingsBox);
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ состав

  static List<EmployeeModel> get all {
    final box = _open();
    if (box == null) return const [];
    final list = box.values.toList();
    // Владелец первым, дальше по имени — список читают глазами.
    list.sort((a, b) {
      if (a.isOwner != b.isOwner) return a.isOwner ? -1 : 1;
      return a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
    });
    return list;
  }

  static EmployeeModel? byId(String id) => _open()?.get(id);

  static EmployeeModel? byLogin(String login) {
    final normalized = CredentialsGenerator.normalize(login);
    for (final e in all) {
      if (e.login == normalized) return e;
    }
    return null;
  }

  static EmployeeModel? get owner {
    for (final e in all) {
      if (e.isOwner) return e;
    }
    return null;
  }

  // ------------------------------------------------------------ кто вошёл

  /// Кто сейчас в приложении. null — никто не входил (режим владельца).
  static EmployeeModel? get current {
    final id = _settings()?.get(_currentKey);
    if (id is! String || id.isEmpty) return null;
    return byId(id);
  }

  /// Права того, кто сейчас в приложении.
  ///
  /// Никто не вошёл — значит это владелец на своём устройстве: приложение
  /// работает локально и до появления сотрудников вообще не знает о правах.
  /// Отдавать в этом случае пустой набор значило бы запереть человека в
  /// пустом приложении сразу после установки.
  static TeamPermissions get currentPermissions =>
      current?.permissions ?? TeamPermissions.owner;

  static bool get isOwnerSession => current == null || current!.isOwner;

  static Future<void> signIn(EmployeeModel employee) async {
    await _settings()?.put(_currentKey, employee.id);
    revision.value++;
  }

  static Future<void> signOut() async {
    await _settings()?.delete(_currentKey);
    revision.value++;
  }

  /// Проверяет логин и пароль. null — не совпало.
  ///
  /// Одинаковый ответ на «нет такого логина» и «пароль не тот» — намеренно:
  /// разный позволял бы перебором выяснить, кто вообще есть в компании.
  static EmployeeModel? verify(String login, String password) {
    final employee = byLogin(login);
    if (employee == null) return null;
    if (employee.passwordHash.isEmpty || employee.passwordSalt.isEmpty) {
      return null;
    }
    final hash = ShieldService.derive(
      password,
      employee.passwordSalt,
      _iterations,
    );
    return _constantTimeEquals(hash, employee.passwordHash) ? employee : null;
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }

  // ------------------------------------------------------------- изменения

  static String _newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    return base64.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  /// Заводит сотрудника: занимает свободный логин, генерирует пароль.
  ///
  /// Возвращает null, если свободных логинов не осталось.
  static Future<CreatedEmployee?> create({
    required String fullName,
    String nickname = '',
    String position = '',
    String phone = '',
    String email = '',
    Map<String, String> socials = const {},
    String notes = '',
    TeamPermissions permissions = TeamPermissions.employeeDefault,
    int avatarIndex = 0,
    String? login,
    String? password,
    Random? random,
    bool withDemoStats = true,
  }) async {
    final box = _open();
    if (box == null) return null;

    final chosen = login ?? LoginPoolService.suggest(random: random);
    if (chosen == null) return null;
    final normalized = CredentialsGenerator.normalize(chosen);
    if (!await LoginPoolService.reserve(normalized)) return null;

    final pass = password ?? CredentialsGenerator.password();
    final salt = _newSalt(random);

    final employee = EmployeeModel(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      login: normalized,
      fullName: fullName.trim(),
      nickname: nickname.trim(),
      position: position.trim(),
      phone: phone.trim(),
      email: email.trim(),
      socials: socials,
      notes: notes,
      permissions: permissions,
      passwordHash: ShieldService.derive(pass, salt, _iterations),
      passwordSalt: salt,
      avatarIndex: avatarIndex,
      createdAt: DateTime.now(),
      demoStats: withDemoStats ? generateDemoStats(random: random) : const {},
    );

    await box.put(employee.id, employee);
    revision.value++;
    return CreatedEmployee(employee, pass);
  }

  /// Заводит карточку владельца — один раз, при первом открытии контактов.
  static Future<EmployeeModel?> ensureOwner({String name = 'Владелец'}) async {
    final box = _open();
    if (box == null) return null;
    final existing = owner;
    if (existing != null) return existing;

    final employee = EmployeeModel(
      id: 'owner',
      login: 'owner',
      fullName: name,
      position: 'CEO',
      permissions: TeamPermissions.owner,
      createdAt: DateTime.now(),
      isOwner: true,
    );
    await LoginPoolService.reserve('owner');
    await box.put(employee.id, employee);
    revision.value++;
    return employee;
  }

  static Future<void> save(EmployeeModel employee) async {
    await _open()?.put(employee.id, employee);
    revision.value++;
  }

  /// Убирает сотрудника. Логин возвращается в свободные, пароль исчезает
  /// вместе с записью.
  static Future<bool> remove(String id) async {
    final box = _open();
    final employee = box?.get(id);
    if (box == null || employee == null) return false;
    // Владельца удалить нельзя: без него некому заводить остальных.
    if (employee.isOwner) return false;

    await box.delete(id);
    await LoginPoolService.release(employee.login);
    if (current?.id == id) await signOut();
    revision.value++;
    return true;
  }

  /// Смена пароля — сотрудником себе или владельцем сотруднику.
  static Future<void> setPassword(String id, String password) async {
    final employee = byId(id);
    if (employee == null) return;
    final salt = _newSalt();
    await save(employee.copyWith(
      passwordSalt: salt,
      passwordHash: ShieldService.derive(password, salt, _iterations),
    ));
  }

  /// Выдаёт сотруднику новый пароль и возвращает его — показать один раз.
  static Future<String?> resetPassword(String id) async {
    if (byId(id) == null) return null;
    final pass = CredentialsGenerator.password();
    await setPassword(id, pass);
    return pass;
  }

  // ------------------------------------------------------ проверочные данные

  /// Случайные показатели, пока настоящих нет.
  ///
  /// Нужны ровно затем, чтобы можно было пройти путь целиком — завести
  /// человека, войти под ним, посмотреть его аналитику — до того, как
  /// появится сервер с реальными цифрами. Значения помечены как демо и
  /// уходят при первой настоящей синхронизации.
  static Map<String, double> generateDemoStats({Random? random}) {
    final rng = random ?? Random();
    double between(double a, double b) => a + rng.nextDouble() * (b - a);
    return {
      'balance': between(20000, 400000),
      'incomeMonth': between(30000, 250000),
      'expenseMonth': between(10000, 180000),
      'tasksDone': rng.nextInt(80).toDouble(),
      'tasksOpen': rng.nextInt(25).toDouble(),
      'efficiency': between(0.45, 0.98),
    };
  }

  /// Приводит список занятых логинов в соответствие с составом.
  static Future<void> reconcileLogins() =>
      LoginPoolService.reconcile(all.map((e) => e.login));
}
