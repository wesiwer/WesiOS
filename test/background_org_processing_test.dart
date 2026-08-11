import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/features/organizations/models/organization_model.dart';
import 'package:wesios/features/organizations/models/transaction_audit_model.dart';
import 'package:wesios/features/organizations/services/organization_context.dart';
import 'package:wesios/features/organizations/services/organization_service.dart';
import 'package:wesios/features/treasury/models/account_model.dart';
import 'package:wesios/features/treasury/models/transaction_model.dart';
import 'package:wesios/features/treasury/services/account_service.dart';
import 'package:wesios/features/treasury/services/forecast_engine.dart';
import 'package:wesios/features/treasury/services/horizon_calibration.dart';
import 'package:wesios/features/treasury/services/horizon_engine_competition.dart';
import 'package:wesios/features/treasury/services/horizon_prediction_registry.dart';
import 'package:wesios/features/treasury/services/treasury_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUpAll(() async {
    temp = await Directory.systemTemp.createTemp('wesios-background-org-');
    Hive.init(temp.path);
    if (!Hive.isAdapterRegistered(1)) Hive.registerAdapter(TransactionModelAdapter());
    if (!Hive.isAdapterRegistered(2)) Hive.registerAdapter(TransactionTypeAdapter());
    if (!Hive.isAdapterRegistered(3)) Hive.registerAdapter(RecurringPeriodAdapter());
    if (!Hive.isAdapterRegistered(14)) Hive.registerAdapter(AccountKindAdapter());
    if (!Hive.isAdapterRegistered(15)) Hive.registerAdapter(AccountModelAdapter());
    if (!Hive.isAdapterRegistered(80)) Hive.registerAdapter(OrganizationStatusAdapter());
    if (!Hive.isAdapterRegistered(81)) Hive.registerAdapter(OrganizationModelAdapter());
    if (!Hive.isAdapterRegistered(85)) Hive.registerAdapter(TransactionAuditModelAdapter());
    if (!Hive.isAdapterRegistered(86)) Hive.registerAdapter(TransactionSourceAdapter());

    await Hive.openBox('wesios_settings');
    await Hive.openBox<OrganizationModel>(OrganizationService.boxName);
    await Hive.openBox<AccountModel>('wesios_accounts');
    await Hive.openBox<TransactionModel>('wesios_treasury');
    await Hive.openBox<TransactionAuditModel>('wesios_transaction_audit');
    await Hive.openBox<dynamic>(HorizonPredictionRegistry.boxName);
    await Hive.openBox<dynamic>(HorizonEngineCompetitionService.boxName);
  });

  setUp(() async {
    await Hive.box('wesios_settings').clear();
    await Hive.box<OrganizationModel>(OrganizationService.boxName).clear();
    await Hive.box<AccountModel>('wesios_accounts').clear();
    await Hive.box<TransactionModel>('wesios_treasury').clear();
    await Hive.box<TransactionAuditModel>('wesios_transaction_audit').clear();
    await Hive.box<dynamic>(HorizonPredictionRegistry.boxName).clear();
    await Hive.box<dynamic>(HorizonEngineCompetitionService.boxName).clear();
    await OrganizationService.ensureBaseline();
  });

  tearDownAll(() async {
    await Hive.close();
    if (await temp.exists()) await temp.delete(recursive: true);
  });

  test('due recurring in child org materializes while UI context is root only', () async {
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final account = await AccountService.ensureMain(organizationId: child.id);
    final anchorDate = DateTime.now().subtract(const Duration(days: 70));
    await Hive.box<TransactionModel>('wesios_treasury').put(
      'child-recurring',
      TransactionModel(
        id: 'child-recurring',
        title: 'Child subscription',
        amount: 500,
        type: TransactionType.expense,
        date: anchorDate,
        isRecurring: true,
        recurringPeriod: RecurringPeriod.monthly,
        accountId: account.id,
        organizationId: child.id,
      ),
    );

    await OrganizationContext.initialize();
    await OrganizationContext.selectOrganization(OrganizationModel.rootId);
    await OrganizationContext.setScope(OrganizationScope.only);
    await TreasuryService().processRecurringPayments();

    final raw = await TreasuryService().getAllTransactionsRaw();
    final generated = raw.where((t) =>
        t.source == TransactionSource.recurring &&
        t.effectiveOrganizationId == child.id);
    expect(generated, isNotEmpty);
    expect(generated.every((t) => t.organizationId == child.id), isTrue);
    expect(generated.every((t) => t.accountId == account.id), isTrue);
  });

  test('issued Horizon prediction keeps explicit child organization and scope', () async {
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final points = List<double>.generate(180, (i) => 1000 + i.toDouble());
    final forecast = ForecastResult(
      p10: points.map((v) => v - 100).toList(),
      p50: points,
      p90: points.map((v) => v + 100).toList(),
      trendPerDay: 1,
      dailyVolatility: 10,
      historyDaysSpan: 90,
      simulatedPaths: 100,
      insufficientData: false,
      seasonalityApplied: false,
      belowZeroProbability: List<double>.filled(180, 0),
    );

    await HorizonPredictionRegistry.recordBaseForecast(
      forecast: forecast,
      currentBalance: 1000,
      calibration: HorizonCalibrationProfile.identity,
      now: DateTime(2026, 8, 10),
      organizationId: child.id,
      organizationScope: 'only',
    );

    final records = await HorizonPredictionRegistry.records();
    expect(records, hasLength(1));
    expect(records.single.organizationId, child.id);
    expect(records.single.organizationScope, 'only');
    expect(records.single.id, startsWith('${child.id}:only:'));
  });

  test('engine championship storage is isolated per organization and scope', () async {
    final child = await OrganizationService.create(
      name: 'Studio A',
      parentId: OrganizationModel.rootId,
      createdBy: 'test',
    );
    final box = Hive.box<dynamic>(HorizonEngineCompetitionService.boxName);
    await box.put(
      'championship_v2',
      jsonEncode({
        'evaluatedAt': DateTime(2026, 8, 1).toIso8601String(),
        'metrics': const [],
      }),
    );
    await box.put(
      'championship_v2.${child.id}.only',
      jsonEncode({
        'evaluatedAt': DateTime(2026, 8, 2).toIso8601String(),
        'metrics': const [],
      }),
    );

    final root = await HorizonEngineCompetitionService.load(
      organizationId: OrganizationModel.rootId,
      organizationScope: 'only',
    );
    final studio = await HorizonEngineCompetitionService.load(
      organizationId: child.id,
      organizationScope: 'only',
    );
    expect(root, isNotNull);
    expect(studio, isNotNull);
    expect(root!.evaluatedAt, DateTime(2026, 8, 1));
    expect(studio!.evaluatedAt, DateTime(2026, 8, 2));
  });
}
