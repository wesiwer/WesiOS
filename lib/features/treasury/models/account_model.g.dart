// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'account_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

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
