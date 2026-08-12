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

@HiveType(typeId: 15)
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
