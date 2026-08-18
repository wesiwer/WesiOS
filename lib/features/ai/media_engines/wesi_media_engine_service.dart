import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/services/update_endpoint.dart';
import 'wesi_media_archive_guard.dart';

enum WesiMediaEngineKind { image, music, video }

enum WesiMediaInstallStage { idle, downloading, verifying, extracting, done, failed }

class WesiMediaInstallProgress {
  final WesiMediaInstallStage stage;
  final int bytesDownloaded;
  final int? totalBytes;
  final double bytesPerSecond;
  final String? error;

  const WesiMediaInstallProgress({
    this.stage = WesiMediaInstallStage.idle,
    this.bytesDownloaded = 0,
    this.totalBytes,
    this.bytesPerSecond = 0,
    this.error,
  });

  double? get fraction => totalBytes == null || totalBytes! <= 0
      ? null
      : (bytesDownloaded / totalBytes!).clamp(0.0, 1.0);
}

class WesiMediaEngineRelease {
  final WesiMediaEngineKind kind;
  final String id;
  final String name;
  final String version;
  final String path;
  final String sha256Hex;
  final int sizeBytes;
  final String license;
  final String licenseUrl;
  final String launcher;
  final int minRamGb;
  final int recommendedVramGb;
  final List<String> platforms;
  final bool enabled;

  const WesiMediaEngineRelease({
    required this.kind,
    required this.id,
    required this.name,
    required this.version,
    required this.path,
    required this.sha256Hex,
    required this.sizeBytes,
    required this.license,
    required this.licenseUrl,
    required this.launcher,
    required this.minRamGb,
    required this.recommendedVramGb,
    required this.platforms,
    required this.enabled,
  });

  static WesiMediaEngineRelease? tryParse(Map<String, dynamic> json) {
    try {
      final kind = WesiMediaEngineKind.values.byName('${json['kind']}');
      final sha = '${json['sha256']}'.toLowerCase().trim();
      final path = '${json['path']}'.trim();
      final launcher = '${json['launcher']}'.trim();
      final version = '${json['version']}'.trim();
      final id = '${json['id']}'.trim();
      if (id.isEmpty || version.isEmpty || path.isEmpty || launcher.isEmpty) return null;
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(sha)) return null;
      if (path.startsWith('/') || path.contains('..') || launcher.contains('..')) return null;
      final size = (json['sizeBytes'] as num?)?.toInt() ?? 0;
      if (size <= 0) return null;
      return WesiMediaEngineRelease(
        kind: kind,
        id: id,
        name: '${json['name'] ?? id}',
        version: version,
        path: path,
        sha256Hex: sha,
        sizeBytes: size,
        license: '${json['license'] ?? 'Unknown'}',
        licenseUrl: '${json['licenseUrl'] ?? ''}',
        launcher: launcher,
        minRamGb: (json['requirements']?['minRamGb'] as num?)?.toInt() ?? 0,
        recommendedVramGb:
            (json['requirements']?['recommendedVramGb'] as num?)?.toInt() ?? 0,
        platforms: (json['platforms'] as List? ?? const [])
            .map((v) => '$v'.toLowerCase())
            .toList(growable: false),
        enabled: json['enabled'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  String get downloadUrl => UpdateEndpoint.fileUrl(path);
}

/// Optional local Wesi AI media engines.
///
/// The application ships without model weights. A small manifest served by
/// Wesi infrastructure describes immutable ZIP packages. Every package is
/// verified with SHA-256 before extraction; a failed verification is deleted
/// and can never become an installed engine.
class WesiMediaEngineService {
  static const _box = 'wesios_settings';
  static const _manifestPath = 'media-engines/manifest.json';
  static const _manifestTtl = Duration(hours: 2);

  static final progress = ValueNotifier<Map<WesiMediaEngineKind, WesiMediaInstallProgress>>({});
  static final revision = ValueNotifier<int>(0);

  static Map<WesiMediaEngineKind, WesiMediaEngineRelease>? _manifest;
  static DateTime? _manifestFetchedAt;

  static String get manifestUrl => '${UpdateEndpoint.base}/$_manifestPath';

  static String get _platformName {
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  static Future<Directory> _rootDir() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}${Platform.pathSeparator}wesi-ai${Platform.pathSeparator}media-engines');
  }

  static Future<Directory> engineDir(WesiMediaEngineKind kind) async {
    final root = await _rootDir();
    return Directory('${root.path}${Platform.pathSeparator}${kind.name}');
  }

  static WesiMediaEngineRelease? cachedRelease(WesiMediaEngineKind kind) => _manifest?[kind];

  static Future<Map<WesiMediaEngineKind, WesiMediaEngineRelease>?> fetchManifest({bool force = false}) async {
    final fresh = _manifestFetchedAt != null &&
        DateTime.now().difference(_manifestFetchedAt!) < _manifestTtl;
    if (!force && fresh && _manifest != null) return _manifest;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse(manifestUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final response = await request.close().timeout(const Duration(seconds: 20));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return _manifest;
      }
      final decoded = jsonDecode(await response.transform(utf8.decoder).join());
      if (decoded is! Map || decoded['schema'] != 1 || decoded['engines'] is! List) {
        return _manifest;
      }
      final parsed = <WesiMediaEngineKind, WesiMediaEngineRelease>{};
      for (final raw in decoded['engines'] as List) {
        if (raw is! Map) continue;
        final release = WesiMediaEngineRelease.tryParse(Map<String, dynamic>.from(raw));
        if (release == null || !release.enabled) continue;
        if (release.platforms.isNotEmpty && !release.platforms.contains(_platformName)) continue;
        parsed[release.kind] = release;
      }
      _manifest = parsed;
      _manifestFetchedAt = DateTime.now();
      revision.value++;
      return _manifest;
    } catch (_) {
      return _manifest;
    } finally {
      client.close(force: true);
    }
  }

  static String _versionKey(WesiMediaEngineKind kind) => 'wesi_media_engine_${kind.name}_version';
  static String? installedVersion(WesiMediaEngineKind kind) {
    try {
      return Hive.box(_box).get(_versionKey(kind)) as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<File?> launcherFile(WesiMediaEngineKind kind) async {
    final release = _manifest?[kind];
    final version = installedVersion(kind);
    if (release == null || version == null || version != release.version) return null;
    final dir = await engineDir(kind);
    final file = File('${dir.path}${Platform.pathSeparator}${release.launcher.replaceAll('/', Platform.pathSeparator)}');
    return await file.exists() ? file : null;
  }

  static Future<bool> isInstalled(WesiMediaEngineKind kind) async => await launcherFile(kind) != null;

  static bool isInstalling(WesiMediaEngineKind kind) {
    final stage = progress.value[kind]?.stage;
    return stage == WesiMediaInstallStage.downloading ||
        stage == WesiMediaInstallStage.verifying ||
        stage == WesiMediaInstallStage.extracting;
  }

  static Future<void> install(WesiMediaEngineKind kind) async {
    if (isInstalling(kind)) return;
    final manifest = await fetchManifest(force: true);
    final release = manifest?[kind];
    if (release == null) {
      _set(kind, const WesiMediaInstallProgress(stage: WesiMediaInstallStage.failed, error: 'not_published'));
      return;
    }

    final root = await _rootDir();
    await root.create(recursive: true);
    final temp = File('${root.path}${Platform.pathSeparator}.${kind.name}-${DateTime.now().microsecondsSinceEpoch}.zip.part');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    IOSink? sink;
    try {
      _set(kind, const WesiMediaInstallProgress(stage: WesiMediaInstallStage.downloading));
      final request = await client.getUrl(Uri.parse(release.downloadUrl));
      request.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final response = await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw const HttpException('media_engine_download_failed');
      }
      final expected = response.contentLength > 0 ? response.contentLength : release.sizeBytes;
      sink = temp.openWrite();
      var received = 0;
      var lastBytes = 0;
      var lastAt = DateTime.now();
      await for (final chunk in response) {
        sink.add(chunk);
        received += chunk.length;
        final now = DateTime.now();
        final elapsed = now.difference(lastAt).inMilliseconds;
        if (elapsed >= 400) {
          final bps = elapsed == 0 ? 0.0 : (received - lastBytes) * 1000 / elapsed;
          _set(kind, WesiMediaInstallProgress(
            stage: WesiMediaInstallStage.downloading,
            bytesDownloaded: received,
            totalBytes: expected,
            bytesPerSecond: bps,
          ));
          lastBytes = received;
          lastAt = now;
        }
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (received != release.sizeBytes) throw const FormatException('size_mismatch');
      _set(kind, WesiMediaInstallProgress(
        stage: WesiMediaInstallStage.verifying,
        bytesDownloaded: received,
        totalBytes: release.sizeBytes,
      ));
      final digest = await sha256.bind(temp.openRead()).first;
      if (digest.toString().toLowerCase() != release.sha256Hex) {
        throw const FormatException('sha256_mismatch');
      }
      await WesiMediaArchiveGuard.validateZip(
        temp.path,
        compressedSizeBytes: received,
      );

      _set(kind, WesiMediaInstallProgress(
        stage: WesiMediaInstallStage.extracting,
        bytesDownloaded: received,
        totalBytes: release.sizeBytes,
      ));
      final target = await engineDir(kind);
      final staging = Directory('${target.path}.staging');
      if (await staging.exists()) await staging.delete(recursive: true);
      await staging.create(recursive: true);
      await extractFileToDisk(temp.path, staging.path);

      final launcher = File('${staging.path}${Platform.pathSeparator}${release.launcher.replaceAll('/', Platform.pathSeparator)}');
      if (!await launcher.exists()) throw const FormatException('launcher_missing');
      if (await target.exists()) await target.delete(recursive: true);
      await staging.rename(target.path);
      await Hive.box(_box).put(_versionKey(kind), release.version);
      _set(kind, WesiMediaInstallProgress(
        stage: WesiMediaInstallStage.done,
        bytesDownloaded: received,
        totalBytes: release.sizeBytes,
      ));
      revision.value++;
    } catch (error) {
      _set(kind, WesiMediaInstallProgress(
        stage: WesiMediaInstallStage.failed,
        error: error is FormatException ? error.message : 'download_failed',
      ));
    } finally {
      try { await sink?.close(); } catch (_) {}
      try { if (await temp.exists()) await temp.delete(); } catch (_) {}
      client.close(force: true);
    }
  }

  static Future<void> remove(WesiMediaEngineKind kind) async {
    if (isInstalling(kind)) return;
    final dir = await engineDir(kind);
    if (await dir.exists()) await dir.delete(recursive: true);
    try { await Hive.box(_box).delete(_versionKey(kind)); } catch (_) {}
    final next = Map<WesiMediaEngineKind, WesiMediaInstallProgress>.from(progress.value)..remove(kind);
    progress.value = next;
    revision.value++;
  }

  /// Starts an installed engine using a newline-delimited JSON protocol.
  /// Engine packages own their Python/runtime dependencies; WesiOS never pip
  /// installs arbitrary code at runtime. The first stdout line must be JSON.
  static Future<Map<String, dynamic>> generate(
    WesiMediaEngineKind kind,
    Map<String, dynamic> request,
  ) async {
    final launcher = await launcherFile(kind);
    if (launcher == null) return {'ok': false, 'code': 'WAI_MEDIA_ENGINE_NOT_INSTALLED'};
    final executable = Platform.isWindows && launcher.path.toLowerCase().endsWith('.bat')
        ? 'cmd.exe'
        : launcher.path;
    final arguments = Platform.isWindows && executable == 'cmd.exe'
        ? ['/c', launcher.path]
        : <String>[];
    try {
      final process = await Process.start(executable, arguments, workingDirectory: launcher.parent.path);
      process.stdin.writeln(jsonEncode(request));
      await process.stdin.close();
      final line = await process.stdout.transform(utf8.decoder).transform(const LineSplitter()).first.timeout(const Duration(minutes: 15));
      final result = jsonDecode(line);
      if (result is Map) return Map<String, dynamic>.from(result);
      return {'ok': false, 'code': 'WAI_MEDIA_ENGINE_BAD_RESPONSE'};
    } catch (_) {
      return {'ok': false, 'code': 'WAI_MEDIA_ENGINE_FAILED'};
    }
  }

  static void _set(WesiMediaEngineKind kind, WesiMediaInstallProgress value) {
    progress.value = Map<WesiMediaEngineKind, WesiMediaInstallProgress>.from(progress.value)..[kind] = value;
  }
}
