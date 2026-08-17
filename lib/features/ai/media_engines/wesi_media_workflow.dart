import 'dart:io';

import 'wesi_media_artifact_store.dart';
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
  videoGenerate,
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
        WesiMediaWorkflowKind.imageReference =>
          'image',
        WesiMediaWorkflowKind.musicGenerate ||
        WesiMediaWorkflowKind.musicStems =>
          'music',
        _ => 'video',
      };

  bool get requiresInput => switch (kind) {
        WesiMediaWorkflowKind.imageEdit ||
        WesiMediaWorkflowKind.imageReference ||
        WesiMediaWorkflowKind.musicStems ||
        WesiMediaWorkflowKind.videoCompose ||
        WesiMediaWorkflowKind.videoVoice ||
        WesiMediaWorkflowKind.videoSfx ||
        WesiMediaWorkflowKind.videoSubtitles =>
          true,
        _ => false,
      };
}

class WesiMediaWorkflowResult {
  final bool ok;
  final String code;
  final String? outputPath;
  final String? mimeType;
  final int? byteSize;
  final String? sha256Hex;

  const WesiMediaWorkflowResult({
    required this.ok,
    required this.code,
    this.outputPath,
    this.mimeType,
    this.byteSize,
    this.sha256Hex,
  });
}

class WesiMediaWorkflow {
  static const int maxInputs = 16;
  static const int maxPromptChars = 12000;
  static const int maxInputBytes = 2 * 1024 * 1024 * 1024;

  const WesiMediaWorkflow._();

  static bool get currentDeviceCanRunL4 =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static WesiMediaWorkflowRequest? fromLocalRequest(
    Map<String, dynamic> raw, {
    List<String> trustedInputPaths = const <String>[],
  }) {
    final mediaType = '${raw['mediaType'] ?? ''}'.trim().toLowerCase();
    final prompt = '${raw['prompt'] ?? ''}'.trim();
    final options = raw['options'] is Map
        ? Map<String, dynamic>.from(raw['options'] as Map)
        : <String, dynamic>{};
    final workflow = '${raw['workflow'] ?? options['workflow'] ?? ''}'.trim();
    final operation = '${raw['operation'] ?? options['operation'] ?? ''}'
        .trim()
        .toLowerCase();

    WesiMediaWorkflowKind? kind = switch (workflow) {
      'imageGenerate' => WesiMediaWorkflowKind.imageGenerate,
      'imageEdit' => WesiMediaWorkflowKind.imageEdit,
      'imageReference' => WesiMediaWorkflowKind.imageReference,
      'musicGenerate' => WesiMediaWorkflowKind.musicGenerate,
      'musicStems' => WesiMediaWorkflowKind.musicStems,
      'videoGenerate' => WesiMediaWorkflowKind.videoGenerate,
      'videoCompose' => WesiMediaWorkflowKind.videoCompose,
      'videoVoice' => WesiMediaWorkflowKind.videoVoice,
      'videoSfx' => WesiMediaWorkflowKind.videoSfx,
      'videoSubtitles' => WesiMediaWorkflowKind.videoSubtitles,
      _ => null,
    };

    kind ??= switch (mediaType) {
      'image' => switch (operation) {
          'edit' || 'imageedit' => WesiMediaWorkflowKind.imageEdit,
          'reference' ||
          'imagereference' =>
            WesiMediaWorkflowKind.imageReference,
          _ => WesiMediaWorkflowKind.imageGenerate,
        },
      'music' || 'audio' => switch (operation) {
          'stems' || 'musicstems' => WesiMediaWorkflowKind.musicStems,
          _ => WesiMediaWorkflowKind.musicGenerate,
        },
      'video' => switch (operation) {
          'compose' || 'videocompose' => WesiMediaWorkflowKind.videoCompose,
          'voice' || 'videovoice' => WesiMediaWorkflowKind.videoVoice,
          'sfx' || 'videosfx' => WesiMediaWorkflowKind.videoSfx,
          'subtitles' ||
          'videosubtitles' =>
            WesiMediaWorkflowKind.videoSubtitles,
          _ => WesiMediaWorkflowKind.videoGenerate,
        },
      _ => null,
    };
    if (kind == null || prompt.isEmpty) return null;

    // Filesystem paths returned by a model/server response are never trusted.
    // Input-based workflows receive paths only from the local attachment
    // stager, which owns and verifies those files before engine execution.
    final inputPaths = trustedInputPaths
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    options.remove('inputs');
    options.remove('inputPaths');

    return WesiMediaWorkflowRequest(
      kind: kind,
      prompt: prompt,
      inputPaths: inputPaths,
      options: options,
    );
  }

  static Future<WesiMediaWorkflowResult> runLocalRequest(
    Map<String, dynamic> raw, {
    List<String> trustedInputPaths = const <String>[],
  }) async {
    final request = fromLocalRequest(
      raw,
      trustedInputPaths: trustedInputPaths,
    );
    if (request == null) {
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_REQUEST_INVALID',
      );
    }
    return run(request, isWorker: currentDeviceCanRunL4);
  }

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
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_REQUEST_INVALID',
      );
    }
    if (request.inputPaths.length > maxInputs ||
        (request.requiresInput && request.inputPaths.isEmpty)) {
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_INPUT_INVALID',
      );
    }

    final verifiedInputs = <String>[];
    var totalBytes = 0;
    for (final rawPath in request.inputPaths) {
      final file = File(rawPath);
      if (!file.isAbsolute || !await file.exists()) {
        return const WesiMediaWorkflowResult(
          ok: false,
          code: 'WAI_MEDIA_INPUT_INVALID',
        );
      }
      final resolved = await file.resolveSymbolicLinks();
      final resolvedFile = File(resolved);
      if (!await resolvedFile.exists()) {
        return const WesiMediaWorkflowResult(
          ok: false,
          code: 'WAI_MEDIA_INPUT_INVALID',
        );
      }
      totalBytes += await resolvedFile.length();
      if (totalBytes > maxInputBytes) {
        return const WesiMediaWorkflowResult(
          ok: false,
          code: 'WAI_MEDIA_INPUT_TOO_LARGE',
        );
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

    final promoted = await WesiMediaArtifactStore.promote(
      sourcePath: result.outputPath!,
      mediaType: request.mediaType,
      mimeType: result.mimeType ?? '',
    );
    if (!promoted.ok || promoted.path == null) {
      return WesiMediaWorkflowResult(ok: false, code: promoted.code);
    }
    return WesiMediaWorkflowResult(
      ok: true,
      code: 'OK',
      outputPath: promoted.path,
      mimeType: promoted.mimeType,
      byteSize: promoted.byteSize,
      sha256Hex: promoted.sha256Hex,
    );
  }
}
