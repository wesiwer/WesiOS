// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organization_access_grant.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrganizationAccessGrantAdapter
    extends TypeAdapter<OrganizationAccessGrant> {
  @override
  final int typeId = 82;

  @override
  OrganizationAccessGrant read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrganizationAccessGrant(
      id: fields[0] as String,
      employeeId: fields[1] as String,
      organizationId: fields[2] as String,
      includeSubtree: fields[3] as bool,
      canViewTeamFinance: fields[4] as bool,
      canViewSelfFinance: fields[5] as bool,
      permissions: (fields[6] as List).cast<String>(),
      createdAt: fields[7] as DateTime,
      updatedAt: fields[8] as DateTime,
      createdBy: fields[9] as String,
    );
  }

  @override
  void write(BinaryWriter writer, OrganizationAccessGrant obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.employeeId)
      ..writeByte(2)
      ..write(obj.organizationId)
      ..writeByte(3)
      ..write(obj.includeSubtree)
      ..writeByte(4)
      ..write(obj.canViewTeamFinance)
      ..writeByte(5)
      ..write(obj.canViewSelfFinance)
      ..writeByte(6)
      ..write(obj.permissions)
      ..writeByte(7)
      ..write(obj.createdAt)
      ..writeByte(8)
      ..write(obj.updatedAt)
      ..writeByte(9)
      ..write(obj.createdBy);
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
