import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/services/account_liquidity_service.dart';
import 'package:wesios/features/treasury/services/account_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-liquidity-migration-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());

    await Hive.openBox<dynamic>('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<dynamic>(AccountLiquidityService.boxName);
  });

  setUp(() async {
    await Hive.box<dynamic>('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await AccountLiquidityService.clearForTest();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('legacy risk fields migrate even when current employee lacks manage_accounts',
      () async {
    final account = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final employee = EmployeeModel(
      id: 'read-only',
      login: 'read-only',
      fullName: 'Read only',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);
    await Hive.box<dynamic>('wesios_settings')
        .put('team_current_employee', employee.id);

    await Hive.box<dynamic>(AccountLiquidityService.boxName).put(
      'meta_v1',
      jsonEncode({
        account.id: {
          'accountId': account.id,
          'currency': 'rub',
          'minimumBalanceRub': 0,
          'allowNetting': true,
          'fxHaircut': 0.12,
          'transferDelayDays': 3,
        },
      }),
    );

    final migrated = await AccountLiquidityService.forAccount(account);
    expect(migrated.fxHaircut, closeTo(0.12, 1e-12));
    expect(migrated.transferDelayDays, 3);

    final persisted = await AccountService.byId(account.id);
    expect(persisted, isNotNull);
    expect(persisted!.fxHaircut, closeTo(0.12, 1e-12));
    expect(persisted.transferDelayDays, 3);
    expect(
      Hive.box<dynamic>(AccountLiquidityService.boxName).containsKey('meta_v1'),
      isFalse,
      reason: 'legacy metadata is removed only after successful migration',
    );
  });
}
