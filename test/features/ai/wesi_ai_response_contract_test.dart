import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('response contract decodes a JSON object', () {
    final value = WesiAiApi.decodeJsonObjectResponse(
      '{"ok":true,"answer":"OK"}',
      httpStatus: 200,
      contentType: 'application/json',
    );
    expect(value['ok'], isTrue);
    expect(value['answer'], 'OK');
  });

  test('response contract rejects HTML with actionable diagnostics', () {
    expect(
      () => WesiAiApi.decodeJsonObjectResponse(
        '<html><body>502 Bad Gateway</body></html>',
        httpStatus: 502,
        contentType: 'text/html',
        stage: 'LOBBY',
        component: 'WesiAiLobbyApi',
        operation: 'decode response',
        lastSuccess: 'LOBBY_RESPONSE_RECEIVED',
      ),
      throwsA(
        isA<WesiAiApiException>()
            .having((e) => e.code, 'code', 'WAI_BAD_SERVER_RESPONSE')
            .having((e) => e.httpStatus, 'httpStatus', 502)
            .having((e) => e.stage, 'stage', 'LOBBY')
            .having((e) => e.detail, 'detail', contains('text/html'))
            .having((e) => e.detail, 'detail', contains('502 Bad Gateway')),
      ),
    );
  });

  test('response contract rejects non-object JSON roots', () {
    expect(
      () => WesiAiApi.decodeJsonObjectResponse(
        '[{"answer":"wrong envelope"}]',
        httpStatus: 200,
        contentType: 'application/json',
      ),
      throwsA(isA<WesiAiApiException>().having(
        (e) => e.code,
        'code',
        'WAI_BAD_SERVER_RESPONSE',
      )),
    );
  });
}
