import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/sync/sync_codec.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/employee_admin_service.dart';
import 'package:wesios/features/team/services/team_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-employee-sync-lifecycle-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('employee sync tombstone archives stable identity before active deletion',
      () async {
    final employee = EmployeeModel(
      id: 'employee-history',
      login: 'employee-history',
      fullName: 'Historical Employee',
      position: 'Engineer',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);

    await EmployeesSync().removeById(employee.id);

    expect(Hive.box<EmployeeModel>(TeamService.boxName).get(employee.id), isNull);
    final archived = EmployeeAdminService.deleted
        .singleWhere((row) => row['id'] == employee.id);
    expect(archived['fullName'], employee.fullName);
    expect(archived['position'], employee.position);
    expect(archived['reason'], 'Synced employee removal');
  });

  test('owner sync tombstone is still ignored', () async {
    final owner = EmployeeModel(
      id: 'owner-history',
      login: 'owner-history',
      fullName: 'Owner',
      createdAt: DateTime(2026, 1, 1),
      permissions: TeamPermissions.owner,
      isOwner: true,
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(owner.id, owner);

    await EmployeesSync().removeById(owner.id);

    expect(Hive.box<EmployeeModel>(TeamService.boxName).get(owner.id), isNotNull);
    expect(EmployeeAdminService.deleted.where((row) => row['id'] == owner.id), isEmpty);
  });
}
