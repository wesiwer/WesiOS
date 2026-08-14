import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';

void main() {
  test('markdown export is classified as text/markdown', () {
    final attachment = WesiAiAttachment.fromPlatformFile(
      PlatformFile(
        name: 'exported-chat.md',
        size: 5,
        bytes: Uint8List.fromList('hello'.codeUnits),
      ),
    );
    expect(attachment.mimeType, 'text/markdown');
    expect(attachment.toTransportJson()['dataBase64'], isNotEmpty);
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

  test('batch rejects more than four attachments', () {
    final item = WesiAiAttachment(
      name: 'a.txt',
      mimeType: 'text/plain',
      byteSize: 1,
      bytes: Uint8List.fromList(<int>[65]),
    );
    expect(
      () => WesiAiAttachment.validateBatch(List<WesiAiAttachment>.filled(5, item)),
      throwsFormatException,
    );
  });
}
