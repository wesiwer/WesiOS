import 'package:hive/hive.dart';

import '../../organizations/models/organization_model.dart';

part 'account_model.g.dart';

/// Purpose of an account inside one organization.
/// Existing byte values are immutable because old Hive data uses them.
@HiveType(typeId: 14)
enum AccountKind {
  @HiveField(0)
  main,
  @HiveField(1)
  card,
  @HiveField(2)
  cash,
  @HiveField(3)
  savings, // legacy value; retained for backward compatibility
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
  @HiveField(8)
  final String? organizationId;

  @HiveField(9)
  final double minimumBalance;

  @HiveField(10)
  final bool allowNetting;

  @HiveField(11)
  final String currency;

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
  });

  /// Legacy main account id. It remains the Wesi Beats main account forever.
  static const String mainId = 'main';

  static String mainIdFor(String organizationId) =>
      organizationId == OrganizationModel.wesiBeatsId
          ? mainId
          : 'main:$organizationId';

  String get effectiveOrganizationId =>
      organizationId ?? OrganizationModel.wesiBeatsId;

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
        currency: currency ?? this.currency,
      );
}
