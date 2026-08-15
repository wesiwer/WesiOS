import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class WesiAiAttachment {
  /// Ограничение количества файлов относится и к inline, и к staged upload.
  static const int maxFiles = 4;

  /// Маленькие вложения по-прежнему можно передавать одним подписанным JSON.
  static const int inlineMaxFileBytes = 15 * 1024 * 1024;
  static const int inlineMaxTotalBytes = 18 * 1024 * 1024;

  /// Большие файлы не Base64-кодируются целиком. Они идут чанками через Main
  /// Server и временно собираются на Foreign Relay. Лимиты намеренно ниже
  /// теоретических provider limits, чтобы не забивать диск/память устройств.
  static const int stagedMaxFileBytes = 256 * 1024 * 1024;
  static const int stagedMaxTotalBytes = 512 * 1024 * 1024;
  static const int stagedChunkBytes = 1024 * 1024;

  // Старые имена оставлены как aliases для совместимости существующего кода.
  static const int maxFileBytes = inlineMaxFileBytes;
  static const int maxTotalBytes = inlineMaxTotalBytes;

  final String name;
  final String mimeType;
  final int byteSize;
  final Uint8List? _bytes;
  final String? localPath;

  const WesiAiAttachment._({
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required Uint8List? bytes,
    required this.localPath,
  }) : _bytes = bytes;

  factory WesiAiAttachment.fromPlatformFile(PlatformFile file) {
    if (file.size <= 0) {
      throw const FormatException('Файл пустой');
    }
    if (file.size > stagedMaxFileBytes) {
      throw const FormatException('Файл больше 256 МБ');
    }
    final safeName = _safeName(file.name);
    final data = file.bytes;
    if (data != null) {
      return WesiAiAttachment.fromBytes(name: safeName, bytes: data);
    }
    final path = file.path?.trim();
    if (path == null || path.isEmpty) {
      throw const FormatException('Файл не удалось открыть для отправки');
    }
    return WesiAiAttachment._(
      name: safeName,
      mimeType: _mimeFor(safeName),
      byteSize: file.size,
      bytes: null,
      localPath: path,
    );
  }

  factory WesiAiAttachment.fromBytes({
    required String name,
    required Uint8List bytes,
    String? mimeType,
  }) {
    if (bytes.isEmpty) throw const FormatException('Файл пустой');
    if (bytes.lengthInBytes > stagedMaxFileBytes) {
      throw const FormatException('Файл больше 256 МБ');
    }
    final safeName = _safeName(name);
    return WesiAiAttachment._(
      name: safeName,
      mimeType: mimeType ?? _mimeFor(safeName),
      byteSize: bytes.lengthInBytes,
      bytes: bytes,
      localPath: null,
    );
  }

  bool get isMemoryBacked => _bytes != null;

  int get chunkCount => (byteSize + stagedChunkBytes - 1) ~/ stagedChunkBytes;

  /// Тяжёлые bytes/path специально не попадают в локальную историю чата.
  Map<String, dynamic> toMetadataJson() => <String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'byteSize': byteSize,
      };

  Future<Map<String, dynamic>> toInlineTransportJson() async {
    if (byteSize > inlineMaxFileBytes) {
      throw const FormatException('Файл требует поэтапной загрузки');
    }
    final data = await readChunk(0, byteSize);
    if (data.lengthInBytes != byteSize) {
      throw const FormatException('Файл изменился или больше недоступен');
    }
    return <String, dynamic>{
      'name': name,
      'mimeType': mimeType,
      'byteSize': byteSize,
      'dataBase64': base64Encode(data),
    };
  }

  Future<Uint8List> readChunk(int offset, int length) async {
    if (offset < 0 || length < 0 || offset > byteSize) {
      throw const FormatException('Некорректный диапазон файла');
    }
    final safeLength = math.min(length, byteSize - offset);
    final data = _bytes;
    if (data != null) {
      return Uint8List.sublistView(data, offset, offset + safeLength);
    }

    final path = localPath;
    if (path == null || path.isEmpty) {
      throw const FormatException('Файл больше недоступен на устройстве');
    }
    RandomAccessFile? handle;
    try {
      handle = await File(path).open(mode: FileMode.read);
      final actualLength = await handle.length();
      if (actualLength != byteSize) {
        throw const FormatException('Файл изменился после прикрепления');
      }
      await handle.setPosition(offset);
      return await handle.read(safeLength);
    } on FileSystemException {
      throw const FormatException('Файл больше недоступен на устройстве');
    } finally {
      await handle?.close();
    }
  }

  static void validateBatch(List<WesiAiAttachment> items) {
    if (items.length > maxFiles) {
      throw const FormatException('Можно прикрепить не больше 4 файлов');
    }
    var total = 0;
    for (final item in items) {
      if (item.byteSize <= 0) throw const FormatException('Файл пустой');
      if (item.byteSize > stagedMaxFileBytes) {
        throw const FormatException('Один из файлов больше 256 МБ');
      }
      total += item.byteSize;
      if (total > stagedMaxTotalBytes) {
        throw const FormatException('Суммарный размер вложений больше 512 МБ');
      }
    }
  }

  static bool requiresStagedUpload(List<WesiAiAttachment> items) {
    var total = 0;
    for (final item in items) {
      if (item.byteSize > inlineMaxFileBytes) return true;
      total += item.byteSize;
    }
    return total > inlineMaxTotalBytes;
  }

  static String _safeName(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_');
    if (value.isEmpty) value = 'file';
    if (value.length > 180) value = value.substring(value.length - 180);
    return value;
  }

  static String _mimeFor(String name) {
    final ext = name.toLowerCase().split('.').last;
    return switch (ext) {
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'heic' || 'heif' => 'image/heic',
      'bmp' => 'image/bmp',
      'tif' || 'tiff' => 'image/tiff',
      'pdf' => 'application/pdf',
      'mp3' => 'audio/mpeg',
      'wav' => 'audio/wav',
      'flac' => 'audio/flac',
      'm4a' => 'audio/mp4',
      'ogg' || 'oga' => 'audio/ogg',
      'aac' => 'audio/aac',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'mkv' => 'video/x-matroska',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      'md' || 'markdown' => 'text/markdown',
      'txt' || 'log' || 'ini' || 'cfg' || 'conf' => 'text/plain',
      'csv' => 'text/csv',
      'tsv' => 'text/tab-separated-values',
      'json' => 'application/json',
      'jsonl' => 'application/x-ndjson',
      'xml' => 'application/xml',
      'yaml' || 'yml' => 'application/yaml',
      'html' || 'htm' => 'text/html',
      'css' => 'text/css',
      'js' || 'mjs' || 'cjs' => 'text/javascript',
      'dart' ||
      'py' ||
      'java' ||
      'kt' ||
      'swift' ||
      'c' ||
      'h' ||
      'cpp' ||
      'hpp' ||
      'cs' ||
      'go' ||
      'rs' ||
      'rb' ||
      'php' ||
      'sh' ||
      'ps1' ||
      'sql' =>
        'text/plain',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' =>
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'doc' => 'application/msword',
      'xls' => 'application/vnd.ms-excel',
      'ppt' => 'application/vnd.ms-powerpoint',
      'rtf' => 'application/rtf',
      'epub' => 'application/epub+zip',
      'zip' => 'application/zip',
      '7z' => 'application/x-7z-compressed',
      'rar' => 'application/vnd.rar',
      'tar' => 'application/x-tar',
      'gz' || 'tgz' => 'application/gzip',
      'bz2' || 'tbz2' => 'application/x-bzip2',
      'xz' || 'txz' => 'application/x-xz',
      _ => 'application/octet-stream',
    };
  }
}
