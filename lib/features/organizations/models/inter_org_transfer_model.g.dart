// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inter_org_transfer_model.dart';

class InterOrgTransferModelAdapter extends TypeAdapter<InterOrgTransferModel> {
  @override
  final int typeId = 84;

  @override
  InterOrgTransferModel read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
    };
    return InterOrgTransferModel(
      id: fields[0] as String,
      fromOrganizationId: fields[1] as String,
      toOrganizationId: fields[2] as String,
      fromAccountId: fields[3] as String,
      toAccountId: fields[4] as String,
      amount: (fields[5] as num).toDouble(),
      currency: fields[6] as String? ?? 'RUB',
      amountInFromOrgBase: (fields[7] as num?)?.toDouble() ?? (fields[5] as num).toDouble(),
      amountInToOrgBase: (fields[8] as num?)?.toDouble() ?? (fields[5] as num).toDouble(),
      type: fields[9] as InterOrgTransferType? ?? InterOrgTransferType.other,
      note: fields[10] as String?,
      date: fields[11] as DateTime,
      createdBy: fields[12] as String? ?? 'unknown',
      createdAt: fields[13] as DateTime? ?? DateTime.fromMillisecondsSinceEpoch(0),
      linkedDebitTransactionId: fields[14] as String,
      linkedCreditTransactionId: fields[15] as String,
      cancelled: fields[16] as bool? ?? false,
      cancelledAt: fields[17] as DateTime?,
      cancelledBy: fields[18] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, InterOrgTransferModel obj) {
    writer
      ..writeByte(19)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.fromOrganizationId)
      ..writeByte(2)..write(obj.toOrganizationId)
      ..writeByte(3)..write(obj.fromAccountId)
      ..writeByte(4)..write(obj.toAccountId)
      ..writeByte(5)..write(obj.amount)
      ..writeByte(6)..write(obj.currency)
      ..writeByte(7)..write(obj.amountInFromOrgBase)
      ..writeByte(8)..write(obj.amountInToOrgBase)
      ..writeByte(9)..write(obj.type)
      ..writeByte(10)..write(obj.note)
      ..writeByte(11)..write(obj.date)
      ..writeByte(12)..write(obj.createdBy)
      ..writeByte(13)..write(obj.createdAt)
      ..writeByte(14)..write(obj.linkedDebitTransactionId)
      ..writeByte(15)..write(obj.linkedCreditTransactionId)
      ..writeByte(16)..write(obj.cancelled)
      ..writeByte(17)..write(obj.cancelledAt)
      ..writeByte(18)..write(obj.cancelledBy);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterOrgTransferModelAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

class InterOrgTransferTypeAdapter extends TypeAdapter<InterOrgTransferType> {
  @override
  final int typeId = 83;

  @override
  InterOrgTransferType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0: return InterOrgTransferType.investment;
      case 1: return InterOrgTransferType.profitShare;
      case 2: return InterOrgTransferType.funding;
      case 3: return InterOrgTransferType.internalTransfer;
      case 4:
      default: return InterOrgTransferType.other;
    }
  }

  @override
  void write(BinaryWriter writer, InterOrgTransferType obj) {
    switch (obj) {
      case InterOrgTransferType.investment: writer.writeByte(0); break;
      case InterOrgTransferType.profitShare: writer.writeByte(1); break;
      case InterOrgTransferType.funding: writer.writeByte(2); break;
      case InterOrgTransferType.internalTransfer: writer.writeByte(3); break;
      case InterOrgTransferType.other: writer.writeByte(4); break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InterOrgTransferTypeAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
