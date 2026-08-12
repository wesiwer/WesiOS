import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/tasks/services/task_cash_impact.dart';
import 'package:wesios/features/treasury/services/horizon_scenarios.dart';

void main() {
  group('Wesi Horizon product integration', () {
    test('Task cash tag round-trips committed expense', () {
      const value = TaskCashImpact(
        direction: TaskCashDirection.expense,
        amount: 12500,
      );
      final parsed = TaskCashImpact.fromTags([value.tag]);

      expect(parsed, isNotNull);
      expect(parsed!.direction, TaskCashDirection.expense);
      expect(parsed.amount, 12500);
      expect(parsed.committed, isTrue);
      expect(parsed.probability, 1);
      expect(parsed.signedAmount, -12500);
    });

    test('Task cash tag round-trips uncertain income and preserves human tags', () {
      const value = TaskCashImpact(
        direction: TaskCashDirection.income,
        amount: 42000,
        committed: false,
        probability: .35,
      );
      final next = value.applyTo([
        'client:alpha',
        'urgent',
        'cash:-999.00',
      ]);
      final parsed = TaskCashImpact.fromTags(next);

      expect(next, containsAll(<String>['client:alpha', 'urgent']));
      expect(next.where(TaskCashImpact.isCashTag), hasLength(1));
      expect(parsed, isNotNull);
      expect(parsed!.direction, TaskCashDirection.income);
      expect(parsed.amount, 42000);
      expect(parsed.committed, isFalse);
      expect(parsed.probability, closeTo(.35, .001));
    });

    test('stress library has finite income shock and isolated main-source loss', () {
      final stresses = HorizonScenarioService.stressLibrary(
        currentBalance: 100000,
        dailyVolatility: 2500,
      );
      final incomeDown =
          stresses.singleWhere((value) => value.key == 'income-down-30');
      final mainLoss =
          stresses.singleWhere((value) => value.key == 'main-source-loss');
      final delay =
          stresses.singleWhere((value) => value.key == 'incoming-delay-30');

      expect(incomeDown.scenario.incomeMultiplier, .70);
      expect(incomeDown.scenario.incomeMultiplierDays, 60);
      expect(mainLoss.scenario.mainIncomeLossDays, 60);
      expect(mainLoss.scenario.incomeMultiplier, 1,
          reason: 'main-source loss must not globally erase all income');
      expect(delay.scenario.incomeDelayDays, 30);
    });

    test('Forecast exposes decision layer and backtest-selected Combined', () {
      final source = File('lib/features/treasury/forecast_chart_screen.dart')
          .readAsStringSync();
      expect(source, contains('HorizonDecisionPanel(forecast: _forecast)'));
      expect(source,
          contains('HorizonEngineCompetitionService.smartCombined'));
      expect(source, contains('_combinedWasRejected'));
      expect(source, contains('усреднение отклонено backtest'));
    });

    test('company cash sources are wired without schema migrations', () {
      final taskEditor = File(
              'lib/features/tasks/widgets/task_editor_dialog.dart')
          .readAsStringSync();
      final business = File(
              'lib/features/treasury/services/horizon_business_context.dart')
          .readAsStringSync();
      final vault = File('lib/features/audio/audio_vault_v2_screen.dart')
          .readAsStringSync();
      final accounts = File('lib/features/treasury/widgets/accounts_bar.dart')
          .readAsStringSync();
      final sandbox = File(
              'lib/features/treasury/sandbox_forecast_screen.dart')
          .readAsStringSync();

      expect(taskEditor, contains('TaskCashImpactField'));
      expect(business, contains('TaskCashImpact.fromTags'));
      expect(vault, contains('HorizonContractDialog.show'));
      expect(accounts, contains('AccountLiquidityDialog.show'));
      expect(sandbox, contains('HorizonDecisionPanel(forecast: _baseline)'));
    });
  });
}
