// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organization_access_grant.dart';

class OrganizationAccessGrantAdapter extends TypeAdapter<OrganizationAccessGrant> {
  @override
  final int typeId = 82;

  @override
  OrganizationAccessGrant read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return OrganizationAccessGrant(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      organizationId: fields[2] as String,
      includeSubtree: fields[3] as bool? ?? false,
      canViewTeamFinance: fields[4] as bool? ?? false,
      canViewSelfFinance: fields[5] as bool? ?? true,
      permissions: (fields[6] as List?)?.cast<String>() ?? const [OrganizationPermissions.view],
      createdAt: fields[7] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: fields[8] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
      createdBy: fields[9] as String? ?? 'migration',
    );
  }

  @override
  void write(BinaryWriter writer, OrganizationAccessGrant obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.employeeId)
      ..writeByte(2)..write(obj.organizationId)
      ..writeByte(3)..write(obj.includeSubtree)
      ..writeByte(4)..write(obj.canViewTeamFinance)
      ..writeByte(5)..write(obj.canViewSelfFinance)
      ..writeByte(6)..write(obj.permissions)
      ..writeByte(7)..write(obj.createdAt)
      ..writeByte(8)..write(obj.updatedAt)
      ..writeByte(9)..write(obj.createdBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrganizationAccessGrantAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
