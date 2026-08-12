import 'package:hive/hive.dart';

import 'account_model.dart';

part 'transaction_model.g.dart';

@HiveType(typeId: 1)
class TransactionModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String title;

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

  /// К какому счёту относится операция.
  ///
  /// null у всех записей, созданных до появления счетов — они трактуются как
  /// операции основного счёта (`AccountModel.mainId`). Если бы старые записи
  /// просто выпали из выборки, баланс обнулился бы сразу после обновления.
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
  @HiveField(12)
  final DateTime? recurringAnchor;

  /// Якорь регулярного платежа: явный, если он есть, иначе дата записи.
  DateTime get recurringAnchorDate => recurringAnchor ?? date;

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
  });

  /// Счёт операции с учётом старых записей без явного счёта.
  String get effectiveAccountId => accountId ?? AccountModel.mainId;

  TransactionModel copyWith({
    String? id,
    String? title,
    double? amount,
    TransactionType? type,
    DateTime? date,
    String? category,
    String? description,
    bool? isRecurring,
    RecurringPeriod? recurringPeriod,
    bool? isAnomaly,
    double? zScore,
    String? accountId,
    DateTime? recurringAnchor,
  }) {
    return TransactionModel(
      id: id ?? this.id,
      title: title ?? this.title,
      amount: amount ?? this.amount,
      type: type ?? this.type,
      date: date ?? this.date,
      category: category ?? this.category,
      description: description ?? this.description,
      isRecurring: isRecurring ?? this.isRecurring,
      recurringPeriod: recurringPeriod ?? this.recurringPeriod,
      isAnomaly: isAnomaly ?? this.isAnomaly,
      zScore: zScore ?? this.zScore,
      accountId: accountId ?? this.accountId,
      recurringAnchor: recurringAnchor ?? this.recurringAnchor,
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
  };
}

/// Аннотации обязательны, хотя адаптеры для этих enum уже лежали в
/// `transaction_model.g.dart`: без них build_runner при следующей генерации
/// просто выкидывает `TransactionTypeAdapter` и `RecurringPeriodAdapter` из
/// файла, и приложение перестаёт собираться. typeId 2 и 3 и порядок значений
/// менять нельзя — по ним читаются уже записанные на диск транзакции.
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
