import 'dart:io';

/// Resolves a media-engine output only when the final filesystem target stays
/// inside the verified engine directory.
///
/// The engine may return only a relative path. Both the engine root and the
/// candidate are resolved through symlinks before the containment check, so a
/// package cannot place an in-tree symlink that points to an arbitrary file.
class WesiMediaEnginePathGuard {
  const WesiMediaEnginePathGuard._();

  static Future<String?> resolveOutput(
    Directory root,
    String rawRelative,
  ) async {
    final relative = rawRelative.replaceAll('\\', '/').trim();
    if (relative.isEmpty ||
        relative.startsWith('/') ||
        relative.contains('\u0000') ||
        RegExp(r'^[A-Za-z]:').hasMatch(relative)) {
      return null;
    }
    final segments = relative.split('/');
    if (segments.any(
        (segment) => segment.isEmpty || segment == '.' || segment == '..')) {
      return null;
    }

    try {
      if (!await root.exists()) return null;
      final resolvedRoot = Directory(await root.resolveSymbolicLinks());
      final candidate = File(
        '${resolvedRoot.path}${Platform.pathSeparator}'
        '${segments.join(Platform.pathSeparator)}',
      );
      if (!await candidate.exists()) return null;
      final resolvedCandidate = File(await candidate.resolveSymbolicLinks());
      if (!await resolvedCandidate.exists()) return null;

      final rootPath = _comparisonPath(resolvedRoot.absolute.path);
      final childPath = _comparisonPath(resolvedCandidate.absolute.path);
      final prefix = rootPath.endsWith(Platform.pathSeparator)
          ? rootPath
          : '$rootPath${Platform.pathSeparator}';
      if (!childPath.startsWith(prefix)) return null;
      return resolvedCandidate.absolute.path;
    } on FileSystemException {
      return null;
    }
  }

  static String _comparisonPath(String path) =>
      Platform.isWindows ? path.toLowerCase() : path;
}
