import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class WesiMediaArtifactResult {
  final bool ok;
  final String code;
  final String? path;
  final String? mimeType;
  final int? byteSize;
  final String? sha256Hex;

  const WesiMediaArtifactResult({
    required this.ok,
    required this.code,
    this.path,
    this.mimeType,
    this.byteSize,
    this.sha256Hex,
  });
}

/// Durable application-owned storage for successful local media results.
///
/// Raw paths returned by a media engine never become chat history. A result is
/// first checked against a media-specific MIME/size allowlist, copied into an
/// opaque WesiOS path, verified byte-for-byte by SHA-256, then atomically
/// renamed from `.part` to its final artifact name.
class WesiMediaArtifactStore {
  static const int maxImageBytes = 128 * 1024 * 1024;
  static const int maxMusicBytes = 512 * 1024 * 1024;
  static const int maxVideoBytes = 2 * 1024 * 1024 * 1024;

  static final Random _random = Random.secure();

  const WesiMediaArtifactStore._();

  static const Map<String, String> _imageMimeExtensions = <String, String>{
    'image/png': 'png',
    'image/jpeg': 'jpg',
    'image/webp': 'webp',
  };
  static const Map<String, String> _musicMimeExtensions = <String, String>{
    'audio/mpeg': 'mp3',
    'audio/mp3': 'mp3',
    'audio/wav': 'wav',
    'audio/x-wav': 'wav',
    'audio/flac': 'flac',
    'audio/ogg': 'ogg',
    'audio/mp4': 'm4a',
    'audio/aac': 'aac',
    // A stems workflow may emit one bounded archive containing its tracks.
    'application/zip': 'zip',
  };
  static const Map<String, String> _videoMimeExtensions = <String, String>{
    'video/mp4': 'mp4',
    'video/webm': 'webm',
    'video/quicktime': 'mov',
    'video/x-matroska': 'mkv',
  };

  static Future<WesiMediaArtifactResult> promote({
    required String sourcePath,
    required String mediaType,
    required String mimeType,
    Directory? rootDirectory,
  }) async {
    final normalizedType = mediaType.trim().toLowerCase();
    final normalizedMime = mimeType.split(';').first.trim().toLowerCase();
    final mimeExtensions = _mimeExtensions(normalizedType);
    final extension = mimeExtensions?[normalizedMime];
    final maxBytes = _maxBytes(normalizedType);
    if (extension == null || maxBytes == null) {
      return const WesiMediaArtifactResult(
        ok: false,
        code: 'WAI_MEDIA_ARTIFACT_MIME_FORBIDDEN',
      );
    }

    try {
      final source = File(sourcePath);
      if (!source.isAbsolute || !await source.exists()) {
        return const WesiMediaArtifactResult(
          ok: false,
          code: 'WAI_MEDIA_ARTIFACT_INVALID',
        );
      }
      final resolvedSource = File(await source.resolveSymbolicLinks());
      if (!await resolvedSource.exists()) {
        return const WesiMediaArtifactResult(
          ok: false,
          code: 'WAI_MEDIA_ARTIFACT_INVALID',
        );
      }
      final sourceBytes = await resolvedSource.length();
      if (sourceBytes <= 0 || sourceBytes > maxBytes) {
        return const WesiMediaArtifactResult(
          ok: false,
          code: 'WAI_MEDIA_ARTIFACT_SIZE_INVALID',
        );
      }

      final sourceDigest = await sha256.bind(resolvedSource.openRead()).first;
      final sourceHex = sourceDigest.toString();
      final root = rootDirectory ?? await _defaultRoot();
      final typeRoot = Directory(
        '${root.path}${Platform.pathSeparator}$normalizedType',
      );
      await typeRoot.create(recursive: true);

      final opaque = '${DateTime.now().microsecondsSinceEpoch}_'
          '${_random.nextInt(0x7fffffff).toRadixString(16)}';
      final finalFile = File(
        '${typeRoot.path}${Platform.pathSeparator}$opaque.$extension',
      );
      final partFile = File('${finalFile.path}.part');
      IOSink? sink;
      try {
        sink = partFile.openWrite(mode: FileMode.writeOnly);
        await resolvedSource.openRead().pipe(sink);
        sink = null;
        final copiedBytes = await partFile.length();
        if (copiedBytes != sourceBytes ||
            copiedBytes <= 0 ||
            copiedBytes > maxBytes) {
          return const WesiMediaArtifactResult(
            ok: false,
            code: 'WAI_MEDIA_ARTIFACT_CHANGED',
          );
        }
        final copiedDigest = await sha256.bind(partFile.openRead()).first;
        if (copiedDigest.toString() != sourceHex) {
          return const WesiMediaArtifactResult(
            ok: false,
            code: 'WAI_MEDIA_ARTIFACT_CHANGED',
          );
        }
        await partFile.rename(finalFile.path);
        return WesiMediaArtifactResult(
          ok: true,
          code: 'OK',
          path: finalFile.absolute.path,
          mimeType: normalizedMime,
          byteSize: sourceBytes,
          sha256Hex: sourceHex,
        );
      } finally {
        try {
          await sink?.close();
        } catch (_) {}
        try {
          if (await partFile.exists()) await partFile.delete();
        } catch (_) {}
      }
    } on FileSystemException {
      return const WesiMediaArtifactResult(
        ok: false,
        code: 'WAI_MEDIA_ARTIFACT_IO_FAILED',
      );
    }
  }

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(
      '${support.path}${Platform.pathSeparator}wesi-ai'
      '${Platform.pathSeparator}media-artifacts',
    );
  }

  static Map<String, String>? _mimeExtensions(String mediaType) =>
      switch (mediaType) {
        'image' => _imageMimeExtensions,
        'music' || 'audio' => _musicMimeExtensions,
        'video' => _videoMimeExtensions,
        _ => null,
      };

  static int? _maxBytes(String mediaType) => switch (mediaType) {
        'image' => maxImageBytes,
        'music' || 'audio' => maxMusicBytes,
        'video' => maxVideoBytes,
        _ => null,
      };
}
