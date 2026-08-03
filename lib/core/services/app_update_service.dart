import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_version.dart';
import 'github_auth_service.dart';

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

  static const String repoOwner = 'wesiwer';
  static const String repoName = 'WesiOS';

  /// Текст помощи, если Defender / Controlled Folder Access мешает подмене файлов.
  static const String windowsDefenderHelp =
      'Windows Defender или Controlled Folder Access мог заблокировать '
      'замену файлов. Открой Защитник Windows → Защита от вирусов → '
      'Управление параметрами → Исключения → Добавить папку с WesiOS '
      'и %TEMP%. Лог обновления: %TEMP%\\wesios_update.log';

  /// Прямая ссылка на файл релиза. Работает только для публичных
  /// репозиториев; для приватного нужен путь через API — см. [_openAsset].
  static String releaseFileUrl(String asset) =>
      'https://github.com/$repoOwner/$repoName/releases/download/$_releaseTag/$asset';

  static String get _releaseApiUrl =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$_releaseTag';

  /// id ассетов релиза по именам. Нужны, чтобы скачивать через API: у
  /// приватного репозитория `browser_download_url` отдаёт 404 без входа.
  static Future<Map<String, int>?> _assetIds(
      HttpClient client, Map<String, String> headers) async {
    final req = await client.getUrl(Uri.parse(_releaseApiUrl));
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
    final res = await req.close();
    if (res.statusCode != 200) return null;
    final json = jsonDecode(await res.transform(utf8.decoder).join());
    if (json is! Map || json['assets'] is! List) return null;
    return {
      for (final a in json['assets'] as List)
        if (a is Map && a['name'] is String && a['id'] is int)
          a['name'] as String: a['id'] as int,
    };
  }

  /// Открывает поток с содержимым ассета.
  ///
  /// Редирект обрабатывается вручную и **намеренно**: GitHub отвечает 302 на
  /// подписанную ссылку в хранилище, а хранилище отклоняет запрос, в котором
  /// есть ещё и заголовок Authorization — «только один механизм за раз».
  /// `followRedirects: true` протащил бы наш заголовок дальше и сломал бы
  /// скачивание именно там, где всё уже почти получилось.
  static Future<HttpClientResponse?> _openAsset(
    HttpClient client,
    int assetId,
    Map<String, String> headers,
  ) async {
    final req = await client.getUrl(Uri.parse(
        'https://api.github.com/repos/$repoOwner/$repoName/releases/assets/$assetId'));
    req.followRedirects = false;
    headers.forEach(req.headers.set);
    req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
    req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
    final res = await req.close();

    if (res.statusCode == 200) return res;
    if (res.statusCode == 302 || res.statusCode == 307) {
      final location = res.headers.value(HttpHeaders.locationHeader);
      // Тело первого ответа нужно вычитать, иначе соединение зависнет.
      await res.drain<void>();
      if (location == null) return null;
      final redirect = await client.getUrl(Uri.parse(location));
      redirect.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      return redirect.close();
    }
    await res.drain<void>();
    return null;
  }

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

  /// Кеш id ассетов текущего релиза — чтобы скачивание не делало ещё
  /// один запрос к API за тем же списком.
  static Map<String, int>? _assetIdCache;

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
      final headers = await GitHubAuthService.authHeaders();
      if (headers.isEmpty) {
        // Репозиторий приватный: без входа релиз не увидеть. Говорим об этом
        // только при явной проверке — «обновлений нет» и «не смог проверить»
        // снаружи выглядят одинаково, и человек сидел бы на старой версии,
        // считая её свежей. Но красный баннер при каждом запуске про то, что
        // требует отдельного действия, — уже шум.
        progress.value = force
            ? UpdateProgress(
                stage: UpdateStage.failed,
                error: GitHubAuthService.isConfigured
                    ? 'Нужен вход в GitHub: релизы лежат в приватном '
                        'репозитории. Настройки → Обновление → Войти.'
                    : 'Вход в GitHub не настроен — не задан client_id '
                        'приложения. См. Настройки → Обновление.',
              )
            : const UpdateProgress(stage: UpdateStage.idle);
        return null;
      }

      final assets = await _assetIds(client, headers);
      final manifestId = assets?[_manifestAsset];
      if (manifestId == null) {
        progress.value = force
            ? const UpdateProgress(
                stage: UpdateStage.failed,
                error: 'Релиз найден, но в нём нет app-manifest.json',
              )
            : const UpdateProgress(stage: UpdateStage.idle);
        return null;
      }
      _assetIdCache = assets;

      final response = await _openAsset(client, manifestId, headers);
      if (response == null || response.statusCode != 200) {
        progress.value = force
            ? UpdateProgress(
                stage: UpdateStage.failed,
                error: 'Не удалось прочитать манифест '
                    '(HTTP ${response?.statusCode ?? '—'})',
              )
            : const UpdateProgress(stage: UpdateStage.idle);
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
      final headers = await GitHubAuthService.authHeaders();
      if (headers.isEmpty) {
        progress.value = const UpdateProgress(
          stage: UpdateStage.failed,
          error: 'Нужен вход в GitHub: Настройки → Обновление → Войти.',
        );
        return;
      }
      // Список ассетов уже прочитан при проверке — второй запрос к API за той
      // же информацией только тратит лимит.
      final assets = _assetIdCache ?? await _assetIds(client, headers);
      final assetId = assets?[release.assetName];
      if (assetId == null) {
        progress.value = UpdateProgress(
          stage: UpdateStage.failed,
          error: 'В релизе нет файла ${release.assetName}',
        );
        return;
      }

      final response = await _openAsset(client, assetId, headers);
      if (response == null || response.statusCode != 200) {
        progress.value = UpdateProgress(
          stage: UpdateStage.failed,
          error: 'HTTP ${response?.statusCode ?? '—'}',
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

  /// Best-effort: добавить каталог установки и Temp в исключения Defender.
  ///
  /// Без прав администратора `Add-MpPreference` падает — это нормально,
  /// bat потом попробует ещё раз (и при необходимости поднимет UAC).
  /// Ошибки глотаем: отсутствие исключения не должно блокировать обновление.
  static Future<void> ensureWindowsDefenderExclusions({
    required String exeDir,
    required String tempDir,
  }) async {
    if (!Platform.isWindows) return;
    try {
      final ps = '''
\$ErrorActionPreference = 'SilentlyContinue'
Add-MpPreference -ExclusionPath '$exeDir' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionPath '$tempDir' -ErrorAction SilentlyContinue
Add-MpPreference -ExclusionProcess 'wesios.exe' -ErrorAction SilentlyContinue
''';
      await Process.run(
        'powershell',
        ['-NoProfile', '-NonInteractive', '-Command', ps],
        runInShell: false,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      // нет прав / Defender выключен / таймаут — не критично
    }
  }

  /// Windows: портативная сборка, поэтому «установка» — это подмена файлов.
  ///
  /// Своё же приложение переписать на ходу нельзя: exe заблокирован, пока
  /// процесс жив. Поэтому пишем .bat, который:
  /// 1) ждёт завершения процесса,
  /// 2) (best-effort) добавляет исключения Defender,
  /// 3) распаковывает zip,
  /// 4) robocopy поверх папки установки с retry,
  /// 5) при успехе перезапускает приложение,
  /// 6) пишет лог в %TEMP%\\wesios_update.log.
  static Future<void> _installWindows(String zipPath) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    // На Windows resolvedExecutable почти всегда с `\`, но на всякий случай.
    final exeName = Platform.resolvedExecutable
        .replaceAll('/', r'\')
        .split(r'\')
        .last;
    final tempDir = await getTemporaryDirectory();
    final scriptPath = '${tempDir.path}\wesios_update.bat';
    final extractDir = '${tempDir.path}\wesios_update_unpacked';
    final logPath = '${tempDir.path}\wesios_update.log';

    await ensureWindowsDefenderExclusions(
      exeDir: exeDir,
      tempDir: tempDir.path,
    );

    // Экранируем пути для bat: кавычки внутри уже в кавычках не нужны,
    // достаточно не допускать `"` в путях (Windows-пути их не содержат).
    final script = '''
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "LOG=$logPath"
echo ==== WesiOS update %DATE% %TIME% ==== > "%LOG%"
echo exeDir=$exeDir>> "%LOG%"
echo exeName=$exeName>> "%LOG%"
echo zipPath=$zipPath>> "%LOG%"
echo extractDir=$extractDir>> "%LOG%"

rem Ждём, пока WesiOS закроется — иначе файлы заняты и копирование упадёт.
echo Waiting for process to exit...>> "%LOG%"
set /a _waits=0
:waitloop
tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL
if not errorlevel 1 (
  set /a _waits+=1
  if !_waits! GEQ 60 (
    echo TIMEOUT waiting for process>> "%LOG%"
    goto :fail
  )
  timeout /t 1 /nobreak >NUL
  goto waitloop
)
echo Process gone after !_waits!s>> "%LOG%"

rem Best-effort Defender exclusions (может потребовать UAC — пробуем тихо).
echo Adding Defender exclusions...>> "%LOG%"
powershell -NoProfile -NonInteractive -Command "Try { Add-MpPreference -ExclusionPath '$exeDir' -EA SilentlyContinue; Add-MpPreference -ExclusionPath '$tempDir.path' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess '$exeName' -EA SilentlyContinue; 'ok' } Catch { \$_.Exception.Message }" >> "%LOG%" 2>&1

if exist "$extractDir" (
  echo Cleaning old extract dir>> "%LOG%"
  rmdir /S /Q "$extractDir" 2>> "%LOG%"
)
mkdir "$extractDir" 2>> "%LOG%"
if errorlevel 1 (
  echo Failed to mkdir extract dir>> "%LOG%"
  goto :fail
)

echo Expanding archive...>> "%LOG%"
powershell -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$extractDir' -Force" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo Expand-Archive failed>> "%LOG%"
  goto :fail
)

rem CI пакует Release/* в корень zip. Иногда бывает одна вложенная папка.
set "SRC=$extractDir"
if not exist "%SRC%\\$exeName" (
  for /D %%D in ("$extractDir\\*") do (
    if exist "%%D\\$exeName" set "SRC=%%D"
  )
)
echo SRC=!SRC!>> "%LOG%"
if not exist "!SRC!\\$exeName" (
  echo ERROR: $exeName not found after extract>> "%LOG%"
  dir /s /b "$extractDir" >> "%LOG%" 2>&1
  goto :fail
)

echo Robocopy from !SRC! to $exeDir>> "%LOG%"
rem /E = subdirs, /R:5 = retries, /W:2 = wait, /NFL /NDL = quieter log
robocopy "!SRC!" "$exeDir" /E /R:5 /W:2 /NFL /NDL /NP >> "%LOG%" 2>&1
set "RC=!ERRORLEVEL!"
echo robocopy exit=!RC!>> "%LOG%"
rem robocopy: 0-7 = success-ish (files copied / same / extras), >=8 = failure
if !RC! GEQ 8 (
  echo Robocopy failed with code !RC!>> "%LOG%"
  goto :fail
)

if not exist "$exeDir\\$exeName" (
  echo ERROR: $exeName missing after copy>> "%LOG%"
  goto :fail
)

echo SUCCESS — starting app>> "%LOG%"
start "" "$exeDir\\$exeName"
rmdir /S /Q "$extractDir" 2>> "%LOG%"
del /F /Q "$zipPath" 2>> "%LOG%"
echo Cleanup done>> "%LOG%"
(goto) 2>nul & del "%~f0"
exit /b 0

:fail
echo FAIL — not restarting app. See log.>> "%LOG%"
echo.>> "%LOG%"
echo If Access Denied: add folder to Defender exclusions:>> "%LOG%"
echo   $exeDir>> "%LOG%"
echo   $tempDir.path>> "%LOG%"
rem Оставляем zip и extract для разбора; bat не удаляем сразу, чтобы лог жил.
exit /b 1
''';

    await File(scriptPath).writeAsString(script);
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '', '/min', scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    // Даём bat-у мгновение стартовать до того, как процесс исчезнет из tasklist.
    await Future<void>.delayed(const Duration(milliseconds: 300));
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
