import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:wesios/core/services/app_update_service.dart';
import 'package:wesios/core/services/update_endpoint.dart';

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

  group('свой сервер как источник обновлений', () {
    late Directory dir;

    setUpAll(() async {
      dir = Directory.systemTemp.createTempSync('wesios_update_src');
      Hive.init(dir.path);
      await Hive.openBox('wesios_settings');
    });

    tearDownAll(() async {
      await Hive.close();
      dir.deleteSync(recursive: true);
    });

    setUp(() => UpdateEndpoint.setOverride(null));

    test('по умолчанию — свой сервер, а не GitHub', () {
      expect(UpdateEndpoint.base, UpdateEndpoint.defaultBase);
      expect(UpdateEndpoint.manifestUrl, endsWith('/app/app-manifest.json'));
    });

    test('адрес можно переопределить — иначе переезд сервера не пережить',
        () async {
      // Сборка со старым адресом остаётся у людей на руках, и обновиться,
      // чтобы узнать новый адрес, она уже не может. Круг размыкается только
      // настройкой.
      await UpdateEndpoint.setOverride('https://other.example.com/files');
      expect(UpdateEndpoint.manifestUrl,
          'https://other.example.com/files/app/app-manifest.json');
    });

    test('лишние косые черты не превращаются в двойные', () async {
      await UpdateEndpoint.setOverride('https://x.example.com/files///');
      expect(UpdateEndpoint.fileUrl('/app/0.1.5+12/wesios-android.apk'),
          'https://x.example.com/files/app/0.1.5+12/wesios-android.apk');
    });

    test('пустая строка возвращает адрес по умолчанию, а не ломает ссылки',
        () async {
      await UpdateEndpoint.setOverride('   ');
      expect(UpdateEndpoint.base, UpdateEndpoint.defaultBase);
    });
  });

  group('контрольная сумма в манифесте', () {
    test('разбирается, когда сервер её прислал', () {
      final release = AppRelease.tryParse({
        'version': '0.1.5',
        'build': 12,
        'asset': 'wesios-android.apk',
        'path': 'app/0.1.5+12/wesios-android.apk',
        'sizeBytes': 26000000,
        'sha256': 'ABCDEF0123456789',
      })!;
      expect(release.sha256, 'ABCDEF0123456789');
    });

    test('её отсутствие не мешает обновиться со старого источника', () {
      // GitHub Releases сумму не отдаёт. Обновление оттуда должно остаться
      // возможным, иначе запасной путь перестанет быть путём.
      final release = AppRelease.tryParse({
        'version': '0.1.5',
        'build': 12,
        'asset': 'wesios-android.apk',
      })!;
      expect(release.sha256, isNull);
      expect(release.downloadUrl, isNull);
    });

    test('ссылка приклеивается, не теряя остального', () {
      final base = AppRelease.tryParse({
        'version': '0.1.5',
        'build': 12,
        'asset': 'wesios-android.apk',
        'sizeBytes': 100,
        'sha256': 'abc',
        'notes': 'Что нового',
      })!;
      final withUrl = base.withDownloadUrl('https://s/app/x.apk');
      expect(withUrl.downloadUrl, 'https://s/app/x.apk');
      expect(withUrl.sha256, 'abc');
      expect(withUrl.sizeBytes, 100);
      expect(withUrl.notes, 'Что нового');
      expect(withUrl.version, '0.1.5');
    });
  });

  group('коды ошибок', () {
    test('несовпадение суммы — отдельный код, а не «ошибка скачивания»', () {
      // Обрыв связи чинится повтором, несовпадение суммы — нет. Смешав их в
      // один код, человека отправили бы жать «повторить» до бесконечности.
      final mismatch = UpdateError.byCode('W111');
      final network = UpdateError.byCode('W103');
      expect(mismatch.code, isNot(network.code));
      expect(mismatch.titleRu, isNot(network.titleRu));
      expect(mismatch.messageRu, contains('умма'));
    });

    test('у каждого кода свой заголовок — иначе они бесполезны', () {
      const codes = [
        'W101', 'W102', 'W103', 'W104', 'W105',
        'W106', 'W107', 'W108', 'W109', 'W110', 'W111',
        'A201', 'A202',
      ];
      final titles = [
        for (final c in codes) UpdateError.byCode(c).titleRu,
      ];
      expect(titles.toSet().length, titles.length);
    });
  });
}
