import 'dart:convert';
import 'dart:typed_data';

import 'package:hive/hive.dart';

import '../../features/calendar/models/calendar_event.dart';
import '../../features/calendar/services/calendar_event_service.dart';
import '../../features/chats/models/chat_message.dart';
import '../../features/chats/models/chat_policy.dart';
import '../../features/chats/models/chat_thread.dart';
import '../../features/chats/services/chat_service.dart';
import '../../features/chats/services/message_store.dart';
import '../../features/knowledge/services/knowledge_service.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/team/services/team_service.dart';
import '../../features/treasury/services/account_service.dart';
import '../../features/treasury/services/treasury_service.dart';
import '../../features/knowledge/models/article_model.dart';
import '../../features/tasks/models/task_model.dart';
import '../../features/team/models/employee_model.dart';
import '../../features/team/models/team_permissions.dart';
import '../../features/treasury/models/account_model.dart';
import '../../features/treasury/models/transaction_model.dart';
import 'sync_journal.dart';
import 'sync_codec_roadmap.dart';
import 'sync_codec_crm.dart';

/// Описание одной синхронизируемой коллекции.
///
/// Перевод модели в поля и обратно вынесен из движка намеренно: движок не
/// должен ничего знать про транзакции и задачи, а модели — про синхронизацию.
/// Добавить шестую коллекцию — значит дописать сюда один класс и одну строку
/// в [SyncCodec.collections], больше нигде.
abstract class SyncCollection<T> {
  /// Имя на сервере. Меняться не должно: по нему лежат уже загруженные
  /// записи.
  String get name;

  /// Имя бокса Hive.
  String get boxName;

  String idOf(T value);

  Map<String, dynamic> encode(T value);

  /// null — запись не разобралась. Такую пропускаем, а не подставляем
  /// значения по умолчанию: наполовину разобранная операция с нулевой суммой
  /// хуже, чем её отсутствие.
  T? decode(Map<String, dynamic> fields);

  /// Участвует ли запись в обмене вообще.
  ///
  /// По умолчанию — да. Исключение одно, и оно объяснено в [ArticlesSync].
  bool shouldSync(T value) => true;

  /// Бокс со своим настоящим типом значений.
  ///
  /// `Hive.box<dynamic>` здесь не работает: Hive сверяет тип и на боксе,
  /// открытом как `Box<TransactionModel>`, бросает «already open and of
  /// type». В коде, обёрнутом в `try`, это выглядит как «синхронизация
  /// прошла, но ничего не нашла» — то есть как молчаливая пустота.
  Box<T>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    try {
      return Hive.box<T>(boxName);
    } catch (_) {
      return null;
    }
  }

  /// Открывает бокс, если он ещё не открыт.
  ///
  /// Сервисы открывают свои боксы лениво — при первом обращении к модулю.
  /// Журналу это не подходит: подписка, поставленная после первой правки,
  /// эту правку уже не увидит, и запись выглядела бы как «не менялась
  /// никогда».
  Future<Box<T>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<T>(boxName)
      : await Hive.openBox<T>(boxName);

  /// Все записи бокса, кроме исключённых [shouldSync]. Ключ — наш
  /// идентификатор.
  Map<String, T> local() {
    final b = box();
    if (b == null) return const {};
    final out = <String, T>{};
    for (final v in b.values) {
      if (!shouldSync(v)) continue;
      out[idOf(v)] = v;
    }
    return out;
  }

  /// Кладёт запись, разобранную из полей. false — не разобралась.
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final value = decode(fields);
    if (value == null) return false;
    await b.put(idOf(value), value);
    return true;
  }

  Future<void> removeById(String id) async => box()?.delete(id);

  /// Записи только что успешно уехали на сервер.
  ///
  /// По умолчанию не делает ничего. Нужно там, где у записи есть состояние
  /// «дошло ли» — у сообщений. Движок про такие состояния знать не должен,
  /// поэтому крючок здесь, а не в нём.
  Future<void> afterUpload(Iterable<String> ids) async {}

  /// Сообщить открытому интерфейсу, что чужие данные уже применены.
  /// Вызывается один раз на коллекцию за проход, а не на каждую запись.
  void notifyChanged() {}
}

// ------------------------------------------------------------------ помощники

/// Разбор значения перечисления по имени.
///
/// Неизвестное имя — это запись от более новой версии приложения. Возвращаем
/// [fallback], а не бросаем: одно незнакомое значение не должно ронять весь
/// проход синхронизации.
T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw is String ? raw : null;
  if (name == null) return fallback;
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime? _date(Object? raw) => raw is String ? DateTime.tryParse(raw) : null;

double? _double(Object? raw) {
  if (raw is num) return raw.toDouble();
  if (raw is String) return double.tryParse(raw);
  return null;
}

int _int(Object? raw, [int fallback = 0]) {
  if (raw is num) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? fallback;
  return fallback;
}

String _str(Object? raw, [String fallback = '']) =>
    raw is String ? raw : fallback;

String? _strOrNull(Object? raw) => raw is String ? raw : null;

List<String> _strings(Object? raw) =>
    raw is List ? [for (final e in raw) '$e'] : const [];

/// Снимок из base64. Испорченная строка — не повод ронять разбор всей
/// карточки: человек важнее его фотографии.
Uint8List? _decodePhoto(String raw) {
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

// ---------------------------------------------------------------- коллекции

class TransactionsSync extends SyncCollection<TransactionModel> {
  @override
  void notifyChanged() => TreasuryService.revision.value++;

  @override
  String get name => 'transactions';

  @override
  String get boxName => 'wesios_treasury';

  @override
  String idOf(TransactionModel value) => value.id;

  @override
  Map<String, dynamic> encode(TransactionModel value) => value.toJson()
    ..['isAnomaly'] = value.isAnomaly
    ..['zScore'] = value.zScore;

  @override
  TransactionModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final amount = _double(fields['amount']);
    final date = _date(fields['date']);
    if (id == null || amount == null || date == null) return null;
    return TransactionModel(
      id: id,
      title: _str(fields['title']),
      amount: amount,
      type: _enumByName(
          TransactionType.values, fields['type'], TransactionType.expense),
      date: date,
      category: _strOrNull(fields['category']),
      description: _strOrNull(fields['description']),
      isRecurring: fields['isRecurring'] == true,
      recurringPeriod: fields['recurringPeriod'] == null
          ? null
          : _enumByName(RecurringPeriod.values, fields['recurringPeriod'],
              RecurringPeriod.monthly),
      isAnomaly: fields['isAnomaly'] == true,
      zScore: _double(fields['zScore']),
      accountId: _strOrNull(fields['accountId']),
    );
  }
}

class AccountsSync extends SyncCollection<AccountModel> {
  @override
  void notifyChanged() => AccountService.revision.value++;

  @override
  String get name => 'accounts';

  @override
  String get boxName => 'wesios_accounts';

  @override
  String idOf(AccountModel value) => value.id;

  @override
  Map<String, dynamic> encode(AccountModel value) => {
        'id': value.id,
        'name': value.name,
        'kind': value.kind.name,
        'openingBalance': value.openingBalance,
        'colorValue': value.colorValue,
        'createdAt': value.createdAt.toIso8601String(),
        'archived': value.archived,
        'note': value.note,
      };

  @override
  AccountModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || createdAt == null) return null;
    return AccountModel(
      id: id,
      name: _str(fields['name']),
      kind: _enumByName(AccountKind.values, fields['kind'], AccountKind.cash),
      openingBalance: _double(fields['openingBalance']) ?? 0,
      colorValue: _int(fields['colorValue']),
      createdAt: createdAt,
      archived: fields['archived'] == true,
      note: _strOrNull(fields['note']),
    );
  }
}

class TasksSync extends SyncCollection<TaskModel> {
  @override
  void notifyChanged() => TaskService.revision.value++;

  @override
  String get name => 'tasks';

  @override
  String get boxName => 'wesios_tasks';

  @override
  String idOf(TaskModel value) => value.id;

  @override
  Map<String, dynamic> encode(TaskModel value) => {
        'id': value.id,
        'title': value.title,
        'description': value.description,
        'status': value.status.name,
        'priority': value.priority.name,
        'createdAt': value.createdAt.toIso8601String(),
        'dueDate': value.dueDate?.toIso8601String(),
        'assignee': value.assignee,
        'tags': value.tags,
        'order': value.order,
        'subtasks': [
          for (final s in value.subtasks) {'title': s.title, 'done': s.done},
        ],
      };

  @override
  TaskModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || createdAt == null) return null;
    final raw = fields['subtasks'];
    return TaskModel(
      id: id,
      title: _str(fields['title']),
      description: _strOrNull(fields['description']),
      status:
          _enumByName(TaskStatus.values, fields['status'], TaskStatus.backlog),
      priority: _enumByName(
          TaskPriority.values, fields['priority'], TaskPriority.normal),
      createdAt: createdAt,
      dueDate: _date(fields['dueDate']),
      assignee: _strOrNull(fields['assignee']),
      subtasks: raw is! List
          ? const []
          : [
              for (final s in raw)
                if (s is Map)
                  SubTask(title: _str(s['title']), done: s['done'] == true),
            ],
      tags: _strings(fields['tags']),
      order: _int(fields['order']),
    );
  }
}

class ArticlesSync extends SyncCollection<ArticleModel> {
  @override
  void notifyChanged() => KnowledgeService.revision.value++;

  @override
  String get name => 'articles';

  @override
  String get boxName => 'wesios_knowledge';

  @override
  String idOf(ArticleModel value) => value.id;

  /// Встроенные статьи не синхронизируются.
  ///
  /// Они живут в коде и заново раскладываются при каждом запуске, поэтому на
  /// сервере оказались бы просто копией того, что и так приезжает с
  /// обновлением. Хуже того: устройство со старой сборкой отправляло бы
  /// туда старый текст, а новое — новый, и справка начала бы спорить сама с
  /// собой. Редактировать и удалять их и так нельзя.
  @override
  bool shouldSync(ArticleModel value) => !value.builtIn;

  @override
  Map<String, dynamic> encode(ArticleModel value) => {
        'id': value.id,
        'title': value.title,
        'body': value.body,
        'section': value.section.name,
        'tags': value.tags,
        'createdAt': value.createdAt.toIso8601String(),
        'updatedAt': value.updatedAt.toIso8601String(),
        'builtIn': value.builtIn,
        'pinned': value.pinned,
        'parentId': value.parentId,
        'isFolder': value.isFolder,
      };

  @override
  ArticleModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || createdAt == null) return null;
    return ArticleModel(
      id: id,
      title: _str(fields['title']),
      body: _str(fields['body']),
      section: _enumByName(
          ArticleSection.values, fields['section'], ArticleSection.guide),
      tags: _strings(fields['tags']),
      createdAt: createdAt,
      updatedAt: _date(fields['updatedAt']) ?? createdAt,
      builtIn: fields['builtIn'] == true,
      pinned: fields['pinned'] == true,
      parentId: _strOrNull(fields['parentId']),
      isFolder: fields['isFolder'] == true,
    );
  }
}

/// Собственные события Calendar синхронизируются между устройствами.
/// Time Center (будильники/таймер/секундомер) остаётся device-local, чтобы
/// одно и то же локальное действие не срабатывало одновременно везде.
class CalendarEventsSync extends SyncCollection<dynamic> {
  @override
  void notifyChanged() {
    CalendarEventService.revision.value++;
    CalendarEventService().restoreSchedules();
  }

  @override
  String get name => 'calendar_events';

  @override
  String get boxName => CalendarEventService.boxName;

  @override
  String idOf(dynamic value) => value is Map ? '${value['id'] ?? ''}' : '';

  @override
  Map<String, dynamic> encode(dynamic value) {
    if (value is! Map) return const {};
    try {
      return CalendarEvent.fromJson(value).toJson();
    } catch (_) {
      return const {};
    }
  }

  @override
  dynamic decode(Map<String, dynamic> fields) {
    try {
      final event = CalendarEvent.fromJson(fields);
      if (event.id.isEmpty || event.title.trim().isEmpty) return null;
      return event.toJson();
    } catch (_) {
      return null;
    }
  }

  @override
  Box<dynamic>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    try {
      return Hive.box<dynamic>(boxName);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Box<dynamic>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<dynamic>(boxName)
      : await Hive.openBox<dynamic>(boxName);

  @override
  Map<String, dynamic> local() {
    final b = box();
    if (b == null) return const {};
    final out = <String, dynamic>{};
    for (final raw in b.values) {
      if (raw is! Map) continue;
      try {
        final event = CalendarEvent.fromJson(raw);
        if (event.id.isEmpty || event.title.trim().isEmpty) continue;
        out[event.id] = event.toJson();
      } catch (_) {}
    }
    return out;
  }

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final decoded = decode(fields);
    if (decoded is! Map) return false;
    final event = CalendarEvent.fromJson(decoded);
    await b.put(event.id, event.toJson());
    return true;
  }

  @override
  Future<void> removeById(String id) async => box()?.delete(id);
}

/// Состав.
///
/// Хеш и соль пароля **уезжают вместе с человеком**. Это не оплошность:
/// сотрудник, заведённый на компьютере, должен войти с телефона, а проверять
/// пароль без хеша нечем. Хеш для того и нужен — по нему пароль не
/// восстанавливается, а PBKDF2 со 60 000 итераций делает перебор дорогим.
///
/// [EmployeeModel.toPublicJson] здесь не годится по той же причине: он
/// сделан для показа карточки, а не для переноса учётной записи.
class EmployeesSync extends SyncCollection<EmployeeModel> {
  @override
  void notifyChanged() => TeamService.revision.value++;

  @override
  String get name => 'employees';

  @override
  String get boxName => 'wesios_team';

  @override
  String idOf(EmployeeModel value) => value.id;

  @override
  Map<String, dynamic> encode(EmployeeModel value) => {
        'id': value.id,
        'login': value.login,
        'fullName': value.fullName,
        'nickname': value.nickname,
        'position': value.position,
        'phone': value.phone,
        'email': value.email,
        'socials': value.socials,
        'notes': value.notes,
        'permissions': value.permissions.toJson(),
        'passwordHash': value.passwordHash,
        'passwordSalt': value.passwordSalt,
        'avatarIndex': value.avatarIndex,
        'createdAt': value.createdAt.toIso8601String(),
        'isOwner': value.isOwner,
        'demoStats': value.demoStats,
        // Снимок — в base64: JSON не умеет байты, а без снимка «аватарки
        // видны другим» перестаёт работать ровно там, где и должно —
        // на втором устройстве.
        'photo': value.photo == null ? null : base64Encode(value.photo!),
      };

  @override
  EmployeeModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || createdAt == null) return null;
    final socials = fields['socials'];
    final stats = fields['demoStats'];
    final perms = fields['permissions'];
    return EmployeeModel(
      id: id,
      login: _str(fields['login']),
      fullName: _str(fields['fullName']),
      nickname: _str(fields['nickname']),
      position: _str(fields['position']),
      phone: _str(fields['phone']),
      email: _str(fields['email']),
      socials: socials is Map
          ? {for (final e in socials.entries) '${e.key}': '${e.value}'}
          : const {},
      notes: _str(fields['notes']),
      permissions: perms is Map
          ? TeamPermissions.fromJson(Map<String, dynamic>.from(perms))
          : const TeamPermissions(),
      passwordHash: _str(fields['passwordHash']),
      passwordSalt: _str(fields['passwordSalt']),
      avatarIndex: _int(fields['avatarIndex']),
      createdAt: createdAt,
      isOwner: fields['isOwner'] == true,
      photo: fields['photo'] is String
          ? _decodePhoto(fields['photo'] as String)
          : null,
      demoStats: stats is Map
          ? {
              for (final e in stats.entries)
                if (_double(e.value) != null) '${e.key}': _double(e.value)!,
            }
          : const {},
    );
  }
}

/// Разговоры.
///
/// Уезжают **только рабочие** — см. [ChatEnvelopePolicy.travels], там же
/// написано, почему личные остаются на устройстве и что должно появиться,
/// чтобы это изменилось.
class ChatsSync extends SyncCollection<ChatThread> {
  @override
  void notifyChanged() => ChatService.revision.value++;

  @override
  String get name => 'chats';

  @override
  String get boxName => 'wesios_chats';

  @override
  String idOf(ChatThread value) => value.id;

  @override
  bool shouldSync(ChatThread value) => ChatEnvelopePolicy.travels(value.kind);

  /// `lastOpenedAt` в [ChatThread.toJson] намеренно нет: «докуда я дочитал» —
  /// это про устройство, а не про разговор. Уехав на сервер, эта отметка
  /// обнуляла бы непрочитанное на телефоне каждый раз, когда человек
  /// заглядывает в тот же чат с компьютера.
  @override
  Map<String, dynamic> encode(ChatThread value) => value.toJson();

  @override
  ChatThread? decode(Map<String, dynamic> fields) =>
      ChatThread.tryParse(fields);

  /// Своя отметка о прочтении переживает приезд чужой правки.
  ///
  /// Без этого достаточно было бы, чтобы кто-то переименовал группу, — и всё
  /// непрочитанное во всех разговорах на этом устройстве обнулилось бы разом,
  /// потому что запись легла бы поверх местной целиком.
  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final incoming = decode(fields);
    if (incoming == null) return false;
    final mine = b.get(incoming.id);
    await b.put(
      incoming.id,
      mine == null
          ? incoming
          : incoming.copyWith(lastOpenedAt: mine.lastOpenedAt),
    );
    return true;
  }
}

/// Сообщения.
///
/// Две вещи, которые здесь важнее самого переноса.
///
/// **Архивное не уезжает и не удаляется чужим надгробием.** Архив — это то,
/// что человек решил сохранить у себя навсегда; он и заведён как местное
/// решение. Отправлять его на сервер незачем, а позволить удалению с чужого
/// устройства до него дотянуться — значит сломать единственное обещание,
/// которое архив даёт.
///
/// **Личная переписка не уезжает вовсе**, пока нет конвертного шифрования, —
/// по той же причине, что и сами личные чаты.
class MessagesSync extends SyncCollection<ChatMessage> {
  @override
  void notifyChanged() {
    MessageStore.revision.value++;
    ChatService.revision.value++;
  }

  @override
  String get name => 'messages';

  @override
  String get boxName => 'wesios_messages';

  @override
  String idOf(ChatMessage value) => value.id;

  @override
  bool shouldSync(ChatMessage value) {
    if (value.archived) return false;
    final chat = _chatOf(value.chatId);
    // Сообщение без разговора — либо мусор, либо приехало вперёд своего
    // чата. И то и другое лучше пропустить: отправлять переписку, про
    // которую неизвестно, личная она или рабочая, нельзя.
    return chat != null && ChatEnvelopePolicy.travels(chat.kind);
  }

  /// Состояние доставки наружу **не уезжает**.
  ///
  /// «Моё сообщение ушло с этого телефона» — факт про этот телефон, и
  /// собеседнику он не сообщает ничего. Уехав, он бы ещё и перетирал
  /// местное состояние на других устройствах владельца.
  ///
  /// Приехавшее сообщение получает [DeliveryState.sent] по умолчанию — и
  /// это правда: раз оно приехало, оно точно было отправлено.
  @override
  Map<String, dynamic> encode(ChatMessage value) =>
      value.toJson()..remove('state');

  @override
  ChatMessage? decode(Map<String, dynamic> fields) =>
      ChatMessage.tryParse(fields);

  /// Сообщение уехало — значит оно отправлено, и человеку пора это увидеть.
  ///
  /// До этого крючка состояние не менялось никогда: `markState` существовал,
  /// но его никто не вызывал, и галочка под своим сообщением оставалась
  /// «часиками» навсегда.
  ///
  /// **Отметка в журнале сохраняется прежней.** Иначе получилась бы качель:
  /// пометили «отправлено» → журнал увидел правку → на следующем проходе
  /// сообщение уехало снова → снова пометили. И так до бесконечности.
  @override
  Future<void> afterUpload(Iterable<String> ids) async {
    final b = box();
    if (b == null) return;
    for (final id in ids) {
      final m = b.get(id);
      if (m == null || m.state != DeliveryState.pending) continue;
      final stamp = SyncJournal.stampOf(name, id);
      if (stamp != null) SyncJournal.expect(name, id, stamp);
      await b.put(id, m.copyWith(state: DeliveryState.sent));
    }
  }

  /// Надгробие не дотягивается до архива.
  ///
  /// Проверка стоит здесь, а не только в [MessageStore.remove]: удаление,
  /// приехавшее с другого устройства, идёт мимо неё — прямо в бокс.
  @override
  Future<void> removeById(String id) async {
    final b = box();
    if (b == null) return;
    if (b.get(id)?.archived == true) return;
    await b.delete(id);
  }

  static ChatThread? _chatOf(String chatId) {
    if (!Hive.isBoxOpen('wesios_chats')) return null;
    try {
      return Hive.box<ChatThread>('wesios_chats').get(chatId);
    } catch (_) {
      return null;
    }
  }
}

/// Что синхронизируется.
class SyncCodec {
  /// Порядок важен: счета приезжают раньше операций, чтобы операция не
  /// провела в интерфейсе ни одного кадра, ссылаясь на ещё не приехавший
  /// счёт.
  ///
  /// По той же причине состав идёт раньше разговоров, а разговоры — раньше
  /// сообщений: сообщение без своего чата не пройдёт даже отбор
  /// ([MessagesSync.shouldSync]), а чат без людей показался бы разговором с
  /// пустым именем.
  static final List<SyncCollection<dynamic>> collections = [
    AccountsSync(),
    TransactionsSync(),
    TasksSync(),
    CalendarEventsSync(),
    ArticlesSync(),
    EmployeesSync(),
    ChatsSync(),
    MessagesSync(),
    // Проекты и вехи дорожной карты — описаны в sync_codec_roadmap.dart.
    RoadmapProjectsSync(),
    RoadmapItemsSync(),
    // Клиенты, сделки и касания — описаны в sync_codec_crm.dart.
    CrmClientsSync(),
    CrmDealsSync(),
    CrmInteractionsSync(),
    // Каталог битов: карточки едут, файлы остаются на своём устройстве.
    AudioBeatsSync(),
    // Профиль человека — одна запись на все его устройства.
    ProfileSync(),
  ];

  static SyncCollection<dynamic>? byName(String name) {
    for (final c in collections) {
      if (c.name == name) return c;
    }
    return null;
  }

  /// Боксы, за которыми должен следить журнал.
  static List<String> get boxNames => [for (final c in collections) c.boxName];
}
