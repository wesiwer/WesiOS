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
import '../../features/knowledge/models/article_model.dart';
import '../../features/knowledge/services/knowledge_service.dart';
import '../../features/organizations/models/inter_org_transfer_model.dart';
import '../../features/organizations/models/organization_access_grant.dart';
import '../../features/organizations/models/organization_model.dart';
import '../../features/organizations/models/transaction_audit_model.dart';
import '../../features/organizations/services/inter_org_transfer_service.dart';
import '../../features/organizations/services/organization_access_service.dart';
import '../../features/organizations/services/organization_service.dart';
import '../../features/tasks/models/task_model.dart';
import '../../features/tasks/services/task_service.dart';
import '../../features/team/models/employee_model.dart';
import '../../features/team/models/team_permissions.dart';
import '../../features/team/services/team_service.dart';
import '../../features/treasury/models/account_model.dart';
import '../../features/treasury/models/transaction_model.dart';
import '../../features/treasury/services/account_service.dart';
import '../../features/treasury/services/treasury_service.dart';
import 'sync_journal.dart';

abstract class SyncCollection<T> {
  String get name;
  String get boxName;
  String idOf(T value);
  Map<String, dynamic> encode(T value);
  T? decode(Map<String, dynamic> fields);
  bool shouldSync(T value) => true;

  Box<T>? box() {
    if (!Hive.isBoxOpen(boxName)) return null;
    try {
      return Hive.box<T>(boxName);
    } catch (_) {
      return null;
    }
  }

  Future<Box<T>> ensureBox() async => Hive.isBoxOpen(boxName)
      ? Hive.box<T>(boxName)
      : await Hive.openBox<T>(boxName);

  Map<String, T> local() {
    final b = box();
    if (b == null) return const {};
    final out = <String, T>{};
    for (final value in b.values) {
      if (shouldSync(value)) out[idOf(value)] = value;
    }
    return out;
  }

  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final value = decode(fields);
    if (value == null) return false;
    await b.put(idOf(value), value);
    return true;
  }

  Future<void> removeById(String id) async => box()?.delete(id);
  Future<void> afterUpload(Iterable<String> ids) async {}
  void notifyChanged() {}
}

T _enumByName<T extends Enum>(List<T> values, Object? raw, T fallback) {
  final name = raw is String ? raw : null;
  if (name == null) return fallback;
  for (final value in values) {
    if (value.name == name) return value;
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

Uint8List? _decodePhoto(String raw) {
  try {
    return base64Decode(raw);
  } catch (_) {
    return null;
  }
}

class OrganizationsSync extends SyncCollection<OrganizationModel> {
  @override
  String get name => 'organizations';
  @override
  String get boxName => OrganizationService.boxName;
  @override
  String idOf(OrganizationModel value) => value.id;
  @override
  void notifyChanged() => OrganizationService.revision.value++;

  @override
  Map<String, dynamic> encode(OrganizationModel value) => value.toJson();

  @override
  OrganizationModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final name = _strOrNull(fields['name']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || name == null || createdAt == null) return null;
    return OrganizationModel(
      id: id,
      name: name,
      parentId: _strOrNull(fields['parentId']),
      isRoot: fields['isRoot'] == true,
      baseCurrency: _str(fields['baseCurrency'], 'RUB'),
      status: _enumByName(
        OrganizationStatus.values,
        fields['status'],
        OrganizationStatus.active,
      ),
      createdAt: createdAt,
      updatedAt: _date(fields['updatedAt']) ?? createdAt,
      createdBy: _str(fields['createdBy'], 'sync'),
      code: _strOrNull(fields['code']),
      description: _strOrNull(fields['description']),
      colorValue: fields['colorValue'] == null ? null : _int(fields['colorValue']),
      sortOrder: _int(fields['sortOrder']),
    );
  }
}

class AccountsSync extends SyncCollection<AccountModel> {
  @override
  String get name => 'accounts';
  @override
  String get boxName => 'wesios_accounts';
  @override
  String idOf(AccountModel value) => value.id;
  @override
  void notifyChanged() => AccountService.revision.value++;

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
        'organizationId': value.organizationId,
        'minimumBalance': value.minimumBalance,
        'allowNetting': value.allowNetting,
        'currency': value.currency,
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
      organizationId: _strOrNull(fields['organizationId']),
      minimumBalance: _double(fields['minimumBalance']) ?? 0,
      allowNetting: fields['allowNetting'] != false,
      currency: _str(fields['currency'], 'RUB'),
    );
  }
}

class TransactionsSync extends SyncCollection<TransactionModel> {
  @override
  String get name => 'transactions';
  @override
  String get boxName => 'wesios_treasury';
  @override
  String idOf(TransactionModel value) => value.id;
  @override
  void notifyChanged() => TreasuryService.revision.value++;

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
        TransactionType.values,
        fields['type'],
        TransactionType.expense,
      ),
      date: date,
      category: _strOrNull(fields['category']),
      description: _strOrNull(fields['description']),
      isRecurring: fields['isRecurring'] == true,
      recurringPeriod: fields['recurringPeriod'] == null
          ? null
          : _enumByName(
              RecurringPeriod.values,
              fields['recurringPeriod'],
              RecurringPeriod.monthly,
            ),
      isAnomaly: fields['isAnomaly'] == true,
      zScore: _double(fields['zScore']),
      accountId: _strOrNull(fields['accountId']),
      organizationId: _strOrNull(fields['organizationId']),
      projectId: _strOrNull(fields['projectId']),
      counterpartyId: _strOrNull(fields['counterpartyId']),
      source: _enumByName(
        TransactionSource.values,
        fields['source'],
        TransactionSource.manual,
      ),
      createdBy: _strOrNull(fields['createdBy']),
      updatedBy: _strOrNull(fields['updatedBy']),
      updatedAt: _date(fields['updatedAt']),
      ownerEmployeeId: _strOrNull(fields['ownerEmployeeId']),
      interOrgTransferId: _strOrNull(fields['interOrgTransferId']),
      createdByEmployeeId: _strOrNull(fields['createdByEmployeeId']),
    );
  }
}

class TasksSync extends SyncCollection<TaskModel> {
  @override
  String get name => 'tasks';
  @override
  String get boxName => 'wesios_tasks';
  @override
  String idOf(TaskModel value) => value.id;
  @override
  void notifyChanged() => TaskService.revision.value++;

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
      status: _enumByName(TaskStatus.values, fields['status'], TaskStatus.backlog),
      priority: _enumByName(
        TaskPriority.values,
        fields['priority'],
        TaskPriority.normal,
      ),
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

class CalendarEventsSync extends SyncCollection<dynamic> {
  @override
  String get name => 'calendar_events';
  @override
  String get boxName => CalendarEventService.boxName;
  @override
  String idOf(dynamic value) => value is Map ? '${value['id'] ?? ''}' : '';
  @override
  void notifyChanged() {
    CalendarEventService.revision.value++;
    CalendarEventService().restoreSchedules();
  }

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
}

class ArticlesSync extends SyncCollection<ArticleModel> {
  @override
  String get name => 'articles';
  @override
  String get boxName => 'wesios_knowledge';
  @override
  String idOf(ArticleModel value) => value.id;
  @override
  void notifyChanged() => KnowledgeService.revision.value++;
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
        ArticleSection.values,
        fields['section'],
        ArticleSection.guide,
      ),
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

class EmployeesSync extends SyncCollection<EmployeeModel> {
  @override
  String get name => 'employees';
  @override
  String get boxName => 'wesios_team';
  @override
  String idOf(EmployeeModel value) => value.id;
  @override
  void notifyChanged() => TeamService.revision.value++;

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

class OrganizationGrantsSync extends SyncCollection<OrganizationAccessGrant> {
  @override
  String get name => 'organization_grants';
  @override
  String get boxName => OrganizationAccessService.boxName;
  @override
  String idOf(OrganizationAccessGrant value) => value.id;
  @override
  void notifyChanged() => OrganizationAccessService.revision.value++;

  @override
  Map<String, dynamic> encode(OrganizationAccessGrant value) => {
        'id': value.id,
        'employeeId': value.employeeId,
        'organizationId': value.organizationId,
        'includeSubtree': value.includeSubtree,
        'canViewTeamFinance': value.canViewTeamFinance,
        'canViewSelfFinance': value.canViewSelfFinance,
        'permissions': value.permissions,
        'createdAt': value.createdAt.toIso8601String(),
        'updatedAt': value.updatedAt.toIso8601String(),
        'createdBy': value.createdBy,
      };

  @override
  OrganizationAccessGrant? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final employeeId = _strOrNull(fields['employeeId']);
    final organizationId = _strOrNull(fields['organizationId']);
    final createdAt = _date(fields['createdAt']);
    if (id == null || employeeId == null || organizationId == null || createdAt == null) {
      return null;
    }
    return OrganizationAccessGrant(
      id: id,
      employeeId: employeeId,
      organizationId: organizationId,
      includeSubtree: fields['includeSubtree'] == true,
      canViewTeamFinance: fields['canViewTeamFinance'] == true,
      canViewSelfFinance: fields['canViewSelfFinance'] != false,
      permissions: _strings(fields['permissions']),
      createdAt: createdAt,
      updatedAt: _date(fields['updatedAt']) ?? createdAt,
      createdBy: _str(fields['createdBy'], 'sync'),
    );
  }
}

class InterOrgTransfersSync extends SyncCollection<InterOrgTransferModel> {
  @override
  String get name => 'inter_org_transfers';
  @override
  String get boxName => InterOrgTransferService.boxName;
  @override
  String idOf(InterOrgTransferModel value) => value.id;
  @override
  void notifyChanged() => InterOrgTransferService.revision.value++;

  @override
  Map<String, dynamic> encode(InterOrgTransferModel value) => {
        'id': value.id,
        'fromOrganizationId': value.fromOrganizationId,
        'toOrganizationId': value.toOrganizationId,
        'fromAccountId': value.fromAccountId,
        'toAccountId': value.toAccountId,
        'amount': value.amount,
        'currency': value.currency,
        'amountInFromOrgBase': value.amountInFromOrgBase,
        'amountInToOrgBase': value.amountInToOrgBase,
        'type': value.type.name,
        'note': value.note,
        'date': value.date.toIso8601String(),
        'createdBy': value.createdBy,
        'createdAt': value.createdAt.toIso8601String(),
        'linkedDebitTransactionId': value.linkedDebitTransactionId,
        'linkedCreditTransactionId': value.linkedCreditTransactionId,
        'cancelled': value.cancelled,
        'cancelledAt': value.cancelledAt?.toIso8601String(),
        'cancelledBy': value.cancelledBy,
      };

  @override
  InterOrgTransferModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final fromOrg = _strOrNull(fields['fromOrganizationId']);
    final toOrg = _strOrNull(fields['toOrganizationId']);
    final fromAccount = _strOrNull(fields['fromAccountId']);
    final toAccount = _strOrNull(fields['toAccountId']);
    final amount = _double(fields['amount']);
    final date = _date(fields['date']);
    final createdAt = _date(fields['createdAt']);
    final debit = _strOrNull(fields['linkedDebitTransactionId']);
    final credit = _strOrNull(fields['linkedCreditTransactionId']);
    if (id == null ||
        fromOrg == null ||
        toOrg == null ||
        fromAccount == null ||
        toAccount == null ||
        amount == null ||
        date == null ||
        createdAt == null ||
        debit == null ||
        credit == null) {
      return null;
    }
    return InterOrgTransferModel(
      id: id,
      fromOrganizationId: fromOrg,
      toOrganizationId: toOrg,
      fromAccountId: fromAccount,
      toAccountId: toAccount,
      amount: amount,
      currency: _str(fields['currency'], 'RUB'),
      amountInFromOrgBase: _double(fields['amountInFromOrgBase']) ?? amount,
      amountInToOrgBase: _double(fields['amountInToOrgBase']) ?? amount,
      type: _enumByName(
        InterOrgTransferType.values,
        fields['type'],
        InterOrgTransferType.other,
      ),
      note: _strOrNull(fields['note']),
      date: date,
      createdBy: _str(fields['createdBy'], 'sync'),
      createdAt: createdAt,
      linkedDebitTransactionId: debit,
      linkedCreditTransactionId: credit,
      cancelled: fields['cancelled'] == true,
      cancelledAt: _date(fields['cancelledAt']),
      cancelledBy: _strOrNull(fields['cancelledBy']),
    );
  }
}

class TransactionAuditsSync extends SyncCollection<TransactionAuditModel> {
  @override
  String get name => 'transaction_audit';
  @override
  String get boxName => 'wesios_transaction_audit';
  @override
  String idOf(TransactionAuditModel value) => value.id;

  @override
  Map<String, dynamic> encode(TransactionAuditModel value) => {
        'id': value.id,
        'transactionId': value.transactionId,
        'changedBy': value.changedBy,
        'changedAt': value.changedAt.toIso8601String(),
        'beforeJson': value.beforeJson,
        'afterJson': value.afterJson,
        'reason': value.reason,
        'organizationId': value.organizationId,
      };

  @override
  TransactionAuditModel? decode(Map<String, dynamic> fields) {
    final id = _strOrNull(fields['id']);
    final transactionId = _strOrNull(fields['transactionId']);
    final changedAt = _date(fields['changedAt']);
    if (id == null || transactionId == null || changedAt == null) return null;
    return TransactionAuditModel(
      id: id,
      transactionId: transactionId,
      changedBy: _str(fields['changedBy'], 'sync'),
      changedAt: changedAt,
      beforeJson: _strOrNull(fields['beforeJson']),
      afterJson: _strOrNull(fields['afterJson']),
      reason: _strOrNull(fields['reason']),
      organizationId: _str(
        fields['organizationId'],
        OrganizationModel.wesiBeatsId,
      ),
    );
  }
}

class ChatsSync extends SyncCollection<ChatThread> {
  @override
  String get name => 'chats';
  @override
  String get boxName => 'wesios_chats';
  @override
  String idOf(ChatThread value) => value.id;
  @override
  void notifyChanged() => ChatService.revision.value++;
  @override
  bool shouldSync(ChatThread value) => ChatEnvelopePolicy.travels(value.kind);
  @override
  Map<String, dynamic> encode(ChatThread value) => value.toJson();
  @override
  ChatThread? decode(Map<String, dynamic> fields) => ChatThread.tryParse(fields);

  @override
  Future<bool> applyFields(Map<String, dynamic> fields) async {
    final b = box();
    if (b == null) return false;
    final incoming = decode(fields);
    if (incoming == null) return false;
    final mine = b.get(incoming.id);
    await b.put(
      incoming.id,
      mine == null ? incoming : incoming.copyWith(lastOpenedAt: mine.lastOpenedAt),
    );
    return true;
  }
}

class MessagesSync extends SyncCollection<ChatMessage> {
  @override
  String get name => 'messages';
  @override
  String get boxName => 'wesios_messages';
  @override
  String idOf(ChatMessage value) => value.id;
  @override
  void notifyChanged() {
    MessageStore.revision.value++;
    ChatService.revision.value++;
  }

  @override
  bool shouldSync(ChatMessage value) {
    if (value.archived) return false;
    final chat = _chatOf(value.chatId);
    return chat != null && ChatEnvelopePolicy.travels(chat.kind);
  }

  @override
  Map<String, dynamic> encode(ChatMessage value) =>
      value.toJson()..remove('state');
  @override
  ChatMessage? decode(Map<String, dynamic> fields) => ChatMessage.tryParse(fields);

  @override
  Future<void> afterUpload(Iterable<String> ids) async {
    final b = box();
    if (b == null) return;
    for (final id in ids) {
      final message = b.get(id);
      if (message == null || message.state != DeliveryState.pending) continue;
      final stamp = SyncJournal.stampOf(name, id);
      if (stamp != null) SyncJournal.expect(name, id, stamp);
      await b.put(id, message.copyWith(state: DeliveryState.sent));
    }
  }

  @override
  Future<void> removeById(String id) async {
    final b = box();
    if (b == null || b.get(id)?.archived == true) return;
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

class SyncCodec {
  /// Referential parents are synchronized before their children. In
  /// particular an organization arrives before accounts/transactions, and an
  /// employee arrives before access grants.
  static final List<SyncCollection<dynamic>> collections = [
    OrganizationsSync(),
    AccountsSync(),
    TransactionsSync(),
    TasksSync(),
    CalendarEventsSync(),
    ArticlesSync(),
    EmployeesSync(),
    OrganizationGrantsSync(),
    InterOrgTransfersSync(),
    TransactionAuditsSync(),
    ChatsSync(),
    MessagesSync(),
  ];

  static SyncCollection<dynamic>? byName(String name) {
    for (final collection in collections) {
      if (collection.name == name) return collection;
    }
    return null;
  }

  static List<String> get boxNames => [for (final c in collections) c.boxName];
}
