// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_audit_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionAuditModelAdapter extends TypeAdapter<TransactionAuditModel> {
  @override
  final int typeId = 85;

  @override
  TransactionAuditModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TransactionAuditModel(
      id: fields[0] as String,
      transactionId: fields[1] as String,
      changedBy: fields[2] as String,
      changedAt: fields[3] as DateTime,
      beforeJson: fields[4] as String?,
      afterJson: fields[5] as String?,
      reason: fields[6] as String?,
      organizationId: fields[7] as String,
    );
  }

  @override
  void write(BinaryWriter writer, TransactionAuditModel obj) {
    writer
      ..writeByte(8)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.transactionId)
      ..writeByte(2)
      ..write(obj.changedBy)
      ..writeByte(3)
      ..write(obj.changedAt)
      ..writeByte(4)
      ..write(obj.beforeJson)
      ..writeByte(5)
      ..write(obj.afterJson)
      ..writeByte(6)
      ..write(obj.reason)
      ..writeByte(7)
      ..write(obj.organizationId);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionAuditModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
