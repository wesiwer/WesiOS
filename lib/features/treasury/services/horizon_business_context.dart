import 'calendar_days.dart';
import 'dart:math';

import '../../../core/services/currency_service.dart';
import '../../audio/services/audio_vault_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/crm_service.dart';
import '../../organizations/models/organization_model.dart';
import '../../organizations/services/organization_context.dart';
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
    Set<String>? organizationIds,
  }) async {
    final today = _day(now ?? DateTime.now());
    final end = addDays(today, days);
    final events = <HorizonCashEvent>[];
    final warnings = <ForecastActionPrompt>[];
    final exposure = <String, double>{};
    final ids = organizationIds ??
        await OrganizationContext.effectiveOrganizationIds();

    await _addCrm(events, exposure, warnings, today, end, ids);
    if (ids.contains(OrganizationModel.rootId)) {
      await _addContracts(events, exposure, warnings, today, end);
    }
    await _addTaskObligations(events, warnings, today, end, ids);

    List<AccountLiquiditySnapshot> accounts = const [];
    try {
      accounts = await AccountLiquidityService.snapshots(
        transactions,
        organizationIds: ids,
      );
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
    Set<String> organizationIds,
  ) async {
    try {
      final deals = await CrmService.dealsForOrganizations(organizationIds);
      for (final deal in deals) {
        if (!deal.isOpen || deal.expectedCloseAt == null || deal.amount <= 0) {
          continue;
        }
        final due = _day(deal.expectedCloseAt!);
        var eventDate = due;
        var probability =
            (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        var committed =
            probability >= 0.9 && deal.stage == DealStage.negotiation;
        if (!due.isAfter(today)) {
          final overdueDays = max(0, dayDiff(due, today));
          final decay = exp(-overdueDays / 45.0).clamp(0.25, 0.80);
          probability = (probability * decay).clamp(0.01, 0.75).toDouble();
          committed = false;
          eventDate = today.add(const Duration(days: 1));
          warnings.add(ForecastActionPrompt(
            code: 'crm-overdue-${deal.id}',
            severity: ForecastPromptSeverity.warning,
            textRu:
                'Срок ожидаемой сделки «${deal.title}» уже прошёл. Horizon не удаляет входящий поток, но снизил его вероятность до ${(probability * 100).round()}%.',
            textEn:
                'The expected close date for “${deal.title}” has passed. Horizon keeps the incoming cash visible but reduced its probability to ${(probability * 100).round()}%.',
            day: 1,
          ));
        }
        if (eventDate.isAfter(end)) continue;
        final rub = deal.amount *
            CurrencyService.rateToRub(deal.currency.toLowerCase());
        events.add(HorizonCashEvent(
          title: 'CRM: ${deal.title}',
          amount: rub,
          date: eventDate,
          probability: probability,
          committed: committed,
          source: 'crm',
          riskSource: 'crm:${deal.clientId}',
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
            riskSource: 'audio:${beat.id}',
          ));
          exposure['audio:${beat.id}'] =
              (exposure['audio:${beat.id}'] ?? 0) +
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
            riskSource: 'audio:${beat.id}',
          ));
          exposure['audio:${beat.id}'] =
              (exposure['audio:${beat.id}'] ?? 0) +
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

  static Future<void> _addTaskObligations(
    List<HorizonCashEvent> events,
    List<ForecastActionPrompt> warnings,
    DateTime today,
    DateTime end,
    Set<String> organizationIds,
  ) async {
    try {
      final tasks = await TaskService().getForOrganizations(organizationIds);
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

          final missedIncoming = overdue && parsed.signedAmount > 0;
          final overdueProbability = missedIncoming
              ? min(parsed.probability, 0.65).toDouble()
              : parsed.probability;
          events.add(HorizonCashEvent(
            title: 'Task: ${task.title}',
            amount: parsed.signedAmount,
            date: today.add(const Duration(days: 1)),
            probability: overdueProbability,
            committed: missedIncoming ? false : parsed.committed,
            source: 'task-obligation-overdue',
            riskSource: 'task:${task.id}',
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
          riskSource: 'task:${task.id}',
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
