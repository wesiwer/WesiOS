import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'team_permissions.dart';

// Сгенерированного файла у этой модели больше нет: адаптер написан руками
// ниже, а перечислений, которые генератор мог бы обслуживать, здесь нет.

/// Адаптер написан руками — см. [EmployeeModelAdapter] в конце файла.
///
/// Здесь это не перестраховка, а починка уже случившегося. Терпимость к
/// профилям без полей 17–22 была дописана в сгенерированный файл руками, а
/// при слиянии её затёрло свежей генерацией. Так профили, заведённые до
/// появления навыков и нагрузки, стали нечитаемыми — а коробка сотрудников
/// открывается при запуске раньше всего остального, то есть приложение
/// переставало открываться вообще.
///
/// Правка в сгенерированном файле не переживает ни одного `build_runner`.
/// Поэтому адаптер вынесен сюда: теперь его нельзя стереть перегенерацией,
/// а причина написана рядом с кодом, а не в чужой памяти.
///
/// Аннотации `@HiveField` оставлены как карта занятых номеров: под ними
/// лежат данные на устройствах, переиспользовать их нельзя.
class EmployeeModel {
  @HiveField(0)
  final String id;
  @HiveField(1)
  final String login;
  @HiveField(2)
  final String fullName;
  @HiveField(3)
  final String nickname;
  @HiveField(4)
  final String position;
  @HiveField(5)
  final String phone;
  @HiveField(6)
  final String email;
  @HiveField(7)
  final Map<String, String> socials;
  @HiveField(8)
  final String notes;
  @HiveField(9)
  final TeamPermissions permissions;
  @HiveField(10)
  final String passwordHash;
  @HiveField(11)
  final String passwordSalt;
  @HiveField(12)
  final int avatarIndex;
  @HiveField(13)
  final DateTime createdAt;
  @HiveField(14)
  final bool isOwner;
  @HiveField(15)
  final Map<String, double> demoStats;
  @HiveField(16)
  final Uint8List? photo;

  /// Практические навыки сотрудника. Это не должность: один человек может
  /// одновременно владеть несколькими направлениями, и Wesi AI использует
  /// этот список при выборе исполнителя.
  @HiveField(17)
  final List<String> skills;

  /// Условная недельная ёмкость в баллах задач. Значение 10 подходит для
  /// обычной полной загрузки и может быть уменьшено для part-time.
  @HiveField(18)
  final double weeklyCapacityPoints;

  /// Нижняя и верхняя границы нормальной загрузки относительно ёмкости.
  @HiveField(19)
  final double workloadMinRatio;
  @HiveField(20)
  final double workloadMaxRatio;

  /// Руководитель, которому можно показывать уведомления по нагрузке.
  @HiveField(21)
  final String? managerEmployeeId;

  /// manager / ceo / both / off.
  @HiveField(22)
  final String workloadAlertTarget;

  const EmployeeModel({
    required this.id,
    required this.login,
    required this.fullName,
    this.nickname = '',
    this.position = '',
    this.phone = '',
    this.email = '',
    this.socials = const {},
    this.notes = '',
    this.permissions = const TeamPermissions(),
    this.passwordHash = '',
    this.passwordSalt = '',
    this.avatarIndex = 0,
    required this.createdAt,
    this.isOwner = false,
    this.demoStats = const {},
    this.photo,
    this.skills = const [],
    this.weeklyCapacityPoints = 10,
    this.workloadMinRatio = .65,
    this.workloadMaxRatio = 1.10,
    this.managerEmployeeId,
    this.workloadAlertTarget = 'manager',
  });

  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (nickname.trim().isNotEmpty) return nickname.trim();
    return login;
  }

  bool get hasContacts =>
      phone.trim().isNotEmpty || email.trim().isNotEmpty || socials.isNotEmpty;

  EmployeeModel copyWith({
    String? login,
    String? fullName,
    String? nickname,
    String? position,
    String? phone,
    String? email,
    Map<String, String>? socials,
    String? notes,
    TeamPermissions? permissions,
    String? passwordHash,
    String? passwordSalt,
    int? avatarIndex,
    Map<String, double>? demoStats,
    Uint8List? photo,
    bool clearPhoto = false,
    List<String>? skills,
    double? weeklyCapacityPoints,
    double? workloadMinRatio,
    double? workloadMaxRatio,
    String? managerEmployeeId,
    bool clearManager = false,
    String? workloadAlertTarget,
  }) =>
      EmployeeModel(
        id: id,
        login: login ?? this.login,
        fullName: fullName ?? this.fullName,
        nickname: nickname ?? this.nickname,
        position: position ?? this.position,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        socials: socials ?? this.socials,
        notes: notes ?? this.notes,
        permissions: permissions ?? this.permissions,
        passwordHash: passwordHash ?? this.passwordHash,
        passwordSalt: passwordSalt ?? this.passwordSalt,
        avatarIndex: avatarIndex ?? this.avatarIndex,
        createdAt: createdAt,
        isOwner: isOwner,
        demoStats: demoStats ?? this.demoStats,
        photo: clearPhoto ? null : (photo ?? this.photo),
        skills: skills ?? this.skills,
        weeklyCapacityPoints: weeklyCapacityPoints ?? this.weeklyCapacityPoints,
        workloadMinRatio: workloadMinRatio ?? this.workloadMinRatio,
        workloadMaxRatio: workloadMaxRatio ?? this.workloadMaxRatio,
        managerEmployeeId:
            clearManager ? null : (managerEmployeeId ?? this.managerEmployeeId),
        workloadAlertTarget: workloadAlertTarget ?? this.workloadAlertTarget,
      );

  Map<String, dynamic> toPublicJson() => {
        'id': id,
        'login': login,
        'fullName': fullName,
        'nickname': nickname,
        'position': position,
        'phone': phone,
        'email': email,
        'socials': socials,
        'avatarIndex': avatarIndex,
        'createdAt': createdAt.toIso8601String(),
        'skills': skills,
        'weeklyCapacityPoints': weeklyCapacityPoints,
        'workloadMinRatio': workloadMinRatio,
        'workloadMaxRatio': workloadMaxRatio,
        'managerEmployeeId': managerEmployeeId,
        'workloadAlertTarget': workloadAlertTarget,
      };
}

/// Чтение и запись профиля сотрудника.
///
/// Поля 0–16 существуют с самой первой версии и читаются строго. Права и
/// признак владельца намеренно среди них: подставить их молча значило бы
/// придумать человеку доступ, которого ему не давали, а это хуже честного
/// отказа.
///
/// Поля 17–22 (навыки, ёмкость, границы нагрузки, руководитель, кому идут
/// оповещения) добавились позже. У профилей, заведённых до них, этих полей
/// в базе нет — там берётся то же умолчание, что и в конструкторе.
class EmployeeModelAdapter extends TypeAdapter<EmployeeModel> {
  @override
  final int typeId = 21;

  @override
  EmployeeModel read(BinaryReader reader) {
    final count = reader.readByte();
    final fields = <int, dynamic>{
      for (var i = 0; i < count; i++) reader.readByte(): reader.read(),
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
      skills: (fields[17] as List?)?.map((e) => '$e').toList() ?? const [],
      weeklyCapacityPoints: (fields[18] as num?)?.toDouble() ?? 10,
      workloadMinRatio: (fields[19] as num?)?.toDouble() ?? .65,
      workloadMaxRatio: (fields[20] as num?)?.toDouble() ?? 1.10,
      managerEmployeeId: fields[21] as String?,
      workloadAlertTarget: fields[22] as String? ?? 'manager',
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
