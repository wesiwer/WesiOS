import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/wesi_ai_api.dart';

void main() {
  test('diagnostic exception renders actionable technical details', () {
    final error = WesiAiApiException.fromPayload(
        'WAI_TOOL_FAILED', 'Инструмент не выполнил запрос', <String, dynamic>{
      'requestId': 'wai_test_123',
      'diagnostic': <String, dynamic>{
        'stage': 'TOOL',
        'component': 'finance_summary',
        'operation': 'tool.execute',
        'httpStatus': 500,
        'lastSuccess': 'TOOL_DISPATCH',
        'durationMs': 42,
        'detail': 'read failed'
      }
    });
    expect(error.displayMessage, contains('Этап: TOOL'));
    expect(error.displayMessage, contains('Компонент: finance_summary'));
    expect(error.displayMessage, contains('Request ID: wai_test_123'));
    final apiSource =
        File('lib/features/ai/wesi_ai_api.dart').readAsStringSync();
    expect(apiSource, contains("? 'AUTH'"));
    final controllerSource =
        File('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
            .readAsStringSync();
    expect(controllerSource, contains("parts.add('Этап: \$stage')"));
    expect(controllerSource, contains("parts.add('Request ID: \$requestId')"));
  });
  test('server and gateway expose diagnostic contract', () {
    final gateway =
        File('server/wesi-ai-stream/gateway.mjs').readAsStringSync();
    final routes =
        File('server/pb_hooks/wesi_ai_routes.pb.js').readAsStringSync();
    expect(gateway, contains('diagnosticPayload'));
    expect(gateway, contains("stage: 'PROVIDER'"));
    expect(gateway, contains("stage: 'TOOL'"));
    expect(routes, contains('diagnostic("PROVIDER"'));
    expect(routes, contains('diagnostic("TOOL"'));
  });
}
