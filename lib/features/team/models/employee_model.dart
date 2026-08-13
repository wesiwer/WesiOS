import 'dart:typed_data';

import 'package:hive/hive.dart';

import 'team_permissions.dart';

part 'employee_model.g.dart';

@HiveType(typeId: 21)
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
