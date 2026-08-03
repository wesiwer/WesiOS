import 'package:hive/hive.dart';

import 'team_permissions.dart';

part 'employee_model.g.dart';

/// Сотрудник или партнёр.
///
/// Разделение полей здесь не косметическое, а смысловое:
/// - **открытые** (имя, должность, телефон, почта, соцсети) видит любой, кто
///   открыл контакты — за тем список и нужен;
/// - **[notes]** видит только владелец и тот, кому он это открыл. Сюда идёт
///   всё остальное: договорённости, ставка, что-то личное.
///
/// **Пароля здесь нет и не будет.** Хранится [passwordHash] и [passwordSalt].
/// Разница принципиальная: если пароль можно посмотреть, его можно и украсть
/// — вместе с базой, резервной копией или экраном. Владелец видит пароль
/// ОДИН раз, в момент создания, когда тот ещё не сохранён никуда; дальше
/// только сброс на новый. Это единственное требование из задумки, которое
/// я выполнить не могу, и подменять его тихой заглушкой было бы хуже, чем
/// сказать прямо.
@HiveType(typeId: 21)
class EmployeeModel {
  @HiveField(0)
  final String id;

  /// Логин для входа. Уникален, берётся из свободных (см. LoginPoolService).
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

  /// Соцсети: название сети → ссылка или @имя.
  @HiveField(7)
  final Map<String, String> socials;

  /// Скрытые заметки. Показываются только по праву canSeeNotes.
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

  /// Владелец — тот, кто завёл систему. Его нельзя удалить и урезать в правах.
  @HiveField(14)
  final bool isOwner;

  /// Показатели для проверки, пока настоящих данных нет (см. TeamService).
  @HiveField(15)
  final Map<String, double> demoStats;

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
  });

  /// Как показывать человека в списке.
  String get displayName {
    if (fullName.trim().isNotEmpty) return fullName.trim();
    if (nickname.trim().isNotEmpty) return nickname.trim();
    return login;
  }

  /// Есть ли что показать в открытой части карточки.
  bool get hasContacts =>
      phone.trim().isNotEmpty ||
      email.trim().isNotEmpty ||
      socials.isNotEmpty;

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
      );

  /// Для будущей отправки на сервер.
  ///
  /// Хеш и соль сюда НЕ попадают: проверять пароль будет сервер, и отдавать
  /// ему материал для перебора незачем. Заметки тоже отдельно — они
  /// защищены другим правилом, чем открытая карточка.
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
      };
}
