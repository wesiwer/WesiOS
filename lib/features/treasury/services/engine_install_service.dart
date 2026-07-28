import 'dart:async';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
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
  static const String _releaseTag = 'engines-v1';
  static const Map<ForecastEngineKind, String> _assetName = {
    ForecastEngineKind.sarimax: 'wesios-engine-sarimax-win64.zip',
    ForecastEngineKind.prophet: 'wesios-engine-prophet-win64.zip',
  };

  /// Ориентировочный размер (для текста на кнопке «Скачать» ДО того, как
  /// сервер успел ответить с реальным Content-Length).
  static const Map<ForecastEngineKind, int> approxSizeBytes = {
    ForecastEngineKind.sarimax: 350 * 1024 * 1024,
    ForecastEngineKind.prophet: 1700 * 1024 * 1024,
  };

  static String _downloadUrl(ForecastEngineKind kind) =>
      'https://github.com/wesiwer/WesiOS/releases/download/$_releaseTag/${_assetName[kind]}';

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

    final client = HttpClient();
    File? tempZip;
    try {
      final request = await client.getUrl(Uri.parse(_downloadUrl(kind)));
      final response = await request.close();
      if (response.statusCode != 200) {
        _update(
          kind,
          EngineInstallProgress(
              stage: InstallStage.failed, error: 'HTTP ${response.statusCode}'),
        );
        return;
      }

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
