import 'dart:convert';
import 'models/wesi_ai_chat_models.dart';

class WesiAiLobbyTurn {
  final WesiAiMessageAuthor author;
  final String text;
  const WesiAiLobbyTurn(this.author, this.text);
}

class WesiAiLobbyCodec {
  static const prefix = '__WESI_LOBBY_V1__';
  static List<WesiAiLobbyTurn> decode(String value) {
    if (!value.startsWith(prefix)) return const [];
    try {
      final raw = jsonDecode(value.substring(prefix.length));
      if (raw is! List) return const [];
      final out = <WesiAiLobbyTurn>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final text = '${item['text'] ?? ''}'.trim();
        if (text.isEmpty) continue;
        final author = switch ('${item['author'] ?? ''}') {
          'zane' => WesiAiMessageAuthor.zane,
          'nirvana' => WesiAiMessageAuthor.nirvana,
          _ => WesiAiMessageAuthor.system,
        };
        out.add(WesiAiLobbyTurn(author, text));
      }
      return out;
    } catch (_) { return const []; }
  }
}
