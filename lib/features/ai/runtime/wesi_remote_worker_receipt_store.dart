import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wesi_remote_worker_models.dart';

enum WesiRemoteWorkerReceiptState { started, completed }

class WesiRemoteWorkerReceipt {
  final String assignmentMessageId;
  final String jobId;
  final String leaseId;
  final int generation;
  final WesiRemoteWorkerReceiptState state;
  final DateTime startedAt;
  final WesiRemoteJobMessage? resultMessage;

  const WesiRemoteWorkerReceipt({
    required this.assignmentMessageId,
    required this.jobId,
    required this.leaseId,
    required this.generation,
    required this.state,
    required this.startedAt,
    this.resultMessage,
  });

  WesiRemoteWorkerReceipt complete(WesiRemoteJobMessage result) =>
      WesiRemoteWorkerReceipt(
        assignmentMessageId: assignmentMessageId,
        jobId: jobId,
        leaseId: leaseId,
        generation: generation,
        state: WesiRemoteWorkerReceiptState.completed,
        startedAt: startedAt,
        resultMessage: result,
      );
}

abstract class WesiRemoteWorkerReceiptJournal {
  Future<String?> read();

  Future<void> write(String value);
}

class WesiMemoryRemoteWorkerReceiptJournal
    implements WesiRemoteWorkerReceiptJournal {
  String? value;

  WesiMemoryRemoteWorkerReceiptJournal([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class WesiFileRemoteWorkerReceiptJournal
    implements WesiRemoteWorkerReceiptJournal {
  final File file;
  final int maxBytes;

  const WesiFileRemoteWorkerReceiptJournal(
    this.file, {
    this.maxBytes = WesiRemoteWorkerReceiptStore.maxJournalBytes,
  });

  File get _backup => File('${file.path}.previous');

  @override
  Future<String?> read() async {
    if (!await file.exists() && await _backup.exists()) {
      await _backup.rename(file.path);
    }
    if (!await file.exists()) return null;
    if ((await file.stat()).size > maxBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_RECEIPT_JOURNAL_TOO_LARGE',
        'Remote worker receipt journal exceeds its bounded persistence limit',
      );
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_RECEIPT_JOURNAL_TOO_LARGE',
        'Remote worker receipt journal exceeds its bounded persistence limit',
      );
    }
    await file.parent.create(recursive: true);
    final temp = File(
      '${file.path}.tmp-${DateTime.now().microsecondsSinceEpoch}',
    );
    await temp.writeAsBytes(bytes, flush: true);
    if (await _backup.exists()) await _backup.delete();
    if (await file.exists()) await file.rename(_backup.path);
    try {
      await temp.rename(file.path);
      if (await _backup.exists()) await _backup.delete();
    } catch (_) {
      if (await file.exists()) await file.delete();
      if (await _backup.exists()) await _backup.rename(file.path);
      if (await temp.exists()) await temp.delete();
      rethrow;
    }
  }
}

/// Worker-local at-most-once receipt journal. A `started` receipt is persisted
/// before any tool call begins. If the desktop process restarts without a
/// completed result, the assignment is never automatically executed again.
class WesiRemoteWorkerReceiptStore {
  static const int schemaVersion = 1;
  static const int maxReceipts = 512;
  static const int maxJournalBytes = 2 * 1024 * 1024;

  final WesiRemoteWorkerReceiptJournal journal;
  final Map<String, WesiRemoteWorkerReceipt> _receipts =
      <String, WesiRemoteWorkerReceipt>{};
  Future<void> _serial = Future<void>.value();
  bool _initialized = false;

  WesiRemoteWorkerReceiptStore({required this.journal});

  WesiRemoteWorkerReceipt? get(String assignmentMessageId) {
    _ensureInitialized();
    return _receipts[assignmentMessageId];
  }

  Future<void> restore() => _locked(() async {
        final raw = await journal.read();
        if (raw == null || raw.trim().isEmpty) {
          _receipts.clear();
          _initialized = true;
          return;
        }
        if (utf8.encode(raw).length > maxJournalBytes) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_RECEIPT_JOURNAL_TOO_LARGE',
            'Remote worker receipt journal exceeds its bounded persistence limit',
          );
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_CORRUPT_RECEIPT_JOURNAL',
            'Remote worker receipt journal root is invalid',
          );
        }
        final root = decoded.map((key, value) => MapEntry('$key', value));
        final rawReceipts = root['receipts'];
        if (root['schemaVersion'] != schemaVersion ||
            rawReceipts is! List ||
            rawReceipts.length > maxReceipts) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_RECEIPT_SCHEMA_UNSUPPORTED',
            'Remote worker receipt journal schema is unsupported',
          );
        }
        final restored = <String, WesiRemoteWorkerReceipt>{};
        for (final rawReceipt in rawReceipts) {
          if (rawReceipt is! Map) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_CORRUPT_RECEIPT_JOURNAL',
              'Remote worker receipt is invalid',
            );
          }
          final receipt = _receiptFromJson(
            rawReceipt.map((key, value) => MapEntry('$key', value)),
          );
          if (restored.containsKey(receipt.assignmentMessageId)) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_CORRUPT_RECEIPT_JOURNAL',
              'Remote worker receipt journal contains duplicates',
            );
          }
          restored[receipt.assignmentMessageId] = receipt;
        }
        _receipts
          ..clear()
          ..addAll(restored);
        _initialized = true;
      });

  Future<WesiRemoteWorkerReceipt> markStarted({
    required String assignmentMessageId,
    required String jobId,
    required String leaseId,
    required int generation,
    DateTime? now,
  }) =>
      _locked(() async {
        _ensureInitialized();
        final existing = _receipts[assignmentMessageId];
        if (existing != null) {
          if (existing.jobId != jobId ||
              existing.leaseId != leaseId ||
              existing.generation != generation) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_RECEIPT_ID_COLLISION',
              'Remote worker assignment receipt identity collision',
            );
          }
          return existing;
        }
        if (_receipts.length >= maxReceipts) {
          final completed = _receipts.values
              .where((item) =>
                  item.state == WesiRemoteWorkerReceiptState.completed)
              .toList()
            ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
          if (completed.isEmpty) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_RECEIPT_CAPACITY',
              'Remote worker receipt journal capacity is exhausted',
            );
          }
          _receipts.remove(completed.first.assignmentMessageId);
        }
        final receipt = WesiRemoteWorkerReceipt(
          assignmentMessageId: assignmentMessageId,
          jobId: jobId,
          leaseId: leaseId,
          generation: generation,
          state: WesiRemoteWorkerReceiptState.started,
          startedAt: (now ?? DateTime.now()).toUtc(),
        );
        _receipts[assignmentMessageId] = receipt;
        try {
          await _persist();
        } catch (_) {
          _receipts.remove(assignmentMessageId);
          rethrow;
        }
        return receipt;
      });

  Future<WesiRemoteWorkerReceipt> markCompleted(
    String assignmentMessageId,
    WesiRemoteJobMessage resultMessage,
  ) =>
      _locked(() async {
        _ensureInitialized();
        final existing = _receipts[assignmentMessageId];
        if (existing == null) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_RECEIPT_NOT_FOUND',
            'Remote worker assignment receipt does not exist',
          );
        }
        if (resultMessage.jobId != existing.jobId ||
            resultMessage.kind != WesiRemoteJobMessageKind.result) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_BAD_RECEIPT_RESULT',
            'Remote worker receipt result does not match its assignment',
          );
        }
        final next = existing.complete(resultMessage);
        _receipts[assignmentMessageId] = next;
        try {
          await _persist();
        } catch (_) {
          _receipts[assignmentMessageId] = existing;
          rethrow;
        }
        return next;
      });

  Future<void> _persist() async {
    final ordered = _receipts.values.toList()
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final raw = jsonEncode(<String, dynamic>{
      'schemaVersion': schemaVersion,
      'receipts': ordered.map(_receiptToJson).toList(growable: false),
    });
    if (utf8.encode(raw).length > maxJournalBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_RECEIPT_JOURNAL_TOO_LARGE',
        'Remote worker receipt journal exceeds its bounded persistence limit',
      );
    }
    await journal.write(raw);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_RECEIPT_STORE_NOT_RESTORED',
        'Restore the remote worker receipt store before using it',
      );
    }
  }

  Future<T> _locked<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _serial = _serial.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

Map<String, dynamic> _receiptToJson(WesiRemoteWorkerReceipt value) =>
    <String, dynamic>{
      'assignmentMessageId': value.assignmentMessageId,
      'jobId': value.jobId,
      'leaseId': value.leaseId,
      'generation': value.generation,
      'state': value.state.name,
      'startedAt': value.startedAt.toUtc().toIso8601String(),
      if (value.resultMessage != null)
        'resultMessage': value.resultMessage!.toJson(),
    };

WesiRemoteWorkerReceipt _receiptFromJson(Map<String, dynamic> json) {
  final assignmentMessageId = '${json['assignmentMessageId'] ?? ''}';
  final jobId = '${json['jobId'] ?? ''}';
  final leaseId = '${json['leaseId'] ?? ''}';
  final generation = json['generation'];
  final startedAt = DateTime.tryParse('${json['startedAt'] ?? ''}')?.toUtc();
  WesiRemoteWorkerReceiptState? state;
  for (final candidate in WesiRemoteWorkerReceiptState.values) {
    if (candidate.name == '${json['state'] ?? ''}') {
      state = candidate;
      break;
    }
  }
  final idPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
  if (!idPattern.hasMatch(assignmentMessageId) ||
      !idPattern.hasMatch(jobId) ||
      !RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(leaseId) ||
      generation is! num ||
      generation.isNaN ||
      generation.isInfinite ||
      generation.toInt().toDouble() != generation.toDouble() ||
      generation.toInt() < 1 ||
      startedAt == null ||
      state == null) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_RECEIPT_JOURNAL',
      'Remote worker receipt is invalid',
    );
  }
  WesiRemoteJobMessage? result;
  final rawResult = json['resultMessage'];
  if (rawResult != null) {
    if (rawResult is! Map) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_CORRUPT_RECEIPT_JOURNAL',
        'Remote worker receipt result is invalid',
      );
    }
    result = _messageFromJson(
      rawResult.map((key, value) => MapEntry('$key', value)),
    );
  }
  if (state == WesiRemoteWorkerReceiptState.completed && result == null) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_RECEIPT_JOURNAL',
      'Completed remote worker receipt is missing its result',
    );
  }
  return WesiRemoteWorkerReceipt(
    assignmentMessageId: assignmentMessageId,
    jobId: jobId,
    leaseId: leaseId,
    generation: generation.toInt(),
    state: state,
    startedAt: startedAt,
    resultMessage: result,
  );
}

WesiRemoteJobMessage _messageFromJson(Map<String, dynamic> json) {
  WesiRemoteJobMessageKind? kind;
  for (final candidate in WesiRemoteJobMessageKind.values) {
    if (candidate.name == '${json['kind'] ?? ''}') {
      kind = candidate;
      break;
    }
  }
  final sequence = json['sequence'];
  final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc();
  final payload = json['payload'];
  if (json['v'] != wesiRemoteWorkerProtocolVersion ||
      kind == null ||
      sequence is! num ||
      sequence.toInt().toDouble() != sequence.toDouble() ||
      createdAt == null ||
      payload is! Map) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_RECEIPT_JOURNAL',
      'Remote worker receipt message is invalid',
    );
  }
  return WesiRemoteJobMessage(
    messageId: '${json['messageId'] ?? ''}',
    jobId: '${json['jobId'] ?? ''}',
    kind: kind,
    sequence: sequence.toInt(),
    createdAt: createdAt,
    payload: payload.map((key, value) => MapEntry('$key', value)),
  );
}
