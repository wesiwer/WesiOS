from pathlib import Path
import re


def sub_once(path: str, pattern: str, replacement: str, label: str) -> None:
    p = Path(path)
    text = p.read_text()
    out, n = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if n != 1:
        raise SystemExit(f"{label}: expected 1 replacement, got {n}")
    p.write_text(out)


api = "lib/features/ai/wesi_ai_api.dart"
sub_once(
    api,
    r"httpStatus: response\.statusCode,\s*stage: 'MAIN',\s*component: 'WesiOS Main',\s*operation: 'chat',\s*lastSuccess: 'CLIENT',",
    """httpStatus: response.statusCode,
          stage: response.statusCode == 401 || response.statusCode == 403
              ? 'AUTH'
              : 'MAIN',
          component: response.statusCode == 401 || response.statusCode == 403
              ? 'WesiOS Auth'
              : 'WesiOS Main',
          operation: 'chat',
          lastSuccess: 'CLIENT',""",
    "main-auth-classification",
)
sub_once(
    api,
    r"httpStatus: response\.statusCode,\s*stage: 'STREAM_GATEWAY',\s*component: 'Streaming edge',\s*operation: 'chat\.stream',\s*lastSuccess: 'CLIENT_AUTH',",
    """httpStatus: response.statusCode,
        stage: response.statusCode == 401 || response.statusCode == 403
            ? 'AUTH'
            : 'STREAM_GATEWAY',
        component: response.statusCode == 401 || response.statusCode == 403
            ? 'Streaming Auth'
            : 'Streaming edge',
        operation: 'chat.stream',
        lastSuccess: response.statusCode == 401 || response.statusCode == 403
            ? 'CLIENT'
            : 'CLIENT_AUTH',""",
    "stream-auth-classification",
)

controller = "lib/features/ai/controllers/wesi_ai_chat_controller.dart"
sub_once(
    controller,
    r"String streamedToolDetail\(Map<String, dynamic> raw\) \{\s*final parts = <String>\[\];",
    """String streamedToolDetail(Map<String, dynamic> raw) {
      final parts = <String>[];
      final rawDiagnostic = raw['diagnostic'];
      if (rawDiagnostic is Map) {
        final diagnostic = Map<String, dynamic>.from(rawDiagnostic);
        final stage = '${diagnostic['stage'] ?? ''}'.trim();
        final component = '${diagnostic['component'] ?? ''}'.trim();
        final operation = '${diagnostic['operation'] ?? ''}'.trim();
        final diagnosticCode = '${diagnostic['code'] ?? ''}'.trim();
        final lastSuccess = '${diagnostic['lastSuccess'] ?? ''}'.trim();
        final requestId = '${diagnostic['requestId'] ?? ''}'.trim();
        if (stage.isNotEmpty) parts.add('Этап: $stage');
        if (component.isNotEmpty) parts.add('Компонент: $component');
        if (operation.isNotEmpty) parts.add('Операция: $operation');
        if (diagnosticCode.isNotEmpty) parts.add('Код: $diagnosticCode');
        if (lastSuccess.isNotEmpty) parts.add('После: $lastSuccess');
        if (requestId.isNotEmpty) parts.add('Request ID: $requestId');
      }""",
    "tool-diagnostic-detail",
)
sub_once(
    controller,
    r"\} else if \(type == 'activity'\) \{\s*activity\.add\(activityEntry\(\s*kind: '\$\{raw\['kind'\] \?\? 'reasoning'\}',\s*label: '\$\{raw\['label'\] \?\? 'Ход работы'\}'\.trim\(\),\s*sourceName: name,\s*detail: '\$\{raw\['detail'\] \?\? raw\['message'\] \?\? ''\}'\.trim\(\),",
    """} else if (type == 'activity') {
        var detail = '${raw['detail'] ?? raw['message'] ?? ''}'.trim();
        final rawDiagnostic = raw['diagnostic'];
        if (rawDiagnostic is Map) {
          final diagnostic = Map<String, dynamic>.from(rawDiagnostic);
          final diagnosticParts = <String>[
            if ('${diagnostic['stage'] ?? ''}'.trim().isNotEmpty)
              'Этап: ${diagnostic['stage']}',
            if ('${diagnostic['component'] ?? ''}'.trim().isNotEmpty)
              'Компонент: ${diagnostic['component']}',
            if ('${diagnostic['code'] ?? ''}'.trim().isNotEmpty)
              'Код: ${diagnostic['code']}',
            if ('${diagnostic['requestId'] ?? ''}'.trim().isNotEmpty)
              'Request ID: ${diagnostic['requestId']}',
          ];
          final diagnosticText = diagnosticParts.join(' · ');
          if (diagnosticText.isNotEmpty && !detail.contains(diagnosticText)) {
            detail = detail.isEmpty ? diagnosticText : '$detail\\n$diagnosticText';
          }
        }
        activity.add(activityEntry(
          kind: '${raw['kind'] ?? 'reasoning'}',
          label: '${raw['label'] ?? 'Ход работы'}'.trim(),
          sourceName: name,
          detail: detail,""",
    "generic-activity-diagnostic-detail",
)

test = Path("test/wesi_ai_diagnostics_contract_test.dart")
text = test.read_text()
marker = "expect(error.displayMessage, contains('Request ID: wai_test_123'));"
if marker not in text:
    raise SystemExit("diagnostic test marker missing")
addition = """expect(error.displayMessage, contains('Request ID: wai_test_123'));
    final apiSource = File('lib/features/ai/wesi_ai_api.dart').readAsStringSync();
    expect(apiSource, contains("? 'AUTH'"));
    final controllerSource = File('lib/features/ai/controllers/wesi_ai_chat_controller.dart').readAsStringSync();
    expect(controllerSource, contains("parts.add('Этап: $stage')"));
    expect(controllerSource, contains("parts.add('Request ID: $requestId')"));"""
test.write_text(text.replace(marker, addition, 1))
