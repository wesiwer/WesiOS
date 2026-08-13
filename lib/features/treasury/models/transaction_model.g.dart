// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'transaction_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TransactionModelAdapter extends TypeAdapter<TransactionModel> {
  @override
  final int typeId = 1;

  @override
  TransactionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TransactionModel(
      id: fields[0] as String,
      title: fields[1] as String,
      amount: fields[2] as double,
      type: fields[3] as TransactionType,
      date: fields[4] as DateTime,
      category: fields[5] as String?,
      description: fields[6] as String?,
      isRecurring: fields[7] as bool,
      recurringPeriod: fields[8] as RecurringPeriod?,
      isAnomaly: fields[9] as bool,
      zScore: fields[10] as double?,
      accountId: fields[11] as String?,
      recurringAnchor: fields[12] as DateTime?,
      organizationId: fields[13] as String?,
      projectId: fields[14] as String?,
      counterpartyId: fields[15] as String?,
      source: fields[16] as TransactionSource,
      createdBy: fields[17] as String?,
      updatedBy: fields[18] as String?,
      updatedAt: fields[19] as DateTime?,
      ownerEmployeeId: fields[20] as String?,
      interOrgTransferId: fields[21] as String?,
      createdByEmployeeId: fields[22] as String?,
      originalAmount: fields[23] as double?,
      originalCurrency: fields[24] as String,
      organizationBaseAmount: fields[25] as double?,
      organizationBaseCurrency: fields[26] as String,
      fxRateToReporting: fields[27] as double,
      fxRateAt: fields[28] as DateTime?,
      fxSource: fields[29] as String,
    );
  }

  @override
  void write(BinaryWriter writer, TransactionModel obj) {
    writer
      ..writeByte(30)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.amount)
      ..writeByte(3)
      ..write(obj.type)
      ..writeByte(4)
      ..write(obj.date)
      ..writeByte(5)
      ..write(obj.category)
      ..writeByte(6)
      ..write(obj.description)
      ..writeByte(7)
      ..write(obj.isRecurring)
      ..writeByte(8)
      ..write(obj.recurringPeriod)
      ..writeByte(9)
      ..write(obj.isAnomaly)
      ..writeByte(10)
      ..write(obj.zScore)
      ..writeByte(11)
      ..write(obj.accountId)
      ..writeByte(12)
      ..write(obj.recurringAnchor)
      ..writeByte(13)
      ..write(obj.organizationId)
      ..writeByte(14)
      ..write(obj.projectId)
      ..writeByte(15)
      ..write(obj.counterpartyId)
      ..writeByte(16)
      ..write(obj.source)
      ..writeByte(17)
      ..write(obj.createdBy)
      ..writeByte(18)
      ..write(obj.updatedBy)
      ..writeByte(19)
      ..write(obj.updatedAt)
      ..writeByte(20)
      ..write(obj.ownerEmployeeId)
      ..writeByte(21)
      ..write(obj.interOrgTransferId)
      ..writeByte(22)
      ..write(obj.createdByEmployeeId)
      ..writeByte(23)
      ..write(obj.originalAmount)
      ..writeByte(24)
      ..write(obj.originalCurrency)
      ..writeByte(25)
      ..write(obj.organizationBaseAmount)
      ..writeByte(26)
      ..write(obj.organizationBaseCurrency)
      ..writeByte(27)
      ..write(obj.fxRateToReporting)
      ..writeByte(28)
      ..write(obj.fxRateAt)
      ..writeByte(29)
      ..write(obj.fxSource);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionTypeAdapter extends TypeAdapter<TransactionType> {
  @override
  final int typeId = 2;

  @override
  TransactionType read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionType.income;
      case 1:
        return TransactionType.expense;
      default:
        return TransactionType.income;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionType obj) {
    switch (obj) {
      case TransactionType.income:
        writer.writeByte(0);
        break;
      case TransactionType.expense:
        writer.writeByte(1);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionTypeAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class RecurringPeriodAdapter extends TypeAdapter<RecurringPeriod> {
  @override
  final int typeId = 3;

  @override
  RecurringPeriod read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return RecurringPeriod.daily;
      case 1:
        return RecurringPeriod.weekly;
      case 2:
        return RecurringPeriod.monthly;
      case 3:
        return RecurringPeriod.yearly;
      default:
        return RecurringPeriod.daily;
    }
  }

  @override
  void write(BinaryWriter writer, RecurringPeriod obj) {
    switch (obj) {
      case RecurringPeriod.daily:
        writer.writeByte(0);
        break;
      case RecurringPeriod.weekly:
        writer.writeByte(1);
        break;
      case RecurringPeriod.monthly:
        writer.writeByte(2);
        break;
      case RecurringPeriod.yearly:
        writer.writeByte(3);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RecurringPeriodAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class TransactionSourceAdapter extends TypeAdapter<TransactionSource> {
  @override
  final int typeId = 86;

  @override
  TransactionSource read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return TransactionSource.manual;
      case 1:
        return TransactionSource.import;
      case 2:
        return TransactionSource.recurring;
      case 3:
        return TransactionSource.crm;
      case 4:
        return TransactionSource.task;
      case 5:
        return TransactionSource.interorg;
      default:
        return TransactionSource.manual;
    }
  }

  @override
  void write(BinaryWriter writer, TransactionSource obj) {
    switch (obj) {
      case TransactionSource.manual:
        writer.writeByte(0);
        break;
      case TransactionSource.import:
        writer.writeByte(1);
        break;
      case TransactionSource.recurring:
        writer.writeByte(2);
        break;
      case TransactionSource.crm:
        writer.writeByte(3);
        break;
      case TransactionSource.task:
        writer.writeByte(4);
        break;
      case TransactionSource.interorg:
        writer.writeByte(5);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransactionSourceAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
