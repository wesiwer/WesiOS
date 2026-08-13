import 'package:hive/hive.dart';

import '../../organizations/models/organization_model.dart';
import 'account_model.dart';

part 'transaction_model.g.dart';

/// Адаптер для этой модели написан руками — см. [TransactionModelAdapter]
/// в конце файла. Генератор для неё намеренно отключён (нет `@HiveType`),
/// и вот почему.
///
/// Сгенерированный адаптер читает поле как `fields[16] as TransactionSource`.
/// У записи, созданной прошлой версией приложения, поля 16 просто нет —
/// `fields[16]` возвращает null, и приведение падает. То есть каждая уже
/// существующая на устройстве операция становится нечитаемой, а поскольку
/// журнал операций читается при запуске, приложение открывается чёрным
/// экраном ещё до первого кадра.
///
/// Заметить это тестами было нельзя: тесты всегда начинают с пустых коробок,
/// где старых записей не бывает. Ловится только чтением того, что записала
/// предыдущая версия, — ровно это и проверяет `hive_legacy_records_test`.
///
/// Номера полей физически лежат на устройствах людей: их нельзя ни менять
/// местами, ни переиспользовать. Аннотации `@HiveField` оставлены как раз
/// затем, чтобы занятые номера были видны прямо рядом с полями.
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

  /// Исходная дата регулярного платежа — та, которую человек назначил.
  ///
  /// [date] у регулярной записи двигается вперёд каждый раз, когда платёж
  /// проводится. Если считать следующий раз от неё, месячная дата съезжает
  /// и больше не возвращается: аренда 31 января становится 28 февраля,
  /// оттуда 28 марта — и остаётся 28-м числом навсегда.
  ///
  /// Здесь хранится якорь, от которого каждое наступление считается заново.
  /// Поле nullable намеренно: у записей, созданных до его появления, в базе
  /// его нет, и не-nullable тип уронил бы их чтение. Для них якорем служит
  /// сама [date] — см. [recurringAnchorDate].
  ///
  /// Номер поля занят раньше остальных и менять его нельзя: под ним уже
  /// лежат данные на устройствах. Поля организации сдвинуты на одно именно
  /// поэтому — прочитать дату как строку значило бы потерять запись.
  @HiveField(12)
  final DateTime? recurringAnchor;

  /// Якорь регулярного платежа: явный, если он есть, иначе дата записи.
  DateTime get recurringAnchorDate => recurringAnchor ?? date;

  /// Null only for legacy rows. Migration/service writes physically backfill
  /// Wesi Inc for all new/updated records.
  @HiveField(13)
  final String? organizationId;
  @HiveField(14)
  final String? projectId;
  @HiveField(15)
  final String? counterpartyId;
  @HiveField(16)
  final TransactionSource source;
  @HiveField(17)
  final String? createdBy;
  @HiveField(18)
  final String? updatedBy;
  @HiveField(19)
  final DateTime? updatedAt;
  @HiveField(20)
  final String? ownerEmployeeId;
  @HiveField(21)
  final String? interOrgTransferId;
  @HiveField(22)
  final String? createdByEmployeeId;

  /// Amount as entered/received in [originalCurrency].
  @HiveField(23)
  final double? originalAmount;
  @HiveField(24)
  final String originalCurrency;

  /// Amount normalized into the owning Organization.baseCurrency.
  @HiveField(25)
  final double? organizationBaseAmount;
  @HiveField(26)
  final String organizationBaseCurrency;

  /// RUB per one unit of [originalCurrency] used when [amount] was frozen.
  @HiveField(27)
  final double fxRateToReporting;
  @HiveField(28)
  final DateTime? fxRateAt;
  @HiveField(29)
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
    this.recurringAnchor,
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
    DateTime? recurringAnchor,
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
      recurringAnchor: recurringAnchor ?? this.recurringAnchor,
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

/// Чтение и запись операции в Hive.
///
/// Пишем всегда все поля. Читаем так, чтобы отсутствующее поле означало
/// «эту запись сделала версия, которая про него ещё не знала», а не отказ.
/// Поэтому у всего, что появилось после выхода прошлой версии, есть
/// умолчание — то же самое, что стоит в конструкторе.
///
/// Поля 0–12 существовали всегда и читаются строго: если в записи нет
/// суммы или даты, это не старый формат, а испорченные данные, и молча
/// подставлять им ноль было бы хуже, чем сказать об этом вслух.
class TransactionModelAdapter extends TypeAdapter<TransactionModel> {
  @override
  final int typeId = 1;

  @override
  TransactionModel read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return TransactionModel(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: fields[2] as double,
      type: fields[3] as TransactionType,
      date: fields[4] as DateTime,
      category: fields[5] as String?,
      description: fields[6] as String?,
      isRecurring: fields[7] as bool? ?? false,
      recurringPeriod: fields[8] as RecurringPeriod?,
      isAnomaly: fields[9] as bool? ?? false,
      zScore: fields[10] as double?,
      accountId: fields[11] as String?,
      recurringAnchor: fields[12] as DateTime?,
      organizationId: fields[13] as String?,
      projectId: fields[14] as String?,
      counterpartyId: fields[15] as String?,
      source: fields[16] as TransactionSource? ?? TransactionSource.manual,
      createdBy: fields[17] as String?,
      updatedBy: fields[18] as String?,
      updatedAt: fields[19] as DateTime?,
      ownerEmployeeId: fields[20] as String?,
      interOrgTransferId: fields[21] as String?,
      createdByEmployeeId: fields[22] as String?,
      originalAmount: fields[23] as double?,
      originalCurrency: fields[24] as String? ?? 'RUB',
      organizationBaseAmount: fields[25] as double?,
      organizationBaseCurrency: fields[26] as String? ?? 'RUB',
      fxRateToReporting: fields[27] as double? ?? 1.0,
      fxRateAt: fields[28] as DateTime?,
      fxSource: fields[29] as String? ?? 'legacy',
    );
  }

  @override
  void write(BinaryWriter writer, TransactionModel obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.isRecurring)
      ..writeByte(8)
      ..write(obj.recurringPeriod)
      ..writeByte(9)
      ..write(obj.isAnomaly)
      ..writeByte(10)
      ..write(obj.zScore)
      ..writeByte(11)
      ..write(obj.accountId)
      ..writeByte(12)
      ..write(obj.recurringAnchor)
      ..writeByte(13)
      ..write(obj.organizationId)
      ..writeByte(14)
      ..write(obj.projectId)
      ..writeByte(15)
      ..write(obj.counterpartyId)
      ..writeByte(16)
      ..write(obj.source)
      ..writeByte(17)
      ..write(obj.createdBy)
      ..writeByte(18)
      ..write(obj.updatedBy)
      ..writeByte(19)
      ..write(obj.updatedAt)
      ..writeByte(20)
      ..write(obj.ownerEmployeeId)
      ..writeByte(21)
      ..write(obj.interOrgTransferId)
      ..writeByte(22)
      ..write(obj.createdByEmployeeId)
      ..writeByte(23)
      ..write(obj.originalAmount)
      ..writeByte(24)
      ..write(obj.originalCurrency)
      ..writeByte(25)
      ..write(obj.organizationBaseAmount)
      ..writeByte(26)
      ..write(obj.organizationBaseCurrency)
      ..writeByte(27)
      ..write(obj.fxRateToReporting)
      ..writeByte(28)
      ..write(obj.fxRateAt)
      ..writeByte(29)
      ..write(obj.fxSource);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
