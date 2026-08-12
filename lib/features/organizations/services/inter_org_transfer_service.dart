import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../team/services/team_service.dart';
import '../../treasury/models/transaction_model.dart';
import '../../treasury/services/account_service.dart';
import '../../treasury/services/treasury_service.dart';
import '../models/inter_org_transfer_model.dart';
import '../models/organization_access_grant.dart';
import 'organization_access_service.dart';
import 'organization_context.dart';
import 'organization_service.dart';

class InterOrgTransferService {
  InterOrgTransferService._();

  static const String boxName = 'wesios_inter_org_transfers';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static Box<InterOrgTransferModel>? _box;

  static Future<Box<InterOrgTransferModel>> _open() async {
    _box ??= await Hive.openBox<InterOrgTransferModel>(boxName);
    return _box!;
  }

  static String _label(InterOrgTransferType type) => switch (type) {
        InterOrgTransferType.investment => 'Investment',
        InterOrgTransferType.profitShare => 'Profit share',
        InterOrgTransferType.funding => 'Funding',
        InterOrgTransferType.internalTransfer => 'Internal transfer',
        InterOrgTransferType.other => 'Inter-org transfer',
      };

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
    final debitId = '${id}_debit';
    final creditId = '${id}_credit';
    final fromAmount = amountInFromOrgBase ?? amount;
    final toAmount = amountInToOrgBase ?? amount;
    final treasury = TreasuryService();

    final debit = TransactionModel(
      id: debitId,
      title: '${_label(type)} → ${toOrg.name}',
      amount: fromAmount,
      type: TransactionType.expense,
      date: transferDate,
      description: note,
      accountId: fromAccountId,
      organizationId: fromOrganizationId,
      source: TransactionSource.interorg,
      createdBy: actor,
      createdByEmployeeId: actor,
      ownerEmployeeId: ownerEmployeeId,
      interOrgTransferId: id,
    );
    final credit = TransactionModel(
      id: creditId,
      title: '${_label(type)} ← ${fromOrg.name}',
      amount: toAmount,
      type: TransactionType.income,
      date: transferDate,
      description: note,
      accountId: toAccountId,
      organizationId: toOrganizationId,
      source: TransactionSource.interorg,
      createdBy: actor,
      createdByEmployeeId: actor,
      ownerEmployeeId: ownerEmployeeId,
      interOrgTransferId: id,
    );

    var debitWritten = false;
    var creditWritten = false;
    try {
      await treasury.addTransaction(debit);
      debitWritten = true;
      await treasury.addTransaction(credit);
      creditWritten = true;
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
        linkedDebitTransactionId: debitId,
        linkedCreditTransactionId: creditId,
      );
      await (await _open()).put(id, model);
      revision.value++;
      return model;
    } catch (_) {
      if (creditWritten) {
        await treasury.deleteTransaction(
          creditId,
          reason: 'rollback failed inter-org transfer',
          allowInterOrg: true,
        );
      }
      if (debitWritten) {
        await treasury.deleteTransaction(
          debitId,
          reason: 'rollback failed inter-org transfer',
          allowInterOrg: true,
        );
      }
      rethrow;
    }
  }

  static Future<InterOrgTransferModel?> byId(String id) async =>
      (await _open()).get(id);

  static Future<List<InterOrgTransferModel>> allVisible() async {
    final ids = await OrganizationContext.effectiveOrganizationIds();
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
    final treasury = TreasuryService();
    await treasury.deleteTransaction(
      transfer.linkedDebitTransactionId,
      reason: reason ?? 'inter-org transfer cancelled',
      allowInterOrg: true,
    );
    await treasury.deleteTransaction(
      transfer.linkedCreditTransactionId,
      reason: reason ?? 'inter-org transfer cancelled',
      allowInterOrg: true,
    );
    await box.put(
      id,
      transfer.cancel(by: TeamService.current?.id ?? 'system'),
    );
    revision.value++;
  }
}
