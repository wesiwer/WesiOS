import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/wesi_ai_chat_models.dart';

class WesiAiLocalStore {
  static const String boxName = 'wesios_ai_local_v1';
  final String employeeId;
  const WesiAiLocalStore(this.employeeId);

  String get _stateKey => 'employee:$employeeId';

  Future<Box<String>> _box() async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<String>(boxName);
    return Hive.openBox<String>(boxName);
  }

  Future<WesiAiLocalState> load() async {
    final box = await _box();
    final raw = box.get(_stateKey);
    if (raw == null || raw.isEmpty) return WesiAiLocalState.empty(employeeId);
    return WesiAiLocalState.fromJson(jsonDecode(raw) as Map<String, dynamic>, expectedEmployeeId: employeeId);
  }

  Future<void> save(WesiAiLocalState state) async {
    if (state.employeeId != employeeId) throw StateError('Employee mismatch');
    final box = await _box();
    await box.put(_stateKey, jsonEncode(state.toJson()));
  }

  static String namespaceFor(String employeeId) => 'employee:$employeeId';
}

class WesiAiLocalState {
  final String employeeId;
  final WesiAiTier tier;
  final String? activeConversationId;
  final List<WesiAiConversation> conversations;
  final List<WesiAiMessage> messages;
  final WesiAiMemorySnapshot memory;

  const WesiAiLocalState({required this.employeeId, required this.tier, required this.activeConversationId, required this.conversations, required this.messages, required this.memory});

  factory WesiAiLocalState.empty(String employeeId) => WesiAiLocalState(employeeId: employeeId, tier: WesiAiTier.fast, activeConversationId: null, conversations: const [], messages: const [], memory: const WesiAiMemorySnapshot());

  WesiAiConversation? get activeConversation {
    final id = activeConversationId;
    if (id == null) return null;
    for (final item in conversations) {
      if (item.id == id) return item;
    }
    return null;
  }

  List<WesiAiMessage> messagesFor(String conversationId) {
    final result = messages.where((m) => m.employeeId == employeeId && m.conversationId == conversationId).toList();
    result.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return result;
  }

  WesiAiLocalState copyWith({WesiAiTier? tier, String? activeConversationId, bool clearActiveConversation = false, List<WesiAiConversation>? conversations, List<WesiAiMessage>? messages, WesiAiMemorySnapshot? memory}) => WesiAiLocalState(employeeId: employeeId, tier: tier ?? this.tier, activeConversationId: clearActiveConversation ? null : (activeConversationId ?? this.activeConversationId), conversations: conversations ?? this.conversations, messages: messages ?? this.messages, memory: memory ?? this.memory);

  Map<String, dynamic> toJson() => {'employeeId': employeeId, 'tier': tier.name, 'activeConversationId': activeConversationId, 'conversations': conversations.map((e) => e.toJson()).toList(), 'messages': messages.map((e) => e.toJson()).toList(), 'memory': memory.toJson()};

  factory WesiAiLocalState.fromJson(Map<String, dynamic> json, {required String expectedEmployeeId}) {
    final storedEmployeeId = json['employeeId'] as String? ?? '';
    if (storedEmployeeId != expectedEmployeeId) throw StateError('Employee mismatch');
    final conversations = (json['conversations'] as List? ?? const []).map((e) => WesiAiConversation.fromJson(Map<String, dynamic>.from(e as Map))).where((e) => e.employeeId == expectedEmployeeId).toList();
    final messages = (json['messages'] as List? ?? const []).map((e) => WesiAiMessage.fromJson(Map<String, dynamic>.from(e as Map))).where((e) => e.employeeId == expectedEmployeeId).toList();
    return WesiAiLocalState(employeeId: expectedEmployeeId, tier: WesiAiTier.values.byName(json['tier'] as String? ?? 'fast'), activeConversationId: json['activeConversationId'] as String?, conversations: conversations, messages: messages, memory: WesiAiMemorySnapshot.fromJson(Map<String, dynamic>.from(json['memory'] as Map? ?? const {})));
  }
}
