import 'models/wesi_ai_chat_models.dart';
import 'storage/wesi_ai_local_store.dart';

/// Presentation-only helpers for the ordinary Wesi AI chat.
///
/// Important: these names do not change the transport tier keys. In
/// particular, the historical `maximum` key is kept for compatibility while
/// the product-facing name is Ultra.
class WesiAiChatUi {
  const WesiAiChatUi._();

  static bool shouldCreateInitialConversation(WesiAiLocalState state) =>
      state.activeConversation == null && state.conversations.isEmpty;

  static String tierLabel(WesiAiTier tier) => switch (tier) {
        WesiAiTier.fast => 'Быстрый',
        WesiAiTier.pro => 'Pro',
        WesiAiTier.maximum => 'Ultra',
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
}
