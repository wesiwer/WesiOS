import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';

void main() {
  test('markdown export is classified as text/markdown', () async {
    final attachment = WesiAiAttachment.fromPlatformFile(
      PlatformFile(
        name: 'exported-chat.md',
        size: 5,
        bytes: Uint8List.fromList('hello'.codeUnits),
      ),
    );
    expect(attachment.mimeType, 'text/markdown');
    final transport = await attachment.toInlineTransportJson();
    expect(transport['dataBase64'], isNotEmpty);
  });

  test('unknown extension is still accepted as octet-stream', () {
    final attachment = WesiAiAttachment.fromPlatformFile(
      PlatformFile(
        name: 'project.custom-format',
        size: 3,
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      ),
    );
    expect(attachment.mimeType, 'application/octet-stream');
  });

  test('history metadata never exposes bytes or local file path', () {
    final attachment = WesiAiAttachment.fromPlatformFile(
      PlatformFile(
        name: 'private.txt',
        size: 12,
        path: '/private/device/path/private.txt',
      ),
    );
    final metadata = attachment.toMetadataJson();
    expect(metadata, <String, dynamic>{
      'name': 'private.txt',
      'mimeType': 'text/plain',
      'byteSize': 12,
    });
    expect(metadata.containsKey('localPath'), isFalse);
    expect(metadata.containsKey('dataBase64'), isFalse);
    expect(metadata.containsKey('bytes'), isFalse);
  });

  test('batch rejects more than four attachments', () {
    final item = WesiAiAttachment.fromBytes(
      name: 'a.txt',
      bytes: Uint8List.fromList(<int>[65]),
      mimeType: 'text/plain',
    );
    expect(
      () => WesiAiAttachment.validateBatch(List<WesiAiAttachment>.filled(5, item)),
      throwsFormatException,
    );
  });

  test('inline transport rejects files that require staging', () async {
    final attachment = WesiAiAttachment.fromPlatformFile(
      PlatformFile(
        name: 'large.bin',
        size: 20 * 1024 * 1024,
        path: '/not-opened-by-this-test/large.bin',
      ),
    );
    expect(WesiAiAttachment.requiresStagedUpload([attachment]), isTrue);
    expect(
      attachment.toInlineTransportJson,
      throwsA(isA<FormatException>()),
    );
  });
}
