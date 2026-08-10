import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_access_grant.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/organization_access_service.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/team/models/employee_model.dart';
import 'package:wesios/features/team/models/team_permissions.dart';
import 'package:wesios/features/team/services/team_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-org-domain-perms-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(20)) Hive.registerAdapter(TeamPermissionsAdapter());
    if (!Hive.isAdapterRegistered(21)) Hive.registerAdapter(EmployeeModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(82)) Hive.registerAdapter(OrganizationAccessGrantAdapter());
    if (!Hive.isAdapterRegistered(85)) Hive.registerAdapter(TransactionAuditModelAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<EmployeeModel>(TeamService.boxName);
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<OrganizationAccessGrant>(OrganizationAccessService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<EmployeeModel>(TeamService.boxName).clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<OrganizationAccessGrant>(OrganizationAccessService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  Future<EmployeeModel> addEmployee(String id) async {
    final employee = EmployeeModel(
      id: id,
      login: id,
      fullName: id,
      createdAt: DateTime(2026, 1, 1),
      permissions: const TeamPermissions(),
    );
    await Hive.box<EmployeeModel>(TeamService.boxName).put(id, employee);
    return employee;
  }

  Future<void> signIn(String employeeId) =>
      Hive.box('wesios_settings').put('team_current_employee', employeeId);

  test('OrganizationService rejects direct tree mutation without manage_org_settings', () async {
    final employee = await addEmployee('employee');
    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [OrganizationPermissions.view],
      enforceActor: false,
    );
    await signIn(employee.id);

    await expectLater(
      OrganizationService.create(
        name: 'Forbidden child',
        parentId: OrganizationModel.rootId,
        createdBy: employee.id,
      ),
      throwsStateError,
    );

    expect(
      (await OrganizationService.all()).where((o) => o.name == 'Forbidden child'),
      isEmpty,
    );
  });

  test('transaction cannot be re-owned into an organization actor cannot edit', () async {
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'setup',
    );
    final rootAccount = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );
    final childAccount = await AccountService.ensureMain(organizationId: child.id);
    final original = TransactionModel(
      id: 'tx-root',
      title: 'Root money',
      amount: 1000,
      type: TransactionType.income,
      date: DateTime(2026, 8, 1),
      accountId: rootAccount.id,
      organizationId: OrganizationModel.rootId,
    );
    await Hive.box<TransactionModel>('wesios_treasury').put(original.id, original);

    final employee = await addEmployee('finance-root');
    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
        OrganizationPermissions.editTransactions,
      ],
      enforceActor: false,
    );
    await signIn(employee.id);

    await expectLater(
      TreasuryService().updateTransaction(
        original.copyWith(
          organizationId: child.id,
          accountId: childAccount.id,
        ),
      ),
      throwsStateError,
    );

    final persisted = Hive.box<TransactionModel>('wesios_treasury').get(original.id)!;
    expect(persisted.effectiveOrganizationId, OrganizationModel.rootId);
    expect(persisted.effectiveAccountId, rootAccount.id);
  });

  test('create_transactions alone cannot create recurring schedule', () async {
    final employee = await addEmployee('cashier');
    await OrganizationAccessService.grant(
      employeeId: employee.id,
      organizationId: OrganizationModel.rootId,
      includeSubtree: false,
      permissions: const [
        OrganizationPermissions.view,
        OrganizationPermissions.viewFinance,
        OrganizationPermissions.createTransactions,
      ],
      enforceActor: false,
    );
    await signIn(employee.id);
    final account = await AccountService.ensureMain(
      organizationId: OrganizationModel.rootId,
    );

    await expectLater(
      TreasuryService().addTransaction(
        TransactionModel(
          id: 'recurring-denied',
          title: 'Subscription',
          amount: 100,
          type: TransactionType.expense,
          date: DateTime(2026, 8, 1),
          isRecurring: true,
          recurringPeriod: RecurringPeriod.monthly,
          accountId: account.id,
          organizationId: OrganizationModel.rootId,
        ),
      ),
      throwsStateError,
    );
    expect(Hive.box<TransactionModel>('wesios_treasury').containsKey('recurring-denied'), isFalse);
  });
}
