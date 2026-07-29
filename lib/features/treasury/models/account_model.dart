import 'package:hive/hive.dart';

part 'account_model.g.dart';

/// Назначение счёта. Влияет только на иконку и подпись — деньги везде
/// считаются одинаково, а вот «карта» и «наличные» в списке различаются
/// с одного взгляда.
@HiveType(typeId: 14)
enum AccountKind {
  @HiveField(0)
  main,
  @HiveField(1)
  card,
  @HiveField(2)
  cash,
  @HiveField(3)
  savings,
  @HiveField(4)
  project,
}

/// Отдельный счёт внутри Wesi Inc.
///
/// Раньше баланс был один на всё, и разделить направления бизнеса было
/// нечем: деньги проекта, резерв и операционка лежали в одной куче. Теперь
/// операция принадлежит счёту, а общий баланс — это сумма по всем счетам.
@HiveType(typeId: 15)
class AccountModel {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final AccountKind kind;

  /// Стартовая сумма на счёте — то, что уже лежало там до первой операции.
  /// Хранится в рублёвом эквиваленте, как и суммы операций.
  @HiveField(3)
  final double openingBalance;

  /// Цвет карточки — ARGB. Нужен, чтобы счета отличались в списке и на
  /// диаграммах.
  @HiveField(4)
  final int colorValue;

  @HiveField(5)
  final DateTime createdAt;

  /// Архивный счёт не показывается в выборе при добавлении операции, но его
  /// история никуда не девается — удаление счёта с операциями потеряло бы
  /// часть прошлого.
  @HiveField(6)
  final bool archived;

  @HiveField(7)
  final String? note;

  const AccountModel({
    required this.id,
    required this.name,
    this.kind = AccountKind.main,
    this.openingBalance = 0,
    this.colorValue = 0xFFF97316,
    required this.createdAt,
    this.archived = false,
    this.note,
  });

  /// Идентификатор счёта по умолчанию.
  ///
  /// Операции, созданные до появления счетов, не имеют `accountId` — они
  /// считаются принадлежащими основному счёту, иначе после обновления
  /// приложения баланс обнулился бы на глазах у пользователя.
  static const String mainId = 'main';

  AccountModel copyWith({
    String? name,
    AccountKind? kind,
    double? openingBalance,
    int? colorValue,
    bool? archived,
    String? note,
    bool clearNote = false,
  }) =>
      AccountModel(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        openingBalance: openingBalance ?? this.openingBalance,
        colorValue: colorValue ?? this.colorValue,
        createdAt: createdAt,
        archived: archived ?? this.archived,
        note: clearNote ? null : (note ?? this.note),
      );
}
