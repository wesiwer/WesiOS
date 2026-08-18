class WesiMediaOutputValidationResult {
  final bool ok;
  final String code;

  const WesiMediaOutputValidationResult({
    required this.ok,
    required this.code,
  });
}

/// Validates structured evidence emitted by a verified media engine package.
///
/// `ok: true` from an engine is never sufficient for music/video artifacts.
/// The engine package must prove that it inspected the output and must return
/// bounded metadata rather than filesystem paths. Video/audio probes are
/// produced by ffprobe inside the verified engine package; stems archives use
/// a per-stem manifest with hashes and durations.
class WesiMediaOutputValidator {
  static const String protocol = 'wesi-media-v1';
  static const int maxDurationMs = 24 * 60 * 60 * 1000;
  static const int maxStemCount = 32;
  static const int maxStemBytes = 512 * 1024 * 1024;

  const WesiMediaOutputValidator._();

  static WesiMediaOutputValidationResult validate({
    required String mediaType,
    required String workflow,
    required String mimeType,
    required Object? evidence,
  }) {
    if (evidence is! Map) return _failed('WAI_MEDIA_VALIDATION_MISSING');
    final validation = Map<String, dynamic>.from(evidence);
    if ('${validation['validator'] ?? ''}'.trim() != protocol) {
      return _failed('WAI_MEDIA_VALIDATION_UNTRUSTED');
    }

    final type = mediaType.trim().toLowerCase();
    final mime = mimeType.split(';').first.trim().toLowerCase();
    if (type == 'image') return _validateImage(mime, validation['image']);
    if (type == 'video') return _validateProbe(mime, validation['probe'], requireVideo: true);
    if (type == 'music' || type == 'audio') {
      if (workflow == 'musicStems') {
        if (mime != 'application/zip') return _failed('WAI_MEDIA_VALIDATION_MIME_MISMATCH');
        return _validateStems(validation['stems']);
      }
      if (workflow == 'musicExport' && mime == 'application/zip') {
        return _validateStems(validation['stems']);
      }
      return _validateProbe(mime, validation['probe'], requireVideo: false);
    }
    return _failed('WAI_MEDIA_VALIDATION_UNSUPPORTED');
  }

  static WesiMediaOutputValidationResult _validateImage(String mime, Object? raw) {
    if (raw is! Map) return _failed('WAI_MEDIA_VALIDATION_INVALID');
    final image = Map<String, dynamic>.from(raw);
    final width = _int(image['width']);
    final height = _int(image['height']);
    final format = '${image['format'] ?? ''}'.trim().toLowerCase();
    const expected = <String, String>{
      'image/png': 'png',
      'image/jpeg': 'jpeg',
      'image/webp': 'webp',
    };
    if (width == null || height == null || width <= 0 || height <= 0 || width > 32768 || height > 32768) {
      return _failed('WAI_MEDIA_VALIDATION_INVALID');
    }
    if (expected[mime] != format) return _failed('WAI_MEDIA_VALIDATION_MIME_MISMATCH');
    return _ok();
  }

  static WesiMediaOutputValidationResult _validateProbe(
    String mime,
    Object? raw, {
    required bool requireVideo,
  }) {
    if (raw is! Map) return _failed('WAI_MEDIA_VALIDATION_INVALID');
    final probe = Map<String, dynamic>.from(raw);
    if ('${probe['engine'] ?? ''}'.trim().toLowerCase() != 'ffprobe') {
      return _failed('WAI_MEDIA_VALIDATION_UNTRUSTED');
    }
    final durationMs = _int(probe['durationMs']);
    if (durationMs == null || durationMs <= 0 || durationMs > maxDurationMs) {
      return _failed('WAI_MEDIA_VALIDATION_DURATION_INVALID');
    }
    final container = '${probe['container'] ?? ''}'.trim().toLowerCase();
    final expectedContainers = _containersForMime(mime);
    if (expectedContainers == null || !expectedContainers.contains(container)) {
      return _failed('WAI_MEDIA_VALIDATION_CONTAINER_INVALID');
    }
    final rawStreams = probe['streams'];
    if (rawStreams is! List || rawStreams.isEmpty || rawStreams.length > 64) {
      return _failed('WAI_MEDIA_VALIDATION_STREAMS_INVALID');
    }
    var hasAudio = false;
    var hasVideo = false;
    for (final rawStream in rawStreams) {
      if (rawStream is! Map) return _failed('WAI_MEDIA_VALIDATION_STREAMS_INVALID');
      final stream = Map<String, dynamic>.from(rawStream);
      final type = '${stream['type'] ?? ''}'.trim().toLowerCase();
      final codec = '${stream['codec'] ?? ''}'.trim().toLowerCase();
      if (codec.isEmpty || codec.length > 64) return _failed('WAI_MEDIA_VALIDATION_STREAMS_INVALID');
      if (type == 'audio') hasAudio = true;
      if (type == 'video') hasVideo = true;
      if (type != 'audio' && type != 'video' && type != 'subtitle') {
        return _failed('WAI_MEDIA_VALIDATION_STREAMS_INVALID');
      }
    }
    if (requireVideo && !hasVideo) return _failed('WAI_MEDIA_VALIDATION_VIDEO_STREAM_MISSING');
    if (!requireVideo && !hasAudio) return _failed('WAI_MEDIA_VALIDATION_AUDIO_STREAM_MISSING');
    return _ok();
  }

  static WesiMediaOutputValidationResult _validateStems(Object? raw) {
    if (raw is! List || raw.length < 2 || raw.length > maxStemCount) {
      return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
    }
    final seen = <String>{};
    for (final rawStem in raw) {
      if (rawStem is! Map) return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      final stem = Map<String, dynamic>.from(rawStem);
      if (stem.containsKey('path') || stem.containsKey('absolutePath')) {
        return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      }
      final name = '${stem['name'] ?? ''}'.trim();
      final mime = '${stem['mimeType'] ?? ''}'.split(';').first.trim().toLowerCase();
      final byteSize = _int(stem['byteSize']);
      final durationMs = _int(stem['durationMs']);
      final hash = '${stem['sha256'] ?? ''}'.trim().toLowerCase();
      if (!RegExp(r'^[A-Za-z0-9 _.-]{1,80}$').hasMatch(name) || !seen.add(name.toLowerCase())) {
        return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      }
      if (!_audioMimes.contains(mime) || byteSize == null || byteSize <= 0 || byteSize > maxStemBytes) {
        return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      }
      if (durationMs == null || durationMs <= 0 || durationMs > maxDurationMs) {
        return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      }
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
        return _failed('WAI_MEDIA_VALIDATION_STEMS_INVALID');
      }
    }
    return _ok();
  }

  static const Set<String> _audioMimes = <String>{
    'audio/mpeg',
    'audio/mp3',
    'audio/wav',
    'audio/x-wav',
    'audio/flac',
    'audio/ogg',
    'audio/mp4',
    'audio/aac',
  };

  static Set<String>? _containersForMime(String mime) => switch (mime) {
        'audio/mpeg' || 'audio/mp3' => const <String>{'mp3'},
        'audio/wav' || 'audio/x-wav' => const <String>{'wav'},
        'audio/flac' => const <String>{'flac'},
        'audio/ogg' => const <String>{'ogg'},
        'audio/mp4' => const <String>{'m4a', 'mp4'},
        'audio/aac' => const <String>{'aac'},
        'video/mp4' => const <String>{'mp4'},
        'video/webm' => const <String>{'webm'},
        'video/quicktime' => const <String>{'mov'},
        'video/x-matroska' => const <String>{'matroska', 'mkv'},
        _ => null,
      };

  static int? _int(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}');
  }

  static WesiMediaOutputValidationResult _ok() =>
      const WesiMediaOutputValidationResult(ok: true, code: 'OK');

  static WesiMediaOutputValidationResult _failed(String code) =>
      WesiMediaOutputValidationResult(ok: false, code: code);
}
