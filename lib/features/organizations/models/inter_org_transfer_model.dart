import 'package:hive/hive.dart';

part 'inter_org_transfer_model.g.dart';

@HiveType(typeId: 83)
enum InterOrgTransferType {
  @HiveField(0)
  investment,
  @HiveField(1)
  profitShare,
  @HiveField(2)
  funding,
  @HiveField(3)
  internalTransfer,
  @HiveField(4)
  other,
}

/// Write-ahead journal record for one transfer between two organizations.
/// It is persisted before either ledger leg so recovery can deterministically
/// reconstruct a complete transfer after any interrupted write.
@HiveType(typeId: 84)
class InterOrgTransferModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String fromOrganizationId;
  @HiveField(2)
  final String toOrganizationId;
  @HiveField(3)
  final String fromAccountId;
  @HiveField(4)
  final String toAccountId;
  @HiveField(5)
  final double amount;
  @HiveField(6)
  final String currency;
  @HiveField(7)
  final double amountInFromOrgBase;
  @HiveField(8)
  final double amountInToOrgBase;
  @HiveField(9)
  final InterOrgTransferType type;
  @HiveField(10)
  final String? note;
  @HiveField(11)
  final DateTime date;
  @HiveField(12)
  final String createdBy;
  @HiveField(13)
  final DateTime createdAt;
  @HiveField(14)
  final String linkedDebitTransactionId;
  @HiveField(15)
  final String linkedCreditTransactionId;
  @HiveField(16)
  final bool cancelled;
  @HiveField(17)
  final DateTime? cancelledAt;
  @HiveField(18)
  final String? cancelledBy;
  @HiveField(19)
  final String? ownerEmployeeId;

  const InterOrgTransferModel({
    required this.id,
    required this.fromOrganizationId,
    required this.toOrganizationId,
    required this.fromAccountId,
    required this.toAccountId,
    required this.amount,
    required this.currency,
    required this.amountInFromOrgBase,
    required this.amountInToOrgBase,
    required this.type,
    this.note,
    required this.date,
    required this.createdBy,
    required this.createdAt,
    required this.linkedDebitTransactionId,
    required this.linkedCreditTransactionId,
    this.cancelled = false,
    this.cancelledAt,
    this.cancelledBy,
    this.ownerEmployeeId,
  });

  InterOrgTransferModel cancel({required String by, DateTime? at}) =>
      InterOrgTransferModel(
        id: id,
        fromOrganizationId: fromOrganizationId,
        toOrganizationId: toOrganizationId,
        fromAccountId: fromAccountId,
        toAccountId: toAccountId,
        amount: amount,
        currency: currency,
        amountInFromOrgBase: amountInFromOrgBase,
        amountInToOrgBase: amountInToOrgBase,
        type: type,
        note: note,
        date: date,
        createdBy: createdBy,
        createdAt: createdAt,
        linkedDebitTransactionId: linkedDebitTransactionId,
        linkedCreditTransactionId: linkedCreditTransactionId,
        cancelled: true,
        cancelledAt: at ?? DateTime.now(),
        cancelledBy: by,
        ownerEmployeeId: ownerEmployeeId,
      );
}
