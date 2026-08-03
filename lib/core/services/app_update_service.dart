import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../constants/app_version.dart';
import 'github_auth_service.dart';

enum UpdateStage { idle, checking, available, downloading, ready, installing, failed }

class UpdateProgress {
  final UpdateStage stage;
  final int bytesDownloaded;
  final int? totalBytes;
  final double bytesPerSecond;
  final String? error;
  final String? errorCode;

  const UpdateProgress({
    this.stage = UpdateStage.idle,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.bytesPerSecond = 0,
    this.error,
    this.errorCode,
  });

  double? get fraction => (totalBytes != null && totalBytes! > 0)
      ? (bytesDownloaded / totalBytes!).clamp(0.0, 1.0)
      : null;

  bool get isBusy =>
      stage == UpdateStage.downloading ||
      stage == UpdateStage.checking ||
      stage == UpdateStage.installing;
}

/// Структурированная ошибка обновления для стилизованного диалога WesiOS.
class UpdateError {
  /// Код вида W107 / A201 — показывается пользователю.
  final String code;
  final String titleRu;
  final String titleEn;
  final String messageRu;
  final String messageEn;
  final String? helpRu;
  final String? helpEn;
  final String? detail;
  final String? logPath;

  const UpdateError({
    required this.code,
    required this.titleRu,
    required this.titleEn,
    required this.messageRu,
    required this.messageEn,
    this.helpRu,
    this.helpEn,
    this.detail,
    this.logPath,
  });

  String title(bool ru) => ru ? titleRu : titleEn;
  String message(bool ru) => ru ? messageRu : messageEn;
  String? help(bool ru) {
    final h = ru ? helpRu : helpEn;
    if (h == null || h.isEmpty) return null;
    return h;
  }

  static UpdateError byCode(String code, {String? detail, String? logPath}) {
    switch (code) {
      case 'W101':
        return UpdateError(
          code: code,
          titleRu: 'Нужен вход в GitHub',
          titleEn: 'GitHub sign-in required',
          messageRu:
              'Релизы лежат в репозитории, к которому нет доступа без входа. Открой Настройки → Обновление → Войти.',
          messageEn:
              'Releases need authentication. Open Settings → Updates → Sign in.',
          detail: detail,
          logPath: logPath,
        );
      case 'W102':
        return UpdateError(
          code: code,
          titleRu: 'В релизе нет файла сборки',
          titleEn: 'Release asset missing',
          messageRu:
              'Манифест ссылается на файл, которого нет в GitHub Release. Запусти Publish ещё раз или проверь app-latest.',
          messageEn:
              'The manifest points to a file that is not on the GitHub Release. Re-run Publish or check app-latest.',
          detail: detail,
          logPath: logPath,
        );
      case 'W103':
        return UpdateError(
          code: code,
          titleRu: 'Ошибка скачивания',
          titleEn: 'Download failed',
          messageRu:
              'Не удалось скачать сборку с GitHub. Проверь интернет и повтори попытку.',
          messageEn:
              'Could not download the build from GitHub. Check the network and try again.',
          detail: detail,
          logPath: logPath,
        );
      case 'W104':
        return UpdateError(
          code: code,
          titleRu: 'Сбой обновления',
          titleEn: 'Update failed',
          messageRu: 'Во время скачивания или подготовки установки произошла ошибка.',
          messageEn: 'An error occurred while downloading or preparing the install.',
          detail: detail,
          logPath: logPath,
        );
      case 'W105':
        return UpdateError(
          code: code,
          titleRu: 'Не удалось распаковать архив',
          titleEn: 'Could not unpack archive',
          messageRu:
              'Expand-Archive не смог распаковать zip. Файл мог повредиться при скачивании.',
          messageEn:
              'Expand-Archive failed to unpack the zip. The file may be corrupted.',
          helpRu: 'Повтори обновление. Если снова ошибка — скачай zip вручную с GitHub Releases.',
          helpEn: 'Retry the update. If it fails again, download the zip manually from GitHub Releases.',
          detail: detail,
          logPath: logPath,
        );
      case 'W106':
        return UpdateError(
          code: code,
          titleRu: 'В архиве нет WesiOS',
          titleEn: 'WesiOS not found in archive',
          messageRu:
              'После распаковки не найден исполняемый файл. Структура zip неожиданная.',
          messageEn:
              'After unpacking, the executable was not found. Unexpected zip layout.',
          detail: detail,
          logPath: logPath,
        );
      case 'W107':
        return UpdateError(
          code: code,
          titleRu: 'Не удалось заменить файлы',
          titleEn: 'Could not replace files',
          messageRu:
              'Копирование в папку установки завершилось с ошибкой. Часто виноват Windows Defender или Controlled Folder Access.',
          messageEn:
              'Copying into the install folder failed. Windows Defender or Controlled Folder Access is a common cause.',
          helpRu:
              'Добавь папку с WesiOS и %TEMP% в исключения Защитника Windows, затем нажми «Повторить».',
          helpEn:
              'Add the WesiOS folder and %TEMP% to Windows Defender exclusions, then tap Retry.',
          detail: detail,
          logPath: logPath,
        );
      case 'W108':
        return UpdateError(
          code: code,
          titleRu: 'Исполняемый файл пропал после копирования',
          titleEn: 'Executable missing after copy',
          messageRu:
              'После robocopy wesios.exe не найден в папке установки. Возможно, антивирус удалил файл.',
          messageEn:
              'After robocopy, wesios.exe is missing from the install folder. Antivirus may have removed it.',
          helpRu: 'Проверь карантин Защитника и исключения для папки установки.',
          helpEn: 'Check Defender quarantine and exclusions for the install folder.',
          detail: detail,
          logPath: logPath,
        );
      case 'W109':
        return UpdateError(
          code: code,
          titleRu: 'Процесс не завершился вовремя',
          titleEn: 'Process did not exit in time',
          messageRu:
              'Установщик ждал закрытия WesiOS слишком долго. Закрой приложение полностью и обнови снова.',
          messageEn:
              'The installer waited too long for WesiOS to exit. Fully quit the app and update again.',
          detail: detail,
          logPath: logPath,
        );
      case 'W110':
        return UpdateError(
          code: code,
          titleRu: 'Ошибка установки на Windows',
          titleEn: 'Windows install error',
          messageRu: 'Установка новой версии не завершилась. Подробности — в логе.',
          messageEn: 'Installing the new version did not finish. See the log for details.',
          helpRu:
              'Открой лог и при необходимости добавь папку установки в исключения Defender.',
          helpEn:
              'Open the log and, if needed, add the install folder to Defender exclusions.',
          detail: detail,
          logPath: logPath,
        );
      case 'A201':
        return UpdateError(
          code: code,
          titleRu: 'Нужно разрешение на установку',
          titleEn: 'Install permission required',
          messageRu:
              'Android не даёт ставить APK из WesiOS. Разреши «установку из этого источника» в открывшемся экране настроек.',
          messageEn:
              'Android blocked APK installs from WesiOS. Allow “install from this source” in the settings screen that opened.',
          detail: detail,
          logPath: logPath,
        );
      case 'A202':
        return UpdateError(
          code: code,
          titleRu: 'Не удалось запустить установщик APK',
          titleEn: 'Could not start APK installer',
          messageRu: 'Системный установщик Android не открылся или вернул ошибку.',
          messageEn: 'The system APK installer did not open or returned an error.',
          detail: detail,
          logPath: logPath,
        );
      default:
        return UpdateError(
          code: code,
          titleRu: 'Ошибка обновления',
          titleEn: 'Update error',
          messageRu: 'Не удалось обновить WesiOS.',
          messageEn: 'Could not update WesiOS.',
          detail: detail,
          logPath: logPath,
        );
    }
  }
}

class AppRelease {
  final String version;
  final int build;
  final String assetName;
  final int? sizeBytes;
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

class AppUpdateService {
  static const String _releaseTag = 'app-latest';
  static const String _manifestAsset = 'app-manifest.json';
  static const _channel = MethodChannel('wesios/updater');
  static const _box = 'wesios_settings';
  static const _skippedKey = 'update_skipped_version';
  static const String _errorArgPrefix = '--wesios-update-error=';
  static const String _errorFileName = 'wesios_update_error.json';

  static const String repoOwner = 'wesiwer';
  static const String repoName = 'WesiOS';

  static const String windowsDefenderHelp =
      'Windows Defender или Controlled Folder Access мог заблокировать '
      'замену файлов. Открой Защитник Windows → Защита от вирусов → '
      'Управление параметрами → Исключения → Добавить папку с WesiOS '
      'и %TEMP%. Лог: %TEMP%\\wesios_update.log';

  static String releaseFileUrl(String asset) =>
      'https://github.com/$repoOwner/$repoName/releases/download/$_releaseTag/$asset';

  static String get _releaseApiUrl =>
      'https://api.github.com/repos/$repoOwner/$repoName/releases/tags/$_releaseTag';

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
      await res.drain<void>();
      if (location == null) return null;
      final redirect = await client.getUrl(Uri.parse(location));
      redirect.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      return redirect.close();
    }
    await res.drain<void>();
    return null;
  }

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

  /// Ошибка для стилизованного диалога (overlay).
  static final ValueNotifier<UpdateError?> pendingError = ValueNotifier(null);

  static Map<String, int>? _assetIdCache;
  static AppRelease? _release;
  static DateTime? _checkedAt;
  static const Duration _checkTtl = Duration(hours: 6);

  static String get currentVersion => AppVersion.number;
  static int get currentBuild => AppVersion.build;

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
    } catch (_) {}
  }

  static bool get updateAvailable {
    final r = _release;
    if (r == null) return false;
    if (!r.isNewerThan(currentVersion, currentBuild)) return false;
    return skippedVersion != r.version;
  }

  static void reportFailure(UpdateError error) {
    pendingError.value = error;
    progress.value = UpdateProgress(
      stage: UpdateStage.failed,
      error: '${error.code}: ${error.messageRu}',
      errorCode: error.code,
    );
  }

  static void clearPendingError() {
    pendingError.value = null;
    if (progress.value.stage == UpdateStage.failed) {
      progress.value = const UpdateProgress(stage: UpdateStage.idle);
    }
  }

  /// Читает маркер ошибки от bat / CLI после рестарта Windows-установки.
  static Future<void> consumePendingInstallError() async {
    if (kIsWeb) return;

    String? code;
    String? detail;
    String? logPath;

    for (final arg in Platform.executableArguments) {
      if (arg.startsWith(_errorArgPrefix)) {
        code = arg.substring(_errorArgPrefix.length).trim();
        break;
      }
    }

    try {
      final temp = await getTemporaryDirectory();
      final marker = File('${temp.path}${Platform.pathSeparator}$_errorFileName');
      if (await marker.exists()) {
        final raw = await marker.readAsString();
        final json = jsonDecode(raw);
        if (json is Map) {
          code ??= json['code'] as String?;
          detail = json['detail'] as String?;
          logPath = json['logPath'] as String?;
        }
        await marker.delete();
      }
      logPath ??= '${temp.path}${Platform.pathSeparator}wesios_update.log';
    } catch (_) {}

    if (code == null || code.isEmpty) return;
    reportFailure(UpdateError.byCode(code, detail: detail, logPath: logPath));
  }

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
        if (force) {
          reportFailure(UpdateError.byCode('W101'));
        } else {
          progress.value = const UpdateProgress(stage: UpdateStage.idle);
        }
        return null;
      }

      final assets = await _assetIds(client, headers);
      final manifestId = assets?[_manifestAsset];
      if (manifestId == null) {
        if (force) {
          reportFailure(UpdateError.byCode('W102',
              detail: 'app-manifest.json missing in release assets'));
        } else {
          progress.value = const UpdateProgress(stage: UpdateStage.idle);
        }
        return null;
      }
      _assetIdCache = assets;

      final response = await _openAsset(client, manifestId, headers);
      if (response == null || response.statusCode != 200) {
        if (force) {
          reportFailure(UpdateError.byCode('W103',
              detail: 'manifest HTTP ${response?.statusCode ?? '—'}'));
        } else {
          progress.value = const UpdateProgress(stage: UpdateStage.idle);
        }
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
      progress.value = const UpdateProgress(stage: UpdateStage.idle);
      return null;
    } finally {
      client.close();
    }
  }

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
        reportFailure(UpdateError.byCode('W101'));
        return;
      }
      final assets = _assetIdCache ?? await _assetIds(client, headers);
      final assetId = assets?[release.assetName];
      if (assetId == null) {
        reportFailure(UpdateError.byCode('W102',
            detail: release.assetName));
        return;
      }

      final response = await _openAsset(client, assetId, headers);
      if (response == null || response.statusCode != 200) {
        reportFailure(UpdateError.byCode('W103',
            detail: 'HTTP ${response?.statusCode ?? '—'}'));
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
      final msg = '$e';
      if (msg.contains('install_permission_required')) {
        reportFailure(UpdateError.byCode('A201'));
      } else if (Platform.isAndroid) {
        reportFailure(UpdateError.byCode('A202', detail: msg));
      } else {
        reportFailure(UpdateError.byCode('W104', detail: msg));
      }
    } finally {
      client.close();
    }
  }

  static Future<Directory> _downloadDir() async {
    if (Platform.isAndroid) {
      final dir = await getExternalStorageDirectory();
      if (dir != null) return dir;
    }
    return getTemporaryDirectory();
  }

  static Future<void> _installAndroid(String path) async {
    final canInstall =
        await _channel.invokeMethod<bool>('canInstall') ?? false;
    if (!canInstall) {
      await _channel.invokeMethod('openInstallPermissionSettings');
      throw const _UpdateException('install_permission_required');
    }
    await _channel.invokeMethod('installApk', {'path': path});
  }

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
    } catch (_) {}
  }

  static Future<void> _installWindows(String zipPath) async {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    final exeName = Platform.resolvedExecutable
        .replaceAll('/', r'\')
        .split(r'\')
        .last;
    final tempDir = await getTemporaryDirectory();

    // ВНИМАНИЕ на разделитель пути.
    //
    // Здесь стояло `'${tempDir.path}\wesios_update.bat'` — без `r` и с одной
    // косой чертой. В Dart `\w` не является escape-последовательностью, и
    // такая строка молча теряет разделитель: путь превращался в
    // `…\Local\Tempwesios_update.bat`. Компилятор об этом не предупреждает.
    //
    // Хуже того, `'${tempDir.path}\$_errorFileName'` — это уже экранированный
    // доллар, то есть буквальный текст `$_errorFileName`. Скрипт записывал
    // отчёт об ошибке в файл с таким именем, а приложение искало
    // `wesios_update_error.json` (см. checkPendingError). Встретиться они не
    // могли никогда — поэтому любая неудача обновления на Windows проходила
    // совершенно молча: программа закрывалась, открывалась, версия оставалась
    // прежней, и никакого сообщения не появлялось.
    String tempFile(String name) =>
        '${tempDir.path}${Platform.pathSeparator}$name';

    final scriptPath = tempFile('wesios_update.bat');
    final extractDir = tempFile('wesios_update_unpacked');
    final logPath = tempFile('wesios_update.log');
    final errorPath = tempFile(_errorFileName);

    await ensureWindowsDefenderExclusions(
      exeDir: exeDir,
      tempDir: tempDir.path,
    );

    final script = '''
@echo off
setlocal EnableExtensions EnableDelayedExpansion
set "LOG=$logPath"
set "ERRFILE=$errorPath"
set "ERRCODE=W110"
echo ==== WesiOS update %DATE% %TIME% ==== > "%LOG%"
echo exeDir=$exeDir>> "%LOG%"
echo exeName=$exeName>> "%LOG%"
echo zipPath=$zipPath>> "%LOG%"
echo extractDir=$extractDir>> "%LOG%"

echo Waiting for process to exit...>> "%LOG%"
set /a _waits=0
:waitloop
tasklist /FI "IMAGENAME eq $exeName" 2>NUL | find /I "$exeName" >NUL
if not errorlevel 1 (
  set /a _waits+=1
  if !_waits! GEQ 60 (
    echo TIMEOUT waiting for process>> "%LOG%"
    set "ERRCODE=W109"
    goto :fail
  )
  timeout /t 1 /nobreak >NUL
  goto waitloop
)
echo Process gone after !_waits!s>> "%LOG%"

echo Adding Defender exclusions...>> "%LOG%"
powershell -NoProfile -NonInteractive -Command "Try { Add-MpPreference -ExclusionPath '$exeDir' -EA SilentlyContinue; Add-MpPreference -ExclusionPath '${tempDir.path}' -EA SilentlyContinue; Add-MpPreference -ExclusionProcess '$exeName' -EA SilentlyContinue; 'ok' } Catch { \$_.Exception.Message }" >> "%LOG%" 2>&1

if exist "$extractDir" (
  echo Cleaning old extract dir>> "%LOG%"
  rmdir /S /Q "$extractDir" 2>> "%LOG%"
)
mkdir "$extractDir" 2>> "%LOG%"
if errorlevel 1 (
  echo Failed to mkdir extract dir>> "%LOG%"
  set "ERRCODE=W110"
  goto :fail
)

echo Expanding archive...>> "%LOG%"
powershell -NoProfile -NonInteractive -Command "Expand-Archive -LiteralPath '$zipPath' -DestinationPath '$extractDir' -Force" >> "%LOG%" 2>&1
if errorlevel 1 (
  echo Expand-Archive failed>> "%LOG%"
  set "ERRCODE=W105"
  goto :fail
)

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
  set "ERRCODE=W106"
  goto :fail
)

echo Robocopy from !SRC! to $exeDir>> "%LOG%"
robocopy "!SRC!" "$exeDir" /E /R:5 /W:2 /NFL /NDL /NP >> "%LOG%" 2>&1
set "RC=!ERRORLEVEL!"
echo robocopy exit=!RC!>> "%LOG%"
if !RC! GEQ 8 (
  echo Robocopy failed with code !RC!>> "%LOG%"
  set "ERRCODE=W107"
  goto :fail
)

if not exist "$exeDir\\$exeName" (
  echo ERROR: $exeName missing after copy>> "%LOG%"
  set "ERRCODE=W108"
  goto :fail
)

echo SUCCESS — starting app>> "%LOG%"
if exist "%ERRFILE%" del /F /Q "%ERRFILE%" 2>NUL
start "" "$exeDir\\$exeName"
rmdir /S /Q "$extractDir" 2>> "%LOG%"
del /F /Q "$zipPath" 2>> "%LOG%"
echo Cleanup done>> "%LOG%"
(goto) 2>nul & del "%~f0"
exit /b 0

:fail
echo FAIL code=!ERRCODE!>> "%LOG%"
powershell -NoProfile -NonInteractive -Command "@{code='!ERRCODE!'; detail=('bat fail '+'!ERRCODE!'); logPath='$logPath'} | ConvertTo-Json -Compress | Set-Content -LiteralPath '$errorPath' -Encoding UTF8" >> "%LOG%" 2>&1
echo Restarting app with error flag>> "%LOG%"
start "" "$exeDir\\$exeName" $_errorArgPrefix!ERRCODE!
exit /b 1
''';

    await File(scriptPath).writeAsString(script);
    await Process.start(
      'cmd.exe',
      ['/c', 'start', '', '/min', scriptPath],
      mode: ProcessStartMode.detached,
      runInShell: true,
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    exit(0);
  }

  static void reset() {
    progress.value = const UpdateProgress();
    pendingError.value = null;
  }
}

class _UpdateException implements Exception {
  final String code;
  const _UpdateException(this.code);
  @override
  String toString() => code;
}
