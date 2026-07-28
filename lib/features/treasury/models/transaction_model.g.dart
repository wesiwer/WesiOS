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
      isRecurring: fields[7] as bool? ?? false,
      recurringPeriod: fields[8] as RecurringPeriod?,
      isAnomaly: fields[9] as bool? ?? false,
      zScore: fields[10] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, TransactionModel obj) {
    writer
      ..writeByte(11)
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
      ..write(obj.zScore);
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
        return RecurringPeriod.monthly;
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
