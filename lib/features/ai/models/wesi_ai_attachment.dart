import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class WesiAiAttachment {
  static const int maxFiles = 4;
  static const int maxFileBytes = 15 * 1024 * 1024;
  static const int maxTotalBytes = 18 * 1024 * 1024;

  final String name;
  final String mimeType;
  final int byteSize;
  final Uint8List bytes;

  const WesiAiAttachment({
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.bytes,
  });

  factory WesiAiAttachment.fromPlatformFile(PlatformFile file) {
    final data = file.bytes;
    if (data == null) {
      throw const FormatException('Файл не удалось прочитать');
    }
    if (data.lengthInBytes > maxFileBytes) {
      throw const FormatException('Файл больше 15 МБ');
    }
    return WesiAiAttachment(
      name: _safeName(file.name),
      mimeType: _mimeFor(file.name),
      byteSize: data.lengthInBytes,
      bytes: data,
    );
  }

  Map<String, dynamic> toTransportJson() => <String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'dataBase64': base64Encode(bytes),
      };

  Map<String, dynamic> toMetadataJson() => <String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'byteSize': byteSize,
      };

  static void validateBatch(List<WesiAiAttachment> items) {
    if (items.length > maxFiles) {
      throw const FormatException('Можно прикрепить не больше 4 файлов');
    }
    final total = items.fold<int>(0, (sum, item) => sum + item.byteSize);
    if (total > maxTotalBytes) {
      throw const FormatException('Суммарный размер вложений больше 18 МБ');
    }
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
      'dart' || 'py' || 'java' || 'kt' || 'swift' || 'c' || 'h' || 'cpp' || 'hpp' || 'cs' || 'go' || 'rs' || 'rb' || 'php' || 'sh' || 'ps1' || 'sql' => 'text/plain',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
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
