import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/core/services/app_update_service.dart';

void main() {
  group('AppRelease.compareVersions', () {
    test('compares numerically, not lexicographically — as strings "0.10.0" '
        'sorts BEFORE "0.9.0", and updates would silently stop being offered '
        'after the tenth minor', () {
      expect(AppRelease.compareVersions('0.10.0', '0.9.0'), greaterThan(0));
      expect(AppRelease.compareVersions('0.9.0', '0.10.0'), lessThan(0));
      expect(AppRelease.compareVersions('1.0.0', '0.99.99'), greaterThan(0));
    });

    test('equal versions compare equal regardless of shape', () {
      expect(AppRelease.compareVersions('1.2.3', '1.2.3'), 0);
      expect(AppRelease.compareVersions('1.2', '1.2.0'), 0);
      expect(AppRelease.compareVersions('1', '1.0.0'), 0);
    });

    test('a missing component counts as zero, not as "greater"', () {
      expect(AppRelease.compareVersions('1.2', '1.2.1'), lessThan(0));
      expect(AppRelease.compareVersions('1.2.1', '1.2'), greaterThan(0));
    });

    test('garbage components degrade to zero instead of throwing', () {
      expect(() => AppRelease.compareVersions('1.x.3', '1.0.3'),
          returnsNormally);
      expect(AppRelease.compareVersions('1.x.3', '1.0.3'), 0);
    });
  });

  group('AppRelease.isNewerThan', () {
    AppRelease release(String version, int build) => AppRelease(
          version: version,
          build: build,
          assetName: 'wesios-android.apk',
        );

    test('a higher version is newer even with a lower build number — the '
        'version wins, otherwise a rebuild counter reset would block the '
        'update forever', () {
      expect(release('0.9.0', 1).isNewerThan('0.8.0', 99), isTrue);
    });

    test('same version, higher build is newer', () {
      expect(release('0.8.0', 11).isNewerThan('0.8.0', 10), isTrue);
    });

    test('same version and build is not newer', () {
      expect(release('0.8.0', 10).isNewerThan('0.8.0', 10), isFalse);
    });

    test('an older version is never newer', () {
      expect(release('0.7.0', 999).isNewerThan('0.8.0', 1), isFalse);
    });
  });

  group('AppRelease.tryParse', () {
    test('parses a platform entry produced by the release workflow', () {
      final json = jsonDecode('''
        {
          "version": "0.9.0",
          "build": 11,
          "asset": "wesios-android.apk",
          "sizeBytes": 24300000,
          "notes": "Автообновление и новая аналитика"
        }
      ''') as Map<String, dynamic>;

      final r = AppRelease.tryParse(json)!;
      expect(r.version, '0.9.0');
      expect(r.build, 11);
      expect(r.assetName, 'wesios-android.apk');
      expect(r.sizeBytes, 24300000);
      expect(r.notes, 'Автообновление и новая аналитика');
    });

    test('returns null instead of throwing when version or asset is missing — '
        'a half-written manifest must not crash the check on startup', () {
      expect(AppRelease.tryParse({'build': 3}), isNull);
      expect(AppRelease.tryParse({'version': '1.0.0'}), isNull);
      expect(AppRelease.tryParse({'asset': 'x.apk'}), isNull);
    });

    test('tolerates a missing build/size/notes block', () {
      final r = AppRelease.tryParse({
        'version': '1.0.0',
        'asset': 'wesios-windows-x64.zip',
      })!;
      expect(r.build, 0);
      expect(r.sizeBytes, isNull);
      expect(r.notes, isNull);
    });
  });

  group('release URLs', () {
    test('point at the fixed app-latest tag, so the address baked into the '
        'app never has to change when a new version ships', () {
      final url = AppUpdateService.releaseFileUrl('app-manifest.json');
      expect(url, contains('/releases/download/app-latest/'));
      expect(url, endsWith('app-manifest.json'));
    });
  });
}
