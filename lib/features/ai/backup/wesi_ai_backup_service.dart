import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../memory/wesi_ai_memory_models.dart';
import '../models/wesi_ai_chat_models.dart';
import '../storage/wesi_ai_local_store.dart';
import 'wesi_ai_backup_crypto.dart';

class WesiAiBackupBuildResult {
  final Uint8List packageBytes;
  final int conversationCount;
  final int messageCount;
  final int artifactCount;
  final int skippedArtifacts;

  const WesiAiBackupBuildResult({
    required this.packageBytes,
    required this.conversationCount,
    required this.messageCount,
    required this.artifactCount,
    required this.skippedArtifacts,
  });
}

class WesiAiBackupImportResult {
  final WesiAiLocalState state;
  final int importedConversations;
  final int importedMessages;
  final int importedMemoryEntries;
  final int restoredArtifacts;

  const WesiAiBackupImportResult({
    required this.state,
    required this.importedConversations,
    required this.importedMessages,
    required this.importedMemoryEntries,
    required this.restoredArtifacts,
  });
}

class WesiAiBackupExportResult {
  final String path;
  final WesiAiBackupBuildResult build;

  const WesiAiBackupExportResult({
    required this.path,
    required this.build,
  });
}

class _DecodedBackup {
  final List<WesiAiProject> projects;
  final List<WesiAiConversation> conversations;
  final List<WesiAiMessage> messages;
  final List<WesiAiMemoryEntry> memoryEntries;
  final WesiAiMemorySettings memorySettings;
  final Map<String, WesiAiConversationMemoryState> conversationMemory;
  final Map<String, Uint8List> artifactBytes;
  final Map<String, Map<String, dynamic>> artifactRecords;

  const _DecodedBackup({
    required this.projects,
    required this.conversations,
    required this.messages,
    required this.memoryEntries,
    required this.memorySettings,
    required this.conversationMemory,
    required this.artifactBytes,
    required this.artifactRecords,
  });
}

class WesiAiBackupService {
  static const int packageVersion = 1;
  static const int maxArtifactBytes = 64 * 1024 * 1024;
  static const int maxTotalArtifactBytes = 256 * 1024 * 1024;
  static const int maxArtifacts = 128;
  static const int maxPackageBytes = 320 * 1024 * 1024;
  static const int maxArchiveEntries = 132;

  const WesiAiBackupService._();

  static Future<WesiAiBackupBuildResult> buildImportantPackage(
    WesiAiLocalState state,
  ) async {
    final selected = state.conversations
        .where((conversation) => conversation.importantForBackup)
        .toList(growable: false);
    if (selected.isEmpty) {
      throw const FormatException('Нет чатов, отмеченных для важного backup');
    }
    final selectedIds = selected.map((item) => item.id).toSet();
    final selectedProjectIds =
        selected.map((item) => item.projectId).whereType<String>().toSet();
    final projects = state.projects
        .where((project) => selectedProjectIds.contains(project.id))
        .toList(growable: false);
    final messages = state.messages
        .where((message) => selectedIds.contains(message.conversationId))
        .toList(growable: false);
    final memoryEntries = state.memoryEntries.where((entry) {
      if (entry.scope == WesiAiMemoryScope.project) {
        return entry.projectId != null &&
            selectedProjectIds.contains(entry.projectId);
      }
      if (entry.sourceConversationId != null &&
          selectedIds.contains(entry.sourceConversationId)) {
        return true;
      }
      return entry.scope == WesiAiMemoryScope.shared ||
          entry.scope == WesiAiMemoryScope.zane ||
          entry.scope == WesiAiMemoryScope.nirvana;
    }).toList(growable: false);

    final archive = Archive();
    final artifactRecords = <Map<String, dynamic>>[];
    final manifestMessages = <Map<String, dynamic>>[];
    var totalArtifactBytes = 0;
    var skippedArtifacts = 0;

    for (final message in messages) {
      final json = Map<String, dynamic>.from(message.toJson());
      final metadata = message.metadata.isEmpty
          ? <String, dynamic>{}
          : Map<String, dynamic>.from(message.metadata);
      final localPath = '${metadata['localPath'] ?? ''}'.trim();
      metadata.remove('localPath');
      if (localPath.isNotEmpty) {
        final artifact = await _artifactForMessage(
          message: message,
          localPath: localPath,
          artifactIndex: artifactRecords.length,
          usedBytes: totalArtifactBytes,
        );
        if (artifact != null) {
          final bytes = artifact.$1;
          final record = artifact.$2;
          totalArtifactBytes += bytes.lengthInBytes;
          archive.addFile(ArchiveFile(
            record['entryPath'] as String,
            bytes.lengthInBytes,
            bytes,
          ));
          artifactRecords.add(record);
          metadata['backupArtifactId'] = record['id'];
        } else {
          skippedArtifacts++;
        }
      }
      json['metadata'] = metadata;
      manifestMessages.add(json);
    }

    final conversationMemory = <Map<String, dynamic>>[];
    for (final id in selectedIds) {
      final item = state.conversationMemory[id];
      if (item != null) conversationMemory.add(item.toJson());
    }
    final manifest = <String, dynamic>{
      'format': 'wesi-ai-backup',
      'version': packageVersion,
      'employeeId': state.employeeId,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'projects': projects.map((item) => item.toJson()).toList(growable: false),
      'conversations':
          selected.map((item) => item.toJson()).toList(growable: false),
      'messages': manifestMessages,
      'memoryEntries':
          memoryEntries.map((item) => item.toJson()).toList(growable: false),
      'memorySettings': state.memorySettings.toJson(),
      'conversationMemory': conversationMemory,
      'artifacts': artifactRecords,
    };
    final manifestBytes = Uint8List.fromList(utf8.encode(jsonEncode(manifest)));
    archive.addFile(ArchiveFile(
      'manifest.json',
      manifestBytes.lengthInBytes,
      manifestBytes,
    ));
    final encoded = ZipEncoder().encode(archive);
    if (encoded == null || encoded.isEmpty) {
      throw const FormatException('Не удалось собрать Wesi AI backup');
    }
    if (encoded.length > maxPackageBytes) {
      throw const FormatException('Wesi AI backup превышает допустимый размер');
    }
    return WesiAiBackupBuildResult(
      packageBytes: Uint8List.fromList(encoded),
      conversationCount: selected.length,
      messageCount: messages.length,
      artifactCount: artifactRecords.length,
      skippedArtifacts: skippedArtifacts,
    );
  }

  static Future<WesiAiBackupExportResult> exportImportantBackup(
    WesiAiLocalState state,
    String passphrase,
  ) async {
    final build = await buildImportantPackage(state);
    final encrypted = WesiAiBackupCrypto.encryptBackup(
      build.packageBytes,
      passphrase,
    );
    final root = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(root.path, 'wesi_ai', 'backups'));
    await dir.create(recursive: true);
    final stamp = DateTime.now()
        .toUtc()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final file = File(p.join(dir.path, 'wesi-ai-important-$stamp.wbackup'));
    await file.writeAsBytes(encrypted, flush: true);
    return WesiAiBackupExportResult(path: file.path, build: build);
  }

  static Future<WesiAiBackupImportResult> importEncryptedBackup({
    required String path,
    required String passphrase,
    required WesiAiLocalState current,
  }) async {
    final file = File(path);
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.file || !await file.exists()) {
      throw const FormatException('Backup-файл недоступен');
    }
    final length = await file.length();
    if (length <= 0 || length > maxPackageBytes + 1024 * 1024) {
      throw const FormatException('Некорректный размер backup-файла');
    }
    final encrypted = await file.readAsBytes();
    final package = WesiAiBackupCrypto.decryptBackup(encrypted, passphrase);
    return importPackage(package: package, current: current);
  }

  static Future<WesiAiBackupImportResult> importPackage({
    required Uint8List package,
    required WesiAiLocalState current,
    Directory? artifactRootOverride,
  }) async {
    final decoded = _decodePackage(package, current.employeeId);
    final artifactPaths = await _restoreArtifacts(
      decoded.artifactBytes,
      decoded.artifactRecords,
      rootOverride: artifactRootOverride,
    );

    final projectsById = <String, WesiAiProject>{
      for (final item in current.projects) item.id: item,
    };
    for (final imported in decoded.projects) {
      final existing = projectsById[imported.id];
      if (existing == null || imported.updatedAt.isAfter(existing.updatedAt)) {
        projectsById[imported.id] = imported;
      }
    }

    final conversationsById = <String, WesiAiConversation>{
      for (final item in current.conversations) item.id: item,
    };
    for (final imported in decoded.conversations) {
      final existing = conversationsById[imported.id];
      if (existing == null) {
        conversationsById[imported.id] = imported;
        continue;
      }
      final newer =
          imported.updatedAt.isAfter(existing.updatedAt) ? imported : existing;
      conversationsById[imported.id] = newer.copyWith(
        importantForBackup:
            existing.importantForBackup || imported.importantForBackup,
      );
    }

    final messagesById = <String, WesiAiMessage>{
      for (final item in current.messages) item.id: item,
    };
    for (final imported in decoded.messages) {
      final artifactId =
          '${imported.metadata['backupArtifactId'] ?? ''}'.trim();
      var candidate = imported;
      if (artifactId.isNotEmpty && artifactPaths.containsKey(artifactId)) {
        final metadata = Map<String, dynamic>.from(imported.metadata)
          ..remove('backupArtifactId')
          ..['localPath'] = artifactPaths[artifactId];
        candidate = imported.copyWith(metadata: metadata);
      }
      final existing = messagesById[candidate.id];
      if (existing == null) {
        messagesById[candidate.id] = candidate;
      } else if ('${existing.metadata['localPath'] ?? ''}'.trim().isEmpty &&
          '${candidate.metadata['localPath'] ?? ''}'.trim().isNotEmpty) {
        messagesById[candidate.id] = existing.copyWith(
          metadata: <String, dynamic>{
            ...existing.metadata,
            'localPath': candidate.metadata['localPath'],
          },
        );
      }
    }

    final memoryById = <String, WesiAiMemoryEntry>{
      for (final item in current.memoryEntries) item.id: item,
    };
    for (final imported in decoded.memoryEntries) {
      final existing = memoryById[imported.id];
      memoryById[imported.id] =
          existing == null ? imported : _mergeMemoryEntries(existing, imported);
    }
    final dedupMemory = <String, WesiAiMemoryEntry>{};
    for (final item in memoryById.values) {
      final key =
          '${item.scope.name}|${item.projectId ?? ''}|${_normalize(item.text)}';
      final previous = dedupMemory[key];
      dedupMemory[key] =
          previous == null ? item : _mergeMemoryEntries(previous, item);
    }

    final conversationMemory = <String, WesiAiConversationMemoryState>{
      ...current.conversationMemory,
    };
    for (final imported in decoded.conversationMemory.values) {
      final existing = conversationMemory[imported.conversationId];
      if (existing == null ||
          imported.summarizedMessageCount > existing.summarizedMessageCount) {
        conversationMemory[imported.conversationId] = imported;
      }
    }

    final next = current.copyWith(
      projects: projectsById.values.toList(growable: false),
      conversations: conversationsById.values.toList(growable: false)
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
      messages: messagesById.values.toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
      memoryEntries: dedupMemory.values.toList(growable: false),
      conversationMemory: conversationMemory,
    );
    return WesiAiBackupImportResult(
      state: next,
      importedConversations: decoded.conversations.length,
      importedMessages: decoded.messages.length,
      importedMemoryEntries: decoded.memoryEntries.length,
      restoredArtifacts: artifactPaths.length,
    );
  }

  static _DecodedBackup _decodePackage(
    Uint8List package,
    String expectedEmployeeId,
  ) {
    if (package.isEmpty || package.lengthInBytes > maxPackageBytes) {
      throw const FormatException('Некорректный размер Wesi AI package');
    }
    Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(package, verify: true);
    } catch (_) {
      throw const FormatException('Повреждённый Wesi AI package');
    }
    if (archive.length > maxArchiveEntries) {
      throw const FormatException('Слишком много файлов в Wesi AI package');
    }
    final files = <String, Uint8List>{};
    var extractedBytes = 0;
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (!_safeArchiveName(name) || !entry.isFile) {
        throw const FormatException('Небезопасный путь в Wesi AI package');
      }
      final content = entry.content;
      if (content is! List<int>) {
        throw const FormatException('Некорректный файл Wesi AI package');
      }
      final bytes = Uint8List.fromList(content);
      extractedBytes += bytes.lengthInBytes;
      if (extractedBytes > maxPackageBytes) {
        throw const FormatException(
            'Wesi AI package превышает лимит распаковки');
      }
      files[name] = bytes;
    }
    final manifestBytes = files['manifest.json'];
    if (manifestBytes == null ||
        manifestBytes.lengthInBytes > 16 * 1024 * 1024) {
      throw const FormatException('В Wesi AI package нет валидного manifest');
    }
    Map<String, dynamic> manifest;
    try {
      final raw = jsonDecode(utf8.decode(manifestBytes));
      if (raw is! Map) throw const FormatException();
      manifest = Map<String, dynamic>.from(raw);
    } catch (_) {
      throw const FormatException('Повреждён manifest Wesi AI backup');
    }
    if (manifest['format'] != 'wesi-ai-backup' ||
        manifest['version'] != packageVersion ||
        '${manifest['employeeId'] ?? ''}' != expectedEmployeeId) {
      throw const FormatException(
          'Backup принадлежит другому сотруднику или версии');
    }

    final projects = <WesiAiProject>[];
    for (final raw in manifest['projects'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      final item = WesiAiProject.fromJson(Map<String, dynamic>.from(raw));
      if (item.employeeId != expectedEmployeeId) {
        throw const FormatException('Project employee mismatch');
      }
      projects.add(item);
    }
    final projectIds = projects.map((item) => item.id).toSet();

    final conversations = <WesiAiConversation>[];
    for (final raw in manifest['conversations'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      var item = WesiAiConversation.fromJson(Map<String, dynamic>.from(raw));
      if (item.employeeId != expectedEmployeeId) {
        throw const FormatException('Conversation employee mismatch');
      }
      if (item.projectId != null && !projectIds.contains(item.projectId)) {
        item = item.copyWith(clearProject: true);
      }
      conversations.add(item);
    }
    if (conversations.isEmpty || conversations.length > 400) {
      throw const FormatException('Некорректный список conversations в backup');
    }
    final conversationIds = conversations.map((item) => item.id).toSet();

    final messages = <WesiAiMessage>[];
    for (final raw in manifest['messages'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      final item = WesiAiMessage.fromJson(Map<String, dynamic>.from(raw));
      if (item.employeeId != expectedEmployeeId ||
          !conversationIds.contains(item.conversationId)) {
        throw const FormatException('Message isolation mismatch');
      }
      messages.add(item);
      if (messages.length > 100000) {
        throw const FormatException('Слишком много messages в backup');
      }
    }

    final memoryEntries = <WesiAiMemoryEntry>[];
    for (final raw in manifest['memoryEntries'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      memoryEntries.add(WesiAiMemoryEntry.fromJson(
        Map<String, dynamic>.from(raw),
        expectedEmployeeId: expectedEmployeeId,
      ));
      if (memoryEntries.length > 600) {
        throw const FormatException('Слишком много memory entries в backup');
      }
    }
    var memorySettings = const WesiAiMemorySettings();
    final rawSettings = manifest['memorySettings'];
    if (rawSettings is Map) {
      memorySettings = WesiAiMemorySettings.fromJson(
        Map<String, dynamic>.from(rawSettings),
      );
    }
    final conversationMemory = <String, WesiAiConversationMemoryState>{};
    for (final raw
        in manifest['conversationMemory'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      final item = WesiAiConversationMemoryState.fromJson(
        Map<String, dynamic>.from(raw),
        knownConversationIds: conversationIds,
      );
      conversationMemory[item.conversationId] = item;
    }

    final artifactBytes = <String, Uint8List>{};
    final artifactRecords = <String, Map<String, dynamic>>{};
    var totalArtifacts = 0;
    var totalArtifactBytes = 0;
    for (final raw in manifest['artifacts'] as List? ?? const <dynamic>[]) {
      if (raw is! Map) continue;
      final record = Map<String, dynamic>.from(raw);
      final id = '${record['id'] ?? ''}'.trim();
      final messageId = '${record['messageId'] ?? ''}'.trim();
      final entryPath = '${record['entryPath'] ?? ''}'.replaceAll('\\', '/');
      final name = _safeBaseName('${record['name'] ?? ''}');
      final mimeType =
          '${record['mimeType'] ?? 'application/octet-stream'}'.trim();
      final declaredSize = record['byteSize'];
      if (!RegExp(r'^[A-Za-z0-9_-]{8,180}$').hasMatch(id) ||
          messageId.isEmpty ||
          entryPath != 'artifacts/$id/$name' ||
          !_safeArchiveName(entryPath) ||
          mimeType.isEmpty ||
          mimeType.length > 160 ||
          declaredSize is! int ||
          declaredSize <= 0 ||
          declaredSize > maxArtifactBytes) {
        throw const FormatException('Некорректная artifact metadata');
      }
      final bytes = files[entryPath];
      if (bytes == null || bytes.lengthInBytes != declaredSize) {
        throw const FormatException('Artifact отсутствует или повреждён');
      }
      totalArtifacts++;
      totalArtifactBytes += bytes.lengthInBytes;
      if (totalArtifacts > maxArtifacts ||
          totalArtifactBytes > maxTotalArtifactBytes) {
        throw const FormatException('Artifact limits превышены');
      }
      artifactBytes[id] = bytes;
      artifactRecords[id] = <String, dynamic>{
        ...record,
        'name': name,
        'entryPath': entryPath,
      };
    }
    return _DecodedBackup(
      projects: projects,
      conversations: conversations,
      messages: messages,
      memoryEntries: memoryEntries,
      memorySettings: memorySettings,
      conversationMemory: conversationMemory,
      artifactBytes: artifactBytes,
      artifactRecords: artifactRecords,
    );
  }

  static Future<Map<String, String>> _restoreArtifacts(
    Map<String, Uint8List> artifactBytes,
    Map<String, Map<String, dynamic>> artifactRecords, {
    Directory? rootOverride,
  }) async {
    if (artifactBytes.isEmpty) return const <String, String>{};
    final root = rootOverride ?? await getApplicationDocumentsDirectory();
    final base = Directory(p.join(root.path, 'wesi_ai', 'imported_artifacts'));
    await base.create(recursive: true);
    final restored = <String, String>{};
    for (final entry in artifactBytes.entries) {
      final record = artifactRecords[entry.key];
      if (record == null) continue;
      final name = _safeBaseName('${record['name'] ?? 'artifact.bin'}');
      final dir = Directory(p.join(base.path, entry.key));
      await dir.create(recursive: true);
      final file = File(p.join(dir.path, name));
      await file.writeAsBytes(entry.value, flush: true);
      restored[entry.key] = file.path;
    }
    return restored;
  }

  static Future<(Uint8List, Map<String, dynamic>)?> _artifactForMessage({
    required WesiAiMessage message,
    required String localPath,
    required int artifactIndex,
    required int usedBytes,
  }) async {
    if (artifactIndex >= maxArtifacts) return null;
    try {
      final type = await FileSystemEntity.type(localPath, followLinks: false);
      if (type != FileSystemEntityType.file) return null;
      final file = File(localPath);
      final length = await file.length();
      if (length <= 0 ||
          length > maxArtifactBytes ||
          usedBytes + length > maxTotalArtifactBytes) {
        return null;
      }
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes != length) return null;
      final name = _safeBaseName(p.basename(localPath));
      final id = 'artifact_${artifactIndex}_${message.id.hashCode.abs()}';
      final mimeType =
          '${message.metadata['mimeType'] ?? 'application/octet-stream'}';
      return (
        bytes,
        <String, dynamic>{
          'id': id,
          'messageId': message.id,
          'name': name,
          'mimeType':
              mimeType.length <= 160 ? mimeType : 'application/octet-stream',
          'byteSize': bytes.lengthInBytes,
          'entryPath': 'artifacts/$id/$name',
        },
      );
    } catch (_) {
      return null;
    }
  }

  static bool _safeArchiveName(String name) {
    if (name.isEmpty || name.length > 360 || name.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(name)) return false;
    final parts = name.split('/');
    return !parts.any((part) => part.isEmpty || part == '.' || part == '..');
  }

  static String _safeBaseName(String raw) {
    var value = raw.trim().replaceAll(RegExp(r'[\\/\u0000-\u001f]'), '_');
    if (value.isEmpty) value = 'artifact.bin';
    if (value.length > 180) value = value.substring(value.length - 180);
    return value;
  }

  static WesiAiMemoryEntry _mergeMemoryEntries(
    WesiAiMemoryEntry first,
    WesiAiMemoryEntry second,
  ) {
    final newer = second.updatedAt.isAfter(first.updatedAt) ? second : first;
    return newer.copyWith(
      manual: first.manual || second.manual,
      pinned: first.pinned || second.pinned,
      importance: first.importance >= second.importance
          ? first.importance
          : second.importance,
    );
  }

  static String _normalize(String text) =>
      text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}
