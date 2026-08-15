import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';

enum WesiAiUiMode { classic, thinking }

/// Presentation-only helpers for the ordinary Wesi AI chat.
/// Transport keys and backend routing are intentionally not changed here.
class WesiAiChatUi {
  const WesiAiChatUi._();

  static bool shouldCreateInitialConversation(WesiAiLocalState state) =>
      state.activeConversation == null && state.conversations.isEmpty;

  static String tierLabel(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => 'Быстрый',
        WesiAiTier.pro => 'Pro',
        WesiAiTier.maximum => 'Максимальный',
      };

  static String personaEmptyLabel(WesiAiPersona persona) => switch (persona) {
        WesiAiPersona.zane => 'Зейн готов к работе',
        WesiAiPersona.nirvana => 'Нирвана готова к работе',
        WesiAiPersona.lobby => 'Зейн и Нирвана готовы к работе',
      };

  static String sendingLabel(Duration elapsed) {
    final seconds = elapsed.inSeconds < 0 ? 0 : elapsed.inSeconds;
    return 'Формирует ответ · ${seconds}с';
  }

  static String modeLabel(WesiAiUiMode mode) => switch (mode) {
        WesiAiUiMode.classic => 'Классический',
        WesiAiUiMode.thinking => 'Думающий',
      };

  static String safeReasoningSummary(WesiAiMessage message) {
    final rawBlocks = message.metadata['blocks'];
    final blockCount = rawBlocks is List ? rawBlocks.length : 0;
    if (blockCount > 0) {
      return 'Проверил контекст и подготовил ответ с учётом $blockCount структурированных блоков.';
    }
    return 'Сопоставил запрос с контекстом текущего диалога и подготовил итоговый ответ.';
  }

  static List<String> followUps(String answer) {
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
}
