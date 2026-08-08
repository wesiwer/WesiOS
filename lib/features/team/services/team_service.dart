import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/security/shield_service.dart';
import '../../../core/services/firebase_rest_service.dart';
import '../../../core/sync/sync_auto.dart';
import '../../../core/sync/sync_endpoint.dart';
import '../models/employee_model.dart';
import '../models/team_permissions.dart';
import 'credentials_generator.dart';
import 'employee_admin_service.dart';
import 'login_pool_service.dart';
import 'portal_account_service.dart';

/// Результат создания сотрудника.
///
/// Пароль возвращается ЗДЕСЬ и только здесь — это единственный момент, когда
/// он существует в открытом виде. Дальше в базе лежит его хеш, и показать
/// пароль повторно нельзя: можно лишь выдать новый.
class CreatedEmployee {
  final EmployeeModel employee;
  final String password;
  final bool portalProvisioned;

  const CreatedEmployee(
    this.employee,
    this.password, {
    this.portalProvisioned = false,
  });
}

/// Новый пароль вместе с фактическим результатом серверной активации.
class ResetEmployeePassword {
  final String password;
  final PortalCredentialResult portal;

  const ResetEmployeePassword(this.password, this.portal);
}

/// Сотрудники: кто есть, кто чем может пользоваться, кто под каким логином
/// входит.
class TeamService {
  TeamService._();

  static const String boxName = 'wesios_team';
  static const int maxPhotoBytes = 100 * 1024;
  static const String _settingsBox = 'wesios_settings';
  static const String _currentKey = 'team_current_employee';
  static const int _iterations = 60000;

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

  static List<EmployeeModel> get all {
    final box = _open();
    if (box == null) return const [];
    final list = box.values.toList();
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

  static EmployeeModel? get current {
    final id = _settings()?.get(_currentKey);
    if (id is! String || id.isEmpty) return null;
    return byId(id);
  }

  /// Без подтверждённого пользователя нет никаких выдаваемых прав.
  ///
  /// Раньше null означал владельца. На чистой установке это превращало
  /// отсутствие входа в полный административный доступ. Безопасное правило
  /// обратное: нет сессии — нет привилегий.
  static TeamPermissions get currentPermissions =>
      current?.permissions ?? const TeamPermissions();

  static bool get isOwnerSession => current?.isOwner == true;

  static const String _rememberKey = 'team_remember_session';

  static bool get remembered => _settings()?.get(_rememberKey) != false;

  static Future<void> signIn(
    EmployeeModel employee, {
    bool remember = true,
  }) async {
    final box = _settings();
    if (box == null) return;
    await box.put(_currentKey, employee.id);
    await box.put(_rememberKey, remember);
    revision.value++;
  }

  /// Применяет роль и права, которые вернул защищённый серверный bootstrap.
  /// Клиент сам себе владельца или дополнительные модули здесь не назначает.
  static Future<EmployeeModel?> applyServerIdentity(
    PortalAppIdentity identity, {
    bool remember = true,
  }) async {
    final box = _open();
    if (box == null) return null;

    final existing = box.get(identity.employeeId);
    final employee = existing != null && existing.isOwner == identity.isOwner
        ? existing.copyWith(
            login: identity.login,
            fullName: identity.fullName,
            nickname: identity.nickname,
            position: identity.position,
            email: identity.email,
            permissions: identity.permissions,
            avatarIndex: identity.avatarIndex,
          )
        : EmployeeModel(
            id: identity.employeeId,
            login: identity.login,
            fullName: identity.fullName,
            nickname: identity.nickname,
            position: identity.position,
            email: identity.email,
            permissions: identity.permissions,
            avatarIndex: identity.avatarIndex,
            createdAt: identity.createdAt,
            isOwner: identity.isOwner,
          );

    await box.put(employee.id, employee);
    await signIn(employee, remember: remember);
    revision.value++;
    return employee;
  }

  static Future<void> forgetUnrememberedSession() async {
    final box = _settings();
    if (box == null) return;
    if (box.get(_rememberKey) == false) {
      SyncAuto.stop();
      await box.delete(_currentKey);
      await box.delete(_rememberKey);
      await SyncEndpoint.clearSession();
      await FirebaseRestService.signOut();
      revision.value++;
    }
  }

  /// Полный выход из WesiOS.
  ///
  /// Локальная роль, PocketBase-токен и старый Firebase-токен стираются
  /// вместе. Оставлять хотя бы один из них означало бы, что экран входа можно
  /// обойти после logout через другой сервис.
  static Future<void> signOut() async {
    SyncAuto.stop();
    final box = _settings();
    await box?.delete(_currentKey);
    await box?.delete(_rememberKey);
    await SyncEndpoint.clearSession();
    await FirebaseRestService.signOut();
    revision.value++;
  }

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

  static String _newSalt([Random? random]) {
    final rng = random ?? Random.secure();
    return base64.encode(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

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
    Uint8List? photo,
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
      photo: photo,
      createdAt: DateTime.now(),
      demoStats: withDemoStats ? generateDemoStats(random: random) : const {},
    );

    await box.put(employee.id, employee);
    revision.value++;

    final portal = await PortalAccountService.provisionDetailed(
      employee: employee,
      password: pass,
    );
    await EmployeeAdminService.setActivationResult(
      employee.id,
      success: portal.ok,
      message: portal.message,
    );
    revision.value++;

    return CreatedEmployee(
      employee,
      pass,
      portalProvisioned: portal.ok,
    );
  }

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
    await EmployeeAdminService.setActivated(employee.id, true);
    revision.value++;
    return employee;
  }

  static Future<void> save(EmployeeModel employee) async {
    await _open()?.put(employee.id, employee);
    revision.value++;

    // Изменение прав владельцем немедленно фиксируется и в серверной связке
    // аккаунта. Bootstrap сотрудника не должен ждать следующего полного sync.
    if (isOwnerSession && !employee.isOwner && SyncEndpoint.isConnected) {
      await PortalAccountService.updateAccess(employee);
    }
  }

  /// Убирает сотрудника из рабочего состава, но сохраняет закрытый архивный
  /// снимок с датой и причиной. Владелец может просматривать его отдельно.
  static Future<bool> remove(String id, {String reason = ''}) async {
    final box = _open();
    final employee = box?.get(id);
    if (box == null || employee == null) return false;
    if (employee.isOwner) return false;

    // На рабочем устройстве владельца сначала закрываем серверный вход.
    // Иначе удалённый из интерфейса человек продолжал бы иметь действующую
    // учётную запись на сайте и в приложении.
    if (isOwnerSession && SyncEndpoint.isConnected) {
      final revoked = await PortalAccountService.revoke(employee);
      if (!revoked.ok) return false;
    }

    await EmployeeAdminService.archive(employee, reason: reason);
    await box.delete(id);
    await LoginPoolService.release(employee.login);
    if (current?.id == id) await signOut();
    revision.value++;
    return true;
  }

  static const String loginOk = 'ok';
  static const String loginTaken = 'taken';
  static const String loginBad = 'bad';
  static const String loginNoSuchPerson = 'gone';

  static Future<String> setLogin(String id, String login) async {
    final employee = byId(id);
    if (employee == null) return loginNoSuchPerson;

    final normalized = CredentialsGenerator.normalize(login);
    if (normalized.length < 3) return loginBad;
    if (normalized == employee.login) return loginOk;

    final other = byLogin(normalized);
    if (other != null && other.id != id) return loginTaken;
    if (LoginPoolService.isTaken(normalized)) return loginTaken;

    final old = employee.login;
    if (!await LoginPoolService.reserve(normalized)) return loginTaken;
    await save(employee.copyWith(login: normalized));
    await LoginPoolService.release(old);
    return loginOk;
  }

  /// Сохраняет только локальный PBKDF2-хеш пароля, без сетевого запроса.
  ///
  /// Нужен владельцу после того, как сервер уже принял данные и контрольный
  /// вход прошёл: повторная публикация тех же учётных данных создавала вторую
  /// точку отказа после фактически успешной операции.
  static Future<bool> setPasswordLocally(String id, String password) async {
    final employee = byId(id);
    if (employee == null || password.length < 8 || password.length > 128) {
      return false;
    }
    final salt = _newSalt();
    await save(employee.copyWith(
      passwordSalt: salt,
      passwordHash: ShieldService.derive(password, salt, _iterations),
    ));
    return true;
  }

  /// Меняет локальный пароль и сразу возвращает точный результат сервера.
  static Future<PortalCredentialResult?> setPasswordDetailed(
    String id,
    String password,
  ) async {
    final employee = byId(id);
    if (employee == null) return null;
    if (password.length < 8 || password.length > 128) {
      return const PortalCredentialResult.failure(
        'Пароль должен содержать от 8 до 128 символов.',
      );
    }

    if (!await setPasswordLocally(id, password)) return null;
    final updated = byId(id);
    if (updated == null) return null;

    final portal = await PortalAccountService.provisionDetailed(
      employee: updated,
      password: password,
    );
    await EmployeeAdminService.setActivationResult(
      id,
      success: portal.ok,
      message: portal.message,
    );
    revision.value++;
    return portal;
  }

  static Future<bool> setPassword(String id, String password) async {
    final result = await setPasswordDetailed(id, password);
    return result?.ok == true;
  }

  /// Выдаёт новый пароль, повторно создаёт серверную запись и возвращает
  /// человеку как сам пароль, так и фактический результат активации.
  static Future<ResetEmployeePassword?> resetPasswordDetailed(String id) async {
    if (byId(id) == null) return null;
    final pass = CredentialsGenerator.password();
    final portal = await setPasswordDetailed(id, pass);
    if (portal == null) return null;
    return ResetEmployeePassword(pass, portal);
  }

  /// Совместимость со старым интерфейсом сброса пароля.
  static Future<String?> resetPassword(String id) async {
    final result = await resetPasswordDetailed(id);
    return result?.password;
  }

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

  static Future<void> reconcileLogins() =>
      LoginPoolService.reconcile(all.map((e) => e.login));
}
