from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:80]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


def replace_all_nonempty(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count < 1:
        raise SystemExit(f'{path}: expected at least one anchor: {old[:80]!r}')
    p.write_text(text.replace(old, new), encoding='utf-8')


validator = 'lib/features/ai/runtime/wesi_artifact_validator.dart'
replace_once(
    validator,
    'size.clamp(1, 1024 * 1024)',
    'size.clamp(1, 1024 * 1024).toInt()',
)
replace_once(
    validator,
    '''      case WesiArtifactKind.docx:\n      case WesiArtifactKind.xlsx:\n      case WesiArtifactKind.pptx:\n      case WesiArtifactKind.apk:\n      case WesiArtifactKind.video:\n      case WesiArtifactKind.other:\n        return true;\n      case WesiArtifactKind.text:\n      case WesiArtifactKind.json:\n      case WesiArtifactKind.pdf:\n      case WesiArtifactKind.zip:\n      case WesiArtifactKind.windowsExecutable:\n      case WesiArtifactKind.png:\n      case WesiArtifactKind.jpeg:\n      case WesiArtifactKind.wav:\n      case WesiArtifactKind.mp3:\n      case WesiArtifactKind.sourceArchive:\n        return false;''',
    '''      case WesiArtifactKind.pdf:\n      case WesiArtifactKind.zip:\n      case WesiArtifactKind.sourceArchive:\n      case WesiArtifactKind.docx:\n      case WesiArtifactKind.xlsx:\n      case WesiArtifactKind.pptx:\n      case WesiArtifactKind.apk:\n      case WesiArtifactKind.windowsExecutable:\n      case WesiArtifactKind.wav:\n      case WesiArtifactKind.mp3:\n      case WesiArtifactKind.video:\n      case WesiArtifactKind.other:\n        return true;\n      case WesiArtifactKind.text:\n      case WesiArtifactKind.json:\n      case WesiArtifactKind.png:\n      case WesiArtifactKind.jpeg:\n        return false;''',
)
# `_BuiltinValidation.fail` carries runtime code/message values. It cannot be a
# const constructor because its nested result is built from those parameters.
replace_all_nonempty(
    validator,
    'const _BuiltinValidation.fail(',
    '_BuiltinValidation.fail(',
)
# A RandomAccessFile cannot be closed while an async read is still pending.
# Await the read before the finally block closes the handle.
replace_once(
    validator,
    '      return handle.read(count);',
    '      return await handle.read(count);',
)

engine = 'lib/features/ai/runtime/wesi_self_debug_engine.dart'
replace_once(
    engine,
    '''    for (final step in steps) {\n      if (_wallExpired(startedAt)) return _StepRun(false, toolCalls);\n      if (toolCalls >= limits.maxToolCalls) return _StepRun(false, toolCalls);\n      toolCalls++;''',
    '''    for (final step in steps) {\n      if (_wallExpired(startedAt)) {\n        evidence.add(const WesiDebugEvidence(\n          stepId: 'runtime-limit',\n          tool: 'self-debug.wall-time',\n          ok: false,\n          code: 'WSD_WALL_TIME_EXCEEDED',\n          exitCode: null,\n          summary: 'Self-debug wall-time limit reached',\n        ));\n        return _StepRun(false, toolCalls);\n      }\n      if (toolCalls >= limits.maxToolCalls) {\n        evidence.add(const WesiDebugEvidence(\n          stepId: 'runtime-limit',\n          tool: 'self-debug.tool-budget',\n          ok: false,\n          code: 'WSD_TOOL_CALL_LIMIT',\n          exitCode: null,\n          summary: 'Self-debug tool-call limit reached',\n        ));\n        return _StepRun(false, toolCalls);\n      }\n      toolCalls++;''',
)

observer = 'lib/features/ai/runtime/wesi_self_debug_job_observer.dart'
replace_once(
    observer,
    '''class WesiSelfDebugJobObserver implements WesiSelfDebugObserver {\n  final WesiJobCoordinator coordinator;\n  final String jobId;\n\n  const WesiSelfDebugJobObserver({\n    required this.coordinator,\n    required this.jobId,\n  });''',
    '''class WesiSelfDebugJobObserver implements WesiSelfDebugObserver {\n  final WesiJobCoordinator coordinator;\n  final String jobId;\n  double _lastProgress = 0;\n\n  WesiSelfDebugJobObserver({\n    required this.coordinator,\n    required this.jobId,\n  });''',
)
replace_once(
    observer,
    '''  Future<void> onProgress(WesiSelfDebugProgress progress) async {\n    await coordinator.updateProgress(\n      jobId,\n      progress: _progressFor(progress.phase),\n      stage: _stageFor(progress),\n    );\n  }''',
    '''  Future<void> onProgress(WesiSelfDebugProgress progress) async {\n    final requested = _progressFor(progress.phase);\n    final monotonic = requested < _lastProgress ? _lastProgress : requested;\n    _lastProgress = monotonic;\n    await coordinator.updateProgress(\n      jobId,\n      progress: monotonic,\n      stage: _stageFor(progress),\n    );\n  }''',
)

doc = 'docs/WESI_AI_SELF_DEBUG_ARTIFACTS.md'
replace_once(
    doc,
    'Built-in validators cover bounded UTF-8 text, JSON, PDF header, ZIP signature, PE/MZ executable header, PNG/JPEG, WAV and basic MP3 headers.\n\nComplex container/runtime formats such as DOCX/XLSX/PPTX/APK/video require a trusted external validator. File extension or model assertion is insufficient.',
    'Built-in prechecks cover bounded UTF-8 text, JSON, PDF/ZIP/PE/image/audio signatures. Only UTF-8 text, JSON, PNG and JPEG may pass without a second validator.\n\nPDF/ZIP/source archives, DOCX/XLSX/PPTX/APK, Windows executables, WAV/MP3, video and unknown formats require a trusted external validator after the built-in precheck. File extension, magic bytes or model assertion alone are insufficient.',
)

tracker = 'docs/WESI_AI_STAGE_TRACKER.md'
replace_once(tracker, '# Wesi AI — Stage Tracker 8/16', '# Wesi AI — Stage Tracker 9/16')
replace_once(
    tracker,
    '| 8/16 | **IN PROGRESS** | Resource Scheduler, L0–L4 adaptive classification, resource/foreground policy, bounded durable jobs, checkpoints, pause/resume and `waiting_for_worker`. |',
    '| 8/16 | **DONE** | Adaptive L0–L4 Resource Scheduler, trusted capability/resource/foreground policy, Control Plane heavy-work boundary, bounded durable job journal, checkpoints, pause/resume, `waiting_for_worker` and coordinator integration. PR #170, main `4fca3101927d4686e365aaf33530786ea7345b82`. Full PR analyze/test, Android debug build and Windows release build passed. No production deploy/release triggered. |',
)
replace_once(
    tracker,
    '| 9/16 | TODO | Self-debug loop + validated artifact creation/build delivery. |',
    '| 9/16 | **IN PROGRESS** | Bounded self-debug loop + objective verify/diagnose/repair/re-test + fail-closed validated artifact creation and delivery. |',
)

print('Stage 9 hardening applied')
