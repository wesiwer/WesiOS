import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/treasury/services/engine_install_service.dart';

/// Ровно тот JSON, который собирает publish-manifest в build-engines.yml.
/// Если формат манифеста в workflow поменяется, а парсер — нет (или
/// наоборот), этот тест поймает расхождение здесь, а не у пользователя
/// в виде «обновления никогда не предлагаются».
const _realWorldManifest = '''
{
  "schema": 1,
  "engines": {
    "sarimax": {
      "version": "2026.07.28",
      "asset": "wesios-engine-sarimax-win64.zip",
      "sizeBytes": 367001600,
      "packages": {"numpy":"2.4.6","pandas":"3.0.5","statsmodels":"0.14.6"}
    },
    "prophet": {
      "version": "2026.08.04",
      "asset": "wesios-engine-prophet-win64.zip",
      "sizeBytes": 1825361100,
      "packages": {"numpy":"2.4.6","pandas":"3.0.5","prophet":"1.3.0"}
    }
  }
}
''';

void main() {
  group('EngineRelease.tryParse', () {
    test('parses an entry produced by the build-engines workflow', () {
      final decoded = jsonDecode(_realWorldManifest) as Map<String, dynamic>;
      final engines = decoded['engines'] as Map<String, dynamic>;

      final sarimax =
          EngineRelease.tryParse(engines['sarimax'] as Map<String, dynamic>);

      expect(sarimax, isNotNull);
      expect(sarimax!.version, '2026.07.28');
      expect(sarimax.assetName, 'wesios-engine-sarimax-win64.zip');
      expect(sarimax.sizeBytes, 367001600);
      expect(sarimax.packages['statsmodels'], '0.14.6');
    });

    test('reads each engine independently — versions may differ when one '
        'rebuild succeeded and the other did not', () {
      final decoded = jsonDecode(_realWorldManifest) as Map<String, dynamic>;
      final engines = decoded['engines'] as Map<String, dynamic>;

      final sarimax =
          EngineRelease.tryParse(engines['sarimax'] as Map<String, dynamic>);
      final prophet =
          EngineRelease.tryParse(engines['prophet'] as Map<String, dynamic>);

      expect(sarimax!.version, isNot(prophet!.version));
    });

    test('returns null instead of throwing on a malformed entry', () {
      expect(EngineRelease.tryParse(const {'asset': 'x.zip'}), isNull);
      expect(EngineRelease.tryParse(const {'version': '2026.01.01'}), isNull);
      expect(EngineRelease.tryParse(const {}), isNull);
    });

    test('tolerates a missing sizeBytes/packages block', () {
      final release = EngineRelease.tryParse(const {
        'version': '2026.01.01',
        'asset': 'x.zip',
      });

      expect(release, isNotNull);
      expect(release!.sizeBytes, isNull);
      expect(release.packages, isEmpty);
    });
  });
}
