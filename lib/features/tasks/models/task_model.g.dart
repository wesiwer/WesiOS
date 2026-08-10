// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'task_model.dart';

class SubTaskAdapter extends TypeAdapter<SubTask> {
  @override
  final int typeId = 12;

  @override
  SubTask read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SubTask(
      title: fields[0] as String,
      done: fields[1] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, SubTask obj) {
    writer
      ..writeByte(2)
      ..writeByte(0)..write(obj.title)
      ..writeByte(1)..write(obj.done);
  }

  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) => identical(this, other) || other is SubTaskAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

class TaskModelAdapter extends TypeAdapter<TaskModel> {
  @override
  final int typeId = 13;

  @override
  TaskModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TaskModel(
      id: fields[0] as String,
      title: fields[1] as String,
      description: fields[2] as String?,
      status: fields[3] as TaskStatus,
      priority: fields[4] as TaskPriority,
      createdAt: fields[5] as DateTime,
      dueDate: fields[6] as DateTime?,
      assignee: fields[7] as String?,
      subtasks: (fields[8] as List? ?? const []).cast<SubTask>(),
      tags: (fields[9] as List? ?? const []).cast<String>(),
      order: fields[10] as int? ?? 0,
      organizationId: fields[11] as String?,
      responsibleEmployeeId: fields[12] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, TaskModel obj) {
    writer
      ..writeByte(13)
      ..writeByte(0)..write(obj.id)
      ..writeByte(1)..write(obj.title)
      ..writeByte(2)..write(obj.description)
      ..writeByte(3)..write(obj.status)
      ..writeByte(4)..write(obj.priority)
      ..writeByte(5)..write(obj.createdAt)
      ..writeByte(6)..write(obj.dueDate)
      ..writeByte(7)..write(obj.assignee)
      ..writeByte(8)..write(obj.subtasks)
      ..writeByte(9)..write(obj.tags)
      ..writeByte(10)..write(obj.order)
      ..writeByte(11)..write(obj.organizationId)
      ..writeByte(12)..write(obj.responsibleEmployeeId);
  }

  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) => identical(this, other) || other is TaskModelAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

class TaskStatusAdapter extends TypeAdapter<TaskStatus> {
  @override
  final int typeId = 10;
  @override
  TaskStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 1: return TaskStatus.inProgress;
      case 2: return TaskStatus.review;
      case 3: return TaskStatus.done;
      case 0:
      default: return TaskStatus.backlog;
    }
  }
  @override
  void write(BinaryWriter writer, TaskStatus obj) {
    switch (obj) {
      case TaskStatus.backlog: writer.writeByte(0); break;
      case TaskStatus.inProgress: writer.writeByte(1); break;
      case TaskStatus.review: writer.writeByte(2); break;
      case TaskStatus.done: writer.writeByte(3); break;
    }
  }
  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) => identical(this, other) || other is TaskStatusAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}

class TaskPriorityAdapter extends TypeAdapter<TaskPriority> {
  @override
  final int typeId = 11;
  @override
  TaskPriority read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 1: return TaskPriority.normal;
      case 2: return TaskPriority.high;
      case 3: return TaskPriority.urgent;
      case 0:
      default: return TaskPriority.low;
    }
  }
  @override
  void write(BinaryWriter writer, TaskPriority obj) {
    switch (obj) {
      case TaskPriority.low: writer.writeByte(0); break;
      case TaskPriority.normal: writer.writeByte(1); break;
      case TaskPriority.high: writer.writeByte(2); break;
      case TaskPriority.urgent: writer.writeByte(3); break;
    }
  }
  @override
  int get hashCode => typeId.hashCode;
  @override
  bool operator ==(Object other) => identical(this, other) || other is TaskPriorityAdapter && runtimeType == other.runtimeType && typeId == other.typeId;
}
