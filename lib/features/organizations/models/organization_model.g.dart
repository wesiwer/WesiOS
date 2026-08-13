// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'organization_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class OrganizationModelAdapter extends TypeAdapter<OrganizationModel> {
  @override
  final int typeId = 81;

  @override
  OrganizationModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return OrganizationModel(
      id: fields[0] as String,
      name: fields[1] as String,
      parentId: fields[2] as String?,
      isRoot: fields[3] as bool,
      baseCurrency: fields[4] as String,
      status: fields[5] as OrganizationStatus,
      createdAt: fields[6] as DateTime,
      updatedAt: fields[7] as DateTime,
      createdBy: fields[8] as String,
      code: fields[9] as String?,
      description: fields[10] as String?,
      colorValue: fields[11] as int?,
      sortOrder: fields[12] as int,
    );
  }

  @override
  void write(BinaryWriter writer, OrganizationModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.name)
      ..writeByte(2)
      ..write(obj.parentId)
      ..writeByte(3)
      ..write(obj.isRoot)
      ..writeByte(4)
      ..write(obj.baseCurrency)
      ..writeByte(5)
      ..write(obj.status)
      ..writeByte(6)
      ..write(obj.createdAt)
      ..writeByte(7)
      ..write(obj.updatedAt)
      ..writeByte(8)
      ..write(obj.createdBy)
      ..writeByte(9)
      ..write(obj.code)
      ..writeByte(10)
      ..write(obj.description)
      ..writeByte(11)
      ..write(obj.colorValue)
      ..writeByte(12)
      ..write(obj.sortOrder);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrganizationModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class OrganizationStatusAdapter extends TypeAdapter<OrganizationStatus> {
  @override
  final int typeId = 80;

  @override
  OrganizationStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return OrganizationStatus.active;
      case 1:
        return OrganizationStatus.archived;
      default:
        return OrganizationStatus.active;
    }
  }

  @override
  void write(BinaryWriter writer, OrganizationStatus obj) {
    switch (obj) {
      case OrganizationStatus.active:
        writer.writeByte(0);
        break;
      case OrganizationStatus.archived:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is OrganizationStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
