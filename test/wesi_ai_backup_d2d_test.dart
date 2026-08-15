import 'dart:convert';
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
    kind:
        artifactPath == null ? WesiAiMessageKind.text : WesiAiMessageKind.file,
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
    final encrypted =
        WesiAiBackupCrypto.encryptBackup(plain, 'correct horse battery');
    expect(
      utf8.decode(
          WesiAiBackupCrypto.decryptBackup(encrypted, 'correct horse battery')),
      'important Wesi AI data',
    );
    expect(
      () => WesiAiBackupCrypto.decryptBackup(encrypted, 'wrong password'),
      throwsFormatException,
    );
    final tampered = Uint8List.fromList(encrypted)
      ..[encrypted.length - 1] ^= 0x01;
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
      final sourceFile =
          File('${temp.path}${Platform.pathSeparator}source.txt');
      await sourceFile.writeAsString('artifact payload');
      final build = await WesiAiBackupService.buildImportantPackage(
        _state('employee_artifact', artifactPath: sourceFile.path),
      );
      expect(build.artifactCount, 1);
      final restoreRoot =
          Directory('${temp.path}${Platform.pathSeparator}restore');
      final imported = await WesiAiBackupService.importPackage(
        package: build.packageBytes,
        current: WesiAiLocalState.empty('employee_artifact'),
        artifactRootOverride: restoreRoot,
      );
      final restoredPath =
          '${imported.state.messages.single.metadata['localPath'] ?? ''}';
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

  test('D2D descriptor enforces TTL/fingerprint and transfer is one-time',
      () async {
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
    expect(() => WesiAiD2DDescriptor.decode(expired.encode()),
        throwsFormatException);
  });

  test('D2D auth token binds both key and session id', () {
    final key = WesiAiBackupCrypto.randomSessionKey();
    final other = WesiAiBackupCrypto.randomSessionKey();
    final token =
        WesiAiBackupCrypto.transferAuthToken('session_123456789', key);
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
