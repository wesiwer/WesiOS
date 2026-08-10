import 'package:hive/hive.dart';

import '../../organizations/models/organization_model.dart';
import 'account_model.dart';

part 'transaction_model.g.dart';

@HiveType(typeId: 1)
class TransactionModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String title;

  /// Canonical Wesi reporting amount. Org hierarchy v1 keeps RUB as the
  /// reporting currency because all pre-existing WesiOS ledger history was
  /// already stored as RUB-equivalent. Mixed-currency arithmetic therefore
  /// always aggregates this normalized amount, never raw local amounts.
  @HiveField(2)
  final double amount;
  @HiveField(3)
  final TransactionType type;
  @HiveField(4)
  final DateTime date;
  @HiveField(5)
  final String? category;
  @HiveField(6)
  final String? description;
  @HiveField(7)
  final bool isRecurring;
  @HiveField(8)
  final RecurringPeriod? recurringPeriod;
  @HiveField(9)
  final bool isAnomaly;
  @HiveField(10)
  final double? zScore;
  @HiveField(11)
  final String? accountId;

  /// Null only for legacy rows. Migration/service writes physically backfill
  /// Wesi Inc for all new/updated records.
  @HiveField(12)
  final String? organizationId;
  @HiveField(13)
  final String? projectId;
  @HiveField(14)
  final String? counterpartyId;
  @HiveField(15)
  final TransactionSource source;
  @HiveField(16)
  final String? createdBy;
  @HiveField(17)
  final String? updatedBy;
  @HiveField(18)
  final DateTime? updatedAt;
  @HiveField(19)
  final String? ownerEmployeeId;
  @HiveField(20)
  final String? interOrgTransferId;
  @HiveField(21)
  final String? createdByEmployeeId;

  /// Amount as entered/received in [originalCurrency].
  @HiveField(22)
  final double? originalAmount;
  @HiveField(23)
  final String originalCurrency;

  /// Amount normalized into the owning Organization.baseCurrency.
  @HiveField(24)
  final double? organizationBaseAmount;
  @HiveField(25)
  final String organizationBaseCurrency;

  /// RUB per one unit of [originalCurrency] used when [amount] was frozen.
  @HiveField(26)
  final double fxRateToReporting;
  @HiveField(27)
  final DateTime? fxRateAt;
  @HiveField(28)
  final String fxSource;

  const TransactionModel({
    required this.id,
    required this.title,
    required this.amount,
    required this.type,
    required this.date,
    this.category,
    this.description,
    this.isRecurring = false,
    this.recurringPeriod,
    this.isAnomaly = false,
    this.zScore,
    this.accountId,
    this.organizationId,
    this.projectId,
    this.counterpartyId,
    this.source = TransactionSource.manual,
    this.createdBy,
    this.updatedBy,
    this.updatedAt,
    this.ownerEmployeeId,
    this.interOrgTransferId,
    this.createdByEmployeeId,
    this.originalAmount,
    this.originalCurrency = 'RUB',
    this.organizationBaseAmount,
    this.organizationBaseCurrency = 'RUB',
    this.fxRateToReporting = 1.0,
    this.fxRateAt,
    this.fxSource = 'legacy',
  });

  String get effectiveOrganizationId =>
      organizationId ?? OrganizationModel.rootId;

  String get effectiveAccountId =>
      accountId ?? AccountModel.mainIdFor(effectiveOrganizationId);

  double get effectiveOriginalAmount => originalAmount ?? amount;
  double get effectiveOrganizationBaseAmount =>
      organizationBaseAmount ?? amount;

  TransactionModel copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    DateTime? date,
    String? category,
    bool clearCategory = false,
    String? description,
    bool clearDescription = false,
    bool? isRecurring,
    RecurringPeriod? recurringPeriod,
    bool clearRecurringPeriod = false,
    bool? isAnomaly,
    double? zScore,
    bool clearZScore = false,
    String? accountId,
    bool clearAccountId = false,
    String? organizationId,
    String? projectId,
    bool clearProjectId = false,
    String? counterpartyId,
    bool clearCounterpartyId = false,
    TransactionSource? source,
    String? createdBy,
    String? updatedBy,
    DateTime? updatedAt,
    String? ownerEmployeeId,
    bool clearOwnerEmployeeId = false,
    String? interOrgTransferId,
    bool clearInterOrgTransferId = false,
    String? createdByEmployeeId,
    double? originalAmount,
    String? originalCurrency,
    double? organizationBaseAmount,
    String? organizationBaseCurrency,
    double? fxRateToReporting,
    DateTime? fxRateAt,
    String? fxSource,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      date: date ?? this.date,
      category: clearCategory ? null : (category ?? this.category),
      description:
          clearDescription ? null : (description ?? this.description),
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPeriod: clearRecurringPeriod
          ? null
          : (recurringPeriod ?? this.recurringPeriod),
      isAnomaly: isAnomaly ?? this.isAnomaly,
      zScore: clearZScore ? null : (zScore ?? this.zScore),
      accountId: clearAccountId ? null : (accountId ?? this.accountId),
      organizationId: organizationId ?? this.organizationId,
      projectId: clearProjectId ? null : (projectId ?? this.projectId),
      counterpartyId: clearCounterpartyId
          ? null
          : (counterpartyId ?? this.counterpartyId),
      source: source ?? this.source,
      createdBy: createdBy ?? this.createdBy,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerEmployeeId: clearOwnerEmployeeId
          ? null
          : (ownerEmployeeId ?? this.ownerEmployeeId),
      interOrgTransferId: clearInterOrgTransferId
          ? null
          : (interOrgTransferId ?? this.interOrgTransferId),
      createdByEmployeeId:
          createdByEmployeeId ?? this.createdByEmployeeId,
      originalAmount: originalAmount ?? this.originalAmount,
      originalCurrency:
          (originalCurrency ?? this.originalCurrency).toUpperCase(),
      organizationBaseAmount:
          organizationBaseAmount ?? this.organizationBaseAmount,
      organizationBaseCurrency:
          (organizationBaseCurrency ?? this.organizationBaseCurrency)
              .toUpperCase(),
      fxRateToReporting: fxRateToReporting ?? this.fxRateToReporting,
      fxRateAt: fxRateAt ?? this.fxRateAt,
      fxSource: fxSource ?? this.fxSource,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'amount': amount,
        'type': type.name,
        'date': date.toIso8601String(),
        'category': category,
        'description': description,
        'isRecurring': isRecurring,
        'recurringPeriod': recurringPeriod?.name,
        'isAnomaly': isAnomaly,
        'zScore': zScore,
        'accountId': accountId,
        'organizationId': organizationId,
        'projectId': projectId,
        'counterpartyId': counterpartyId,
        'source': source.name,
        'createdBy': createdBy,
        'updatedBy': updatedBy,
        'updatedAt': updatedAt?.toIso8601String(),
        'ownerEmployeeId': ownerEmployeeId,
        'interOrgTransferId': interOrgTransferId,
        'createdByEmployeeId': createdByEmployeeId,
        'originalAmount': originalAmount,
        'originalCurrency': originalCurrency,
        'organizationBaseAmount': organizationBaseAmount,
        'organizationBaseCurrency': organizationBaseCurrency,
        'fxRateToReporting': fxRateToReporting,
        'fxRateAt': fxRateAt?.toIso8601String(),
        'fxSource': fxSource,
      };
}

@HiveType(typeId: 2)
enum TransactionType {
  @HiveField(0)
  income,
  @HiveField(1)
  expense,
}

@HiveType(typeId: 3)
enum RecurringPeriod {
  @HiveField(0)
  daily,
  @HiveField(1)
  weekly,
  @HiveField(2)
  monthly,
  @HiveField(3)
  yearly,
}

@HiveType(typeId: 86)
enum TransactionSource {
  @HiveField(0)
  manual,
  @HiveField(1)
  import,
  @HiveField(2)
  recurring,
  @HiveField(3)
  crm,
  @HiveField(4)
  task,
  @HiveField(5)
  interorg,
}
