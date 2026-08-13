import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_migration_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/tasks/models/task_model.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-revoke-');
    Hive.init(temp.path);
    Hive.registerAdapter(TransactionModelAdapter());
    Hive.registerAdapter(TransactionTypeAdapter());
    Hive.registerAdapter(RecurringPeriodAdapter());
    Hive.registerAdapter(TransactionSourceAdapter());
    Hive.registerAdapter(TaskStatusAdapter());
    Hive.registerAdapter(TaskPriorityAdapter());
    Hive.registerAdapter(SubTaskAdapter());
    Hive.registerAdapter(TaskModelAdapter());
    Hive.registerAdapter(AccountKindAdapter());
    Hive.registerAdapter(AccountModelAdapter());
    Hive.registerAdapter(TeamPermissionsAdapter());
    Hive.registerAdapter(EmployeeModelAdapter());
    Hive.registerAdapter(OrganizationStatusAdapter());
    Hive.registerAdapter(OrganizationModelAdapter());
    Hive.registerAdapter(OrganizationAccessGrantAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
  });

  setUp(() async {
    for (final name in [
      OrganizationService.boxName,
      OrganizationAccessService.boxName,
      OrganizationMigrationService.logBoxName,
      OrganizationMigrationService.accountBoxName,
      OrganizationMigrationService.treasuryBoxName,
      OrganizationMigrationService.taskBoxName,
      OrganizationMigrationService.crmBoxName,
    ]) {
      if (Hive.isBoxOpen(name)) {
        await Hive.box(name).close();
      }
      await Hive.deleteBoxFromDisk(name);
    }
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('legacy grant is created once and explicit revoke survives relaunch', () async {
    final employee = EmployeeModel(
      id: 'legacy-employee',
      login: 'legacy-employee',
      fullName: 'Legacy employee',
      permissions: const TeamPermissions(
        moduleList: ['treasury'],
      ),
      createdAt: DateTime(2026, 1, 1),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);
    await Hive.box('wesios_settings').put('team_current_employee', employee.id);

    await OrganizationMigrationService.runV1();
    final initial = await OrganizationAccessService.grantsFor(employee.id);
    expect(initial, hasLength(1));
    expect(initial.single.organizationId, OrganizationModel.rootId);

    await OrganizationAccessService.revoke(
      employee.id,
      OrganizationModel.rootId,
      enforceActor: false,
    );
    expect(await OrganizationAccessService.grantsFor(employee.id), isEmpty);

    await OrganizationContext.initialize();
    await OrganizationMigrationService.runV1();

    expect(
      await OrganizationAccessService.grantsFor(employee.id),
      isEmpty,
      reason: 'an explicit revoke must never be recreated as legacy access',
    );
    expect(await OrganizationContext.effectiveOrganizationIds(), isEmpty);
  });
}
