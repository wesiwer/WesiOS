// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'team_permissions.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class TeamPermissionsAdapter extends TypeAdapter<TeamPermissions> {
  @override
  final int typeId = 20;

  @override
  TeamPermissions read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return TeamPermissions(
      moduleList: (fields[0] as List).cast<String>(),
      knowledgeIdList: (fields[1] as List).cast<String>(),
      knowledgeAll: fields[2] as bool,
      canManageTeam: fields[3] as bool,
      canSeeOthersStats: fields[4] as bool,
      canSeeNotes: fields[5] as bool,
    );
  }

  @override
  void write(BinaryWriter writer, TeamPermissions obj) {
    writer
      ..writeByte(6)
      ..writeByte(0)
      ..write(obj.moduleList)
      ..writeByte(1)
      ..write(obj.knowledgeIdList)
      ..writeByte(2)
      ..write(obj.knowledgeAll)
      ..writeByte(3)
      ..write(obj.canManageTeam)
      ..writeByte(4)
      ..write(obj.canSeeOthersStats)
      ..writeByte(5)
      ..write(obj.canSeeNotes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TeamPermissionsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
