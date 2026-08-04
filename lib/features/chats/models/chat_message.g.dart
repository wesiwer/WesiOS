// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'chat_message.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ChatMessageAdapter extends TypeAdapter<ChatMessage> {
  @override
  final int typeId = 24;

  @override
  ChatMessage read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ChatMessage(
      id: fields[0] as String,
      chatId: fields[1] as String,
      authorId: fields[2] as String,
      body: fields[3] as String,
      at: fields[4] as DateTime,
      kind: fields[5] as MessageKind,
      state: fields[6] as DeliveryState,
      expiresAt: fields[7] as DateTime?,
      archived: fields[8] as bool,
      topicId: fields[9] as String?,
      replyTo: fields[10] as String?,
      editedAt: fields[11] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, ChatMessage obj) {
    writer
      ..writeByte(12)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.chatId)
      ..writeByte(2)
      ..write(obj.authorId)
      ..writeByte(3)
      ..write(obj.body)
      ..writeByte(4)
      ..write(obj.at)
      ..writeByte(5)
      ..write(obj.kind)
      ..writeByte(6)
      ..write(obj.state)
      ..writeByte(7)
      ..write(obj.expiresAt)
      ..writeByte(8)
      ..write(obj.archived)
      ..writeByte(9)
      ..write(obj.topicId)
      ..writeByte(10)
      ..write(obj.replyTo)
      ..writeByte(11)
      ..write(obj.editedAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ChatMessageAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class MessageKindAdapter extends TypeAdapter<MessageKind> {
  @override
  final int typeId = 22;

  @override
  MessageKind read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return MessageKind.text;
      case 1:
        return MessageKind.sticker;
      case 2:
        return MessageKind.system;
      default:
        return MessageKind.text;
    }
  }

  @override
  void write(BinaryWriter writer, MessageKind obj) {
    switch (obj) {
      case MessageKind.text:
        writer.writeByte(0);
        break;
      case MessageKind.sticker:
        writer.writeByte(1);
        break;
      case MessageKind.system:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MessageKindAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class DeliveryStateAdapter extends TypeAdapter<DeliveryState> {
  @override
  final int typeId = 23;

  @override
  DeliveryState read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return DeliveryState.pending;
      case 1:
        return DeliveryState.sent;
      case 2:
        return DeliveryState.delivered;
      case 3:
        return DeliveryState.read;
      case 4:
        return DeliveryState.failed;
      default:
        return DeliveryState.pending;
    }
  }

  @override
  void write(BinaryWriter writer, DeliveryState obj) {
    switch (obj) {
      case DeliveryState.pending:
        writer.writeByte(0);
        break;
      case DeliveryState.sent:
        writer.writeByte(1);
        break;
      case DeliveryState.delivered:
        writer.writeByte(2);
        break;
      case DeliveryState.read:
        writer.writeByte(3);
        break;
      case DeliveryState.failed:
        writer.writeByte(4);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryStateAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
