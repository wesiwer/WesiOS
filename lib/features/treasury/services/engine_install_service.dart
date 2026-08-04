import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/github_release_download.dart';
import 'forecast_engine_kind.dart';

/// Стадия установки движка — используется и баннером на экране прогноза,
/// и плавающим оверлеем прогресса, и разделом в настройках. Один источник
/// правды, не три независимых состояния.
enum InstallStage { idle, downloading, extracting, done, failed }

class EngineInstallProgress {
  final InstallStage stage;
  final int bytesDownloaded;
  final int? totalBytes; // null, если сервер не отдал Content-Length
  final double bytesPerSecond;
  final String? error;

  const EngineInstallProgress({
    this.stage = InstallStage.idle,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.bytesPerSecond = 0,
    this.error,
  });

  double? get fraction =>
      (totalBytes != null && totalBytes! > 0)
          ? (bytesDownloaded / totalBytes!).clamp(0.0, 1.0)
          : null;
}

/// Описание доступной сборки одного движка — берётся из `manifest.json`,
/// который CI публикует рядом с самими zip-ами.
///
/// Существует, чтобы приложению не приходилось выпускать новую версию ради
/// того, чтобы узнать о свежей сборке движка: манифест лежит по постоянному
/// адресу, а его содержимое обновляется при каждой пересборке.
class EngineRelease {
  /// Дата сборки в виде `ГГГГ.ММ.ДД` — монотонна и читаема человеком.
  final String version;
  final String assetName;
  final int? sizeBytes;

  /// Версии ключевых python-пакетов внутри бандла (`statsmodels: 0.14.6`) —
  /// показываем в настройках, чтобы было видно, что именно установлено.
  final Map<String, String> packages;

  const EngineRelease({
    required this.version,
    required this.assetName,
    this.sizeBytes,
    this.packages = const {},
  });

  static EngineRelease? tryParse(Map<String, dynamic> json) {
    final version = json['version'];
    final asset = json['asset'];
    if (version is! String || asset is! String) return null;
    return EngineRelease(
      version: version,
      assetName: asset,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      packages: (json['packages'] as Map?)?.map(
            (k, v) => MapEntry('$k', '$v'),
          ) ??
          const {},
    );
  }
}

/// Скачивает и устанавливает готовые движки прогноза (Prophet/SARIMAX) —
/// портативный Python с уже установленными зависимостями, собранный ОДИН РАЗ
/// в CI (см. `.github/workflows/build-engines.yml`), а не на машине
/// пользователя: у обычного пользователя нет C++ тулчейна для сборки
/// CmdStan (Prophet), поэтому on-device pip install тут не подходит —
/// вместо этого просто скачивается готовый zip и распаковывается.
///
/// Публикуется как GitHub Release asset — стабильный публичный URL,
/// без токенов/авторизации, обычно быстрый (Fastly-CDN у GitHub).
///
/// Устанавливается в `ApplicationSupportDirectory` (не рядом с exe —
/// это может быть Program Files, куда обычный пользователь не может
/// писать без прав администратора).
class EngineInstallService {
  /// Тег Release, под которым лежат и манифест, и сами бандлы. Намеренно
  /// НЕ версия движка: CI перезаписывает ассеты по этому же тегу
  /// (`gh release upload --clobber`), а фактическая версия живёт внутри
  /// `manifest.json`. Так ссылка для скачивания остаётся стабильной
  /// навсегда, а содержимое обновляется — приложению не нужен новый релиз,
  /// чтобы узнать о свежей сборке движка.
  static const String _releaseTag = 'engines-v1';
  static const String _manifestAsset = 'manifest.json';

  static const Map<ForecastEngineKind, String> _assetName = {
    ForecastEngineKind.sarimax: 'wesios-engine-sarimax-win64.zip',
    ForecastEngineKind.prophet: 'wesios-engine-prophet-win64.zip',
  };

  /// Ориентировочный размер — только для текста на кнопке «Скачать» ДО
  /// того, как подтянулся манифест с реальным размером.
  static const Map<ForecastEngineKind, int> approxSizeBytes = {
    ForecastEngineKind.sarimax: 350 * 1024 * 1024,
    ForecastEngineKind.prophet: 1700 * 1024 * 1024,
  };

  /// Общее наблюдаемое состояние — один и тот же экземпляр для баннера,
  /// плавающего оверлея и экрана настроек, чтобы разные виджеты не
  /// запускали параллельные закачки одного и того же движка.
  static final ValueNotifier<Map<ForecastEngineKind, EngineInstallProgress>>
      progress = ValueNotifier({});

  static Future<Directory> _engineDir(ForecastEngineKind kind) async {
    final base = await getApplicationSupportDirectory();
    return Directory(
        '${base.path}${Platform.pathSeparator}engines${Platform.pathSeparator}${kind.name}');
  }

  static Future<String?> pythonExecutable(ForecastEngineKind kind) async {
    if (!_assetName.containsKey(kind)) return null;
    final dir = await _engineDir(kind);
    final exe = File(
        '${dir.path}${Platform.pathSeparator}python${Platform.pathSeparator}python.exe');
    return await exe.exists() ? exe.path : null;
  }

  static Future<String?> scriptDirectory(ForecastEngineKind kind) async {
    if (!_assetName.containsKey(kind)) return null;
    final dir = await _engineDir(kind);
    final scripts =
        Directory('${dir.path}${Platform.pathSeparator}python_engines');
    return await scripts.exists() ? scripts.path : null;
  }

  static Future<bool> isInstalled(ForecastEngineKind kind) async =>
      await pythonExecutable(kind) != null;

  static bool isInstalling(ForecastEngineKind kind) {
    final stage = progress.value[kind]?.stage;
    return stage == InstallStage.downloading ||
        stage == InstallStage.extracting;
  }

  // ===== Манифест: какие версии доступны на сервере =====

  static Map<ForecastEngineKind, EngineRelease>? _manifest;
  static DateTime? _manifestFetchedAt;
  static const Duration _manifestTtl = Duration(hours: 6);

  /// Тянет `manifest.json` с того же Release. Fail-soft: нет сети/битый
  /// JSON — возвращает null, и UI просто не показывает информацию об
  /// обновлениях (вместо того чтобы ругаться на пользователя за то, что
  /// он офлайн). Результат кэшируется на [_manifestTtl], чтобы не ходить
  /// в сеть на каждую перерисовку экрана настроек.
  static Future<Map<ForecastEngineKind, EngineRelease>?> fetchManifest({
    bool force = false,
  }) async {
    final fresh = _manifestFetchedAt != null &&
        DateTime.now().difference(_manifestFetchedAt!) < _manifestTtl;
    if (!force && fresh && _manifest != null) return _manifest;

    final client = HttpClient();
    try {
      final asset = await GitHubReleaseDownload.open(
        client,
        tag: _releaseTag,
        asset: _manifestAsset,
        timeout: const Duration(seconds: 15),
      );
      if (!asset.ok) return _manifest;
      final response = asset.response!;

      final body = await response.transform(utf8.decoder).join();
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final engines = decoded['engines'];
      if (engines is! Map) return _manifest;

      final parsed = <ForecastEngineKind, EngineRelease>{};
      for (final kind in _assetName.keys) {
        final entry = engines[kind.name];
        if (entry is Map<String, dynamic>) {
          final release = EngineRelease.tryParse(entry);
          if (release != null) parsed[kind] = release;
        }
      }
      _manifest = parsed;
      _manifestFetchedAt = DateTime.now();
      return _manifest;
    } catch (_) {
      return _manifest; // офлайн — отдаём то, что уже знали (может быть null)
    } finally {
      client.close();
    }
  }

  /// Последний известный манифест без похода в сеть (для синхронной отрисовки).
  static EngineRelease? cachedRelease(ForecastEngineKind kind) =>
      _manifest?[kind];

  // ===== Версия установленного движка =====

  static String _versionKey(ForecastEngineKind kind) =>
      'engine_version_${kind.name}';

  static String? installedVersion(ForecastEngineKind kind) {
    try {
      return Hive.box(_box).get(_versionKey(kind)) as String?;
    } catch (_) {
      return null;
    }
  }

  /// Есть ли на сервере сборка, отличная от установленной.
  ///
  /// Сравниваем на неравенство, а не «больше/меньше»: версии — даты сборки,
  /// и если по какой-то причине на сервере откатили сборку назад, честнее
  /// предложить синхронизироваться с текущей серверной, чем молча остаться
  /// на отозванной. Если у движка нет записанной версии (установлен до
  /// появления версионирования) — тоже предлагаем обновиться.
  static bool updateAvailable(ForecastEngineKind kind) {
    final latest = _manifest?[kind];
    if (latest == null) return false; // манифест не загружен — молчим
    return installedVersion(kind) != latest.version;
  }

  static Future<void> install(ForecastEngineKind kind) async {
    if (!_assetName.containsKey(kind)) return;
    if (isInstalling(kind)) return; // уже качается — не дублируем запрос

    if (!Platform.isWindows) {
      _update(
        kind,
        const EngineInstallProgress(
          stage: InstallStage.failed,
          error: 'windows_only',
        ),
      );
      return;
    }

    _update(kind, const EngineInstallProgress(stage: InstallStage.downloading));

    // Манифест даёт актуальное имя ассета и версию. Если он недоступен
    // (офлайн/ещё не опубликован) — падаем на зашитое имя: скачать
    // текущую сборку всё равно можно, просто без записи версии.
    final manifest = await fetchManifest();
    final release = manifest?[kind];
    final assetName = release?.assetName ?? _assetName[kind]!;

    final client = HttpClient();
    File? tempZip;
    try {
      final asset = await GitHubReleaseDownload.open(
        client,
        tag: _releaseTag,
        asset: assetName,
        // Движок весит от 350 МБ до 1,7 ГБ: тридцати секунд по умолчанию
        // хватает только на установление связи, не на саму загрузку.
        timeout: const Duration(minutes: 5),
      );
      if (!asset.ok) {
        _update(
          kind,
          EngineInstallProgress(
            stage: InstallStage.failed,
            // Отдельный код, а не «HTTP 404»: закрытый репозиторий без входа
            // в GitHub — единственная причина отказа, которую человек может
            // устранить сам, и она не должна выглядеть как поломка сервера.
            error: switch (asset.status) {
              ReleaseFetch.needsSignIn => 'github_sign_in',
              ReleaseFetch.notFound => 'not_published',
              _ => 'network',
            },
          ),
        );
        return;
      }
      final response = asset.response!;

      final total = response.contentLength > 0 ? response.contentLength : null;
      final tempDir = await getTemporaryDirectory();
      tempZip = File(
          '${tempDir.path}${Platform.pathSeparator}wesios_${kind.name}_download.zip');
      final sink = tempZip.openWrite();

      var downloaded = 0;
      var lastTick = DateTime.now();
      var lastBytes = 0;

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        final now = DateTime.now();
        final elapsedMs = now.difference(lastTick).inMilliseconds;
        // Троттлинг обновлений: не чаще ~3 раз/сек, иначе на быстром канале
        // ValueNotifier заваливает UI перерисовками почём зря.
        if (elapsedMs >= 300) {
          final speed = (downloaded - lastBytes) / (elapsedMs / 1000.0);
          _update(
            kind,
            EngineInstallProgress(
              stage: InstallStage.downloading,
              bytesDownloaded: downloaded,
              totalBytes: total,
              bytesPerSecond: speed,
            ),
          );
          lastTick = now;
          lastBytes = downloaded;
        }
      }
      await sink.flush();
      await sink.close();

      _update(
        kind,
        EngineInstallProgress(
          stage: InstallStage.extracting,
          bytesDownloaded: downloaded,
          totalBytes: total,
        ),
      );

      final dir = await _engineDir(kind);
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);

      final input = InputFileStream(tempZip.path);
      final archive = ZipDecoder().decodeBuffer(input);
      await extractArchiveToDisk(archive, dir.path);
      await input.close();

      // Версию пишем ТОЛЬКО после успешной распаковки — иначе оборванная
      // установка выглядела бы как «актуальная версия уже стоит», и
      // предложение обновиться больше не появилось бы.
      if (release != null) {
        await Hive.box(_box).put(_versionKey(kind), release.version);
      }

      _update(
        kind,
        EngineInstallProgress(
          stage: InstallStage.done,
          bytesDownloaded: downloaded,
          totalBytes: total,
        ),
      );
    } catch (e) {
      _update(kind, EngineInstallProgress(stage: InstallStage.failed, error: '$e'));
    } finally {
      client.close();
      if (tempZip != null && await tempZip.exists()) {
        await tempZip.delete();
      }
    }
  }

  static void _update(ForecastEngineKind kind, EngineInstallProgress p) {
    progress.value = {...progress.value, kind: p};
  }

  static void clearProgress(ForecastEngineKind kind) {
    final next = {...progress.value}..remove(kind);
    progress.value = next;
  }

  // ===== Настройки видимости =====

  static const _box = 'wesios_settings';
  static const _bannerDismissedKey = 'engine_banner_dismissed';

  /// Баннер на экране прогноза закрыт пользователем (крестиком) — больше не
  /// показываем сами, но в Настройках всегда можно докачать движки вручную.
  static bool get bannerDismissed {
    try {
      return Hive.box(_box).get(_bannerDismissedKey, defaultValue: false) as bool;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setBannerDismissed(bool value) async {
    await Hive.box(_box).put(_bannerDismissedKey, value);
  }

  /// Плавающий индикатор загрузки скрыт пользователем — прогресс всё ещё
  /// идёт в фоне, просто без мини-окошка поверх других экранов. Кнопка в
  /// Настройках возвращает его обратно.
  static final ValueNotifier<bool> overlayHidden = ValueNotifier(false);
}
