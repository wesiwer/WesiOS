import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/services/currency_service.dart';
import '../../tasks/models/task_model.dart';
import '../../tasks/services/task_service.dart';
import '../../team/services/team_service.dart';
import '../../treasury/services/horizon_contract_memory.dart';
import '../models/audio_vault_models.dart';

class AudioVaultService {
  AudioVaultService._();

  static const String boxName = 'wesios_audio_vault';
  static const String _beatsKey = 'beats_v1';
  static const String _extendedMetaKey = 'extended_meta_v1';
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static Future<Box<dynamic>> get _box async {
    if (Hive.isBoxOpen(boxName)) return Hive.box<dynamic>(boxName);
    return Hive.openBox<dynamic>(boxName);
  }

  static Future<List<BeatEntry>> all() async {
    final box = await _box;
    final raw = box.get(_beatsKey);
    if (raw is! List) return [];
    final beats = raw
        .whereType<Map>()
        .map((e) => BeatEntry.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    beats.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return beats;
  }

  static Future<BeatEntry?> byId(String id) async {
    final list = await all();
    for (final beat in list) {
      if (beat.id == id) return beat;
    }
    return null;
  }

  static Future<void> save(BeatEntry beat) async {
    final box = await _box;
    final list = await all();
    final index = list.indexWhere((e) => e.id == beat.id);
    if (index < 0) {
      list.add(beat);
    } else {
      list[index] = beat;
    }
    await box.put(_beatsKey, list.map((e) => e.toJson()).toList());
    revision.value++;
  }

  static Future<void> delete(BeatEntry beat) async {
    final box = await _box;

    final reminderTaskId = beat.lease?.reminderTaskId;
    if (reminderTaskId != null && reminderTaskId.isNotEmpty) {
      try {
        await TaskService().delete(reminderTaskId);
      } catch (_) {}
    }

    final list = await all();
    list.removeWhere((e) => e.id == beat.id);
    await box.put(_beatsKey, list.map((e) => e.toJson()).toList());

    final rawMeta = box.get(_extendedMetaKey);
    if (rawMeta is Map && rawMeta.containsKey(beat.id)) {
      final meta = Map<dynamic, dynamic>.from(rawMeta);
      meta.remove(beat.id);
      await box.put(_extendedMetaKey, meta);
    }

    try {
      final dir = await _beatDirectory(beat.id, create: false);
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    revision.value++;
  }

  static Future<Directory> _root() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'WesiOS', 'AudioVault'));
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static Future<Directory> _beatDirectory(String beatId,
      {bool create = true}) async {
    final root = await _root();
    final dir = Directory(p.join(root.path, beatId));
    if (create && !await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  static String _id() =>
      '${DateTime.now().microsecondsSinceEpoch}_${DateTime.now().millisecond}';

  static Future<String?> importSingleFile({
    required String beatId,
    required BeatFileKind kind,
  }) async {
    final extensions = switch (kind) {
      BeatFileKind.mp3 => ['mp3'],
      BeatFileKind.wav => ['wav'],
      BeatFileKind.cover => ['png', 'jpg', 'jpeg', 'webp'],
      BeatFileKind.trackout => ['zip', 'rar', '7z', 'tar', 'gz'],
      _ => <String>[],
    };
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: extensions.isEmpty ? FileType.any : FileType.custom,
      allowedExtensions: extensions.isEmpty ? null : extensions,
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final dir = await _beatDirectory(beatId);
    final safeName = p
        .basename(source.path)
        .replaceAll(RegExp(r'[^A-Za-zА-Яа-я0-9._ -]'), '_');
    final target = File(p.join(dir.path, '${kind.name}_${_id()}_$safeName'));
    await source.copy(target.path);
    return target.path;
  }

  static Future<BeatFileRef?> importAttachment({
    required String beatId,
    BeatFileKind kind = BeatFileKind.document,
  }) async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
      withData: false,
    );
    final sourcePath = result?.files.single.path;
    if (sourcePath == null || sourcePath.isEmpty) return null;
    final source = File(sourcePath);
    if (!await source.exists()) return null;
    final dir = await _beatDirectory(beatId);
    final name = p.basename(source.path);
    final safeName = name.replaceAll(RegExp(r'[^A-Za-zА-Яа-я0-9._ -]'), '_');
    final target = File(p.join(dir.path, '${kind.name}_${_id()}_$safeName'));
    await source.copy(target.path);
    return BeatFileRef(
      id: _id(),
      name: name,
      path: target.path,
      kind: kind,
      bytes: await target.length(),
      createdAt: DateTime.now(),
    );
  }

  static Future<void> sharePath(String? path, {String? subject}) async {
    if (path == null || path.isEmpty) return;
    final file = File(path);
    if (!await file.exists()) return;
    await Share.shareXFiles([XFile(path)], subject: subject);
  }

  static Future<BeatEntry> addComment(BeatEntry beat, String text) async {
    final normalized = text.trim();
    if (normalized.isEmpty) return beat;
    final me = TeamService.current;
    final comment = BeatComment(
      id: _id(),
      text: normalized,
      authorId: me?.id ?? 'owner',
      createdAt: DateTime.now(),
    );
    final next = beat.copyWith(comments: [...beat.comments, comment]);
    await save(next);
    return next;
  }

  static double _leaseRub(BeatLease lease) =>
      lease.amount * CurrencyService.rateToRub(lease.currency.toLowerCase());

  static Future<BeatEntry> setLease(
    BeatEntry beat,
    BeatLease lease, {
    bool createCalendarReminder = true,
  }) async {
    final previous = beat.lease;
    if (previous != null && previous.id != lease.id) {
      await HorizonContractMemoryService.recordClosedLease(
        beatId: beat.id,
        leaseId: previous.id,
        artistName: previous.artistName,
        closedAt: lease.startsAt,
        amountRub: _leaseRub(previous),
      );
      await HorizonContractMemoryService.removeLease(previous.id);
    }

    // If this new contract follows a previously closed one for the same beat
    // or artist, that is realized renewal evidence for future probabilities.
    await HorizonContractMemoryService.markRenewalIfApplicable(
      beatId: beat.id,
      artistName: lease.artistName,
      startedAt: lease.startsAt,
    );

    var nextLease = lease;
    if (createCalendarReminder) {
      final taskId = 'audio-lease-${beat.id}-${lease.id}';
      final task = TaskModel(
        id: taskId,
        title: 'Audio Vault: продление аренды «${beat.title}»',
        description:
            'Исполнитель: ${lease.artistName}\nСоцсеть: ${lease.socialUrl}\n${lease.notes}',
        status: TaskStatus.backlog,
        priority: TaskPriority.high,
        createdAt: DateTime.now(),
        dueDate: lease.endsAt,
        assignee: TeamService.current?.id,
        tags: ['audio-vault', 'lease', beat.id],
      );
      await TaskService().save(task);
      nextLease = lease.copyWith(reminderTaskId: taskId);
    }
    final next = beat.copyWith(stage: BeatStage.leased, lease: nextLease);
    await save(next);
    return next;
  }

  static Future<BeatEntry> clearLease(BeatEntry beat) async {
    final lease = beat.lease;
    if (lease != null && lease.id.isNotEmpty) {
      // Closing a lease is persisted as an outcome. A later new lease can turn
      // it into a renewal; otherwise it remains observed non-renewal evidence.
      await HorizonContractMemoryService.recordClosedLease(
        beatId: beat.id,
        leaseId: lease.id,
        artistName: lease.artistName,
        closedAt: DateTime.now(),
        amountRub: _leaseRub(lease),
      );
      await HorizonContractMemoryService.removeLease(lease.id);
    }
    final taskId = lease?.reminderTaskId;
    if (taskId != null && taskId.isNotEmpty) {
      await TaskService().delete(taskId);
    }
    final next = beat.copyWith(clearLease: true, stage: BeatStage.ready);
    await save(next);
    return next;
  }
}
