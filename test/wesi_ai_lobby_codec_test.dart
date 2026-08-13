import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/wesi_ai_lobby_codec.dart';

void main() {
  test('Lobby codec preserves separate Zane and Nirvana authors', () {
    final turns = WesiAiLobbyCodec.decode(
      '__WESI_LOBBY_V1__[{"author":"zane","text":"Первый"},{"author":"nirvana","text":"Вторая"}]',
    );
    expect(turns, hasLength(2));
    expect(turns[0].author, WesiAiMessageAuthor.zane);
    expect(turns[0].text, 'Первый');
    expect(turns[1].author, WesiAiMessageAuthor.nirvana);
    expect(turns[1].text, 'Вторая');
  });

  test('Lobby codec fails closed on malformed payload', () {
    expect(WesiAiLobbyCodec.decode('__WESI_LOBBY_V1__bad'), isEmpty);
    expect(WesiAiLobbyCodec.decode('ordinary answer'), isEmpty);
  });

  test('old Lobby conversation migrates to smart mode', () {
    final conversation = WesiAiConversation.fromJson({
      'id': 'lobby-1',
      'employeeId': 'emp-1',
      'title': 'Лобби',
      'persona': 'lobby',
      'createdAt': '2026-08-13T00:00:00.000Z',
      'updatedAt': '2026-08-13T00:00:00.000Z',
    });
    expect(conversation.lobbyMode, WesiAiLobbyMode.smart);
    expect(conversation.toJson()['lobbyMode'], 'smart');
  });
}
