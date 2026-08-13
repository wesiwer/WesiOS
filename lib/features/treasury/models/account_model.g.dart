// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class AccountModelAdapter extends TypeAdapter<AccountModel> {
  @override
  final int typeId = 15;

  @override
  AccountModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return AccountModel(
      id: fields[0] as String,
      name: fields[1] as String,
      kind: fields[2] as AccountKind,
      openingBalance: fields[3] as double,
      colorValue: fields[4] as int,
      createdAt: fields[5] as DateTime,
      archived: fields[6] as bool,
      note: fields[7] as String?,
      organizationId: fields[8] as String?,
      minimumBalance: fields[9] as double,
      allowNetting: fields[10] as bool,
      currency: fields[11] as String,
      fxHaircut: fields[12] as double,
      transferDelayDays: fields[13] as int,
    );
  }

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

class AccountKindAdapter extends TypeAdapter<AccountKind> {
  @override
  final int typeId = 14;

  @override
  AccountKind read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return AccountKind.main;
      case 1:
        return AccountKind.card;
      case 2:
        return AccountKind.cash;
      case 3:
        return AccountKind.savings;
      case 4:
        return AccountKind.project;
      case 5:
        return AccountKind.reserve;
      case 6:
        return AccountKind.other;
      default:
        return AccountKind.main;
    }
  }

  @override
  void write(BinaryWriter writer, AccountKind obj) {
    switch (obj) {
      case AccountKind.main:
        writer.writeByte(0);
        break;
      case AccountKind.card:
        writer.writeByte(1);
        break;
      case AccountKind.cash:
        writer.writeByte(2);
        break;
      case AccountKind.savings:
        writer.writeByte(3);
        break;
      case AccountKind.project:
        writer.writeByte(4);
        break;
      case AccountKind.reserve:
        writer.writeByte(5);
        break;
      case AccountKind.other:
        writer.writeByte(6);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AccountKindAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
