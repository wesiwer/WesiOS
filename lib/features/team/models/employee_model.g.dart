// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employee_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class EmployeeModelAdapter extends TypeAdapter<EmployeeModel> {
  @override
  final int typeId = 21;

  @override
  EmployeeModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return EmployeeModel(
      id: fields[0] as String,
      login: fields[1] as String,
      fullName: fields[2] as String,
      nickname: fields[3] as String,
      position: fields[4] as String,
      phone: fields[5] as String,
      email: fields[6] as String,
      socials: (fields[7] as Map).cast<String, String>(),
      notes: fields[8] as String,
      permissions: fields[9] as TeamPermissions,
      passwordHash: fields[10] as String,
      passwordSalt: fields[11] as String,
      avatarIndex: fields[12] as int,
      createdAt: fields[13] as DateTime,
      isOwner: fields[14] as bool,
      demoStats: (fields[15] as Map).cast<String, double>(),
      photo: fields[16] as Uint8List?,
      skills: (fields[17] as List).cast<String>(),
      weeklyCapacityPoints: fields[18] as double,
      workloadMinRatio: fields[19] as double,
      workloadMaxRatio: fields[20] as double,
      managerEmployeeId: fields[21] as String?,
      workloadAlertTarget: fields[22] as String,
    );
  }

  @override
  void write(BinaryWriter writer, EmployeeModel obj) {
    writer
      ..writeByte(23)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.login)
      ..writeByte(2)
      ..write(obj.fullName)
      ..writeByte(3)
      ..write(obj.nickname)
      ..writeByte(4)
      ..write(obj.position)
      ..writeByte(5)
      ..write(obj.phone)
      ..writeByte(6)
      ..write(obj.email)
      ..writeByte(7)
      ..write(obj.socials)
      ..writeByte(8)
      ..write(obj.notes)
      ..writeByte(9)
      ..write(obj.permissions)
      ..writeByte(10)
      ..write(obj.passwordHash)
      ..writeByte(11)
      ..write(obj.passwordSalt)
      ..writeByte(12)
      ..write(obj.avatarIndex)
      ..writeByte(13)
      ..write(obj.createdAt)
      ..writeByte(14)
      ..write(obj.isOwner)
      ..writeByte(15)
      ..write(obj.demoStats)
      ..writeByte(16)
      ..write(obj.photo)
      ..writeByte(17)
      ..write(obj.skills)
      ..writeByte(18)
      ..write(obj.weeklyCapacityPoints)
      ..writeByte(19)
      ..write(obj.workloadMinRatio)
      ..writeByte(20)
      ..write(obj.workloadMaxRatio)
      ..writeByte(21)
      ..write(obj.managerEmployeeId)
      ..writeByte(22)
      ..write(obj.workloadAlertTarget);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EmployeeModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
