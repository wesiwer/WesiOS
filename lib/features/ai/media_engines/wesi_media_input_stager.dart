import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

import '../models/wesi_ai_attachment.dart';
import 'wesi_media_local_request.dart';
import 'wesi_media_workflow.dart';

class WesiMediaStagingException implements Exception {
  final String code;

  const WesiMediaStagingException(this.code);

  @override
  String toString() => code;
}

class WesiMediaStagedInputs {
  final Directory? directory;
  final List<String> paths;

  const WesiMediaStagedInputs({
    required this.directory,
    required this.paths,
  });

  Future<void> cleanup() async {
    final dir = directory;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {
      // Best-effort cleanup. A later temp cleanup may remove leftovers.
    }
  }
}

/// Copies only explicitly selected current-turn attachments into an app-owned
/// temporary directory before a local media engine can read them.
///
/// The server/model never supplies a trusted filesystem path. Even a file that
/// originally came from a local path is copied by value into this staging area.
class WesiMediaInputStager {
  static const int copyChunkBytes = 1024 * 1024;
  static final Random _random = Random.secure();

  const WesiMediaInputStager._();

  static Future<WesiMediaStagedInputs> stage(
    Map<String, dynamic> rawRequest,
    List<WesiAiAttachment> attachments, {
    Directory? rootDirectory,
  }) async {
    final request = WesiMediaLocalRequestSanitizer.sanitize(rawRequest);
    if (request == null) {
      throw const WesiMediaStagingException('WAI_MEDIA_REQUEST_INVALID');
    }
    final indexes = (request['attachmentIndexes'] as List)
        .map((item) => item as int)
        .toList(growable: false);
    if (indexes.isEmpty) {
      return const WesiMediaStagedInputs(
        directory: null,
        paths: <String>[],
      );
    }
    if (attachments.isEmpty) {
      throw const WesiMediaStagingException(
        'WAI_MEDIA_INPUT_NOT_AVAILABLE',
      );
    }

    var totalBytes = 0;
    for (final index in indexes) {
      if (index < 0 || index >= attachments.length) {
        throw const WesiMediaStagingException(
          'WAI_MEDIA_INPUT_NOT_AVAILABLE',
        );
      }
      final attachment = attachments[index];
      if (attachment.byteSize <= 0) {
        throw const WesiMediaStagingException('WAI_MEDIA_INPUT_INVALID');
      }
      totalBytes += attachment.byteSize;
      if (totalBytes > WesiMediaWorkflow.maxInputBytes) {
        throw const WesiMediaStagingException(
          'WAI_MEDIA_INPUT_TOO_LARGE',
        );
      }
    }

    final root = rootDirectory ?? await getTemporaryDirectory();
    final base = Directory(
      '${root.path}${Platform.pathSeparator}wesi-ai-media-inputs',
    );
    await base.create(recursive: true);
    final nonce = _random.nextInt(0x7fffffff).toRadixString(16);
    final session = Directory(
      '${base.path}${Platform.pathSeparator}'
      'stage_${DateTime.now().microsecondsSinceEpoch}_$nonce',
    );
    await session.create(recursive: true);

    final paths = <String>[];
    try {
      for (var position = 0; position < indexes.length; position++) {
        final attachment = attachments[indexes[position]];
        final ext = _extensionFor(attachment);
        final fileNonce = _random.nextInt(0x7fffffff).toRadixString(16);
        final target = File(
          '${session.path}${Platform.pathSeparator}'
          'input_${position}_$fileNonce.$ext',
        );
        final sink = target.openWrite();
        var offset = 0;
        try {
          while (offset < attachment.byteSize) {
            final remaining = attachment.byteSize - offset;
            final requested = min(copyChunkBytes, remaining);
            final chunk = await attachment.readChunk(offset, requested);
            if (chunk.lengthInBytes != requested) {
              throw const WesiMediaStagingException(
                'WAI_MEDIA_INPUT_CHANGED',
              );
            }
            sink.add(chunk);
            offset += chunk.lengthInBytes;
          }
          await sink.flush();
        } finally {
          await sink.close();
        }
        if (!await target.exists() ||
            await target.length() != attachment.byteSize) {
          throw const WesiMediaStagingException(
            'WAI_MEDIA_INPUT_CHANGED',
          );
        }
        paths.add(target.absolute.path);
      }
      return WesiMediaStagedInputs(
        directory: session,
        paths: List<String>.unmodifiable(paths),
      );
    } catch (_) {
      try {
        if (await session.exists()) await session.delete(recursive: true);
      } catch (_) {}
      rethrow;
    }
  }

  static String _extensionFor(WesiAiAttachment attachment) {
    final mime = attachment.mimeType.toLowerCase().split(';').first.trim();
    const byMime = <String, String>{
      'image/png': 'png',
      'image/jpeg': 'jpg',
      'image/webp': 'webp',
      'audio/mpeg': 'mp3',
      'audio/mp3': 'mp3',
      'audio/wav': 'wav',
      'audio/x-wav': 'wav',
      'audio/flac': 'flac',
      'audio/ogg': 'ogg',
      'audio/mp4': 'm4a',
      'audio/aac': 'aac',
      'video/mp4': 'mp4',
      'video/webm': 'webm',
      'video/quicktime': 'mov',
      'video/x-matroska': 'mkv',
      'text/plain': 'txt',
      'text/vtt': 'vtt',
      'application/x-subrip': 'srt',
    };
    return byMime[mime] ?? 'bin';
  }
}

class WesiMediaTurnExecutor {
  const WesiMediaTurnExecutor._();

  static Future<WesiMediaWorkflowResult> run(
    Map<String, dynamic> rawRequest,
    List<WesiAiAttachment> attachments, {
    Directory? stagingRoot,
  }) async {
    WesiMediaStagedInputs? staged;
    try {
      staged = await WesiMediaInputStager.stage(
        rawRequest,
        attachments,
        rootDirectory: stagingRoot,
      );
      return await WesiMediaWorkflow.runLocalRequest(
        rawRequest,
        trustedInputPaths: staged.paths,
      );
    } on WesiMediaStagingException catch (error) {
      return WesiMediaWorkflowResult(ok: false, code: error.code);
    } on FormatException {
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_INPUT_INVALID',
      );
    } on FileSystemException {
      return const WesiMediaWorkflowResult(
        ok: false,
        code: 'WAI_MEDIA_INPUT_NOT_AVAILABLE',
      );
    } finally {
      await staged?.cleanup();
    }
  }
}
