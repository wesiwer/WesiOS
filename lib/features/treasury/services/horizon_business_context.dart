import 'dart:math';

import '../../../core/services/currency_service.dart';
import '../../audio/services/audio_vault_service.dart';
import '../../crm/models/crm_models.dart';
import '../../crm/services/crm_service.dart';
import '../../tasks/models/task_model.dart';
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

    await _addCrm(events, exposure, today, end);
    await _addContracts(events, exposure, today, end);
    await _addTaskObligations(events, warnings, today, end);

    final accounts = await AccountLiquidityService.snapshots(transactions);
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
        final probability = (deal.probability / 100).clamp(0.01, 0.99).toDouble();
        final rub = deal.amount * CurrencyService.rateToRub(deal.currency.toLowerCase());
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
      // CRM must enrich Horizon, never make Treasury unusable.
    }
  }

  static Future<void> _addContracts(
    List<HorizonCashEvent> events,
    Map<String, double> exposure,
    DateTime today,
    DateTime end,
  ) async {
    try {
      final beats = await AudioVaultService.all();
      final memory = await HorizonContractMemoryService.all();
      for (final beat in beats) {
        final lease = beat.lease;
        if (lease == null) continue;
        final contract = memory[lease.id];
        if (contract == null) continue;

        final renewalDate = _day(lease.endsAt);
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
          exposure['audio:${beat.id}'] =
              (exposure['audio:${beat.id}'] ?? 0) +
                  renewalAmount * contract.renewalProbability;
        }

        final royaltyDate = contract.royaltyDueAt == null
            ? null
            : _day(contract.royaltyDueAt!);
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
          exposure['audio:${beat.id}'] =
              (exposure['audio:${beat.id}'] ?? 0) +
                  contract.expectedRoyaltyRub * contract.royaltyProbability;
        }
      }
    } catch (_) {}
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
        final parsed = _cashFromTags(task.tags);
        if (parsed == null) continue;
        final due = _day(task.dueDate!);
        if (due.isBefore(today)) {
          warnings.add(ForecastActionPrompt(
            code: 'overdue-cash-task-${task.id}',
            severity: ForecastPromptSeverity.critical,
            textRu: 'Просрочено денежное обязательство «${task.title}» (${parsed.amount.toStringAsFixed(0)} ₽).',
            textEn: 'Overdue cash obligation “${task.title}” (${parsed.amount.toStringAsFixed(0)} RUB).',
            amount: parsed.amount.abs(),
          ));
        }
        if (!due.isAfter(today) || due.isAfter(end)) continue;
        events.add(HorizonCashEvent(
          title: 'Task: ${task.title}',
          amount: parsed.amount,
          date: due,
          probability: parsed.probability,
          committed: parsed.committed,
          source: 'task-obligation',
        ));
      }
    } catch (_) {}
  }

  static ({double amount, double probability, bool committed})? _cashFromTags(
    List<String> tags,
  ) {
    for (final raw in tags) {
      final tag = raw.trim().toLowerCase().replaceAll(' ', '');
      if (!tag.startsWith('cash:') && !tag.startsWith('money:')) continue;
      var body = tag.substring(tag.indexOf(':') + 1);
      var committed = true;
      if (body.startsWith('uncertain:')) {
        committed = false;
        body = body.substring('uncertain:'.length);
      } else if (body.startsWith('commit:')) {
        body = body.substring('commit:'.length);
      }
      final at = body.lastIndexOf('@');
      var probability = committed ? 1.0 : 0.5;
      if (at > 0) {
        probability = double.tryParse(body.substring(at + 1)) ?? probability;
        if (probability > 1) probability /= 100;
        body = body.substring(0, at);
      }
      final normalized = body.replaceAll(',', '.').replaceAll(RegExp(r'[^0-9+.-]'), '');
      final amount = double.tryParse(normalized);
      if (amount == null || amount == 0) continue;
      return (
        amount: amount,
        probability: probability.clamp(0.01, 1.0).toDouble(),
        committed: committed && probability >= 0.9,
      );
    }
    return null;
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
        textRu: 'Более ${(share * 100).round()}% ожидаемых входящих завязано на один источник. Horizon учитывает риск его потери в stress-сценарии.',
        textEn: 'More than ${(share * 100).round()}% of expected incoming cash depends on one source. Horizon includes source-loss risk in stress.',
      ));
    }
  }
}
