import 'package:hive/hive.dart';

part 'team_permissions.g.dart';

/// Что человеку открыто.
///
/// Правило одно и оно жёсткое: **всё, чего нет в наборе, закрыто**. Не
/// «показать серым», не «спросить пароль» — не показать вовсе. Человек не
/// должен догадываться о существовании разделов, к которым его не пускали:
/// пустая вкладка с замком — это приглашение постучаться.
///
/// Честная граница. Пока данные лежат на устройстве, эти права — про
/// интерфейс: они решают, что человек видит, а не что он физически может
/// достать из файла с базой. Настоящая защита появится вместе с сервером,
/// где проверка происходит НЕ на устройстве проверяемого. Набор специально
/// сделан таким, чтобы переехать в серверные правила один в один.
@HiveType(typeId: 20)
class TeamPermissions {
  /// Модули, открытые человеку. Ключи — из [TeamModules].
  ///
  /// Внутри список, а наружу — множество ([modules]). Hive не умеет читать
  /// Set: он отдаёт обратно List, и попытка присвоить его полю типа Set
  /// падает при загрузке уже сохранённых данных.
  @HiveField(0)
  final List<String> moduleList;

  /// Разделы базы знаний, открытые человеку: идентификаторы статей и папок.
  ///
  /// Пусто И [knowledgeAll] == false — база знаний не открыта совсем.
  @HiveField(1)
  final List<String> knowledgeIdList;

  /// Открыта вся база знаний, включая то, что появится потом.
  ///
  /// Отдельным флагом, а не «перечислить всё»: иначе каждая новая статья
  /// оказывалась бы закрытой для всех, пока владелец не вспомнит про неё.
  @HiveField(2)
  final bool knowledgeAll;

  /// Может заводить и править сотрудников.
  @HiveField(3)
  final bool canManageTeam;

  /// Видит показатели других людей, а не только свои.
  @HiveField(4)
  final bool canSeeOthersStats;

  /// Видит скрытые заметки в карточках сотрудников.
  @HiveField(5)
  final bool canSeeNotes;

  /// Может ставить задачи другим людям, а не только себе.
  ///
  /// Отдельно от доступа к модулю задач: видеть доску и раздавать по ней
  /// поручения — разные вещи. Исполнителю нужно первое, руководителю группы
  /// — оба.
  ///
  /// **Почему хранится как `bool?`, а наружу отдаётся `bool`.** Поле
  /// добавлено позже остальных, и в уже записанных на диск карточках его
  /// просто нет. Hive отдаёт за него null, а сгенерированный адаптер пишет
  /// `fields[6] as bool` — на непустом наборе сотрудников это падение при
  /// загрузке, то есть исчезнувшие контакты после обновления.
  ///
  /// Тот же приём, что с [moduleList] и [modules]: неудобство прячется в
  /// одном месте, а не расползается по коду. Править сгенерированный файл
  /// руками нельзя — следующий запуск генератора вернёт мину обратно.
  @HiveField(6)
  final bool? canAssignTasksRaw;

  bool get canAssignTasks => canAssignTasksRaw ?? false;

  const TeamPermissions({
    this.moduleList = const [],
    this.knowledgeIdList = const [],
    this.knowledgeAll = false,
    this.canManageTeam = false,
    this.canSeeOthersStats = false,
    this.canSeeNotes = false,
    this.canAssignTasksRaw,
  });

  Set<String> get modules => moduleList.toSet();
  Set<String> get knowledgeIds => knowledgeIdList.toSet();

  /// Что открыто новому сотруднику, пока владелец не решил иначе.
  ///
  /// Главная, задачи, настройки и профиль. Последние два в наборе не
  /// перечислены намеренно — они не отключаются никогда (см. [TeamModules]).
  static const TeamPermissions employeeDefault = TeamPermissions(
    moduleList: [TeamModules.tasks],
  );

  /// Полный доступ — у владельца.
  static TeamPermissions get owner => TeamPermissions(
        moduleList: TeamModules.all,
        knowledgeAll: true,
        canManageTeam: true,
        canSeeOthersStats: true,
        canSeeNotes: true,
        canAssignTasksRaw: true,
      );

  bool allows(String module) {
    if (TeamModules.always.contains(module)) return true;
    return modules.contains(module);
  }

  /// Открыта ли конкретная статья или папка базы знаний.
  bool allowsArticle(String id) =>
      knowledgeAll || knowledgeIds.contains(id);

  TeamPermissions copyWith({
    Set<String>? modules,
    Set<String>? knowledgeIds,
    bool? knowledgeAll,
    bool? canManageTeam,
    bool? canSeeOthersStats,
    bool? canSeeNotes,
    bool? canAssignTasks,
  }) =>
      TeamPermissions(
        moduleList: (modules ?? this.modules).toList()..sort(),
        knowledgeIdList: (knowledgeIds ?? this.knowledgeIds).toList()..sort(),
        knowledgeAll: knowledgeAll ?? this.knowledgeAll,
        canManageTeam: canManageTeam ?? this.canManageTeam,
        canSeeOthersStats: canSeeOthersStats ?? this.canSeeOthersStats,
        canSeeNotes: canSeeNotes ?? this.canSeeNotes,
        canAssignTasksRaw: canAssignTasks ?? this.canAssignTasks,
      );

  TeamPermissions withModule(String module, bool on) {
    final next = Set<String>.from(modules);
    if (on) {
      next.add(module);
    } else {
      next.remove(module);
    }
    return copyWith(modules: next);
  }

  TeamPermissions withArticle(String id, bool on) {
    final next = Set<String>.from(knowledgeIds);
    if (on) {
      next.add(id);
    } else {
      next.remove(id);
    }
    return copyWith(knowledgeIds: next, knowledgeAll: false);
  }

  Map<String, dynamic> toJson() => {
        'modules': modules.toList()..sort(),
        'knowledgeIds': knowledgeIds.toList()..sort(),
        'knowledgeAll': knowledgeAll,
        'canManageTeam': canManageTeam,
        'canSeeOthersStats': canSeeOthersStats,
        'canSeeNotes': canSeeNotes,
        'canAssignTasks': canAssignTasks,
      };

  static TeamPermissions fromJson(Map<String, dynamic> json) =>
      TeamPermissions(
        moduleList: [...?(json['modules'] as List?)?.map((e) => '$e')],
        knowledgeIdList: [
          ...?(json['knowledgeIds'] as List?)?.map((e) => '$e')
        ],
        knowledgeAll: json['knowledgeAll'] == true,
        canManageTeam: json['canManageTeam'] == true,
        canSeeOthersStats: json['canSeeOthersStats'] == true,
        canSeeNotes: json['canSeeNotes'] == true,
        canAssignTasksRaw: json['canAssignTasks'] == true,
      );
}

/// Перечень модулей, доступ к которым настраивается.
class TeamModules {
  TeamModules._();

  static const String treasury = 'treasury';
  static const String forecast = 'forecast';
  static const String sandbox = 'sandbox';
  static const String analytics = 'analytics';
  static const String tasks = 'tasks';
  static const String calendar = 'calendar';
  static const String knowledge = 'knowledge';
  static const String contacts = 'contacts';
  static const String chats = 'chats';
  static const String shield = 'shield';
  static const String keys = 'keys';
  static const String crm = 'crm';
  static const String ai = 'ai';
  static const String audio = 'audio';
  static const String roadmap = 'roadmap';
  static const String sysadmin = 'sysadmin';

  /// Всё, что можно открыть или закрыть.
  static const List<String> all = [
    treasury,
    forecast,
    sandbox,
    analytics,
    tasks,
    calendar,
    knowledge,
    contacts,
    chats,
    shield,
    keys,
    crm,
    ai,
    audio,
    roadmap,
    sysadmin,
  ];

  /// Открыто всегда и никем не отключается.
  ///
  /// Без главной человеку некуда попасть после входа, без настроек он не
  /// сменит себе пароль, без профиля — аватарку. Возможность отобрать это
  /// была бы возможностью случайно запереть человека в пустом приложении.
  static const Set<String> always = {'home', 'settings', 'profile'};

  /// Группировка для экрана прав — чтобы список из пятнадцати переключателей
  /// не выглядел свалкой.
  static const Map<String, List<String>> groups = {
    'Финансы': [treasury, forecast, sandbox, analytics],
    'Работа': [tasks, calendar, roadmap, crm],
    'Знания и общение': [knowledge, contacts, chats],
    'Система': [shield, keys, sysadmin],
    'Прочее': [ai, audio],
  };

  static String labelRu(String module) => switch (module) {
        treasury => 'Финансы',
        forecast => 'Прогноз',
        sandbox => 'Песочница',
        analytics => 'Аналитика',
        tasks => 'Задачи',
        calendar => 'Календарь',
        knowledge => 'База знаний',
        contacts => 'Контакты',
        chats => 'Чаты',
        shield => 'Wesi Shield',
        keys => 'Ключи',
        crm => 'CRM',
        ai => 'Wesi AI',
        audio => 'Audio Vault',
        roadmap => 'Roadmap',
        sysadmin => 'Системный администратор',
        _ => module,
      };

  static String labelEn(String module) => switch (module) {
        treasury => 'Finance',
        forecast => 'Forecast',
        sandbox => 'Sandbox',
        analytics => 'Analytics',
        tasks => 'Tasks',
        calendar => 'Calendar',
        knowledge => 'Knowledge base',
        contacts => 'Contacts',
        chats => 'Chats',
        shield => 'Wesi Shield',
        keys => 'Keys',
        crm => 'CRM',
        ai => 'Wesi AI',
        audio => 'Audio Vault',
        roadmap => 'Roadmap',
        sysadmin => 'System administrator',
        _ => module,
      };

  /// Короткое пояснение, что человек получит вместе с доступом.
  static String hintRu(String module) => switch (module) {
        treasury => 'Свои доходы, траты и счета',
        forecast => 'Прогноз баланса и риск кассового разрыва',
        sandbox => 'Сценарии «что если» на отдельных данных',
        analytics => 'Свои показатели и динамика',
        tasks => 'Канбан, сроки, исполнители',
        calendar => 'Сетка месяца',
        knowledge => 'Регламенты и инструкции — ниже можно выбрать разделы',
        contacts => 'Список коллег с телефонами и почтой',
        chats => 'Личные и групповые переписки',
        shield => 'Пароль, автоблокировка, журнал входов',
        keys => 'Ключи от внешних сервисов',
        crm => 'Клиенты и сделки',
        ai => 'Ассистент по своим данным',
        audio => 'Биты, демо, лицензии',
        roadmap => 'Проекты во времени',
        sysadmin => 'Состояние серверов, доменов и сайта',
        _ => '',
      };
}
