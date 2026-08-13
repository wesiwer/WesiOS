import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive/hive.dart';

import '../models/file_share_models.dart';

/// Хранилище запросов, открытых доступов и журнала выдач.
///
/// Записи маленькие — описание, а не содержимое, — поэтому едут обычной
/// синхронизацией вместе со всем остальным. Сам файл не едет никогда: он
/// передаётся отдельно и только после подтверждения.
///
/// Три бокса, а не один: у каждой сущности своя судьба. Запрос живёт часы,
/// доступ — месяцы, запись журнала не удаляется вовсе.
class FileShareService {
  static const String requestsBoxName = 'wesios_file_requests';
  static const String grantsBoxName = 'wesios_file_grants';
  static const String handoversBoxName = 'wesios_file_handovers';

  /// Сколько ждёт запрос, на который никто не ответил.
  ///
  /// Владелец файла может не открывать приложение сутками, и запрос,
  /// висящий вечно, превращается в мусор: человек давно нашёл файл иначе, а
  /// у владельца копится список просьб из прошлого месяца. Неделя — срок,
  /// за который любой рабочий вопрос либо решается, либо перестаёт быть
  /// вопросом.
  static const Duration requestLifetime = Duration(days: 7);

  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final Map<String, Box<String>> _boxes = {};

  static Future<Box<String>> _open(String name) async {
    final cached = _boxes[name];
    if (cached != null && cached.isOpen) return cached;
    final box = Hive.isBoxOpen(name)
        ? Hive.box<String>(name)
        : await Hive.openBox<String>(name);
    _boxes[name] = box;
    return box;
  }

  static String newId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  // ---------------------------------------------------------------- запросы

  static Future<List<FileShareRequest>> requests() async =>
      _read(await _open(requestsBoxName), FileShareRequest.tryParse)
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Запросы, на которые ждут ответа именно от [employeeId].
  ///
  /// Пустой [FileShareRequest.holderId] означает «у любого, у кого есть» —
  /// такие показываются всем, кто может отдать.
  static Future<List<FileShareRequest>> incoming(String employeeId) async =>
      (await requests())
          .where((r) =>
              r.status == ShareRequestStatus.pending &&
              r.requesterId != employeeId &&
              (r.holderId.isEmpty || r.holderId == employeeId))
          .toList();

  static Future<List<FileShareRequest>> outgoing(String employeeId) async =>
      (await requests()).where((r) => r.requesterId == employeeId).toList();

  static Future<void> saveRequest(FileShareRequest request) async {
    final box = await _open(requestsBoxName);
    await box.put(request.id, jsonEncode(request.toJson()));
    revision.value++;
  }

  static Future<void> deleteRequest(String id) async {
    await (await _open(requestsBoxName)).delete(id);
    revision.value++;
  }

  /// Пометить просроченным всё, на что не ответили за [requestLifetime].
  ///
  /// Именно пометить, а не удалить: запросивший должен понимать, что его
  /// просьба не потерялась, а истекла, и решить — просить снова или уже не
  /// нужно.
  static Future<int> expireStale(DateTime now) async {
    final box = await _open(requestsBoxName);
    var changed = 0;
    for (final request in await requests()) {
      if (request.status != ShareRequestStatus.pending) continue;
      if (now.difference(request.createdAt) < requestLifetime) continue;
      final expired = request.copyWith(
        status: ShareRequestStatus.expired,
        decidedAt: now,
      );
      await box.put(expired.id, jsonEncode(expired.toJson()));
      changed++;
    }
    if (changed > 0) revision.value++;
    return changed;
  }

  // --------------------------------------------------------------- доступы

  static Future<List<FileAccessGrant>> grants() async =>
      _read(await _open(grantsBoxName), FileAccessGrant.tryParse);

  /// Доступы, относящиеся к одной записи.
  static Future<List<FileAccessGrant>> grantsFor(
    ShareSubjectKind kind,
    String subjectId,
  ) async =>
      (await grants())
          .where((g) => g.subjectKind == kind && g.subjectId == subjectId)
          .toList();

  static Future<void> saveGrant(FileAccessGrant grant) async {
    final box = await _open(grantsBoxName);
    await box.put(grant.id, jsonEncode(grant.toJson()));
    revision.value++;
  }

  /// Отозвать доступ.
  ///
  /// Именно удаление, а не отметка «отозван»: запись пропадает у всех через
  /// обычную синхронизацию с надгробием, и восстановить её случайным
  /// слиянием нельзя.
  static Future<void> revokeGrant(String id) async {
    await (await _open(grantsBoxName)).delete(id);
    revision.value++;
  }

  // ---------------------------------------------------------------- журнал

  static Future<List<FileHandover>> handovers() async =>
      _read(await _open(handoversBoxName), FileHandover.tryParse)
        ..sort((a, b) => b.at.compareTo(a.at));

  /// Что уходило по конкретной записи — от кого и кому.
  static Future<List<FileHandover>> handoversFor(
    ShareSubjectKind kind,
    String subjectId,
  ) async =>
      (await handovers())
          .where((h) => h.subjectKind == kind && h.subjectId == subjectId)
          .toList();

  static Future<void> recordHandover(FileHandover handover) async {
    final box = await _open(handoversBoxName);
    await box.put(handover.id, jsonEncode(handover.toJson()));
    revision.value++;
  }

  static List<T> _read<T>(
    Box<String> box,
    T? Function(Map<String, dynamic>) parse,
  ) {
    final out = <T>[];
    for (final raw in box.values) {
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        final value = parse(Map<String, dynamic>.from(decoded));
        if (value != null) out.add(value);
      } catch (_) {
        // Одна испорченная запись не должна прятать остальные.
      }
    }
    return out;
  }

  static Future<void> clearForTest() async {
    for (final name in [requestsBoxName, grantsBoxName, handoversBoxName]) {
      await (await _open(name)).clear();
    }
    revision.value++;
  }
}
