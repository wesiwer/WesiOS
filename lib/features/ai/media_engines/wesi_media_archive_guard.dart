import 'package:archive/archive_io.dart';

class WesiMediaArchiveEntry {
  final String name;
  final int size;
  final bool isSymbolicLink;

  const WesiMediaArchiveEntry({
    required this.name,
    required this.size,
    required this.isSymbolicLink,
  });
}

class WesiMediaArchiveGuard {
  static const int maxEntries = 50000;
  static const int maxExpandedBytes = 128 * 1024 * 1024 * 1024;
  static const int maxExpansionRatio = 128;

  const WesiMediaArchiveGuard._();

  static void validateEntries(
    Iterable<WesiMediaArchiveEntry> entries, {
    required int compressedSizeBytes,
  }) {
    if (compressedSizeBytes <= 0) {
      throw const FormatException('archive_size_invalid');
    }

    var count = 0;
    var expanded = 0;
    for (final entry in entries) {
      count++;
      if (count > maxEntries) {
        throw const FormatException('archive_too_many_entries');
      }
      if (entry.isSymbolicLink) {
        throw const FormatException('archive_symlink_forbidden');
      }
      if (entry.size < 0) {
        throw const FormatException('archive_entry_size_invalid');
      }
      _validateRelativePath(entry.name);
      expanded += entry.size;
      if (expanded > maxExpandedBytes ||
          expanded > compressedSizeBytes * maxExpansionRatio) {
        throw const FormatException('archive_expansion_limit');
      }
    }
  }

  static Future<void> validateZip(
    String archivePath, {
    required int compressedSizeBytes,
  }) async {
    final input = InputFileStream(archivePath);
    try {
      final archive = ZipDecoder().decodeBuffer(input);
      validateEntries(
        archive.files.map(
          (entry) => WesiMediaArchiveEntry(
            name: entry.name,
            size: entry.size,
            isSymbolicLink: entry.isSymbolicLink,
          ),
        ),
        compressedSizeBytes: compressedSizeBytes,
      );
    } finally {
      input.close();
    }
  }

  static void _validateRelativePath(String rawName) {
    final normalized = rawName.replaceAll('\\', '/').trim();
    if (normalized.isEmpty ||
        normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalized)) {
      throw const FormatException('archive_path_invalid');
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part == '..')) {
      throw const FormatException('archive_path_traversal');
    }
  }
}
