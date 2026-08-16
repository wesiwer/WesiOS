from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"{label}: expected exactly one marker, found {count}")
    return text.replace(old, new, 1)


def replace_dart_method(text: str, marker: str, replacement: str) -> str:
    start = text.find(marker)
    if start < 0:
        raise SystemExit(f"method marker not found: {marker}")
    brace = text.find('{', start)
    if brace < 0:
        raise SystemExit("method opening brace not found")
    depth = 0
    quote = None
    escaped = False
    i = brace
    while i < len(text):
        ch = text[i]
        if quote is not None:
            if escaped:
                escaped = False
            elif ch == '\\':
                escaped = True
            elif ch == quote:
                quote = None
            i += 1
            continue
        if ch in ("'", '"'):
            quote = ch
            i += 1
            continue
        if ch == '{':
            depth += 1
        elif ch == '}':
            depth -= 1
            if depth == 0:
                return text[:start] + replacement + text[i + 1:]
        i += 1
    raise SystemExit("method closing brace not found")


# Capability registry: keep all media transformations under the existing
# media/generate WRITE permission boundary.
registry_path = Path('server/pb_hooks/wesi_ai_capability_registry.js')
registry = registry_path.read_text()
old_media = '''  generate_image: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_music: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_video: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
'''
new_media = '''  generate_image: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  edit_image: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  reference_image: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_music: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  separate_music_stems: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_video: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  compose_video: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  add_video_voice: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  add_video_sfx: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  add_video_subtitles: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
'''
registry_path.write_text(replace_once(registry, old_media, new_media, 'media registry'))

# API: one common sanitizer owns workflow/index/path validation.
api_path = Path('lib/features/ai/wesi_ai_api.dart')
api = api_path.read_text()
api = replace_once(
    api,
    "import 'models/wesi_ai_attachment.dart';",
    "import 'media_engines/wesi_media_local_request.dart';\nimport 'models/wesi_ai_attachment.dart';",
    'api sanitizer import',
)
api = replace_dart_method(
    api,
    '  static Map<String, dynamic>? _sanitizeLocalMediaRequest(',
    '''  static Map<String, dynamic>? _sanitizeLocalMediaRequest(
      Map<String, dynamic> raw) =>
      WesiMediaLocalRequestSanitizer.sanitize(raw);''',
)
api_path.write_text(api)

# Controller: current-turn attachments are available until the server reply
# finishes. Pass them only to the media executor; persisted/reloaded turns keep
# the empty default and therefore fail closed for input workflows.
controller_path = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
controller = controller_path.read_text()
controller = replace_once(
    controller,
    "import '../media_engines/wesi_media_workflow.dart';",
    "import '../media_engines/wesi_media_input_stager.dart';",
    'controller media import',
)
controller = replace_once(
    controller,
    '      _startPendingMedia(assistant);',
    '      _startPendingMedia(assistant, turnAttachments: attachments);',
    'assistant pending media call',
)
controller = replace_once(
    controller,
    '  void _startPendingMedia(WesiAiMessage message) {',
    '''  void _startPendingMedia(
    WesiAiMessage message, {
    List<WesiAiAttachment> turnAttachments = const <WesiAiAttachment>[],
  }) {''',
    'pending media signature',
)
controller = replace_once(
    controller,
    '''          unawaited(_runLocalMedia(
            message,
            Map<String, dynamic>.from(localRequest),
            key,
          ));''',
    '''          unawaited(_runLocalMedia(
            message,
            Map<String, dynamic>.from(localRequest),
            key,
            turnAttachments: turnAttachments,
          ));''',
    'local media invocation',
)
controller = replace_once(
    controller,
    '''  Future<void> _runLocalMedia(
    WesiAiMessage source,
    Map<String, dynamic> request,
    String key,
  ) async {''',
    '''  Future<void> _runLocalMedia(
    WesiAiMessage source,
    Map<String, dynamic> request,
    String key, {
    List<WesiAiAttachment> turnAttachments = const <WesiAiAttachment>[],
  }) async {''',
    'local media signature',
)
controller = replace_once(
    controller,
    '      final result = await WesiMediaWorkflow.runLocalRequest(request);',
    '''      final result = await WesiMediaTurnExecutor.run(
        request,
        turnAttachments,
      );''',
    'local media executor',
)
controller_path.write_text(controller)
