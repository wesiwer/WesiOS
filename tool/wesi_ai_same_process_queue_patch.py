from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{path}: expected one anchor, got {count}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

base = "lib/features/ai/controllers/wesi_ai_chat_controller.dart"
replace_once(
    base,
    "  @protected\n  void notifyIfActive() {\n    if (!_disposed) notifyListeners();\n  }\n",
    "  @protected\n  bool get isDisposed => _disposed;\n\n  @protected\n  void notifyIfActive() {\n    if (!_disposed) notifyListeners();\n  }\n",
)

managed = "lib/features/ai/wesi_ai_managed_controller.dart"
replace_once(
    managed,
    "  final String _queueSessionId;\n  bool _drainingQueue = false;\n",
    "  final String _queueSessionId;\n  bool _drainingQueue = false;\n  bool _waitingForSameProcessOwner = false;\n",
)
replace_once(
    managed,
    "  bool get processing => sending || _drainingQueue || _queuedTurns.isNotEmpty;\n",
    "  bool get processing =>\n      sending ||\n      _drainingQueue ||\n      _queuedTurns.isNotEmpty ||\n      _waitingForSameProcessOwner;\n",
)
replace_once(
    managed,
    "        } catch (_) {\n          _queuedTurns.removeAt(0);\n          try {\n            await _appendLocalSubmissionError(\n              turn.conversationId,\n              code: 'WAI_QUEUE_PERSISTENCE_FAILED',\n              text:\n                  'Не удалось безопасно подготовить сохранённое сообщение к отправке. Оно не было отправлено автоматически.',\n            );\n          } catch (_) {\n            _notify();\n          }\n          continue;\n        }\n",
    "        } catch (_) {\n          _queuedTurns.removeAt(0);\n          try {\n            await store.removePendingQueueItem(turn.id);\n          } catch (_) {}\n          final clean = turn.text.trim();\n          final preview = clean.length <= 240 ? clean : '${clean.substring(0, 240)}…';\n          final fileNames = turn.attachments\n              .map((attachment) => attachment.name)\n              .join(', ');\n          final recoveryHint = preview.isNotEmpty\n              ? ' Исходный текст: «$preview».'\n              : (fileNames.isNotEmpty ? ' Вложения: $fileNames.' : '');\n          try {\n            await _appendLocalSubmissionError(\n              turn.conversationId,\n              code: 'WAI_QUEUE_PERSISTENCE_FAILED',\n              text:\n                  'Не удалось безопасно подготовить сохранённое сообщение к отправке. Оно не было отправлено автоматически.$recoveryHint',\n            );\n          } catch (_) {\n            _notify();\n          }\n          continue;\n        }\n",
)
replace_once(
    managed,
    "    if (pending.isEmpty) return;\n\n    final recoveryMessages = <WesiAiMessage>[];\n",
    "    if (pending.isEmpty) return;\n\n    final sameProcessOwned = pending.any(\n      (item) =>\n          item.status != WesiAiPendingQueueStatus.completed &&\n          item.processSessionId == _queueSessionId,\n    );\n    if (sameProcessOwned) {\n      _startSameProcessOwnerWait();\n      return;\n    }\n\n    final recoveryMessages = <WesiAiMessage>[];\n",
)
insert = r'''  void _startSameProcessOwnerWait() {
    if (_waitingForSameProcessOwner || isDisposed) return;
    _waitingForSameProcessOwner = true;
    _notify();
    unawaited(_waitForSameProcessOwner());
  }

  Future<void> _waitForSameProcessOwner() async {
    while (!isDisposed && _waitingForSameProcessOwner) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
      List<WesiAiPendingQueueItem> pending;
      try {
        pending = await store.loadPendingQueueItems();
      } catch (_) {
        continue;
      }
      final stillOwned = pending.any(
        (item) =>
            item.status != WesiAiPendingQueueStatus.completed &&
            item.processSessionId == _queueSessionId,
      );
      if (stillOwned) continue;

      try {
        // The previous controller always persists state before retiring its
        // last pending record. Reloading here therefore cannot miss its reply.
        await super.load();
      } catch (_) {
        continue;
      }
      if (isDisposed) return;
      _waitingForSameProcessOwner = false;
      await _recoverPendingQueue();
      _notify();
      return;
    }
  }

'''
replace_once(
    managed,
    "  WesiAiMessage _recoveryError(\n",
    insert + "  WesiAiMessage _recoveryError(\n",
)

test = "test/wesi_ai_queue_hardening_test.dart"
replace_once(
    test,
    "    expect(apiB.prompts, isEmpty);\n    expect(controllerB.queuedTurnCount, 0);\n    expect(store.pending.length, 2);\n\n    apiA.first.complete(\n",
    "    expect(apiB.prompts, isEmpty);\n    expect(controllerB.queuedTurnCount, 0);\n    expect(controllerB.processing, isTrue);\n    expect(store.pending.length, 2);\n\n    apiA.first.complete(\n",
)
replace_once(
    test,
    "    await _waitUntil(() => store.pending.isEmpty);\n    expect(apiA.prompts, <String>['first-owned', 'second-owned']);\n    expect(apiB.prompts, isEmpty);\n",
    "    await _waitUntil(() => store.pending.isEmpty);\n    await _waitUntil(() => !controllerB.processing);\n    expect(apiA.prompts, <String>['first-owned', 'second-owned']);\n    expect(apiB.prompts, isEmpty);\n    expect(\n      controllerB.state.messages.any(\n        (message) => message.text == 'reply:second-owned',\n      ),\n      isTrue,\n    );\n",
)
