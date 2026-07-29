import 'package:hive/hive.dart';

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
  });

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
