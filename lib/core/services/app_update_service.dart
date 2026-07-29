import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_version.dart';

/// Стадия обновления приложения. Сознательно повторяет форму
/// `InstallStage` у движков прогноза — пользователь уже видел этот сценарий
/// с загрузкой моделей, и обновление приложения должно вести себя так же.
enum UpdateStage { idle, checking, available, downloading, ready, installing, failed }

class UpdateProgress {
  final UpdateStage stage;
  final int bytesDownloaded;
  final int? totalBytes;
  final double bytesPerSecond;
  final String? error;

  const UpdateProgress({
    this.stage = UpdateStage.idle,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.bytesPerSecond = 0,
    this.error,
  });

  double? get fraction => (totalBytes != null && totalBytes! > 0)
      ? (bytesDownloaded / totalBytes!).clamp(0.0, 1.0)
      : null;

  bool get isBusy =>
      stage == UpdateStage.downloading ||
      stage == UpdateStage.checking ||
      stage == UpdateStage.installing;
}

/// Описание доступной сборки приложения из `app-manifest.json`.
class AppRelease {
  /// Версия вида `0.9.0` — сравнивается покомпонентно, не строкой.
  final String version;

  /// Номер сборки (`+N` из pubspec). Нужен, когда версия та же, а сборка новее.
  final int build;

  /// Имя ассета для текущей платформы.
  final String assetName;
  final int? sizeBytes;

  /// Что нового — показываем в диалоге, чтобы обновление не было вслепую.
  final String? notes;

  const AppRelease({
    required this.version,
    required this.build,
    required this.assetName,
    this.sizeBytes,
    this.notes,
  });

  static AppRelease? tryParse(Map<String, dynamic> json) {
    final version = json['version'];
    final asset = json['asset'];
    if (version is! String || asset is! String) return null;
    return AppRelease(
      version: version,
      build: (json['build'] as num?)?.toInt() ?? 0,
      assetName: asset,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt(),
      notes: json['notes'] as String?,
    );
  }

  /// Строго ли эта сборка новее установленной.
  ///
  /// Сравнение покомпонентное, а не лексикографическое: строкой «0.10.0»
  /// меньше «0.9.0», и обновление после десятого минора перестало бы
  /// предлагаться вообще.
  bool isNewerThan(String currentVersion, int currentBuild) {
    final cmp = compareVersions(version, currentVersion);
    if (cmp != 0) return cmp > 0;
    return build > currentBuild;
  }

  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split(RegExp(r'[.+-]'))
        .map((p) => int.tryParse(p) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    final len = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < len; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y ? 1 : -1;
    }
    return 0;
  }
}

/// Проверка, скачивание и установка новой версии самого WesiOS.
///
/// Устроено ровно как загрузка движков прогноза: CI публикует сборки как
/// ассеты GitHub Release под ПОСТОЯННЫМ тегом, рядом лежит `app-manifest.json`
/// с актуальной версией. Приложению не нужно ничего знать заранее — оно
/// читает манифест по неизменному адресу и сравнивает версию со своей.
///
/// Платформа выбирает свой ассет сама: Android скачивает APK и отдаёт его
/// системному установщику, Windows — zip, который распаковывается и
/// подменяет файлы при следующем запуске (см. [_installWindows]).
class AppUpdateService {
  static const String _releaseTag = 'app-latest';
  static const String _manifestAsset = 'app-manifest.json';
  static const _channel = MethodChannel('wesios/updater');
  static const _box = 'wesios_settings';
  static const _skippedKey = 'update_skipped_version';

  static String releaseFileUrl(String asset) =>
      'https://github.com/wesiwer/WesiOS/releases/download/$_releaseTag/$asset';

  /// Ключ платформы в манифесте.
  static String? get platformKey {
    if (kIsWeb) return null;
    if (Platform.isAndroid) return 'android';
    if (Platform.isWindows) return 'windows';
    return null;
  }

  static bool get isSupported => platformKey != null;

  static final ValueNotifier<UpdateProgress> progress =
      ValueNotifier(const UpdateProgress());

  static final ValueNotifier<AppRelease?> latest = ValueNotifier(null);

  static AppRelease? _release;
  static DateTime? _checkedAt;
  static const Duration _checkTtl = Duration(hours: 6);

  static String get currentVersion => AppVersion.number;
  static int get currentBuild => AppVersion.build;

  /// Пользователь нажал «Пропустить эту версию» — больше не дёргаем его,
  /// пока не выйдет следующая.
  static String? get skippedVersion {
    try {
      return Hive.box(_box).get(_skippedKey) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<void> skip(String version) async {
    try {
      await Hive.box(_box).put(_skippedKey, version);
    } catch (_) {/* настройки недоступны — не критично */}
  }

  /// Есть ли обновление, которое стоит показать пользователю.
  static bool get updateAvailable {
    final r = _release;
    if (r == null) return false;
    if (!r.isNewerThan(currentVersion, currentBuild)) return false;
    return skippedVersion != r.version;
  }

  /// Читает манифест. `force: true` игнорирует кеш — для кнопки «Проверить».
  static Future<AppRelease?> check({bool force = false}) async {
    if (!isSupported) return null;
    if (!force &&
        _release != null &&
        _checkedAt != null &&
        DateTime.now().difference(_checkedAt!) < _checkTtl) {
      return _release;
    }

    progress.value = const UpdateProgress(stage: UpdateStage.checking);
    final client = HttpClient();
    try {
      final request =
          await client.getUrl(Uri.parse(releaseFileUrl(_manifestAsset)));
      final response = await request.close();
      if (response.statusCode != 200) {
        progress.value = const UpdateProgress(stage: UpdateStage.idle);
        return null;
      }
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      final platform = json[platformKey!];
      if (platform is! Map) {
        progress.value = const UpdateProgress(stage: UpdateStage.idle);
        return null;
      }
      final release =
          AppRelease.tryParse(Map<String, dynamic>.from(platform));
      _release = release;
      _checkedAt = DateTime.now();
      latest.value = release;
      progress.value = UpdateProgress(
        stage: updateAvailable ? UpdateStage.available : UpdateStage.idle,
      );
      return release;
    } catch (e) {
      // Нет сети или манифест ещё не опубликован — это не ошибка сценария,
      // просто «обновлений нет». Красный баннер тут был бы враньём.
      progress.value = const UpdateProgress(stage: UpdateStage.idle);
      return null;
    } finally {
      client.close();
    }
  }

  /// Скачивает сборку и запускает установку.
  static Future<void> downloadAndInstall() async {
    final release = _release;
    if (release == null || !isSupported) return;
    if (progress.value.isBusy) return;

    progress.value = const UpdateProgress(stage: UpdateStage.downloading);

    final client = HttpClient();
    File? target;
    try {
      final request =
          await client.getUrl(Uri.parse(releaseFileUrl(release.assetName)));
      final response = await request.close();
      if (response.statusCode != 200) {
        progress.value = UpdateProgress(
          stage: UpdateStage.failed,
          error: 'HTTP ${response.statusCode}',
        );
        return;
      }

      final total =
          response.contentLength > 0 ? response.contentLength : release.sizeBytes;
      final dir = await _downloadDir();
      target = File('${dir.path}${Platform.pathSeparator}${release.assetName}');
      if (await target.exists()) await target.delete();
      final sink = target.openWrite();

      var downloaded = 0;
      var lastTick = DateTime.now();
      var lastBytes = 0;
      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        final now = DateTime.now();
        final elapsedMs = now.difference(lastTick).inMilliseconds;
        // Тот же троттлинг, что у движков: чаще 3 раз/сек обновлять UI незачем.
        if (elapsedMs >= 300) {
          progress.value = UpdateProgress(
            stage: UpdateStage.downloading,
            bytesDownloaded: downloaded,
            totalBytes: total,
            bytesPerSecond: (downloaded - lastBytes) / (elapsedMs / 1000.0),
          );
          lastTick = now;
          lastBytes = downloaded;
        }
      }
      await sink.flush();
      await sink.close();

      progress.value = UpdateProgress(
        stage: UpdateStage.installing,
        bytesDownloaded: downloaded,
        totalBytes: total,
      );

      if (Platform.isAndroid) {
        await _installAndroid(target.path);
      } else {
        await _installWindows(target.path);
      }

      progress.value = UpdateProgress(
        stage: UpdateStage.ready,
        bytesDownloaded: downloaded,
        totalBytes: total,
      );
    } catch (e) {
      progress.value =
          UpdateProgress(stage: UpdateStage.failed, error: '$e');
    } finally {
      client.close();
    }
  }

  static Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      // Именно external files dir: FileProvider отдаёт наружу только пути из
      // file_paths.xml, и внутренний getApplicationSupportDirectory туда
      // не входит.
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getTemporaryDirectory();
  }

  /// Android: отдаём APK системному установщику.
  ///
  /// Если у приложения нет разрешения «установка из этого источника»,
  /// система молча ничего не покажет — поэтому сначала спрашиваем нативно
  /// и, если нельзя, отправляем пользователя ровно в нужный экран настроек.
  static Future<void> _installAndroid(String path) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!canInstall) {
      await _channel.invokeMethod('openInstallPermissionSettings');
      throw const _UpdateException('install_permission_required');
    }
    await _channel.invokeMethod('installApk', {'path': path});
  }

  /// Windows: портативная сборка, поэтому «установка» — это подмена файлов.
  ///
  /// Своё же приложение переписать на ходу нельзя: exe заблокирован, пока
  /// процесс жив. Поэтому пишем .bat, который ждёт завершения процесса,
  /// распаковывает архив поверх папки установки и запускает приложение
  /// заново. Скрипт удаляет сам себя последней строкой.
  static Future<void> _installWindows(String zipPath) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final exeName = Platform.resolvedExecutable.split(r'\').last;
    final tempDir = await getTemporaryDirectory();
    final scriptPath = '${tempDir.path}\\wesios_update.bat';
    final extractDir = '${tempDir.path}\\wesios_update_unpacked';

    final script = '''
@echo off
rem Ждём, пока WesiOS закроется — иначе файлы заняты и копирование упадёт.
:waitloop
tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL
if not errorlevel 1 (
  timeout /t 1 /nobreak >NUL
  goto waitloop
)

if exist "$extractDir" rmdir /S /Q "$extractDir"
mkdir "$extractDir"
powershell -NoProfile -Command "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$extractDir' -Force"

rem Сборка лежит внутри одной папки — копируем её содержимое, а не саму папку.
for /D %%D in ("$extractDir\\*") do (
  xcopy "%%D\\*" "$exeDir\\" /E /Y /I >NUL
)
xcopy "$extractDir\\*.*" "$exeDir\\" /Y >NUL 2>&1

start "" "$exeDir\\$exeName"
rmdir /S /Q "$extractDir"
del "$zipPath"
(goto) 2>nul & del "%~f0"
''';

    await File(scriptPath).writeAsString(script);
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '', '/min', scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    exit(0);
  }

  static void reset() => progress.value = const UpdateProgress();
}

class _UpdateException implements Exception {
  final String code;
  const _UpdateException(this.code);
  @override
  String toString() => code;
}
