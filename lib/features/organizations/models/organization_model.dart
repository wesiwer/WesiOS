import 'package:hive/hive.dart';

part 'organization_model.g.dart';

@HiveType(typeId: 80)
enum OrganizationStatus {
  @HiveField(0)
  active,
  @HiveField(1)
  archived,
}

/// A real accounting/operating node in the WesiOS organization tree.
@HiveType(typeId: 81)
class OrganizationModel {
  static const String rootId = 'org_wesi_inc';
  static const String wesiBeatsId = 'org_wesi_beats';

  @HiveField(0)
  final String id;
  @HiveField(1)
  final String name;
  @HiveField(2)
  final String? parentId;
  @HiveField(3)
  final bool isRoot;
  @HiveField(4)
  final String baseCurrency;
  @HiveField(5)
  final OrganizationStatus status;
  @HiveField(6)
  final DateTime createdAt;
  @HiveField(7)
  final DateTime updatedAt;
  @HiveField(8)
  final String createdBy;
  @HiveField(9)
  final String? code;
  @HiveField(10)
  final String? description;
  @HiveField(11)
  final int? colorValue;
  @HiveField(12)
  final int sortOrder;

  const OrganizationModel({
    required this.id,
    required this.name,
    required this.parentId,
    required this.isRoot,
    required this.baseCurrency,
    this.status = OrganizationStatus.active,
    required this.createdAt,
    required this.updatedAt,
    required this.createdBy,
    this.code,
    this.description,
    this.colorValue,
    this.sortOrder = 0,
  });

  bool get archived => status == OrganizationStatus.archived;

  OrganizationModel copyWith({
    String? name,
    String? parentId,
    bool clearParent = false,
    String? baseCurrency,
    OrganizationStatus? status,
    DateTime? updatedAt,
    String? code,
    bool clearCode = false,
    String? description,
    bool clearDescription = false,
    int? colorValue,
    bool clearColor = false,
    int? sortOrder,
  }) =>
      OrganizationModel(
        id: id,
        name: name ?? this.name,
        parentId: clearParent ? null : (parentId ?? this.parentId),
        isRoot: isRoot,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        status: status ?? this.status,
        createdAt: createdAt,
        updatedAt: updatedAt ?? DateTime.now(),
        createdBy: createdBy,
        code: clearCode ? null : (code ?? this.code),
        description:
            clearDescription ? null : (description ?? this.description),
        colorValue: clearColor ? null : (colorValue ?? this.colorValue),
        sortOrder: sortOrder ?? this.sortOrder,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'parentId': parentId,
        'isRoot': isRoot,
        'baseCurrency': baseCurrency,
        'status': status.name,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'createdBy': createdBy,
        'code': code,
        'description': description,
        'colorValue': colorValue,
        'sortOrder': sortOrder,
      };
}
