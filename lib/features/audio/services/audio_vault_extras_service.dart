import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/audio_vault_extended_models.dart';
import '../models/audio_vault_models.dart';
import 'audio_analysis_service.dart';
import 'audio_analysis_v2_service.dart';
import 'audio_vault_service.dart';

class AudioVaultExtrasService {
  AudioVaultExtrasService._();

  static const _metaKey = 'extended_meta_v1';
  static const _musicKey = 'music_library_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<Box<dynamic>> get _box async {
    if (Hive.isBoxOpen(AudioVaultService.boxName)) {
      return Hive.box<dynamic>(AudioVaultService.boxName);
    }
    return Hive.openBox<dynamic>(AudioVaultService.boxName);
  }

  static Future<Map<String, BeatExtendedMeta>> _allMeta() async {
    final box = await _box;
    final raw = box.get(_metaKey);
    if (raw is! Map) return {};
    final out = <String, BeatExtendedMeta>{};
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        out['${entry.key}'] = BeatExtendedMeta.fromJson(
          Map<String, dynamic>.from(entry.value as Map),
        );
      }
    }
    return out;
  }

  static Future<BeatExtendedMeta> metaFor(String beatId) async {
    final all = await _allMeta();
    return all[beatId] ?? const BeatExtendedMeta();
  }

  static Future<void> saveMeta(String beatId, BeatExtendedMeta meta) async {
    final box = await _box;
    final all = await _allMeta();
    all[beatId] = meta;
    await box.put(_metaKey, {
      for (final e in all.entries) e.key: e.value.toJson(),
    });
    revision.value++;
  }

  static Future<String?> chooseAbletonProject() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.custom,
      allowedExtensions: const ['als'],
      withData: false,
    );
    return validateAbletonProjectPath(result?.files.single.path);
  }

  static Future<String?> validateAbletonProjectPath(String? rawPath) async {
    if (rawPath == null) return null;
    var path = rawPath.trim();
    if (path.length >= 2 &&
        ((path.startsWith('"') && path.endsWith('"')) ||
            (path.startsWith("'") && path.endsWith("'")))) {
      path = path.substring(1, path.length - 1).trim();
    }
    if (path.isEmpty || !path.toLowerCase().endsWith('.als')) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    return file.absolute.path;
  }

  static Future<void> setAbletonProject(String beatId, String? path) async {
    final meta = await metaFor(beatId);
    await saveMeta(
      beatId,
      path == null || path.isEmpty
          ? meta.copyWith(clearAbletonProject: true)
          : meta.copyWith(abletonProjectPath: path),
    );
  }

  static Future<String?> openAbletonProject(String? projectPath) async {
    if (projectPath == null || projectPath.isEmpty) {
      return 'Путь к Ableton Project не указан.';
    }
    final file = File(projectPath);
    if (!await file.exists()) {
      return 'Файл Ableton Project больше не найден по сохранённому пути.';
    }
    try {
      if (Platform.isWindows) {
        await Process.start(
          'cmd',
          ['/c', 'start', '', projectPath],
          runInShell: true,
          mode: ProcessStartMode.detached,
        );
        return null;
      }
      if (Platform.isMacOS) {
        await Process.start(
          'open',
          [projectPath],
          mode: ProcessStartMode.detached,
        );
        return null;
      }
      if (Platform.isLinux) {
        await Process.start(
          'xdg-open',
          [projectPath],
          mode: ProcessStartMode.detached,
        );
        return null;
      }
      return 'Открытие Ableton Project доступно в desktop-версии WesiOS.';
    } catch (e) {
      return 'Не удалось открыть Ableton Project: $e';
    }
  }

  /// Возвращает только актуальный отчёт. Если WAV заменён, изменился размер
  /// или mtime, старый анализ больше не показывается как действующий.
  static Future<AudioAnalysisReport?> analysisForBeat(BeatEntry beat) async {
    final meta = await metaFor(beat.id);
    final report = meta.analysis;
    if (report == null) return null;
    // A report received through sync deliberately has no device path. Its QC
    // metrics are portable metadata and remain useful without the local WAV.
    if (report.sourcePath.isEmpty) return report;
    final wav = beat.wavPath;
    if (wav == null || wav.isEmpty) return null;
    final file = File(wav);
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (report.sourcePath != wav) return null;
    if (report.sourceBytes <= 0 || report.sourceModifiedAtMs <= 0) return null;
    if (report.sourceBytes != stat.size) return null;
    if (report.sourceModifiedAtMs != stat.modified.millisecondsSinceEpoch) {
      return null;
    }
    return report;
  }

  static Future<AudioAnalysisReport> analyzeBeat(BeatEntry beat) async {
    final wav = beat.wavPath;
    if (wav == null || wav.isEmpty || !await File(wav).exists()) {
      throw const AudioAnalysisException(
        'Для локального Quick Analysis прикрепи WAV master. Он даёт корректный PCM-доступ без декодирования lossy MP3.',
      );
    }
    final report = await AudioAnalysisV2Service.analyzeWav(wav);
    final meta = await metaFor(beat.id);
    await saveMeta(beat.id, meta.copyWith(analysis: report));
    return report;
  }

  static Future<List<MusicLibraryTrack>> musicLibrary() async {
    final box = await _box;
    final raw = box.get(_musicKey);
    if (raw is! List) return [];
    final list = raw
        .whereType<Map>()
        .map((e) => MusicLibraryTrack.fromJson(Map<String, dynamic>.from(e)))
        .where((e) => File(e.path).existsSync())
        .toList();
    list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return list;
  }

  static Future<Directory> _musicRoot() async {
    final base = await getApplicationDocumentsDirectory();
    final dir =
        Directory(p.join(base.path, 'WesiOS', 'AudioVault', 'MusicHub'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<List<MusicLibraryTrack>> importMusic() async {
    final picked = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: const ['mp3', 'wav', 'ogg', 'flac'],
      withData: false,
    );
    if (picked == null || picked.files.isEmpty) return const [];
    final root = await _musicRoot();
    final existing = await musicLibrary();
    final added = <MusicLibraryTrack>[];
    for (final item in picked.files) {
      final sourcePath = item.path;
      if (sourcePath == null || sourcePath.isEmpty) continue;
      final source = File(sourcePath);
      if (!await source.exists()) continue;
      final now = DateTime.now();
      final id = now.microsecondsSinceEpoch.toString();
      final safe = p
          .basename(sourcePath)
          .replaceAll(RegExp(r'[^A-Za-zА-Яа-я0-9._ -]'), '_');
      final target = File(p.join(root.path, '${id}_$safe'));
      await source.copy(target.path);
      added.add(MusicLibraryTrack(
        id: id,
        title: p.basenameWithoutExtension(item.name),
        path: target.path,
        addedAt: now,
      ));
      await Future<void>.delayed(const Duration(microseconds: 2));
    }
    final box = await _box;
    final all = [...existing, ...added];
    await box.put(_musicKey, all.map((e) => e.toJson()).toList());
    revision.value++;
    return added;
  }

  static Future<void> removeMusic(MusicLibraryTrack track) async {
    final box = await _box;
    final list = await musicLibrary();
    list.removeWhere((e) => e.id == track.id);
    await box.put(_musicKey, list.map((e) => e.toJson()).toList());
    try {
      final f = File(track.path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
    revision.value++;
  }

  static BeatEntry asPlayable(MusicLibraryTrack track) {
    final now = track.addedAt;
    return BeatEntry(
      id: 'music-${track.id}',
      title: track.title,
      authorEmployeeId: 'music-hub',
      mp3Path: track.path,
      stage: BeatStage.ready,
      createdAt: now,
      updatedAt: now,
    );
  }
}
