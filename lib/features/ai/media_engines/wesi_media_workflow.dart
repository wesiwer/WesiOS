import 'dart:io';

import 'wesi_media_engine_runner.dart';

/// Stage 14 media workflow contract.
///
/// Media work is treated as L4: it must execute on a suitable local/remote
/// worker, never on the Control Plane VPS. Inputs and outputs are bounded and
/// every returned artifact must exist before the workflow can report success.
enum WesiMediaWorkflowKind {
  imageGenerate,
  imageEdit,
  imageReference,
  musicGenerate,
  musicStems,
  videoCompose,
  videoVoice,
  videoSfx,
  videoSubtitles,
}

class WesiMediaWorkflowRequest {
  final WesiMediaWorkflowKind kind;
  final String prompt;
  final List<String> inputPaths;
  final Map<String, dynamic> options;

  const WesiMediaWorkflowRequest({
    required this.kind,
    required this.prompt,
    this.inputPaths = const [],
    this.options = const {},
  });

  String get mediaType => switch (kind) {
        WesiMediaWorkflowKind.imageGenerate ||
        WesiMediaWorkflowKind.imageEdit ||
        WesiMediaWorkflowKind.imageReference => 'image',
        WesiMediaWorkflowKind.musicGenerate ||
        WesiMediaWorkflowKind.musicStems => 'music',
        _ => 'video',
      };

  bool get requiresInput => switch (kind) {
        WesiMediaWorkflowKind.imageEdit ||
        WesiMediaWorkflowKind.imageReference ||
        WesiMediaWorkflowKind.musicStems ||
        WesiMediaWorkflowKind.videoCompose ||
        WesiMediaWorkflowKind.videoVoice ||
        WesiMediaWorkflowKind.videoSfx ||
        WesiMediaWorkflowKind.videoSubtitles => true,
        _ => false,
      };
}

class WesiMediaWorkflowResult {
  final bool ok;
  final String code;
  final String? outputPath;
  final String? mimeType;

  const WesiMediaWorkflowResult({
    required this.ok,
    required this.code,
    this.outputPath,
    this.mimeType,
  });
}

class WesiMediaWorkflow {
  static const int maxInputs = 16;
  static const int maxPromptChars = 12000;
  static const int maxInputBytes = 2 * 1024 * 1024 * 1024;

  const WesiMediaWorkflow._();

  static Future<WesiMediaWorkflowResult> run(
    WesiMediaWorkflowRequest request, {
    required bool isWorker,
  }) async {
    if (!isWorker) {
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_REQUIRES_WORKER',
      );
    }
    final prompt = request.prompt.trim();
    if (prompt.isEmpty || prompt.length > maxPromptChars) {
      return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_REQUEST_INVALID');
    }
    if (request.inputPaths.length > maxInputs ||
        (request.requiresInput && request.inputPaths.isEmpty)) {
      return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_INPUT_INVALID');
    }

    final verifiedInputs = <String>[];
    var totalBytes = 0;
    for (final rawPath in request.inputPaths) {
      final file = File(rawPath);
      if (!file.isAbsolute || !await file.exists()) {
        return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_INPUT_INVALID');
      }
      final resolved = await file.resolveSymbolicLinks();
      final resolvedFile = File(resolved);
      if (!await resolvedFile.exists()) {
        return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_INPUT_INVALID');
      }
      totalBytes += await resolvedFile.length();
      if (totalBytes > maxInputBytes) {
        return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_INPUT_TOO_LARGE');
      }
      verifiedInputs.add(resolved);
    }

    final result = await WesiMediaEngineRunner.run(<String, dynamic>{
      'mediaType': request.mediaType,
      'prompt': prompt,
      'options': <String, dynamic>{
        ...request.options,
        'workflow': request.kind.name,
        'inputs': verifiedInputs,
      },
    });
    if (!result.ok || result.outputPath == null) {
      return WesiMediaWorkflowResult(ok: false, code: result.code);
    }
    final artifact = File(result.outputPath!);
    if (!await artifact.exists() || await artifact.length() <= 0) {
      return const WesiMediaWorkflowResult(ok: false, code: 'WAI_MEDIA_ARTIFACT_INVALID');
    }
    return WesiMediaWorkflowResult(
      ok: true,
      code: 'OK',
      outputPath: artifact.path,
      mimeType: result.mimeType,
    );
  }
}
