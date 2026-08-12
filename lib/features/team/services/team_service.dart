import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../../../core/security/session_service.dart';
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

class ResetEmployeePassword {
  final String password;
  final PortalCredentialResult portal;

  const ResetEmployeePassword(this.password, this.portal);
}

class TeamService {
  TeamService._();

  static const String boxName = 'wesios_team';
  static const int maxPhotoBytes = 100 * 1024;
  static const String _settingsBox = 'wesios_settings';
  static const String _currentKey = 'team_current_employee';
  static const String _rememberKey = 'team_remember_session';
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

  static EmployeeModel? byEmail(String email) {
    final normalized = email.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final e in all) {
      if (e.email.trim().toLowerCase() == normalized) return e;
    }
    return null;
  }

  static bool validEmployeeEmail(String value) =>
      PortalAccountService.validSecurityEmail(value);

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

  static TeamPermissions get currentPermissions =>
      current?.permissions ?? const TeamPermissions();

  static bool get isOwnerSession => current?.isOwner == true;
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

  static Future<void> repairLocalSessionReference() async {
    final box = _settings();
    if (box == null) return;
    final currentId = box.get(_currentKey);
    if (currentId is String &&
        currentId.isNotEmpty &&
        byId(currentId) == null) {
      await box.delete(_currentKey);
      await box.delete(_rememberKey);
      revision.value++;
    }
  }

  static Future<void> forgetUnrememberedSession() async {
    final box = _settings();
    if (box == null) return;
    if (box.get(_rememberKey) == false) {
      SyncAuto.stop();
      await SessionService.revokeCurrent();
      SessionService.stopHeartbeat();
      await box.delete(_currentKey);
      await box.delete(_rememberKey);
      await SyncEndpoint.clearSession();
      await FirebaseRestService.signOut();
      revision.value++;
    }
  }

  /// Logout is a real remote logout: the server-side WesiOS session is
  /// revoked first and only then are local credentials removed.
  static Future<void> signOut() async {
    SyncAuto.stop();
    await SessionService.revokeCurrent();
    SessionService.stopHeartbeat();
    final box = _settings();
    await box?.delete(_currentKey);
    await box?.delete(_rememberKey);
    await SyncEndpoint.clearSession();
    await FirebaseRestService.signOut();
    revision.value++;
  }

  /// Legacy local password verification remains only for old maintenance
  /// tests/tools. It is never used to authorize application access.
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
    required String email,
    String nickname = '',
    String position = '',
    String phone = '',
    Map<String, String> socials = const {},
    String notes = '',
    TeamPermissions permissions = TeamPermissions.employeeDefault,
    int avatarIndex = 0,
    Uint8List? photo,
    List<String> skills = const [],
    double weeklyCapacityPoints = 10,
    double workloadMinRatio = .65,
    double workloadMaxRatio = 1.10,
    String? managerEmployeeId,
    String workloadAlertTarget = 'manager',
    String? login,
    String? password,
    Random? random,
  }) async {
    final box = _open();
    if (box == null) return null;

    final normalizedEmail = email.trim().toLowerCase();
    if (!validEmployeeEmail(normalizedEmail)) return null;
    if (byEmail(normalizedEmail) != null) return null;

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
      email: normalizedEmail,
      socials: socials,
      notes: notes,
      permissions: permissions,
      passwordHash: ShieldService.derive(pass, salt, _iterations),
      passwordSalt: salt,
      avatarIndex: avatarIndex,
      photo: photo,
      skills: skills,
      weeklyCapacityPoints: weeklyCapacityPoints,
      workloadMinRatio: workloadMinRatio,
      workloadMaxRatio: workloadMaxRatio,
      managerEmployeeId: managerEmployeeId,
      workloadAlertTarget: workloadAlertTarget,
      createdAt: DateTime.now(),
      // Field kept for Hive compatibility only. New profiles never receive
      // random/demo business figures.
      demoStats: const {},
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

  /// Возвращает удалённого сотрудника из архива.
  ///
  /// Пароль, хеш, права и заметки в архиве намеренно не хранятся — поэтому
  /// при восстановлении выдаётся новый пароль и базовые права сотрудника.
  /// Тот же [id] сохраняется, чтобы не рвать связи в задачах/чатах.
  /// Логин берётся старый, если он свободен; иначе — новый из пула.
  static Future<CreatedEmployee?> restoreFromArchive(
    String archivedId, {
    Random? random,
  }) async {
    if (!isOwnerSession) return null;
    final box = _open();
    if (box == null) return null;
    if (byId(archivedId) != null) return null;

    Map<String, dynamic>? row;
    for (final e in EmployeeAdminService.deleted) {
      if ('${e['id']}' == archivedId) {
        row = e;
        break;
      }
    }
    if (row == null) return null;

    final email = '${row['email']}'.trim().toLowerCase();
    if (!validEmployeeEmail(email)) return null;
    if (byEmail(email) != null) return null;

    var login = CredentialsGenerator.normalize('${row['login']}');
    if (login.isEmpty ||
        byLogin(login) != null ||
        LoginPoolService.isTaken(login)) {
      final suggested = LoginPoolService.suggest(random: random);
      if (suggested == null) return null;
      login = suggested;
    }

    if (!await LoginPoolService.reserve(login)) return null;

    final pass = CredentialsGenerator.password();
    final salt = _newSalt(random);
    final createdAt =
        DateTime.tryParse('${row['createdAt']}') ?? DateTime.now();

    final socialsRaw = row['socials'];
    final socials = <String, String>{};
    if (socialsRaw is Map) {
      socialsRaw.forEach((k, v) {
        final key = '$k'.trim();
        final value = '$v'.trim();
        if (key.isNotEmpty && value.isNotEmpty) socials[key] = value;
      });
    }

    final employee = EmployeeModel(
      id: archivedId,
      login: login,
      fullName: '${row['fullName']}'.trim(),
      nickname: '${row['nickname']}'.trim(),
      position: '${row['position']}'.trim(),
      phone: '${row['phone']}'.trim(),
      email: email,
      socials: socials,
      permissions: TeamPermissions.employeeDefault,
      passwordHash: ShieldService.derive(pass, salt, _iterations),
      passwordSalt: salt,
      createdAt: createdAt,
      demoStats: const {},
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
    await EmployeeAdminService.deleteArchiveEntry(archivedId);
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

    if (isOwnerSession && !employee.isOwner && SyncEndpoint.isConnected) {
      await PortalAccountService.updateAccess(employee);
    }
  }

  static Future<bool> remove(String id, {String reason = ''}) async {
    final box = _open();
    final employee = box?.get(id);
    if (box == null || employee == null) return false;
    if (employee.isOwner) return false;

    // Server revoke deletes the auth account. The security delete hook then
    // revokes every active device session before the local card disappears.
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

  static Future<ResetEmployeePassword?> resetPasswordDetailed(String id) async {
    if (byId(id) == null) return null;
    final pass = CredentialsGenerator.password();
    final portal = await setPasswordDetailed(id, pass);
    if (portal == null) return null;
    return ResetEmployeePassword(pass, portal);
  }

  static Future<String?> resetPassword(String id) async {
    final result = await resetPasswordDetailed(id);
    return result?.password;
  }

  /// Kept for source compatibility with old reports/tests. No random numbers
  /// are produced anymore and new profiles always start from real empty data.
  @Deprecated('Demo business statistics were removed')
  static Map<String, double> generateDemoStats({Random? random}) => const {};

  static Future<void> reconcileLogins() =>
      LoginPoolService.reconcile(all.map((e) => e.login));
}
