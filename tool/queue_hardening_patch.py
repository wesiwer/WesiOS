from pathlib import Path

def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected exactly one match, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

managed = "lib/features/ai/wesi_ai_managed_controller.dart"
replace_once(
    managed,
    "import 'dart:math';\n",
    "import 'dart:async';\nimport 'dart:math';\n",
)
replace_once(
    managed,
    "import 'storage/wesi_ai_local_store.dart';\nimport 'wesi_ai_lobby_controller.dart';\n",
    "import 'storage/wesi_ai_local_store.dart';\nimport 'wesi_ai_api.dart';\nimport 'wesi_ai_lobby_api.dart';\nimport 'wesi_ai_lobby_controller.dart';\n",
)
replace_once(
    managed,
    """class WesiAiManagedChatController extends WesiAiLobbyChatController {
  static const int maxQueuedTurns = 12;
""",
    """enum WesiAiMessageSubmitResult {
  accepted,
  queueFull,
  invalidAttachments,
  unavailable,
}

class WesiAiManagedChatController extends WesiAiLobbyChatController {
  static const int maxQueuedTurns = 12;
""",
)
replace_once(
    managed,
    """  WesiAiManagedChatController({required WesiAiLocalStore store})
      : super(store: store);

  int get queuedTurnCount => _queuedTurns.length;
""",
    """  WesiAiManagedChatController({
    required WesiAiLocalStore store,
    WesiAiApi api = const WesiAiLobbyApi(),
  }) : super(store: store, api: api);

  int get queuedTurnCount => _queuedTurns.length;
""",
)
replace_once(
    managed,
    """  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;

  @override
  Future<void> addUserMessage(
""",
    """  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;

  WesiAiMessageSubmitResult submitUserMessage(
    String text, {
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {
    final conversation = state.activeConversation;
    final clean = text.trim();
    if (conversation == null || (clean.isEmpty && attachments.isEmpty)) {
      return WesiAiMessageSubmitResult.unavailable;
    }
    try {
      WesiAiAttachment.validateBatch(attachments);
    } on FormatException {
      return WesiAiMessageSubmitResult.invalidAttachments;
    }
    if (_queuedTurns.length >= maxQueuedTurns) {
      return WesiAiMessageSubmitResult.queueFull;
    }

    _queuedTurns.add(
      WesiAiQueuedTurn(
        conversationId: conversation.id,
        text: clean,
        attachments: List<WesiAiAttachment>.unmodifiable(attachments),
        queuedAt: DateTime.now(),
      ),
    );
    notifyListeners();
    unawaited(_drainQueuedTurns());
    return WesiAiMessageSubmitResult.accepted;
  }

  @override
  Future<void> addUserMessage(
""",
)
replace_once(
    managed,
    """      while (_queuedTurns.isNotEmpty) {
        final turn = _queuedTurns.removeAt(0);
        WesiAiConversation? target;
        for (final conversation in state.conversations) {
          if (conversation.id == turn.conversationId && !conversation.archived) {
            target = conversation;
            break;
          }
        }
        if (target == null) {
          notifyListeners();
          continue;
        }
        if (state.activeConversationId != target.id) {
          state = state.copyWith(
            activeConversationId: target.id,
            activeProjectId: target.projectId,
            clearActiveProject: target.projectId == null,
          );
          await _save();
        } else {
          notifyListeners();
        }
        await _sendNow(turn.text, attachments: turn.attachments);
      }
""",
    """      while (_queuedTurns.isNotEmpty) {
        final turn = _queuedTurns.removeAt(0);
        try {
          WesiAiConversation? target;
          for (final conversation in state.conversations) {
            if (conversation.id == turn.conversationId && !conversation.archived) {
              target = conversation;
              break;
            }
          }
          if (target == null) {
            notifyListeners();
            continue;
          }
          if (state.activeConversationId != target.id) {
            state = state.copyWith(
              activeConversationId: target.id,
              activeProjectId: target.projectId,
              clearActiveProject: target.projectId == null,
            );
            await _save();
          } else {
            notifyListeners();
          }
          await _sendNow(turn.text, attachments: turn.attachments);
        } catch (_) {
          try {
            await _appendQueueItemError(turn.conversationId);
          } catch (_) {
            notifyListeners();
          }
        }
      }
""",
)
replace_once(
    managed,
    """  Future<void> _appendQueueFullError(String conversationId) async {
""",
    """  Future<void> _appendQueueItemError(String conversationId) async {
    final at = DateTime.now();
    state = state.copyWith(
      messages: <WesiAiMessage>[
        ...state.messages,
        WesiAiMessage(
          id: '${at.microsecondsSinceEpoch}_${Random().nextInt(1 << 20)}',
          conversationId: conversationId,
          employeeId: store.employeeId,
          author: WesiAiMessageAuthor.system,
          kind: WesiAiMessageKind.error,
          text:
              'Не удалось обработать одно из сообщений. Остальная очередь продолжает выполняться.',
          createdAt: at,
          metadata: const <String, dynamic>{
            'code': 'WAI_MESSAGE_QUEUE_ITEM_FAILED',
          },
        ),
      ],
    );
    await _save();
  }

  Future<void> _appendQueueFullError(String conversationId) async {
""",
)

ui = "lib/features/ai/ai_assistant_v2_screen.dart"
replace_once(
    ui,
    """  Future<void> _send(WesiAiManagedChatController controller) async {
    if (controller.processing &&
        controller.queuedTurnCount >= WesiAiManagedChatController.maxQueuedTurns) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Очередь заполнена. Дождитесь обработки сообщения.'),
        ),
      );
      return;
    }
    if (_voice.listening) await _voice.stop();
    final text = _composer.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<WesiAiAttachment>.from(_attachments);
    _composer.clear();
    _voicePrefix = '';
    _voice.clearTranscript();
    setState(() => _attachments.clear());
    await controller.addUserMessage(text, attachments: attachments);
  }
""",
    """  Future<void> _send(WesiAiManagedChatController controller) async {
    if (_voice.listening) await _voice.stop();
    final text = _composer.text.trim();
    if (text.isEmpty && _attachments.isEmpty) return;
    final attachments = List<WesiAiAttachment>.from(_attachments);
    final result = controller.submitUserMessage(
      text,
      attachments: attachments,
    );
    if (result != WesiAiMessageSubmitResult.accepted) {
      if (!mounted) return;
      final message = switch (result) {
        WesiAiMessageSubmitResult.queueFull =>
          'Очередь заполнена. Дождитесь обработки сообщения.',
        WesiAiMessageSubmitResult.invalidAttachments =>
          'Не удалось отправить сообщение: проверьте вложения.',
        WesiAiMessageSubmitResult.unavailable =>
          'Не удалось отправить сообщение в текущий чат.',
        WesiAiMessageSubmitResult.accepted => '',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    _composer.clear();
    _voicePrefix = '';
    _voice.clearTranscript();
    setState(() => _attachments.clear());
  }
""",
)

test_path = Path("test/wesi_ai_queue_hardening_test.dart")
test_path.write_text(r"""import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';
import 'package:wesios/features/ai/wesi_ai_managed_controller.dart';

class _MemoryStore extends WesiAiLocalStore {
  WesiAiLocalState? saved;

  _MemoryStore(String employeeId) : super(employeeId);

  @override
  Future<WesiAiLocalState> load() async =>
      saved ?? WesiAiLocalState.empty(employeeId);

  @override
  Future<void> save(WesiAiLocalState state) async {
    saved = state;
  }
}

class _ControlledApi extends WesiAiApi {
  final Completer<WesiAiReply> first = Completer<WesiAiReply>();
  final List<String> prompts = <String>[];
  final List<List<String>> attachmentNames = <List<String>>[];

  @override
  Future<WesiAiReply> send({
    required WesiAiConversation conversation,
    required WesiAiTier tier,
    required String message,
    required List<WesiAiMessage> history,
    required WesiAiMemorySnapshot memory,
    WesiAiProject? project,
    List<WesiAiAttachment> attachments = const <WesiAiAttachment>[],
  }) {
    prompts.add(message);
    attachmentNames.add(
      attachments.map((attachment) => attachment.name).toList(growable: false),
    );
    if (prompts.length == 1) return first.future;
    return Future<WesiAiReply>.value(
      WesiAiReply(
        answer: 'reply:$message',
        requestId: 'request-${prompts.length}',
      ),
    );
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 400; attempt++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Timed out waiting for Wesi AI queue');
}

Future<WesiAiManagedChatController> _controller(_ControlledApi api) async {
  final controller = WesiAiManagedChatController(
    store: _MemoryStore('employee-1'),
    api: api,
  );
  await controller.load();
  await controller.createConversation(WesiAiPersona.zane);
  return controller;
}

void main() {
  test('queue accepts exactly 12 waiting turns and preserves FIFO', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);

    expect(
      controller.submitUserMessage('first'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    for (var index = 0;
        index < WesiAiManagedChatController.maxQueuedTurns;
        index++) {
      expect(
        controller.submitUserMessage('queued-$index'),
        WesiAiMessageSubmitResult.accepted,
      );
    }
    expect(
      controller.queuedTurnCount,
      WesiAiManagedChatController.maxQueuedTurns,
    );
    expect(
      controller.submitUserMessage('overflow'),
      WesiAiMessageSubmitResult.queueFull,
    );

    api.first.complete(
      const WesiAiReply(answer: 'reply:first', requestId: 'request-1'),
    );
    await _waitUntil(() => !controller.processing);

    expect(
      api.prompts,
      <String>[
        'first',
        for (var index = 0;
            index < WesiAiManagedChatController.maxQueuedTurns;
            index++)
          'queued-$index',
      ],
    );
    expect(controller.queuedTurnCount, 0);
  });

  test('unexpected failure does not stop later queued turns', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);
    final conversationId = controller.state.activeConversationId!;

    expect(
      controller.submitUserMessage('will-fail'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);
    expect(
      controller.submitUserMessage('must-run-after-failure'),
      WesiAiMessageSubmitResult.accepted,
    );

    api.first.completeError(StateError('synthetic unexpected failure'));
    await _waitUntil(() => !controller.processing);

    expect(api.prompts, <String>['will-fail', 'must-run-after-failure']);
    final messages = controller.state.messagesFor(conversationId);
    expect(
      messages.any(
        (message) =>
            message.metadata['code'] == 'WAI_MESSAGE_QUEUE_ITEM_FAILED',
      ),
      isTrue,
    );
    expect(
      messages.any(
        (message) =>
            message.author == WesiAiMessageAuthor.zane &&
            message.text == 'reply:must-run-after-failure',
      ),
      isTrue,
    );
  });

  test('queued turn keeps its chat and attachment context', () async {
    final api = _ControlledApi();
    final controller = await _controller(api);
    final firstChat = controller.state.activeConversationId!;

    await controller.createConversation(WesiAiPersona.nirvana);
    final secondChat = controller.state.activeConversationId!;
    await controller.selectConversation(firstChat);

    expect(
      controller.submitUserMessage('first-chat'),
      WesiAiMessageSubmitResult.accepted,
    );
    await _waitUntil(() => api.prompts.length == 1);

    await controller.selectConversation(secondChat);
    final attachment = WesiAiAttachment.fromBytes(
      name: 'context.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    expect(
      controller.submitUserMessage(
        'second-chat',
        attachments: <WesiAiAttachment>[attachment],
      ),
      WesiAiMessageSubmitResult.accepted,
    );

    api.first.complete(
      const WesiAiReply(answer: 'reply:first-chat', requestId: 'request-1'),
    );
    await _waitUntil(() => !controller.processing);

    expect(
      controller.state
          .messagesFor(firstChat)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      contains('first-chat'),
    );
    expect(
      controller.state
          .messagesFor(secondChat)
          .where((message) => message.author == WesiAiMessageAuthor.user)
          .map((message) => message.text),
      contains('second-chat'),
    );
    expect(api.attachmentNames[1], <String>['context.txt']);
    expect(controller.state.activeConversationId, secondChat);
  });
}
""", encoding="utf-8")
