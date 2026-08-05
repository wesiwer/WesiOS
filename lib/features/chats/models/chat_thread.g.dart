// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_thread.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatThreadAdapter extends TypeAdapter<ChatThread> {
  @override
  final int typeId = 25;

  @override
  ChatThread read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatThread(
      id: fields[0] as String,
      kindName: fields[1] as String,
      participantIds: (fields[2] as List).cast<String>(),
      title: fields[3] as String,
      createdAt: fields[4] as DateTime,
      pinned: fields[5] as bool,
      muted: fields[6] as bool,
      lastOpenedAt: fields[7] as DateTime?,
      lifetimeDays: fields[8] as int?,
      isGroupRaw: fields[9] as bool?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatThread obj) {
    writer
      ..writeByte(10)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.kindName)
      ..writeByte(2)
      ..write(obj.participantIds)
      ..writeByte(3)
      ..write(obj.title)
      ..writeByte(4)
      ..write(obj.createdAt)
      ..writeByte(5)
      ..write(obj.pinned)
      ..writeByte(6)
      ..write(obj.muted)
      ..writeByte(7)
      ..write(obj.lastOpenedAt)
      ..writeByte(8)
      ..write(obj.lifetimeDays)
      ..writeByte(9)
      ..write(obj.isGroupRaw);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatThreadAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
