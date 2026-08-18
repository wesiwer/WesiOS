import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_local_request.dart';

void main() {
  test('producer workflows use bounded current-turn attachment indexes', () {
    final regenerate = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'music',
      'workflow': 'musicRegenerateStem',
      'prompt': 'regenerate bass',
      'attachmentIndexes': <int>[0],
      'options': <String, dynamic>{
        'workflow': 'musicRegenerateStem',
        'stemName': 'bass',
        'inputPath': '/etc/passwd',
      },
    });
    expect(regenerate, isNotNull);
    expect(regenerate!['attachmentIndexes'], <int>[0]);
    expect((regenerate['options'] as Map).containsKey('inputPath'), isFalse);

    final mix = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'music',
      'workflow': 'musicMix',
      'prompt': 'mix',
      'attachmentIndexes': <int>[0, 1],
    });
    expect(mix, isNotNull);

    final export = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'music',
      'workflow': 'musicExport',
      'prompt': 'export stems',
      'attachmentIndexes': <int>[0],
    });
    expect(export, isNotNull);
  });

  test('music mix fails closed with fewer than two inputs', () {
    final result = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'music',
      'workflow': 'musicMix',
      'prompt': 'mix',
      'attachmentIndexes': <int>[0],
    });
    expect(result, isNull);
  });

  test('producer workflow cannot impersonate another media type', () {
    final result = WesiMediaLocalRequestSanitizer.sanitize(<String, dynamic>{
      'mediaType': 'video',
      'workflow': 'musicExport',
      'prompt': 'export',
      'attachmentIndexes': <int>[0],
    });
    expect(result, isNull);
  });
}
