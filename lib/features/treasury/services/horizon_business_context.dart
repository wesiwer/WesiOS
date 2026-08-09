import 'dart:math';

import '../../../core/services/currency_service.dart';
import '../../audio/services/audio_vault_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/crm_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_cash_impact.dart';
import '../../tasks/services/task_service.dart';
import '../models/transaction_model.dart';
import 'account_liquidity_service.dart';
import 'forecast_engine.dart';
import 'horizon_contract_memory.dart';

class HorizonBusinessContext {
  final List<HorizonCashEvent> events;
  final List<AccountLiquiditySnapshot> accounts;
  final List<ForecastActionPrompt> warnings;
  final Map<String, double> sourceExposure;

  const HorizonBusinessContext({
    this.events = const [],
    this.accounts = const [],
    this.warnings = const [],
    this.sourceExposure = const {},
  });
}

/// Company-level context for Horizon. The forecast core stays a deterministic
/// math engine; this layer translates real WesiOS modules into known/uncertain
/// cash events and liquidity locations.
class HorizonBusinessContextService {
  HorizonBusinessContextService._();

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static ForecastActionPrompt _sourceWarning({
    required String code,
    required String ru,
    required String en,
  }) =>
      ForecastActionPrompt(
        code: code,
        severity: ForecastPromptSeverity.warning,
        textRu: ru,
        textEn: en,
      );

  static Future<HorizonBusinessContext> load({
    required List<TransactionModel> transactions,
    required int days,
    DateTime? now,
  }) async {
    final today = _day(now ?? DateTime.now());
    final end = today.add(Duration(days: days));
    final events = <HorizonCashEvent>[];
    final warnings = <ForecastActionPrompt>[];
    final exposure = <String, double>{};

    await _addCrm(events, exposure, warnings, today, end);
    await _addContracts(events, exposure, warnings, today, end);
    await _addTaskObligations(events, warnings, today, end);

    List<AccountLiquiditySnapshot> accounts = const [];
    try {
      accounts = await AccountLiquidityService.snapshots(transactions);
    } catch (_) {
      warnings.add(_sourceWarning(
        code: 'context-accounts-unavailable',
        ru: 'Не удалось прочитать риск-профили счетов. Общий прогноз построен, но локальный риск ликвидности по счетам сейчас неизвестен.',
        en: 'Account risk profiles could not be read. The total forecast is available, but local account liquidity risk is currently unknown.',
      ));
    }
    _addConcentrationWarnings(exposure, warnings);

    return HorizonBusinessContext(
      events: events,
      accounts: accounts,
      warnings: warnings,
      sourceExposure: exposure,
    );
  }

  static Future<void> _addCrm(
    List<HorizonCashEvent> events,
    Map<String, double> exposure,
    List<ForecastActionPrompt> warnings,
    DateTime today,
    DateTime end,
  ) async {
    try {
      final deals = await CrmService.deals();
      for (final deal in deals) {
        if (!deal.isOpen || deal.expectedCloseAt == null || deal.amount <= 0) {
          continue;
        }
        final due = _day(deal.expectedCloseAt!);
        if (!due.isAfter(today) || due.isAfter(end)) continue;
        final probability =
            (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        final rub = deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase());
        events.add(HorizonCashEvent(
          title: 'CRM: ${deal.title}',
          amount: rub,
          date: due,
          probability: probability,
          committed: probability >= 0.9 && deal.stage == DealStage.negotiation,
          source: 'crm',
        ));
        exposure['crm:${deal.clientId}'] =
            (exposure['crm:${deal.clientId}'] ?? 0) + rub * probability;
      }
    } catch (_) {
      warnings.add(_sourceWarning(
        code: 'context-crm-unavailable',
        ru: 'CRM сейчас недоступна для Horizon. Прогноз не включает ожидаемые сделки; не считай отсутствие этих входящих доказательством, что их не будет.',
        en: 'CRM is currently unavailable to Horizon. Expected deals are excluded; their absence from the forecast is not evidence that they will not occur.',
      ));
    }
  }

  static Future<void> _addContracts(
    List<HorizonCashEvent> events,
    Map<String, double> exposure,
    List<ForecastActionPrompt> warnings,
    DateTime today,
    DateTime end,
  ) async {
    try {
      final beats = await AudioVaultService.all();
      final memory = await HorizonContractMemoryService.all();
      for (final beat in beats) {
        final lease = beat.lease;
        if (lease == null) continue;
        final leaseAmountRub = lease.amount *
            CurrencyService.rateToRub(lease.currency.toLowerCase());
        final renewalDate = _day(lease.endsAt);

        // Natural expiry is a realized contract outcome even when the user
        // never presses “close lease”. recordClosedLease is idempotent by
        // leaseId, so a later explicit close cannot duplicate evidence. If a
        // new matching lease appears within the renewal window,
        // markRenewalIfApplicable upgrades this outcome to renewed=true.
        if (!renewalDate.isAfter(today)) {
          await HorizonContractMemoryService.recordClosedLease(
            beatId: beat.id,
            leaseId: lease.id,
            artistName: lease.artistName,
            closedAt: renewalDate,
            amountRub: leaseAmountRub,
          );
        }

        final stored = memory[lease.id];
        final learnedProbability = stored == null
            ? await HorizonContractMemoryService.learnedRenewalProbability(
                beatId: beat.id,
                artistName: lease.artistName,
              )
            : stored.renewalProbability;
        final contract = stored ??
            HorizonContractMemory(
              beatId: beat.id,
              leaseId: lease.id,
              renewalProbability: learnedProbability,
              renewalAmountRub: leaseAmountRub,
              royaltyProbability: 0.50,
              updatedAt: today,
            );

        final renewalAmount = contract.renewalAmountRub > 0
            ? contract.renewalAmountRub
            : lease.amount *
                CurrencyService.rateToRub(lease.currency.toLowerCase());
        if (renewalAmount > 0 &&
            renewalDate.isAfter(today) &&
            !renewalDate.isAfter(end)) {
          events.add(HorizonCashEvent(
            title: 'Audio Vault: продление «${beat.title}»',
            amount: renewalAmount,
            date: renewalDate,
            probability: contract.renewalProbability,
            committed: false,
            source: 'audio-renewal',
          ));
          exposure['audio:${beat.id}'] = (exposure['audio:${beat.id}'] ?? 0) +
              renewalAmount * contract.renewalProbability;
        }

        final royaltyDate =
            contract.royaltyDueAt == null ? null : _day(contract.royaltyDueAt!);
        if (contract.expectedRoyaltyRub > 0 &&
            royaltyDate != null &&
            royaltyDate.isAfter(today) &&
            !royaltyDate.isAfter(end)) {
          events.add(HorizonCashEvent(
            title: 'Audio Vault: ожидаемые роялти «${beat.title}»',
            amount: contract.expectedRoyaltyRub,
            date: royaltyDate,
            probability: contract.royaltyProbability,
            committed: contract.royaltyProbability >= 0.95,
            source: 'audio-royalty',
          ));
          exposure['audio:${beat.id}'] = (exposure['audio:${beat.id}'] ?? 0) +
              contract.expectedRoyaltyRub * contract.royaltyProbability;
        }
      }
    } catch (_) {
      warnings.add(_sourceWarning(
        code: 'context-vault-unavailable',
        ru: 'Audio Vault сейчас недоступен для Horizon. Ожидаемые продления и роялти исключены из этого расчёта, поэтому доля неизвестного фактически выше.',
        en: 'Audio Vault is currently unavailable to Horizon. Expected renewals and royalties are excluded, so true unknown cash exposure is higher.',
      ));
    }
  }

  /// Cash-tag convention on Tasks keeps the task model backward-compatible:
  /// `cash:-50000` -> committed expense at dueDate
  /// `cash:+15000@0.6` -> uncertain incoming with 60% probability
  /// `cash:uncertain:-10000@0.4` is also accepted.
  static Future<void> _addTaskObligations(
    List<HorizonCashEvent> events,
    List<ForecastActionPrompt> warnings,
    DateTime today,
    DateTime end,
  ) async {
    try {
      final tasks = await TaskService().getAll();
      for (final task in tasks) {
        if (task.status == TaskStatus.done || task.dueDate == null) continue;
        final parsed = TaskCashImpact.fromTags(task.tags);
        if (parsed == null) continue;
        final due = _day(task.dueDate!);

        if (!due.isAfter(today)) {
          final overdue = due.isBefore(today);
          warnings.add(ForecastActionPrompt(
            code: overdue
                ? 'overdue-cash-task-${task.id}'
                : 'due-today-cash-task-${task.id}',
            severity: parsed.signedAmount < 0
                ? ForecastPromptSeverity.critical
                : ForecastPromptSeverity.warning,
            textRu: overdue
                ? 'Просрочено денежное обязательство «${task.title}» (${parsed.signedAmount.abs().toStringAsFixed(0)} ₽). Horizon считает его немедленным движением денег.'
                : 'Сегодня наступает денежное обязательство «${task.title}» (${parsed.signedAmount.abs().toStringAsFixed(0)} ₽). Horizon считает его немедленным движением денег.',
            textEn: overdue
                ? 'Overdue cash obligation “${task.title}” (${parsed.signedAmount.abs().toStringAsFixed(0)} RUB). Horizon treats it as immediate cash movement.'
                : 'Cash obligation “${task.title}” is due today (${parsed.signedAmount.abs().toStringAsFixed(0)} RUB). Horizon treats it as immediate cash movement.',
            amount: parsed.signedAmount.abs(),
            day: 1,
          ));

          // Forecast offsets begin at day 1. An unpaid due/overdue cash task
          // must not vanish merely because its calendar date is no longer in
          // the future; move the unresolved obligation to the next forecast
          // step while preserving its committed/probabilistic semantics.
          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: parsed.probability,
            committed: parsed.committed,
            source: 'task-obligation-overdue',
          ));
          continue;
        }

        if (due.isAfter(end)) continue;
        events.add(HorizonCashEvent(
          title: 'Task: ${task.title}',
          amount: parsed.signedAmount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
          source: 'task-obligation',
        ));
      }
    } catch (_) {
      warnings.add(_sourceWarning(
        code: 'context-tasks-unavailable',
        ru: 'Tasks сейчас недоступны для Horizon. Денежные обязательства из задач не попали в этот расчёт; ближайший cash risk может быть занижен.',
        en: 'Tasks are currently unavailable to Horizon. Cash obligations from tasks are excluded; near-term cash risk may be understated.',
      ));
    }
  }

  static void _addConcentrationWarnings(
    Map<String, double> exposure,
    List<ForecastActionPrompt> warnings,
  ) {
    if (exposure.length < 2) return;
    final positive = exposure.values.where((v) => v > 0).toList();
    if (positive.isEmpty) return;
    final total = positive.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return;
    final largest = positive.reduce(max);
    final share = largest / total;
    if (share >= 0.60) {
      warnings.add(ForecastActionPrompt(
        code: 'income-concentration',
        severity: ForecastPromptSeverity.warning,
        textRu:
            'Более ${(share * 100).round()}% ожидаемых входящих завязано на один источник. Horizon учитывает риск его потери в stress-сценарии.',
        textEn:
            'More than ${(share * 100).round()}% of expected incoming cash depends on one source. Horizon includes source-loss risk in stress.',
      ));
    }
  }
}
