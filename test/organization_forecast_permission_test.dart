import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-forecast-permission-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<TransactionModel>('wesios_treasury');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('view_forecast without view_finance is not an effective permission', () async {
    final employee = EmployeeModel(
      id: 'forecast-only',
      login: 'forecast-only',
      fullName: 'Forecast only',
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(employee.id, employee);
    final now = DateTime.now();
    // Bypass the normal grant API to model corrupt legacy/remote state.
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).put(
      '${employee.id}::${OrganizationModel.rootId}',
      OrganizationAccessGrant(
        id: '${employee.id}::${OrganizationModel.rootId}',
        employeeId: employee.id,
        organizationId: OrganizationModel.rootId,
        permissions: const [
          OrganizationPermissions.view,
          OrganizationPermissions.viewForecast,
        ],
        createdAt: now,
        updatedAt: now,
        createdBy: 'legacy-test',
      ),
    );
    await Hive.box('wesios_settings').put('team_current_employee', employee.id);
    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);

    expect(
      await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewForecast,
      ),
      isEmpty,
    );
    expect(
      await OrganizationAccessService.can(
        OrganizationModel.rootId,
        OrganizationPermissions.viewForecast,
      ),
      isFalse,
    );
    await expectLater(
      TreasuryService().generateForecast(),
      throwsStateError,
    );
  });
}
