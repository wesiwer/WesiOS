#!/usr/bin/env python3
from pathlib import Path

# Validation trigger: product changes are committed only after the full one-shot gate passes.
root = Path(__file__).resolve().parents[1]

screen = root / 'lib/features/ai/ai_assistant_v2_screen.dart'
text = screen.read_text(encoding='utf-8')
old = "import 'widgets/wesi_ai_message_actions.dart';\n"
new = "import 'widgets/wesi_ai_message_actions.dart';\nimport 'widgets/wesi_ai_rich_message.dart';\n"
if new not in text:
    if old not in text:
        raise SystemExit('message actions import anchor not found')
    text = text.replace(old, new, 1)
    screen.write_text(text, encoding='utf-8')

chat_ui = root / 'lib/features/ai/wesi_ai_chat_ui.dart'
text = chat_ui.read_text(encoding='utf-8')
old_stop = "'ответ', 'вопрос', 'пожалуйста', 'просто', 'тоже', 'там', 'тут', 'здесь',"
new_stop = "'ответ', 'вопрос', 'почему', 'зачем', 'пожалуйста', 'просто', 'тоже', 'там', 'тут', 'здесь',"
if old_stop in text:
    text = text.replace(old_stop, new_stop, 1)
if 'if (words.length == 4) break;' in text:
    text = text.replace('if (words.length == 4) break;', 'if (words.length == 5) break;', 1)
chat_ui.write_text(text, encoding='utf-8')

# Keep transient chat handles alive in memory until their first accepted turn.
# They stay hidden from history and are never persisted before materialization.
controller = root / 'lib/features/ai/controllers/wesi_ai_chat_controller.dart'
text = controller.read_text(encoding='utf-8')
old_drafts = """    final oldDrafts = Set<String>.from(_transientConversationIds);
    _transientConversationIds
      ..clear()
      ..add(id);
    state = state.copyWith(
      conversations: <WesiAiConversation>[
        c,
        ...state.conversations.where((item) => !oldDrafts.contains(item.id)),
      ],
      messages: state.messages
          .where((message) => !oldDrafts.contains(message.conversationId))
          .toList(growable: false),
      activeConversationId: id,
      conversationMemory: Map<String, WesiAiConversationMemoryState>.fromEntries(
        state.conversationMemory.entries
            .where((entry) => !oldDrafts.contains(entry.key)),
      ),
    );
"""
new_drafts = """    _transientConversationIds.add(id);
    state = state.copyWith(
      conversations: <WesiAiConversation>[c, ...state.conversations],
      activeConversationId: id,
    );
"""
if old_drafts in text:
    text = text.replace(old_drafts, new_drafts, 1)
elif new_drafts not in text:
    raise SystemExit('transient conversation preservation anchor not found')
controller.write_text(text, encoding='utf-8')

print('contextual chat analyzer/topic/lazy-draft fixes applied')
