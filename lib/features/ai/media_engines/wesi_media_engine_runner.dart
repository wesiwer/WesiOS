import 'dart:io';

import 'wesi_media_engine_service.dart';

class WesiMediaRunResult {
  final bool ok;
  final String code;
  final String? outputPath;
  final String? mimeType;

  const WesiMediaRunResult({
    required this.ok,
    required this.code,
    this.outputPath,
    this.mimeType,
  });
}

/// Executes only a server-verified localMediaRequest produced by Wesi tools.
/// The model never chooses an executable path. The selected engine comes from
/// the enum and the output must stay inside that engine's managed directory.
class WesiMediaEngineRunner {
  const WesiMediaEngineRunner._();

  static Future<WesiMediaRunResult> run(Map<String, dynamic> raw) async {
    final mediaType = '${raw['mediaType'] ?? ''}'.trim().toLowerCase();
    final kind = switch (mediaType) {
      'image' => WesiMediaEngineKind.image,
      'music' || 'audio' => WesiMediaEngineKind.music,
      'video' => WesiMediaEngineKind.video,
      _ => null,
    };
    if (kind == null) {
      return const WesiMediaRunResult(
          ok: false, code: 'WAI_MEDIA_REQUEST_INVALID');
    }
    if (!await WesiMediaEngineService.isInstalled(kind)) {
      return const WesiMediaRunResult(
          ok: false, code: 'WAI_MEDIA_ENGINE_NOT_INSTALLED');
    }

    final prompt = '${raw['prompt'] ?? ''}'.trim();
    if (prompt.isEmpty || prompt.length > 12000) {
      return const WesiMediaRunResult(
          ok: false, code: 'WAI_MEDIA_REQUEST_INVALID');
    }
    final options = raw['options'] is Map
        ? Map<String, dynamic>.from(raw['options'] as Map)
        : <String, dynamic>{};
    final result =
        await WesiMediaEngineService.generate(kind, <String, dynamic>{
      'prompt': prompt,
      'options': options,
    });
    if (result['ok'] != true) {
      return WesiMediaRunResult(
        ok: false,
        code: '${result['code'] ?? 'WAI_MEDIA_ENGINE_FAILED'}',
      );
    }

    final relative = '${result['output'] ?? ''}'.replaceAll('\\', '/').trim();
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.split('/').contains('..')) {
      return const WesiMediaRunResult(
          ok: false, code: 'WAI_MEDIA_ENGINE_BAD_OUTPUT');
    }
    final root = await WesiMediaEngineService.engineDir(kind);
    final output = File(
        '${root.path}${Platform.pathSeparator}${relative.replaceAll('/', Platform.pathSeparator)}');
    final rootPath = root.absolute.path;
    final outputPath = output.absolute.path;
    final prefix = rootPath.endsWith(Platform.pathSeparator)
        ? rootPath
        : '$rootPath${Platform.pathSeparator}';
    if (!outputPath.startsWith(prefix) || !await output.exists()) {
      return const WesiMediaRunResult(
          ok: false, code: 'WAI_MEDIA_ENGINE_BAD_OUTPUT');
    }
    return WesiMediaRunResult(
      ok: true,
      code: 'OK',
      outputPath: outputPath,
      mimeType: '${result['mimeType'] ?? ''}'.trim(),
    );
  }
}
