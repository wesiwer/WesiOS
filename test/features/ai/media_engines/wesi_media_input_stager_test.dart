import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_input_stager.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_local_request.dart';
import 'package:wesios/features/ai/models/wesi_ai_attachment.dart';

void main() {
  test('sanitizer keeps only bounded workflow attachment indexes', () {
    final request = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'image',
      'workflow': 'imageEdit',
      'prompt': 'remove background',
      'attachmentIndexes': <int>[1],
      'inputPaths': <String>['/etc/passwd'],
      'options': <String, dynamic>{
        'workflow': 'imageEdit',
        'inputs': '/tmp/model-path',
        'imageSize': '1K',
      },
    });
    expect(request, isNotNull);
    expect(request!['attachmentIndexes'], <int>[1]);
    expect(request.containsKey('inputPaths'), isFalse);
    final options = request['options'] as Map<String, dynamic>;
    expect(options.containsKey('inputs'), isFalse);
    expect(options['imageSize'], '1K');
  });

  test('sanitizer rejects duplicate and out-of-range indexes', () {
    expect(
      WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
        'mediaType': 'video',
        'workflow': 'videoCompose',
        'prompt': 'compose',
        'attachmentIndexes': <int>[0, 0],
      }),
      isNull,
    );
    expect(
      WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
        'mediaType': 'video',
        'workflow': 'videoCompose',
        'prompt': 'compose',
        'attachmentIndexes': <int>[4],
      }),
      isNull,
    );
  });

  test('stager copies selected memory attachment into owned temp', () async {
    final root = await Directory.systemTemp.createTemp('wesi_media_stage_test_');
    try {
      final first = WesiAiAttachment.fromBytes(
        name: 'first.png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final second = WesiAiAttachment.fromBytes(
        name: 'second.wav',
        bytes: Uint8List.fromList(<int>[4, 5, 6, 7]),
      );
      final staged = await WesiMediaInputStager.stage(
        <String, dynamic>{
          'mediaType': 'music',
          'workflow': 'musicStems',
          'prompt': 'split stems',
          'attachmentIndexes': <int>[1],
        },
        <WesiAiAttachment>[first, second],
        rootDirectory: root,
      );
      expect(staged.paths, hasLength(1));
      expect(staged.paths.single.startsWith(root.path), isTrue);
      expect(await File(staged.paths.single).readAsBytes(), <int>[4, 5, 6, 7]);
      final session = staged.directory!;
      await staged.cleanup();
      expect(await session.exists(), isFalse);
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('path-backed source is copied instead of passed to engine', () async {
    final root = await Directory.systemTemp.createTemp('wesi_media_stage_path_');
    final source = File('${root.path}${Platform.pathSeparator}source.mp4');
    await source.writeAsBytes(<int>[8, 9, 10, 11], flush: true);
    try {
      final attachment = WesiAiAttachment.fromPlatformFile(
        PlatformFile(
          name: 'source.mp4',
          size: await source.length(),
          path: source.path,
        ),
      );
      final staged = await WesiMediaInputStager.stage(
        <String, dynamic>{
          'mediaType': 'video',
          'workflow': 'videoSfx',
          'prompt': 'add city ambience',
          'attachmentIndexes': <int>[0],
        },
        <WesiAiAttachment>[attachment],
        rootDirectory: root,
      );
      expect(staged.paths.single, isNot(source.absolute.path));
      expect(await File(staged.paths.single).readAsBytes(), <int>[8, 9, 10, 11]);
      await staged.cleanup();
    } finally {
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('persisted input workflow fails when turn attachments are gone', () async {
    final result = await WesiMediaTurnExecutor.run(
      <String, dynamic>{
        'mediaType': 'image',
        'workflow': 'imageReference',
        'prompt': 'use this reference',
        'attachmentIndexes': <int>[0],
      },
      const <WesiAiAttachment>[],
    );
    expect(result.ok, isFalse);
    expect(result.code, 'WAI_MEDIA_INPUT_NOT_AVAILABLE');
  });
}
