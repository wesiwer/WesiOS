import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/access_profile.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  late Directory tempDir;
  late Box<dynamic> settings;

  EmployeeModel person({
    required String id,
    required TeamPermissions permissions,
    bool owner = false,
  }) =>
      EmployeeModel(
        id: id,
        login: id,
        fullName: id,
        permissions: permissions,
        createdAt: DateTime.utc(2026, 8, 8),
        isOwner: owner,
      );

  setUpAll(() async {
    tempDir = Directory.systemTemp.createTempSync('wesios_access_test');
    Hive.init(tempDir.path);
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    settings = await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  setUp(() async {
    await settings.clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await AccessProfile.clear();
  });

  test('без входа все модули запрещены', () {
    expect(TeamService.current, isNull);
    expect(AccessProfile.current, AccessProfile.defaults);
    for (final module in AccessProfile.modules) {
      expect(AccessProfile.allows(module), isFalse, reason: module);
    }
  });

  test('права берутся из текущего подтверждённого сотрудника', () async {
    final employee = person(
      id: 'employee',
      permissions: const TeamPermissions(moduleList: ['tasks', 'calendar']),
    );
    await TeamService.save(employee);
    await TeamService.signIn(employee);

    expect(AccessProfile.allows('tasks'), isTrue);
    expect(AccessProfile.allows('calendar'), isTrue);
    expect(AccessProfile.allows('treasury'), isFalse);
    expect(AccessProfile.allows('analytics'), isFalse);
  });

  test('владелец получает полный набор только после входа', () async {
    final owner = person(
      id: 'owner',
      permissions: TeamPermissions.owner,
      owner: true,
    );
    await TeamService.save(owner);

    expect(AccessProfile.allows('treasury'), isFalse,
        reason: 'наличие локальной карточки владельца не является входом');

    await TeamService.signIn(owner);
    for (final module in AccessProfile.modules) {
      expect(AccessProfile.allows(module), isTrue, reason: module);
    }
  });

  test('неизвестный модуль всегда запрещён', () {
    expect(AccessProfile.allows('несуществующий_раздел'), isFalse);
  });

  test('refresh не обращается к Firebase и возвращает текущие права', () async {
    final employee = person(
      id: 'employee',
      permissions: const TeamPermissions(moduleList: ['tasks']),
    );
    await TeamService.save(employee);
    await TeamService.signIn(employee);

    final refreshed = await AccessProfile.refresh();
    expect(refreshed['tasks'], isTrue);
    expect(refreshed['treasury'], isFalse);
  });

  test('clear удаляет legacy cache, но не подменяет текущую роль', () async {
    final employee = person(
      id: 'employee',
      permissions: const TeamPermissions(moduleList: ['tasks']),
    );
    await TeamService.save(employee);
    await TeamService.signIn(employee);
    await settings.put('access_profile', {'treasury': true});
    await settings.put('access_profile_uid', 'old-firebase-user');

    await AccessProfile.clear();

    expect(settings.get('access_profile'), isNull);
    expect(settings.get('access_profile_uid'), isNull);
    expect(AccessProfile.allows('tasks'), isTrue);
    expect(AccessProfile.allows('treasury'), isFalse);
  });
}
