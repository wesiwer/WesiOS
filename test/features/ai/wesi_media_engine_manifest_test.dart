import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/media_engines/wesi_media_engine_service.dart';

void main() {
  Map<String, dynamic> valid() => <String, dynamic>{
        'kind': 'image',
        'id': 'wesi-image-test',
        'name': 'Wesi Image Test',
        'version': '2026.08.14',
        'path': 'media-engines/packages/image/test.zip',
        'sha256': 'a' * 64,
        'sizeBytes': 123456,
        'license': 'Apache-2.0',
        'licenseUrl': 'https://example.invalid/license',
        'launcher': 'launcher.bat',
        'platforms': <String>['windows'],
        'requirements': <String, dynamic>{
          'minRamGb': 16,
          'recommendedVramGb': 12,
        },
        'enabled': true,
      };

  test('accepts a complete immutable media release', () {
    final release = WesiMediaEngineRelease.tryParse(valid());
    expect(release, isNotNull);
    expect(release!.kind, WesiMediaEngineKind.image);
    expect(release.sha256Hex, 'a' * 64);
    expect(release.sizeBytes, 123456);
  });

  test('rejects path traversal', () {
    final json = valid()..['path'] = '../private/model.zip';
    expect(WesiMediaEngineRelease.tryParse(json), isNull);
  });

  test('rejects malformed sha256', () {
    final json = valid()..['sha256'] = 'abc';
    expect(WesiMediaEngineRelease.tryParse(json), isNull);
  });

  test('rejects non-positive size', () {
    final json = valid()..['sizeBytes'] = 0;
    expect(WesiMediaEngineRelease.tryParse(json), isNull);
  });

  test('rejects launcher traversal', () {
    final json = valid()..['launcher'] = '../../evil.exe';
    expect(WesiMediaEngineRelease.tryParse(json), isNull);
  });
}
