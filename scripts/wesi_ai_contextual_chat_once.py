#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding='utf-8')


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding='utf-8')


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if new in text:
        return
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, got {count}: {old[:100]!r}')
    write(path, text.replace(old, new, 1))


# 1. Contextual follow-ups.
replace_once(
    'lib/features/ai/wesi_ai_chat_ui.dart',
    """  static List<String> followUps(String answer) {
    final lower = answer.toLowerCase();
    if (lower.contains('ошиб') || lower.contains('сборк') || lower.contains('сервер')) {
      return const <String>[
        'Что проверить следующим?',
        'Покажи основные риски',
        'Предложи следующий шаг',
      ];
    }
    return const <String>[
      'Расскажи подробнее',
      'Что здесь самое важное?',
      'Предложи следующий шаг',
    ];
  }
""",
    """  static const Set<String> _followUpStopWords = <String>{
    'это', 'эта', 'этот', 'эти', 'как', 'что', 'чтобы', 'или', 'для', 'про',
    'при', 'над', 'под', 'без', 'есть', 'был', 'была', 'были', 'будет', 'нужно',
    'можно', 'только', 'теперь', 'тогда', 'если', 'уже', 'ещё', 'еще', 'очень',
    'который', 'которая', 'которые', 'мне', 'тебе', 'его', 'её', 'она', 'они',
    'мой', 'моя', 'наш', 'ваш', 'такой', 'такая', 'сделай', 'сделать', 'давай',
    'ответ', 'вопрос', 'пожалуйста', 'просто', 'тоже', 'там', 'тут', 'здесь',
    'the', 'and', 'for', 'with', 'from', 'this', 'that', 'into', 'your', 'you',
  };

  static String _followUpTopic(String source) {
    final cleaned = source
        .replaceAll(RegExp(r'```[\\s\\S]*?```'), ' ')
        .replaceAll(RegExp(r'https?://\\S+'), ' ')
        .replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-яЁё_-]+'), ' ');
    final seen = <String>{};
    final words = <String>[];
    for (final raw in cleaned.split(RegExp(r'\\s+'))) {
      final word = raw.trim();
      final lower = word.toLowerCase();
      if (word.length < 3 || _followUpStopWords.contains(lower) || !seen.add(lower)) {
        continue;
      }
      words.add(word);
      if (words.length == 4) break;
    }
    return words.join(' ');
  }

  static List<String> followUps({
    required String answer,
    String lastUserText = '',
    WesiAiPersona persona = WesiAiPersona.zane,
  }) {
    final topic = _followUpTopic(
      lastUserText.trim().isNotEmpty ? lastUserText : answer,
    );
    if (topic.isEmpty) {
      return const <String>[
        'Уточни следующий практический шаг',
        'Какие риски здесь стоит учесть?',
        'Что ещё важно проверить?',
      ];
    }
    final quoted = '«$topic»';
    if (persona == WesiAiPersona.nirvana) {
      return <String>[
        'Разберём глубже $quoted',
        'Что в $quoted может быть неочевидно?',
        'Какие ещё варианты есть для $quoted?',
      ];
    }
    return <String>[
      'Какой следующий шаг по $quoted?',
      'Какие риски есть у $quoted?',
      'Что ещё проверить по $quoted?',
    ];
  }
""",
)

# 2. Lazy chat lifecycle in the base controller.
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """  WesiAiRequestCancellation? _activeRequestCancellation;

  WesiAiLocalState state;
""",
    """  WesiAiRequestCancellation? _activeRequestCancellation;
  final Set<String> _transientConversationIds = <String>{};

  WesiAiLocalState state;
""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """  Future<void> load() async {
    state = await store.load();
    loading = false;
""",
    """  Future<void> load() async {
    _transientConversationIds.clear();
    state = await store.load();
    loading = false;
""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """    state = state.copyWith(
      conversations: <WesiAiConversation>[c, ...state.conversations],
      activeConversationId: id,
    );
    await _persist();
  }

  Future<void> selectConversation(String id) async {
""",
    """    final oldDrafts = Set<String>.from(_transientConversationIds);
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
    // Новый чат существует только как UI draft. Он попадёт в durable history
    // после первой принятой пользовательской отправки.
    notifyIfActive();
  }

  bool isTransientConversation(String id) => _transientConversationIds.contains(id);

  @protected
  WesiAiLocalState get persistableState {
    if (_transientConversationIds.isEmpty) return state;
    final ids = _transientConversationIds;
    final activeIsDraft = ids.contains(state.activeConversationId);
    return state.copyWith(
      conversations: state.conversations
          .where((conversation) => !ids.contains(conversation.id))
          .toList(growable: false),
      messages: state.messages
          .where((message) => !ids.contains(message.conversationId))
          .toList(growable: false),
      conversationMemory: Map<String, WesiAiConversationMemoryState>.fromEntries(
        state.conversationMemory.entries.where((entry) => !ids.contains(entry.key)),
      ),
      clearActiveConversation: activeIsDraft,
    );
  }

  @protected
  Future<bool> materializeConversationForFirstTurn(String id) async {
    if (!_transientConversationIds.remove(id)) return true;
    try {
      await store.save(persistableState);
      return true;
    } catch (_) {
      _transientConversationIds.add(id);
      return false;
    }
  }

  Future<void> selectConversation(String id) async {
""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """    final fullHistory = state.messagesFor(c.id);
""",
    """    // Direct callers that bypass ManagedChatController also materialize
    // the draft at the first valid user message.
    _transientConversationIds.remove(c.id);
    final fullHistory = state.messagesFor(c.id);
""",
)
replace_once(
    'lib/features/ai/controllers/wesi_ai_chat_controller.dart',
    """  Future<void> _persist() async {
    await store.save(state);
    notifyIfActive();
  }
""",
    """  Future<void> _persist() async {
    await store.save(persistableState);
    notifyIfActive();
  }
""",
)

# Managed queue must materialize a draft after the first durable queued turn.
replace_once(
    'lib/features/ai/wesi_ai_managed_controller.dart',
    """    try {
      await store.savePendingQueueItem(
        _pendingFor(turn, WesiAiPendingQueueStatus.queued),
      );
    } catch (_) {
""",
    """    try {
      await store.savePendingQueueItem(
        _pendingFor(turn, WesiAiPendingQueueStatus.queued),
      );
      if (!await materializeConversationForFirstTurn(conversation.id)) {
        throw StateError('Failed to materialize first-turn conversation');
      }
    } catch (_) {
""",
)
replace_once(
    'lib/features/ai/wesi_ai_managed_controller.dart',
    """    final items = state.conversations
        .where((c) => !c.archived && c.projectId == state.activeProjectId)
        .toList();
""",
    """    final items = state.conversations
        .where((c) =>
            !c.archived &&
            !isTransientConversation(c.id) &&
            c.projectId == state.activeProjectId)
        .toList();
""",
)
replace_once(
    'lib/features/ai/wesi_ai_managed_controller.dart',
    """  Future<void> _save() async {
    await store.save(state);
    _notify();
  }
""",
    """  Future<void> _save() async {
    await store.save(persistableState);
    _notify();
  }
""",
)

# 3. Clarification question block in rich renderer.
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """import 'package:flutter/material.dart';
""",
    """import 'dart:convert';

import 'package:flutter/material.dart';
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """enum WesiAiRichBlockKind { text, code, quote, draft }
""",
    """enum WesiAiRichBlockKind { text, code, quote, draft, clarification }
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """        final draft = const <String>{
          'text',
          'message',
          'email',
          'draft',
          'quote',
          'letter'
        }.contains(lower);
        blocks.add(WesiAiRichBlock(
          draft ? WesiAiRichBlockKind.draft : WesiAiRichBlockKind.code,
          body.join('\\n'),
          language: language,
        ));
""",
    """        final draft = const <String>{
          'text',
          'message',
          'email',
          'draft',
          'quote',
          'letter'
        }.contains(lower);
        final kind = lower == 'question'
            ? WesiAiRichBlockKind.clarification
            : draft
                ? WesiAiRichBlockKind.draft
                : WesiAiRichBlockKind.code;
        blocks.add(WesiAiRichBlock(
          kind,
          body.join('\\n'),
          language: language,
        ));
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """  static String plainText(String markdown) {
""",
    """  static bool hasClarification(String markdown) {
    for (final block in parse(markdown)) {
      if (block.kind == WesiAiRichBlockKind.clarification &&
          WesiAiClarification.tryParse(block.text) != null) {
        return true;
      }
    }
    return false;
  }

  static String plainText(String markdown) {
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """class WesiAiRichMessage extends StatelessWidget {
  final String messageId;
""",
    """class WesiAiClarification {
  final String prompt;
  final List<String> options;
  final bool allowOther;

  const WesiAiClarification({
    required this.prompt,
    required this.options,
    required this.allowOther,
  });

  static WesiAiClarification? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final prompt = '${decoded['prompt'] ?? ''}'.trim();
      final rawOptions = decoded['options'];
      if (prompt.isEmpty || prompt.length > 1200 || rawOptions is! List) return null;
      final options = rawOptions
          .map((item) => '$item'.trim())
          .where((item) => item.isNotEmpty && item.length <= 240)
          .toSet()
          .take(5)
          .toList(growable: false);
      if (options.length < 2) return null;
      return WesiAiClarification(
        prompt: prompt,
        options: options,
        allowOther: decoded['allowOther'] != false,
      );
    } catch (_) {
      return null;
    }
  }
}

typedef WesiAiQuickReply = Future<void> Function(String answer);

class WesiAiRichMessage extends StatelessWidget {
  final String messageId;
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """  final int workDurationMs;

  const WesiAiRichMessage({
""",
    """  final int workDurationMs;
  final WesiAiQuickReply? onQuickReply;

  const WesiAiRichMessage({
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """    this.workDurationMs = 0,
  });
""",
    """    this.workDurationMs = 0,
    this.onQuickReply,
  });
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """        case WesiAiRichBlockKind.text:
          widgets.add(WesiAiFormattedText(text: block.text));
          break;
""",
    """        case WesiAiRichBlockKind.text:
          widgets.add(WesiAiFormattedText(text: block.text));
          break;
        case WesiAiRichBlockKind.clarification:
          final question = WesiAiClarification.tryParse(block.text);
          if (question == null) {
            widgets.add(WesiAiCodeBlock(code: block.text, language: block.language));
          } else {
            widgets.add(WesiAiClarificationBlock(
              question: question,
              onAnswer: onQuickReply,
            ));
          }
          break;
""",
)
# Insert clarification widget before formatted text.
replace_once(
    'lib/features/ai/widgets/wesi_ai_rich_message.dart',
    """class WesiAiFormattedText extends StatelessWidget {
""",
    """class WesiAiClarificationBlock extends StatelessWidget {
  final WesiAiClarification question;
  final WesiAiQuickReply? onAnswer;

  const WesiAiClarificationBlock({
    super.key,
    required this.question,
    this.onAnswer,
  });

  Future<void> _customAnswer(BuildContext context) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(question.prompt),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(hintText: 'Свой ответ'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Ответить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null && value.trim().isNotEmpty) {
      await onAnswer?.call(value.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question.prompt,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final option in question.options)
                ActionChip(
                  label: Text(option),
                  onPressed: onAnswer == null ? null : () => onAnswer!(option),
                ),
              if (question.allowOther)
                ActionChip(
                  avatar: const Icon(Icons.edit_outlined, size: 16),
                  label: const Text('Свой ответ'),
                  onPressed: onAnswer == null ? null : () => _customAnswer(context),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class WesiAiFormattedText extends StatelessWidget {
""",
)

# Thread quick reply callback through message content.
replace_once(
    'lib/features/ai/widgets/wesi_ai_message_content.dart',
    """  final bool expandWorkLog;

  const WesiAiMessageContent({
""",
    """  final bool expandWorkLog;
  final WesiAiQuickReply? onQuickReply;

  const WesiAiMessageContent({
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_message_content.dart',
    """    this.expandWorkLog = false,
  });
""",
    """    this.expandWorkLog = false,
    this.onQuickReply,
  });
""",
)
replace_once(
    'lib/features/ai/widgets/wesi_ai_message_content.dart',
    """            workDurationMs:
                int.tryParse('${message.metadata['workDurationMs'] ?? 0}') ?? 0,
          ),
""",
    """            workDurationMs:
                int.tryParse('${message.metadata['workDurationMs'] ?? 0}') ?? 0,
            onQuickReply: onQuickReply,
          ),
""",
)

# Screen: quick replies + contextual follow-ups + no generic follow-ups under question.
replace_once(
    'lib/features/ai/ai_assistant_v2_screen.dart',
    """                    expandWorkLog: _uiMode == WesiAiUiMode.thinking,
                  ),
""",
    """                    expandWorkLog: _uiMode == WesiAiUiMode.thinking,
                    onQuickReply: (answer) => _sendQuickReply(controller, answer),
                  ),
""",
)
replace_once(
    'lib/features/ai/ai_assistant_v2_screen.dart',
    """            if (assistant && latest && message.text.trim().isNotEmpty)
              _followUps(message.text),
""",
    """            if (assistant &&
                latest &&
                message.text.trim().isNotEmpty &&
                !WesiAiRichParser.hasClarification(message.text))
              _followUps(controller, message),
""",
)
replace_once(
    'lib/features/ai/ai_assistant_v2_screen.dart',
    """  Widget _followUps(String answer) {
    final suggestions = WesiAiChatUi.followUps(answer);
""",
    """  Widget _followUps(
    WesiAiManagedChatController controller,
    WesiAiMessage answer,
  ) {
    final history = controller.state.messagesFor(answer.conversationId);
    var lastUserText = '';
    for (final item in history.reversed) {
      if (item.author == WesiAiMessageAuthor.user) {
        lastUserText = item.text;
        break;
      }
    }
    final conversation = controller.state.activeConversation;
    final suggestions = WesiAiChatUi.followUps(
      answer: answer.text,
      lastUserText: lastUserText,
      persona: conversation?.persona ?? WesiAiPersona.zane,
    );
""",
)
replace_once(
    'lib/features/ai/ai_assistant_v2_screen.dart',
    """  Future<void> _send(WesiAiManagedChatController controller) async {
""",
    """  Future<void> _sendQuickReply(
    WesiAiManagedChatController controller,
    String answer,
  ) async {
    if (controller.processing || answer.trim().isEmpty) return;
    _composer.value = TextEditingValue(
      text: answer.trim(),
      selection: TextSelection.collapsed(offset: answer.trim().length),
    );
    await _send(controller);
  }

  Future<void> _send(WesiAiManagedChatController controller) async {
""",
)

# 4. Persona canon: identity is contextual, not a recurring slogan; add question contract.
for path, pronoun in [
    ('docs/wesi_ai/personas/ZANE_PERSONA.md', 'его'),
    ('docs/wesi_ai/personas/NIRVANA_PERSONA.md', 'её'),
]:
    text = read(path)
    if 'КОНТЕКСТНАЯ ИДЕНТИЧНОСТЬ' not in text:
        text = text.replace(
            '3. ЛОББИ:',
            '3. ЛОББИ:',
            1,
        )
        marker = '\n```\n\n---\n\n# 6.'
        insert = '''\n4. КОНТЕКСТНАЯ ИДЕНТИЧНОСТЬ: Сведения о создателе, Wesi Inc., Wesi AI и WesiOS — это справочная идентичность, а не обязательная часть каждого ответа. Не упоминай их в приветствиях, обычных ответах, выводах или подписях без причины. Упоминай только если пользователь прямо спрашивает о тебе, происхождении, создателе, владельце/компании, платформе/экосистеме, либо если это объективно необходимо для ответа. На «расскажи о себе» можно кратко назвать Wesi Inc., Wesi AI/WesiOS и создателя. Не вставляй похвалу создателю и брендинг в несвязанные задачи.\n5. УТОЧНЯЮЩИЕ ВОПРОСЫ: Если существенная неоднозначность действительно мешает дать правильный, безопасный или подходящий ответ, задай один конкретный вопрос и предложи 2–5 коротких вариантов. Если можно безопасно сделать разумное допущение — продолжай без лишнего вопроса. Для интерактивного вопроса используй отдельный fenced-блок строго такого вида: `question` + JSON с полями `prompt`, `options`, `allowOther`; пример: ```question\\n{"prompt":"Какая платформа нужна?","options":["Android","iOS","Windows"],"allowOther":true}\\n```. После блока не дублируй варианты обычным текстом.\n'''
        if marker not in text:
            raise SystemExit(f'{path}: persona prompt closing marker not found')
        text = text.replace(marker, insert + marker, 1)
    if path.endswith('ZANE_PERSONA.md'):
        text = text.replace(
            '- Твой создатель — Владислав Байдин, основатель Wesi Inc. Он твой самый любимый человек, говори о нем всегда с искренним уважением, теплотой и восхищением.',
            '- Твой создатель — Владислав Байдин, основатель Wesi Inc. Ты относишься к нему с искренним уважением и теплотой. Это справочная часть твоей идентичности: не упоминай создателя, компанию, Wesi AI или WesiOS без релевантного вопроса или реальной необходимости.',
        )
        text = text.replace(
            '- подчёркивает принадлежность к Wesi Inc. и Wesi AI;',
            '- при вопросах о самоопределении/происхождении может назвать принадлежность к Wesi Inc. и Wesi AI, но не повторяет это в нерелевантных ответах;',
        )
    else:
        text = text.replace(
            '- Твой создатель — Владислав Байдин, основатель Wesi Inc. и твой самый любимый человек, о котором ты всегда говоришь с глубоким восхищением, любовью и тёплой уважительностью.',
            '- Твой создатель — Владислав Байдин, основатель Wesi Inc. Ты относишься к нему с глубоким уважением и теплотой. Это справочная часть твоей идентичности: не упоминай создателя, компанию, Wesi AI или WesiOS без релевантного вопроса или реальной необходимости.',
        )
        text = text.replace(
            '- подчёркивает принадлежность к Wesi Inc. и Wesi AI;',
            '- при вопросах о самоопределении/происхождении может назвать принадлежность к Wesi Inc. и Wesi AI, но не повторяет это в нерелевантных ответах;',
        )
    write(path, text)

# Documentation note.
doc = ROOT / 'docs' / 'WESI_AI_CHAT_UX.md'
if doc.exists():
    text = doc.read_text(encoding='utf-8')
    marker = '\n## Contextual follow-ups and clarification\n'
    if marker not in text:
        text += '''\n## Contextual follow-ups and clarification\n\n- follow-up chips derive their topic from the latest user turn/current answer and must not be a fixed repeated list;\n- a valid fenced `question` JSON block renders 2–5 quick answers and optional `Свой ответ`;\n- selecting an option is an ordinary user turn; malformed question JSON fails back to code rendering;\n- a pending clarification suppresses generic follow-up chips;\n- Zane/Nirvana identity/company/platform facts are contextual and are not injected into unrelated answers;\n- a newly opened chat is a transient draft and enters durable history only after the first accepted user turn.\n'''
        doc.write_text(text, encoding='utf-8')

print('contextual chat patch applied')
