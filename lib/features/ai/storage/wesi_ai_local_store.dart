import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/wesi_ai_chat_models.dart';

enum WesiAiPendingQueueStatus { queued, inflight, completed }

class WesiAiPendingQueueItem {
  final String id;
  final String employeeId;
  final String conversationId;
  final String text;
  final DateTime queuedAt;
  final String processSessionId;
  final WesiAiPendingQueueStatus status;
  final List<Map<String, dynamic>> attachments;

  const WesiAiPendingQueueItem({
    required this.id,
    required this.employeeId,
    required this.conversationId,
    required this.text,
    required this.queuedAt,
    required this.processSessionId,
    required this.status,
    this.attachments = const <Map<String, dynamic>>[],
  });

  WesiAiPendingQueueItem copyWith({
    String? processSessionId,
    WesiAiPendingQueueStatus? status,
  }) =>
      WesiAiPendingQueueItem(
        id: id,
        employeeId: employeeId,
        conversationId: conversationId,
        text: text,
        queuedAt: queuedAt,
        processSessionId: processSessionId ?? this.processSessionId,
        status: status ?? this.status,
        attachments: attachments,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'id': id,
        'employeeId': employeeId,
        'conversationId': conversationId,
        'text': text,
        'queuedAt': queuedAt.toUtc().toIso8601String(),
        'processSessionId': processSessionId,
        'status': status.name,
        if (attachments.isNotEmpty) 'attachments': attachments,
      };

  factory WesiAiPendingQueueItem.fromJson(
    Map<String, dynamic> json, {
    required String expectedEmployeeId,
  }) {
    final id = '${json['id'] ?? ''}'.trim();
    final employeeId = '${json['employeeId'] ?? ''}'.trim();
    final conversationId = '${json['conversationId'] ?? ''}'.trim();
    final text = '${json['text'] ?? ''}';
    final processSessionId = '${json['processSessionId'] ?? ''}'.trim();
    final queuedAt = DateTime.tryParse('${json['queuedAt'] ?? ''}');
    if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id) ||
        employeeId != expectedEmployeeId ||
        conversationId.isEmpty ||
        conversationId.length > 180 ||
        text.length > 32000 ||
        processSessionId.isEmpty ||
        processSessionId.length > 180 ||
        queuedAt == null) {
      throw const FormatException('Invalid Wesi AI pending queue item');
    }

    WesiAiPendingQueueStatus? status;
    final rawStatus = '${json['status'] ?? ''}';
    for (final candidate in WesiAiPendingQueueStatus.values) {
      if (candidate.name == rawStatus) {
        status = candidate;
        break;
      }
    }
    if (status == null) {
      throw const FormatException('Invalid Wesi AI pending queue status');
    }

    final attachments = <Map<String, dynamic>>[];
    final rawAttachments = json['attachments'];
    if (rawAttachments is List) {
      if (rawAttachments.length > 4) {
        throw const FormatException('Too many pending attachment records');
      }
      for (final raw in rawAttachments) {
        if (raw is! Map) {
          throw const FormatException('Invalid pending attachment record');
        }
        final map = Map<String, dynamic>.from(raw);
        final name = '${map['name'] ?? ''}'.trim();
        final mimeType = '${map['mimeType'] ?? ''}'.trim();
        final byteSize = map['byteSize'];
        if (name.isEmpty ||
            name.length > 180 ||
            mimeType.isEmpty ||
            mimeType.length > 120 ||
            byteSize is! int ||
            byteSize <= 0 ||
            byteSize > 256 * 1024 * 1024) {
          throw const FormatException('Invalid pending attachment metadata');
        }
        attachments.add(<String, dynamic>{
          'name': name,
          'mimeType': mimeType,
          'byteSize': byteSize,
        });
      }
    }

    return WesiAiPendingQueueItem(
      id: id,
      employeeId: employeeId,
      conversationId: conversationId,
      text: text,
      queuedAt: queuedAt.toLocal(),
      processSessionId: processSessionId,
      status: status,
      attachments: List<Map<String, dynamic>>.unmodifiable(attachments),
    );
  }
}

class WesiAiLocalStore {
  static const String boxName = 'wesios_ai_local_v1';
  static const int schemaVersion = 2;
  final String employeeId;
  const WesiAiLocalStore(this.employeeId);

  String get _stateKey => 'employee:$employeeId';
  String get _corruptBackupKey => 'employee:$employeeId:corrupt-backup';
  String get _pendingQueuePrefix => 'employee:$employeeId:pending-queue:';

  Future<Box<String>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  Future<WesiAiLocalState> load() async {
    final box = await _box();
    final raw = box.get(_stateKey);
    if (raw == null || raw.isEmpty) return WesiAiLocalState.empty(employeeId);
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map)
        throw const FormatException('AI state is not an object');
      return WesiAiLocalState.fromJson(
        Map<String, dynamic>.from(decoded),
        expectedEmployeeId: employeeId,
      );
    } catch (_) {
      // Повреждённый/несовместимый локальный state не должен блокировать весь
      // AI-модуль. Сохраняем только одну последнюю копию для диагностики и
      // стартуем чистое состояние текущего сотрудника.
      try {
        await box.put(_corruptBackupKey, raw);
      } catch (_) {}
      try {
        await box.delete(_stateKey);
      } catch (_) {}
      return WesiAiLocalState.empty(employeeId);
    }
  }

  Future<void> save(WesiAiLocalState state) async {
    if (state.employeeId != employeeId) throw StateError('Employee mismatch');
    final box = await _box();
    await box.put(_stateKey, jsonEncode(state.toJson()));
  }

  Future<List<WesiAiPendingQueueItem>> loadPendingQueueItems() async {
    final box = await _box();
    final result = <WesiAiPendingQueueItem>[];
    final corruptKeys = <String>[];
    for (final rawKey in box.keys) {
      final key = '$rawKey';
      if (!key.startsWith(_pendingQueuePrefix)) continue;
      final raw = box.get(key);
      if (raw == null || raw.trim().isEmpty) {
        corruptKeys.add(key);
        continue;
      }
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map)
          throw const FormatException('Pending item is not an object');
        final item = WesiAiPendingQueueItem.fromJson(
          Map<String, dynamic>.from(decoded),
          expectedEmployeeId: employeeId,
        );
        if (key != '$_pendingQueuePrefix${item.id}') {
          throw const FormatException('Pending item key mismatch');
        }
        result.add(item);
      } catch (_) {
        corruptKeys.add(key);
      }
    }
    for (final key in corruptKeys) {
      try {
        await box.delete(key);
      } catch (_) {}
    }
    result.sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return result;
  }

  Future<void> savePendingQueueItem(WesiAiPendingQueueItem item) async {
    if (item.employeeId != employeeId) throw StateError('Employee mismatch');
    final box = await _box();
    await box.put('$_pendingQueuePrefix${item.id}', jsonEncode(item.toJson()));
  }

  Future<void> removePendingQueueItem(String id) async {
    if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id)) return;
    final box = await _box();
    await box.delete('$_pendingQueuePrefix$id');
  }

  Future<void> removePendingQueueForConversation(String conversationId) async {
    final items = await loadPendingQueueItems();
    for (final item in items) {
      if (item.conversationId == conversationId) {
        await removePendingQueueItem(item.id);
      }
    }
  }

  static String namespaceFor(String employeeId) => 'employee:$employeeId';
}

class WesiAiLocalState {
  final String employeeId;
  final WesiAiTier tier;
  final String? activeConversationId;
  final String? activeProjectId;
  final List<WesiAiProject> projects;
  final List<WesiAiConversation> conversations;
  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;

  const WesiAiLocalState({
    required this.employeeId,
    required this.tier,
    required this.activeConversationId,
    required this.activeProjectId,
    required this.projects,
    required this.conversations,
    required this.messages,
    required this.memory,
  });

  factory WesiAiLocalState.empty(String employeeId) => WesiAiLocalState(
        employeeId: employeeId,
        tier: WesiAiTier.fast,
        activeConversationId: null,
        activeProjectId: null,
        projects: const [],
        conversations: const [],
        messages: const [],
        memory: const WesiAiMemorySnapshot(),
      );

  WesiAiConversation? get activeConversation {
    final id = activeConversationId;
    if (id == null) return null;
    for (final item in conversations) {
      if (item.id == id) return item;
    }
    return null;
  }

  WesiAiProject? get activeProject {
    final id = activeProjectId;
    if (id == null) return null;
    for (final item in projects) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<WesiAiMessage> messagesFor(String conversationId) {
    final result = messages
        .where((m) =>
            m.employeeId == employeeId && m.conversationId == conversationId)
        .toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  WesiAiLocalState copyWith({
    WesiAiTier? tier,
    String? activeConversationId,
    bool clearActiveConversation = false,
    String? activeProjectId,
    bool clearActiveProject = false,
    List<WesiAiProject>? projects,
    List<WesiAiConversation>? conversations,
    List<WesiAiMessage>? messages,
    WesiAiMemorySnapshot? memory,
  }) =>
      WesiAiLocalState(
        employeeId: employeeId,
        tier: tier ?? this.tier,
        activeConversationId: clearActiveConversation
            ? null
            : (activeConversationId ?? this.activeConversationId),
        activeProjectId: clearActiveProject
            ? null
            : (activeProjectId ?? this.activeProjectId),
        projects: projects ?? this.projects,
        conversations: conversations ?? this.conversations,
        messages: messages ?? this.messages,
        memory: memory ?? this.memory,
      );

  Map<String, dynamic> toJson() => {
        'schemaVersion': WesiAiLocalStore.schemaVersion,
        'employeeId': employeeId,
        'tier': tier.name,
        'activeConversationId': activeConversationId,
        'activeProjectId': activeProjectId,
        'projects': projects.map((e) => e.toJson()).toList(),
        'conversations': conversations.map((e) => e.toJson()).toList(),
        'messages': messages.map((e) => e.toJson()).toList(),
        'memory': memory.toJson(),
      };

  factory WesiAiLocalState.fromJson(Map<String, dynamic> json,
      {required String expectedEmployeeId}) {
    final storedEmployeeId = json['employeeId'] as String? ?? '';
    if (storedEmployeeId != expectedEmployeeId)
      throw StateError('Employee mismatch');

    final projects = <WesiAiProject>[];
    for (final raw in (json['projects'] as List? ?? const [])) {
      try {
        if (raw is! Map) continue;
        final project = WesiAiProject.fromJson(Map<String, dynamic>.from(raw));
        if (project.employeeId == expectedEmployeeId) projects.add(project);
      } catch (_) {}
    }
    final projectIds = projects.map((project) => project.id).toSet();

    final conversations = <WesiAiConversation>[];
    for (final raw in (json['conversations'] as List? ?? const [])) {
      try {
        if (raw is! Map) continue;
        var conversation =
            WesiAiConversation.fromJson(Map<String, dynamic>.from(raw));
        if (conversation.employeeId != expectedEmployeeId) continue;
        if (conversation.projectId != null &&
            !projectIds.contains(conversation.projectId)) {
          conversation = conversation.copyWith(clearProject: true);
        }
        conversations.add(conversation);
      } catch (_) {}
    }
    final conversationIds =
        conversations.map((conversation) => conversation.id).toSet();

    final messages = <WesiAiMessage>[];
    for (final raw in (json['messages'] as List? ?? const [])) {
      try {
        if (raw is! Map) continue;
        final message = WesiAiMessage.fromJson(Map<String, dynamic>.from(raw));
        if (message.employeeId == expectedEmployeeId &&
            conversationIds.contains(message.conversationId)) {
          messages.add(message);
        }
      } catch (_) {}
    }

    WesiAiTier tier = WesiAiTier.fast;
    final rawTier = '${json['tier'] ?? 'fast'}';
    for (final candidate in WesiAiTier.values) {
      if (candidate.name == rawTier) {
        tier = candidate;
        break;
      }
    }

    final rawActiveConversation = json['activeConversationId'] as String?;
    WesiAiConversation? activeConversation;
    if (rawActiveConversation != null) {
      for (final conversation in conversations) {
        if (conversation.id == rawActiveConversation &&
            !conversation.archived) {
          activeConversation = conversation;
          break;
        }
      }
    }

    final rawActiveProject = json['activeProjectId'] as String?;
    String? activeProjectId;
    if (activeConversation != null) {
      // Активный чат является более сильным источником истины: проект в UI
      // обязан совпадать с projectId этого чата после миграции/переноса.
      activeProjectId = activeConversation.projectId;
    } else if (rawActiveProject != null &&
        projectIds.contains(rawActiveProject)) {
      activeProjectId = rawActiveProject;
    }

    WesiAiMemorySnapshot memory = const WesiAiMemorySnapshot();
    try {
      final rawMemory = json['memory'];
      if (rawMemory is Map) {
        memory =
            WesiAiMemorySnapshot.fromJson(Map<String, dynamic>.from(rawMemory));
      }
    } catch (_) {}

    return WesiAiLocalState(
      employeeId: expectedEmployeeId,
      tier: tier,
      activeConversationId: activeConversation?.id,
      activeProjectId: activeProjectId,
      projects: projects,
      conversations: conversations,
      messages: messages,
      memory: memory,
    );
  }
}
