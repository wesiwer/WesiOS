import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'wesi_artifact_models.dart';

class WesiArtifactValidator {
  final int defaultMaxBytes;
  final Map<WesiArtifactKind, WesiArtifactExternalValidator> externalValidators;

  const WesiArtifactValidator({
    this.defaultMaxBytes = 1024 * 1024 * 1024,
    this.externalValidators = const <
        WesiArtifactKind,
        WesiArtifactExternalValidator>{},
  });

  Future<WesiArtifactValidationResult> validate({
    required WesiArtifactDescriptor descriptor,
    required String workspaceRoot,
    DateTime? now,
  }) async {
    if (descriptor.id.trim().isEmpty || descriptor.id.length > 128) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_BAD_ID',
        'Artifact id is invalid',
      );
    }
    final relative = descriptor.relativePath.trim();
    if (relative.isEmpty || relative.length > 4096 || p.isAbsolute(relative)) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_BAD_PATH',
        'Artifact path must be a bounded relative workspace path',
      );
    }
    final normalized = p.normalize(relative);
    final parts = p.split(normalized);
    if (normalized == '..' ||
        normalized.startsWith('../') ||
        parts.contains('..') ||
        parts.contains('.wesi')) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_PATH_FORBIDDEN',
        'Artifact path escapes or targets protected workspace state',
      );
    }

    final root = Directory(workspaceRoot);
    if (!await root.exists()) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_WORKSPACE_MISSING',
        'Workspace does not exist',
      );
    }

    String rootCanonical;
    try {
      rootCanonical = p.normalize(await root.resolveSymbolicLinks());
    } on FileSystemException {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_WORKSPACE_UNRESOLVED',
        'Workspace path could not be resolved safely',
      );
    }

    final file = File(p.join(rootCanonical, normalized));
    if (!await file.exists()) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_MISSING',
        'Artifact file does not exist',
      );
    }

    String canonicalPath;
    try {
      canonicalPath = p.normalize(await file.resolveSymbolicLinks());
    } on FileSystemException {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_PATH_UNRESOLVED',
        'Artifact path could not be resolved safely',
      );
    }
    if (!p.equals(rootCanonical, canonicalPath) &&
        !p.isWithin(rootCanonical, canonicalPath)) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_SYMLINK_ESCAPE',
        'Artifact resolves outside the workspace',
      );
    }

    final stat = await FileStat.stat(canonicalPath);
    if (stat.type != FileSystemEntityType.file) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_NOT_FILE',
        'Artifact must be a regular file',
      );
    }
    final maxBytes = descriptor.maxBytes ?? defaultMaxBytes;
    if (maxBytes <= 0 || maxBytes > 4 * 1024 * 1024 * 1024) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_BAD_LIMIT',
        'Artifact size limit is invalid',
      );
    }
    if (stat.size <= 0) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_EMPTY',
        'Artifact is empty',
      );
    }
    if (stat.size > maxBytes) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_TOO_LARGE',
        'Artifact exceeds its validated size limit',
      );
    }

    final builtin = await _validateBuiltin(
      descriptor.kind,
      canonicalPath,
      stat.size,
    );
    if (!builtin.ok) return builtin.result;

    final external = externalValidators[descriptor.kind];
    if (_requiresExternalValidator(descriptor.kind) && external == null) {
      return const WesiArtifactValidationResult.failure(
        'ARTIFACT_EXTERNAL_VALIDATOR_REQUIRED',
        'This artifact type requires a trusted external validator',
      );
    }

    var externalMetadata = const <String, dynamic>{};
    if (external != null) {
      final externalResult = await external.validate(
        descriptor: descriptor,
        canonicalPath: canonicalPath,
      );
      if (!externalResult.ok) {
        return WesiArtifactValidationResult.failure(
          externalResult.code,
          externalResult.message,
        );
      }
      externalMetadata = externalResult.metadata;
    }

    final digest = await sha256.bind(File(canonicalPath).openRead()).first;
    final artifact = WesiValidatedArtifact(
      descriptor: descriptor,
      canonicalPath: canonicalPath,
      sizeBytes: stat.size,
      sha256Hex: digest.toString(),
      validatedAt: (now ?? DateTime.now()).toUtc(),
      validationMetadata: <String, dynamic>{
        ...builtin.metadata,
        ...externalMetadata,
      },
    );
    return WesiArtifactValidationResult.success(artifact);
  }

  bool _requiresExternalValidator(WesiArtifactKind kind) {
    switch (kind) {
      case WesiArtifactKind.docx:
      case WesiArtifactKind.xlsx:
      case WesiArtifactKind.pptx:
      case WesiArtifactKind.apk:
      case WesiArtifactKind.video:
      case WesiArtifactKind.other:
        return true;
      case WesiArtifactKind.text:
      case WesiArtifactKind.json:
      case WesiArtifactKind.pdf:
      case WesiArtifactKind.zip:
      case WesiArtifactKind.windowsExecutable:
      case WesiArtifactKind.png:
      case WesiArtifactKind.jpeg:
      case WesiArtifactKind.wav:
      case WesiArtifactKind.mp3:
      case WesiArtifactKind.sourceArchive:
        return false;
    }
  }

  Future<_BuiltinValidation> _validateBuiltin(
    WesiArtifactKind kind,
    String path,
    int size,
  ) async {
    final file = File(path);
    switch (kind) {
      case WesiArtifactKind.text:
        try {
          final bytes = await _readPrefix(file, size.clamp(1, 1024 * 1024));
          utf8.decode(bytes);
          return const _BuiltinValidation.ok(<String, dynamic>{
            'validator': 'utf8',
          });
        } on FormatException {
          return const _BuiltinValidation.fail(
            'ARTIFACT_TEXT_INVALID',
            'Text artifact is not valid UTF-8',
          );
        }
      case WesiArtifactKind.json:
        if (size > 16 * 1024 * 1024) {
          return const _BuiltinValidation.fail(
            'ARTIFACT_JSON_TOO_LARGE',
            'JSON artifact exceeds the built-in parser limit',
          );
        }
        try {
          jsonDecode(await file.readAsString());
          return const _BuiltinValidation.ok(<String, dynamic>{
            'validator': 'jsonDecode',
          });
        } on FormatException {
          return const _BuiltinValidation.fail(
            'ARTIFACT_JSON_INVALID',
            'JSON artifact is invalid',
          );
        }
      case WesiArtifactKind.pdf:
        return _magic(
          file,
          const <int>[0x25, 0x50, 0x44, 0x46, 0x2D],
          'pdf-header',
          'ARTIFACT_PDF_INVALID',
        );
      case WesiArtifactKind.zip:
      case WesiArtifactKind.sourceArchive:
      case WesiArtifactKind.docx:
      case WesiArtifactKind.xlsx:
      case WesiArtifactKind.pptx:
      case WesiArtifactKind.apk:
        return _zipMagic(file);
      case WesiArtifactKind.windowsExecutable:
        return _magic(
          file,
          const <int>[0x4D, 0x5A],
          'pe-mz-header',
          'ARTIFACT_EXE_INVALID',
        );
      case WesiArtifactKind.png:
        return _magic(
          file,
          const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
          'png-signature',
          'ARTIFACT_PNG_INVALID',
        );
      case WesiArtifactKind.jpeg:
        return _magic(
          file,
          const <int>[0xFF, 0xD8, 0xFF],
          'jpeg-signature',
          'ARTIFACT_JPEG_INVALID',
        );
      case WesiArtifactKind.wav:
        final prefix = await _readPrefix(file, 12);
        final ok = prefix.length >= 12 &&
            _matches(prefix, 0, const <int>[0x52, 0x49, 0x46, 0x46]) &&
            _matches(prefix, 8, const <int>[0x57, 0x41, 0x56, 0x45]);
        return ok
            ? const _BuiltinValidation.ok(<String, dynamic>{
                'validator': 'riff-wave-header',
              })
            : const _BuiltinValidation.fail(
                'ARTIFACT_WAV_INVALID',
                'WAV artifact header is invalid',
              );
      case WesiArtifactKind.mp3:
        final prefix = await _readPrefix(file, 3);
        final id3 = _matches(prefix, 0, const <int>[0x49, 0x44, 0x33]);
        final frame = prefix.length >= 2 &&
            prefix[0] == 0xFF &&
            (prefix[1] & 0xE0) == 0xE0;
        return id3 || frame
            ? const _BuiltinValidation.ok(<String, dynamic>{
                'validator': 'mp3-header',
              })
            : const _BuiltinValidation.fail(
                'ARTIFACT_MP3_INVALID',
                'MP3 artifact header is invalid',
              );
      case WesiArtifactKind.video:
      case WesiArtifactKind.other:
        return const _BuiltinValidation.ok(<String, dynamic>{
          'validator': 'external-required',
        });
    }
  }

  Future<_BuiltinValidation> _zipMagic(File file) async {
    final prefix = await _readPrefix(file, 4);
    final ok = prefix.length >= 4 &&
        prefix[0] == 0x50 &&
        prefix[1] == 0x4B &&
        ((prefix[2] == 0x03 && prefix[3] == 0x04) ||
            (prefix[2] == 0x05 && prefix[3] == 0x06) ||
            (prefix[2] == 0x07 && prefix[3] == 0x08));
    return ok
        ? const _BuiltinValidation.ok(<String, dynamic>{
            'validator': 'zip-signature',
          })
        : const _BuiltinValidation.fail(
            'ARTIFACT_ZIP_INVALID',
            'ZIP-based artifact header is invalid',
          );
  }

  Future<_BuiltinValidation> _magic(
    File file,
    List<int> expected,
    String validator,
    String failureCode,
  ) async {
    final prefix = await _readPrefix(file, expected.length);
    return _matches(prefix, 0, expected)
        ? _BuiltinValidation.ok(<String, dynamic>{'validator': validator})
        : _BuiltinValidation.fail(
            failureCode,
            'Artifact signature does not match its declared type',
          );
  }

  Future<List<int>> _readPrefix(File file, int count) async {
    final handle = await file.open();
    try {
      return handle.read(count);
    } finally {
      await handle.close();
    }
  }

  bool _matches(List<int> bytes, int offset, List<int> expected) {
    if (bytes.length < offset + expected.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (bytes[offset + i] != expected[i]) return false;
    }
    return true;
  }
}

class _BuiltinValidation {
  final bool ok;
  final WesiArtifactValidationResult result;
  final Map<String, dynamic> metadata;

  const _BuiltinValidation._({
    required this.ok,
    required this.result,
    this.metadata = const <String, dynamic>{},
  });

  const _BuiltinValidation.ok(Map<String, dynamic> metadata)
      : this._(
          ok: true,
          result: const WesiArtifactValidationResult.failure(
            'ARTIFACT_INTERNAL_SENTINEL',
            'Internal validation sentinel',
          ),
          metadata: metadata,
        );

  const _BuiltinValidation.fail(String code, String message)
      : this._(
          ok: false,
          result: WesiArtifactValidationResult.failure(code, message),
        );
}
