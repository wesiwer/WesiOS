import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/services/currency_service.dart';
import '../../team/services/team_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../models/inter_org_transfer_model.dart';
import '../models/organization_access_grant.dart';
import 'critical_audit_service.dart';
import 'organization_access_service.dart';
import 'organization_context.dart';
import 'organization_service.dart';

class InterOrgTransferService {
  InterOrgTransferService._();

  static const String boxName = 'wesios_inter_org_transfers';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<InterOrgTransferModel>? _box;

  /// Fault points: 1=after intent, 2=after debit, 3=after credit,
  /// 4=after cancel intent, 5=after debit removal, 6=after credit removal.
  @visibleForTesting
  static int? debugFailAfterStep;

  static Future<Box<InterOrgTransferModel>> _open() async {
    _box ??= await Hive.openBox<InterOrgTransferModel>(boxName);
    return _box!;
  }

  static void _fail(int step) {
    if (debugFailAfterStep == step) {
      throw StateError('injected inter-org failure after step $step');
    }
  }

  static String _label(InterOrgTransferType type) => switch (type) {
        InterOrgTransferType.investment => 'Investment',
        InterOrgTransferType.profitShare => 'Profit share',
        InterOrgTransferType.funding => 'Funding',
        InterOrgTransferType.internalTransfer => 'Internal transfer',
        InterOrgTransferType.other => 'Inter-org transfer',
      };

  static Map<String, dynamic> _auditJson(InterOrgTransferModel t) => {
        'id': t.id,
        'fromOrganizationId': t.fromOrganizationId,
        'toOrganizationId': t.toOrganizationId,
        'fromAccountId': t.fromAccountId,
        'toAccountId': t.toAccountId,
        'amount': t.amount,
        'currency': t.currency,
        'amountInFromOrgBase': t.amountInFromOrgBase,
        'amountInToOrgBase': t.amountInToOrgBase,
        'type': t.type.name,
        'date': t.date.toIso8601String(),
        'createdBy': t.createdBy,
        'createdAt': t.createdAt.toIso8601String(),
        'debitId': t.linkedDebitTransactionId,
        'creditId': t.linkedCreditTransactionId,
        'cancelled': t.cancelled,
        'cancelledAt': t.cancelledAt?.toIso8601String(),
        'cancelledBy': t.cancelledBy,
        'ownerEmployeeId': t.ownerEmployeeId,
      };

  static Future<void> _validateModel(InterOrgTransferModel transfer) async {
    final fromOrg = await OrganizationService.byId(transfer.fromOrganizationId);
    final toOrg = await OrganizationService.byId(transfer.toOrganizationId);
    if (fromOrg == null || toOrg == null || fromOrg.archived || toOrg.archived) {
      throw StateError('transfer organization unavailable');
    }
    if (transfer.fromOrganizationId == transfer.toOrganizationId) {
      throw StateError('inter-org transfer requires two different organizations');
    }
    final fromAccount = await AccountService.byId(transfer.fromAccountId);
    final toAccount = await AccountService.byId(transfer.toAccountId);
    if (fromAccount == null ||
        toAccount == null ||
        fromAccount.archived ||
        toAccount.archived ||
        fromAccount.effectiveOrganizationId != transfer.fromOrganizationId ||
        toAccount.effectiveOrganizationId != transfer.toOrganizationId) {
      throw StateError('transfer account/organization mismatch');
    }
  }

  static Future<TransactionModel> _debit(InterOrgTransferModel transfer) async {
    final toOrg = await OrganizationService.byId(transfer.toOrganizationId);
    final fromOrg = await OrganizationService.byId(transfer.fromOrganizationId);
    if (toOrg == null || fromOrg == null) {
      throw StateError('transfer organization missing');
    }
    final rate = CurrencyService.rateToRub(transfer.currency.toLowerCase());
    final reporting = transfer.amount * rate;
    return TransactionModel(
      id: transfer.linkedDebitTransactionId,
      title: '${_label(transfer.type)} → ${toOrg.name}',
      amount: reporting,
      type: TransactionType.expense,
      date: transfer.date,
      description: transfer.note,
      accountId: transfer.fromAccountId,
      organizationId: transfer.fromOrganizationId,
      source: TransactionSource.interorg,
      createdBy: transfer.createdBy,
      createdByEmployeeId: transfer.createdBy,
      ownerEmployeeId: transfer.ownerEmployeeId,
      interOrgTransferId: transfer.id,
      originalAmount: transfer.amount,
      originalCurrency: transfer.currency,
      organizationBaseAmount: transfer.amountInFromOrgBase,
      organizationBaseCurrency: fromOrg.baseCurrency,
      fxRateToReporting: rate,
      fxRateAt: transfer.date,
      fxSource: 'CurrencyService',
    );
  }

  static Future<TransactionModel> _credit(InterOrgTransferModel transfer) async {
    final fromOrg = await OrganizationService.byId(transfer.fromOrganizationId);
    final toOrg = await OrganizationService.byId(transfer.toOrganizationId);
    if (fromOrg == null || toOrg == null) {
      throw StateError('transfer organization missing');
    }
    final rate = CurrencyService.rateToRub(transfer.currency.toLowerCase());
    final reporting = transfer.amount * rate;
    return TransactionModel(
      id: transfer.linkedCreditTransactionId,
      title: '${_label(transfer.type)} ← ${fromOrg.name}',
      amount: reporting,
      type: TransactionType.income,
      date: transfer.date,
      description: transfer.note,
      accountId: transfer.toAccountId,
      organizationId: transfer.toOrganizationId,
      source: TransactionSource.interorg,
      createdBy: transfer.createdBy,
      createdByEmployeeId: transfer.createdBy,
      ownerEmployeeId: transfer.ownerEmployeeId,
      interOrgTransferId: transfer.id,
      originalAmount: transfer.amount,
      originalCurrency: transfer.currency,
      organizationBaseAmount: transfer.amountInToOrgBase,
      organizationBaseCurrency: toOrg.baseCurrency,
      fxRateToReporting: rate,
      fxRateAt: transfer.date,
      fxSource: 'CurrencyService',
    );
  }

  static Future<void> _reconcileOne(InterOrgTransferModel transfer) async {
    await _validateModel(transfer);
    final treasury = TreasuryService();
    if (transfer.cancelled) {
      await treasury.deleteInterOrgLegForRecovery(
        transfer.linkedDebitTransactionId,
        transfer.id,
      );
      await treasury.deleteInterOrgLegForRecovery(
        transfer.linkedCreditTransactionId,
        transfer.id,
      );
    } else {
      await treasury.restoreInterOrgLeg(await _debit(transfer));
      await treasury.restoreInterOrgLeg(await _credit(transfer));
    }
  }

  /// Idempotent reconciliation makes the write-ahead journal crash-safe:
  /// every non-cancelled record converges to two legs; every cancelled record
  /// converges to zero legs.
  static Future<void> recoverPending() async {
    final box = await _open();
    for (final transfer in box.values.toList()) {
      try {
        await _reconcileOne(transfer);
      } catch (_) {
        // Keep the journal entry for a later repair instead of deleting evidence.
      }
    }
  }

  static Future<InterOrgTransferModel> execute({
    required String fromOrganizationId,
    required String toOrganizationId,
    required String fromAccountId,
    required String toAccountId,
    required double amount,
    required String currency,
    double? amountInFromOrgBase,
    double? amountInToOrgBase,
    required InterOrgTransferType type,
    String? note,
    DateTime? date,
    String? ownerEmployeeId,
  }) async {
    await recoverPending();
    if (amount <= 0 || !amount.isFinite) {
      throw ArgumentError.value(amount, 'amount', 'must be positive and finite');
    }
    if (fromOrganizationId == toOrganizationId) {
      throw StateError('inter-org transfer requires two different organizations');
    }
    final fromOrg = await OrganizationService.byId(fromOrganizationId);
    final toOrg = await OrganizationService.byId(toOrganizationId);
    if (fromOrg == null || toOrg == null || fromOrg.archived || toOrg.archived) {
      throw StateError('transfer organization unavailable');
    }
    if (TeamService.current != null) {
      if (!await OrganizationAccessService.can(
            fromOrganizationId,
            OrganizationPermissions.createTransactions,
          ) ||
          !await OrganizationAccessService.can(
            toOrganizationId,
            OrganizationPermissions.createTransactions,
          )) {
        throw StateError('create_transactions permission required on both organizations');
      }
    }

    final fromAccount = await AccountService.byId(fromAccountId);
    final toAccount = await AccountService.byId(toAccountId);
    if (fromAccount == null ||
        toAccount == null ||
        fromAccount.archived ||
        toAccount.archived ||
        fromAccount.effectiveOrganizationId != fromOrganizationId ||
        toAccount.effectiveOrganizationId != toOrganizationId) {
      throw StateError('transfer account/organization mismatch');
    }

    final now = DateTime.now();
    final transferDate = date ?? now;
    final actor = TeamService.current?.id ?? 'system';
    final id = 'interorg_${now.microsecondsSinceEpoch}';
    final fromRate = CurrencyService.rateToRub(fromOrg.baseCurrency.toLowerCase());
    final toRate = CurrencyService.rateToRub(toOrg.baseCurrency.toLowerCase());
    final reporting = amount * CurrencyService.rateToRub(currency.toLowerCase());
    final fromAmount = amountInFromOrgBase ??
        (fromRate == 0 ? reporting : reporting / fromRate);
    final toAmount = amountInToOrgBase ??
        (toRate == 0 ? reporting : reporting / toRate);
    final model = InterOrgTransferModel(
      id: id,
      fromOrganizationId: fromOrganizationId,
      toOrganizationId: toOrganizationId,
      fromAccountId: fromAccountId,
      toAccountId: toAccountId,
      amount: amount,
      currency: currency.toUpperCase(),
      amountInFromOrgBase: fromAmount,
      amountInToOrgBase: toAmount,
      type: type,
      note: note,
      date: transferDate,
      createdBy: actor,
      createdAt: now,
      linkedDebitTransactionId: '${id}_debit',
      linkedCreditTransactionId: '${id}_credit',
      ownerEmployeeId: ownerEmployeeId,
    );

    // WRITE-AHEAD: the journal exists before either ledger leg.
    await (await _open()).put(id, model);
    await CriticalAuditService.record(
      event: 'interorg.intent',
      entityType: 'inter_org_transfer',
      entityId: id,
      organizationId: fromOrganizationId,
      after: _auditJson(model),
      actorId: actor,
    );
    revision.value++;
    _fail(1);

    final treasury = TreasuryService();
    await treasury.restoreInterOrgLeg(await _debit(model));
    _fail(2);
    await treasury.restoreInterOrgLeg(await _credit(model));
    _fail(3);

    await CriticalAuditService.record(
      event: 'interorg.committed',
      entityType: 'inter_org_transfer',
      entityId: id,
      organizationId: fromOrganizationId,
      after: _auditJson(model),
      actorId: actor,
    );
    return model;
  }

  static Future<InterOrgTransferModel?> byId(String id) async =>
      (await _open()).get(id);

  static Future<List<InterOrgTransferModel>> allVisible() async {
    await recoverPending();
    var ids = await OrganizationContext.effectiveOrganizationIds();
    if (TeamService.current != null) {
      final financeIds = await OrganizationAccessService.organizationIdsFor(
        OrganizationPermissions.viewFinance,
      );
      ids = ids.intersection(financeIds);
    }
    final list = (await _open())
        .values
        .where((t) =>
            ids.contains(t.fromOrganizationId) ||
            ids.contains(t.toOrganizationId))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  static Future<void> cancel(String id, {String? reason}) async {
    await recoverPending();
    final box = await _open();
    final transfer = box.get(id);
    if (transfer == null || transfer.cancelled) return;
    if (TeamService.current != null &&
        (!await OrganizationAccessService.can(
              transfer.fromOrganizationId,
              OrganizationPermissions.editTransactions,
            ) ||
            !await OrganizationAccessService.can(
              transfer.toOrganizationId,
              OrganizationPermissions.editTransactions,
            ))) {
      throw StateError('edit_transactions permission required on both organizations');
    }

    final actor = TeamService.current?.id ?? 'system';
    final cancelled = transfer.cancel(by: actor);
    // WRITE-AHEAD cancellation marker comes first. Recovery will finish any
    // interrupted leg deletion.
    await box.put(id, cancelled);
    await CriticalAuditService.record(
      event: 'interorg.cancel.intent',
      entityType: 'inter_org_transfer',
      entityId: id,
      organizationId: transfer.fromOrganizationId,
      before: _auditJson(transfer),
      after: _auditJson(cancelled),
      reason: reason,
      actorId: actor,
    );
    revision.value++;
    _fail(4);

    final treasury = TreasuryService();
    await treasury.deleteInterOrgLegForRecovery(
      transfer.linkedDebitTransactionId,
      transfer.id,
    );
    _fail(5);
    await treasury.deleteInterOrgLegForRecovery(
      transfer.linkedCreditTransactionId,
      transfer.id,
    );
    _fail(6);

    await CriticalAuditService.record(
      event: 'interorg.cancelled',
      entityType: 'inter_org_transfer',
      entityId: id,
      organizationId: transfer.fromOrganizationId,
      before: _auditJson(transfer),
      after: _auditJson(cancelled),
      reason: reason,
      actorId: actor,
    );
  }
}
