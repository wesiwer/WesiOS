import 'package:hive/hive.dart';

import '../../organizations/models/organization_model.dart';

part 'account_model.g.dart';

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
  @HiveField(5)
  reserve,
  @HiveField(6)
  other,
}

/// Адаптер написан руками — см. [AccountModelAdapter] в конце файла.
///
/// Причина та же, что и у операции: поля 9–13 появились позже, а у счетов,
/// заведённых прошлой версией, их в базе нет. Сгенерированный адаптер читал
/// бы их как не-nullable и падал на каждом существующем счёте.
///
/// Аннотации `@HiveField` оставлены, чтобы занятые номера были видны рядом
/// с полями: переиспользовать их нельзя — под ними лежат данные на
/// устройствах людей.
class AccountModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final AccountKind kind;

  /// Canonical reporting-currency (RUB in org-v1) equivalent. Legacy WesiOS
  /// already stored account balances in this unit, so keeping the canonical
  /// ledger unit preserves history while [currency] describes where the
  /// liquidity physically lives.
  @HiveField(3)
  final double openingBalance;
  @HiveField(4)
  final int colorValue;
  @HiveField(5)
  final DateTime createdAt;
  @HiveField(6)
  final bool archived;
  @HiveField(7)
  final String? note;

  /// Null only for records written before organization hierarchy v1.
  /// Legacy records belong to Wesi Inc and are physically backfilled by
  /// migration/service writes.
  @HiveField(8)
  final String? organizationId;

  /// Canonical reporting-currency equivalent, matching [openingBalance].
  @HiveField(9)
  final double minimumBalance;
  @HiveField(10)
  final bool allowNetting;

  /// Physical account currency (ISO-style uppercase code).
  @HiveField(11)
  final String currency;

  /// Haircut applied when liquidity must be converted across currencies.
  @HiveField(12)
  final double fxHaircut;

  /// Operational delay before this account can rescue another liquidity
  /// location. This used to live in a second unsynchronized metadata box.
  @HiveField(13)
  final int transferDelayDays;

  const AccountModel({
    required this.id,
    required this.name,
    this.kind = AccountKind.main,
    this.openingBalance = 0,
    this.colorValue = 0xFFF97316,
    required this.createdAt,
    this.archived = false,
    this.note,
    this.organizationId,
    this.minimumBalance = 0,
    this.allowNetting = true,
    this.currency = 'RUB',
    this.fxHaircut = 0.03,
    this.transferDelayDays = 0,
  });

  static const String mainId = 'main';

  static String mainIdFor(String organizationId) =>
      organizationId == OrganizationModel.rootId
          ? mainId
          : 'main:$organizationId';

  String get effectiveOrganizationId =>
      organizationId ?? OrganizationModel.rootId;

  AccountModel copyWith({
    String? name,
    AccountKind? kind,
    double? openingBalance,
    int? colorValue,
    bool? archived,
    String? note,
    bool clearNote = false,
    String? organizationId,
    double? minimumBalance,
    bool? allowNetting,
    String? currency,
    double? fxHaircut,
    int? transferDelayDays,
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
        organizationId: organizationId ?? this.organizationId,
        minimumBalance: minimumBalance ?? this.minimumBalance,
        allowNetting: allowNetting ?? this.allowNetting,
        currency: (currency ?? this.currency).toUpperCase(),
        fxHaircut:
            (fxHaircut ?? this.fxHaircut).clamp(0.0, 0.25).toDouble(),
        transferDelayDays:
            (transferDelayDays ?? this.transferDelayDays).clamp(0, 14).toInt(),
      );
}

/// Чтение и запись счёта в Hive.
///
/// Поля 0–8 существовали в прошлой версии и читаются строго. Всё, что
/// добавилось после неё, имеет умолчание из конструктора: отсутствие поля
/// означает «эту запись сделала версия, которая про него не знала».
class AccountModelAdapter extends TypeAdapter<AccountModel> {
  @override
  final int typeId = 15;

  @override
  AccountModel read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return AccountModel(
      id: fields[0] as String,
      name: fields[1] as String,
      kind: fields[2] as AccountKind? ?? AccountKind.main,
      openingBalance: _num(fields[3]) ?? 0,
      colorValue: (fields[4] as num?)?.toInt() ?? 0xFFF97316,
      createdAt: fields[5] as DateTime,
      archived: fields[6] as bool? ?? false,
      note: fields[7] as String?,
      organizationId: fields[8] as String?,
      minimumBalance: _num(fields[9]) ?? 0,
      allowNetting: fields[10] as bool? ?? true,
      currency: fields[11] as String? ?? 'RUB',
      fxHaircut: _num(fields[12]) ?? 0.03,
      transferDelayDays: (fields[13] as num?)?.toInt() ?? 0,
    );
  }

  /// Число могло быть записано целым: жёсткое приведение к `double?` на
  /// таком значении падает, хотя данные исправны.
  static double? _num(dynamic value) =>
      value is num ? value.toDouble() : null;

  @override
  void write(BinaryWriter writer, AccountModel obj) {
    writer
      ..writeByte(14)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.kind)
      ..writeByte(3)
      ..write(obj.openingBalance)
      ..writeByte(4)
      ..write(obj.colorValue)
      ..writeByte(5)
      ..write(obj.createdAt)
      ..writeByte(6)
      ..write(obj.archived)
      ..writeByte(7)
      ..write(obj.note)
      ..writeByte(8)
      ..write(obj.organizationId)
      ..writeByte(9)
      ..write(obj.minimumBalance)
      ..writeByte(10)
      ..write(obj.allowNetting)
      ..writeByte(11)
      ..write(obj.currency)
      ..writeByte(12)
      ..write(obj.fxHaircut)
      ..writeByte(13)
      ..write(obj.transferDelayDays);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
