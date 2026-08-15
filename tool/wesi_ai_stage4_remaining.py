from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'missing anchor: {label}')
    return text.replace(old, new, 1)


# Persistent schema marker.
p = Path('lib/features/ai/storage/wesi_ai_local_store.dart')
s = p.read_text(encoding='utf-8')
if 'static const int schemaVersion = 4;' not in s:
    s = replace_once(s, '  static const int schemaVersion = 3;', '  static const int schemaVersion = 4;', 'schema v4')
p.write_text(s, encoding='utf-8')

# Controller user operations.
p = Path('lib/features/ai/controllers/wesi_ai_chat_controller.dart')
s = p.read_text(encoding='utf-8')
if 'setConversationBackupImportant' not in s:
    anchor = '''  WesiAiProject? _projectFor(String? projectId) {
'''
    methods = r'''  Future<void> setConversationBackupImportant(
    String conversationId,
    bool important,
  ) async {
    var changed = false;
    final conversations = state.conversations.map((conversation) {
      if (conversation.id != conversationId ||
          conversation.employeeId != store.employeeId ||
          conversation.importantForBackup == important) {
        return conversation;
      }
      changed = true;
      return conversation.copyWith(importantForBackup: important);
    }).toList(growable: false);
    if (!changed) return;
    state = state.copyWith(conversations: conversations);
    await _persist();
  }

  Future<void> applyRestoredState(WesiAiLocalState restored) async {
    if (restored.employeeId != store.employeeId) {
      throw StateError('Employee mismatch');
    }
    state = restored;
    await _persist();
  }

'''
    s = replace_once(s, anchor, methods + anchor, 'backup controller methods')
p.write_text(s, encoding='utf-8')

# App bar entry.
p = Path('lib/features/ai/ai_assistant_v2_screen.dart')
s = p.read_text(encoding='utf-8')
if "backup/wesi_ai_backup_sheet.dart" not in s:
    s = replace_once(
        s,
        "import 'controllers/wesi_ai_chat_controller.dart';\n",
        "import 'backup/wesi_ai_backup_sheet.dart';\nimport 'controllers/wesi_ai_chat_controller.dart';\n",
        'backup sheet import',
    )
if "tooltip: 'Backup и перенос Wesi AI'" not in s:
    anchor = '''          IconButton(
            tooltip: 'Память Wesi AI',
'''
    button = '''          IconButton(
            tooltip: 'Backup и перенос Wesi AI',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => WesiAiBackupSheet(controller: controller),
            ),
            icon: const Icon(Icons.backup_outlined),
          ),
'''
    s = replace_once(s, anchor, button + anchor, 'backup appbar action')
p.write_text(s, encoding='utf-8')

# Backup service: testable artifact destination without changing production default.
p = Path('lib/features/ai/backup/wesi_ai_backup_service.dart')
s = p.read_text(encoding='utf-8')
if 'artifactRootOverride' not in s:
    s = replace_once(
        s,
        '''  static Future<WesiAiBackupImportResult> importPackage({
    required Uint8List package,
    required WesiAiLocalState current,
  }) async {
''',
        '''  static Future<WesiAiBackupImportResult> importPackage({
    required Uint8List package,
    required WesiAiLocalState current,
    Directory? artifactRootOverride,
  }) async {
''',
        'import package test root',
    )
    s = replace_once(
        s,
        '''    final artifactPaths = await _restoreArtifacts(
      decoded.artifactBytes,
      decoded.artifactRecords,
    );
''',
        '''    final artifactPaths = await _restoreArtifacts(
      decoded.artifactBytes,
      decoded.artifactRecords,
      rootOverride: artifactRootOverride,
    );
''',
        'restore root pass',
    )
    s = replace_once(
        s,
        '''  static Future<Map<String, String>> _restoreArtifacts(
    Map<String, Uint8List> artifactBytes,
    Map<String, Map<String, dynamic>> artifactRecords,
  ) async {
    if (artifactBytes.isEmpty) return const <String, String>{};
    final root = await getApplicationDocumentsDirectory();
    final base = Directory(p.join(root.path, 'wesi_ai', 'imported_artifacts'));
''',
        '''  static Future<Map<String, String>> _restoreArtifacts(
    Map<String, Uint8List> artifactBytes,
    Map<String, Map<String, dynamic>> artifactRecords, {
    Directory? rootOverride,
  }) async {
    if (artifactBytes.isEmpty) return const <String, String>{};
    final root = rootOverride ?? await getApplicationDocumentsDirectory();
    final base = Directory(p.join(root.path, 'wesi_ai', 'imported_artifacts'));
''',
        'artifact root override',
    )
p.write_text(s, encoding='utf-8')

# D2D: loopback test hook and configurable short TTL only for tests.
p = Path('lib/features/ai/backup/wesi_ai_d2d_service.dart')
s = p.read_text(encoding='utf-8')
if 'hostOverride' not in s:
    s = replace_once(
        s,
        '''  static Future<WesiAiD2DTransferSession> startSender(
    WesiAiLocalState state,
  ) async {
    final build = await WesiAiBackupService.buildImportantPackage(state);
''',
        '''  static Future<WesiAiD2DTransferSession> startSender(
    WesiAiLocalState state, {
    Duration ttl = sessionTtl,
    InternetAddress? hostOverride,
  }) async {
    if (ttl <= Duration.zero || ttl > sessionTtl) {
      throw const FormatException('Некорректный D2D TTL');
    }
    final build = await WesiAiBackupService.buildImportantPackage(state);
''',
        'd2d test args',
    )
    s = replace_once(s, '    final host = await _privateHost();', '    final host = hostOverride ?? await _privateHost();', 'd2d host override')
    s = replace_once(s, '    final expiresAt = DateTime.now().toUtc().add(sessionTtl);', '    final expiresAt = DateTime.now().toUtc().add(ttl);', 'd2d ttl expiry')
    s = replace_once(s, '    final expiryTimer = Timer(sessionTtl, () async {', '    final expiryTimer = Timer(ttl, () async {', 'd2d ttl timer')
p.write_text(s, encoding='utf-8')

# Tests.
p = Path('test/wesi_ai_backup_d2d_test.dart')
p.write_text(r'''import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/backup/wesi_ai_backup_crypto.dart';
import 'package:wesios/features/ai/backup/wesi_ai_backup_service.dart';
import 'package:wesios/features/ai/backup/wesi_ai_d2d_service.dart';
import 'package:wesios/features/ai/memory/wesi_ai_memory_models.dart';
import 'package:wesios/features/ai/models/wesi_ai_chat_models.dart';
import 'package:wesios/features/ai/storage/wesi_ai_local_store.dart';

WesiAiLocalState _state(
  String employeeId, {
  bool important = true,
  String? artifactPath,
}) {
  final now = DateTime(2026, 8, 15, 12);
  final project = WesiAiProject(
    id: 'project_backup_1',
    employeeId: employeeId,
    title: 'Backup project',
    createdAt: now,
    updatedAt: now,
  );
  final conversation = WesiAiConversation(
    id: 'conversation_backup_1',
    employeeId: employeeId,
    title: 'Important chat',
    persona: WesiAiPersona.zane,
    createdAt: now,
    updatedAt: now,
    projectId: project.id,
    importantForBackup: important,
  );
  final message = WesiAiMessage(
    id: 'message_backup_1',
    conversationId: conversation.id,
    employeeId: employeeId,
    author: WesiAiMessageAuthor.zane,
    kind: artifactPath == null ? WesiAiMessageKind.text : WesiAiMessageKind.file,
    text: 'Backup me',
    createdAt: now,
    metadata: artifactPath == null
        ? const <String, dynamic>{}
        : <String, dynamic>{
            'localPath': artifactPath,
            'mimeType': 'text/plain',
          },
  );
  final memory = WesiAiMemoryEntry(
    id: 'memory_backup_1',
    employeeId: employeeId,
    scope: WesiAiMemoryScope.shared,
    text: 'Important preference',
    createdAt: now,
    updatedAt: now,
    pinned: true,
  );
  return WesiAiLocalState.empty(employeeId).copyWith(
    projects: <WesiAiProject>[project],
    conversations: <WesiAiConversation>[conversation],
    messages: <WesiAiMessage>[message],
    memoryEntries: <WesiAiMemoryEntry>[memory],
    conversationMemory: <String, WesiAiConversationMemoryState>{
      conversation.id: WesiAiConversationMemoryState(
        conversationId: conversation.id,
        rollingSummary: 'Important summary',
        taskState: const <String, dynamic>{'goal': 'preserve context'},
        summarizedMessageCount: 1,
      ),
    },
  );
}

void main() {
  test('backup crypto roundtrip rejects wrong password and tampering', () {
    final plain = Uint8List.fromList(utf8.encode('important Wesi AI data'));
    final encrypted = WesiAiBackupCrypto.encryptBackup(plain, 'correct horse battery');
    expect(
      utf8.decode(WesiAiBackupCrypto.decryptBackup(encrypted, 'correct horse battery')),
      'important Wesi AI data',
    );
    expect(
      () => WesiAiBackupCrypto.decryptBackup(encrypted, 'wrong password'),
      throwsFormatException,
    );
    final tampered = Uint8List.fromList(encrypted)..[encrypted.length - 1] ^= 0x01;
    expect(
      () => WesiAiBackupCrypto.decryptBackup(tampered, 'correct horse battery'),
      throwsFormatException,
    );
  });

  test('only explicitly important chats are packaged', () async {
    expect(
      () => WesiAiBackupService.buildImportantPackage(
        _state('employee_backup_none', important: false),
      ),
      throwsA(isA<FormatException>()),
    );
    final build = await WesiAiBackupService.buildImportantPackage(
      _state('employee_backup_yes'),
    );
    expect(build.conversationCount, 1);
    expect(build.messageCount, 1);
  });

  test('backup package is employee isolated and merge is idempotent', () async {
    final source = _state('employee_backup_same');
    final build = await WesiAiBackupService.buildImportantPackage(source);
    final first = await WesiAiBackupService.importPackage(
      package: build.packageBytes,
      current: WesiAiLocalState.empty('employee_backup_same'),
    );
    final second = await WesiAiBackupService.importPackage(
      package: build.packageBytes,
      current: first.state,
    );
    expect(first.state.conversations.length, 1);
    expect(second.state.conversations.length, 1);
    expect(second.state.messages.length, 1);
    expect(second.state.memoryEntries.length, 1);
    expect(
      () => WesiAiBackupService.importPackage(
        package: build.packageBytes,
        current: WesiAiLocalState.empty('different_employee'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('artifact bytes restore only inside managed import directory', () async {
    final temp = await Directory.systemTemp.createTemp('wesi-ai-backup-test-');
    try {
      final sourceFile = File('${temp.path}${Platform.pathSeparator}source.txt');
      await sourceFile.writeAsString('artifact payload');
      final build = await WesiAiBackupService.buildImportantPackage(
        _state('employee_artifact', artifactPath: sourceFile.path),
      );
      expect(build.artifactCount, 1);
      final restoreRoot = Directory('${temp.path}${Platform.pathSeparator}restore');
      final imported = await WesiAiBackupService.importPackage(
        package: build.packageBytes,
        current: WesiAiLocalState.empty('employee_artifact'),
        artifactRootOverride: restoreRoot,
      );
      final restoredPath = '${imported.state.messages.single.metadata['localPath'] ?? ''}';
      expect(restoredPath, startsWith(restoreRoot.path));
      expect(await File(restoredPath).readAsString(), 'artifact payload');
      expect(imported.restoredArtifacts, 1);
    } finally {
      await temp.delete(recursive: true);
    }
  });

  test('package decoder rejects traversal entry', () async {
    final archive = Archive()
      ..addFile(ArchiveFile('../evil.txt', 4, utf8.encode('evil')))
      ..addFile(ArchiveFile('manifest.json', 2, utf8.encode('{}')));
    final encoded = ZipEncoder().encode(archive)!;
    expect(
      () => WesiAiBackupService.importPackage(
        package: Uint8List.fromList(encoded),
        current: WesiAiLocalState.empty('employee_traversal'),
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('D2D descriptor enforces TTL/fingerprint and transfer is one-time', () async {
    final source = _state('employee_d2d');
    final session = await WesiAiD2DService.startSender(
      source,
      ttl: const Duration(seconds: 4),
      hostOverride: InternetAddress.loopbackIPv4,
    );
    final decoded = WesiAiD2DDescriptor.decode(session.transferCode);
    expect(decoded.fingerprint, session.descriptor.fingerprint);
    final imported = await WesiAiD2DService.receive(
      transferCode: session.transferCode,
      current: WesiAiLocalState.empty('employee_d2d'),
    );
    expect(imported.state.conversations.length, 1);
    expect(session.status.value, WesiAiD2DStatus.completed);
    await expectLater(
      WesiAiD2DService.receive(
        transferCode: session.transferCode,
        current: WesiAiLocalState.empty('employee_d2d'),
      ),
      throwsA(isA<FormatException>()),
    );

    final expiredKey = WesiAiBackupCrypto.randomSessionKey();
    final expired = WesiAiD2DDescriptor(
      host: InternetAddress.loopbackIPv4.address,
      port: 12345,
      sessionId: 'expired_session_123456',
      key: expiredKey,
      fingerprint: WesiAiBackupCrypto.fingerprint(expiredKey),
      expiresAt: DateTime.now().toUtc().subtract(const Duration(seconds: 1)),
    );
    expect(() => WesiAiD2DDescriptor.decode(expired.encode()), throwsFormatException);
  });

  test('D2D auth token binds both key and session id', () {
    final key = WesiAiBackupCrypto.randomSessionKey();
    final other = WesiAiBackupCrypto.randomSessionKey();
    final token = WesiAiBackupCrypto.transferAuthToken('session_123456789', key);
    expect(
      WesiAiBackupCrypto.constantTimeEquals(
        token,
        WesiAiBackupCrypto.transferAuthToken('session_123456789', key),
      ),
      isTrue,
    );
    expect(
      WesiAiBackupCrypto.constantTimeEquals(
        token,
        WesiAiBackupCrypto.transferAuthToken('session_other_123', key),
      ),
      isFalse,
    );
    expect(
      WesiAiBackupCrypto.constantTimeEquals(
        token,
        WesiAiBackupCrypto.transferAuthToken('session_123456789', other),
      ),
      isFalse,
    );
  });
}
''', encoding='utf-8')
