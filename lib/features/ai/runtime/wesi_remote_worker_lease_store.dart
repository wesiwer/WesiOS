import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wesi_remote_worker_models.dart';

abstract class WesiRemoteWorkerLeaseJournal {
  Future<String?> read();

  Future<void> write(String value);
}

class WesiMemoryRemoteWorkerLeaseJournal
    implements WesiRemoteWorkerLeaseJournal {
  String? value;

  WesiMemoryRemoteWorkerLeaseJournal([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class WesiFileRemoteWorkerLeaseJournal
    implements WesiRemoteWorkerLeaseJournal {
  final File file;
  final int maxBytes;

  const WesiFileRemoteWorkerLeaseJournal(
    this.file, {
    this.maxBytes = WesiRemoteWorkerLeaseStore.maxJournalBytes,
  });

  File get _backup => File('${file.path}.previous');

  @override
  Future<String?> read() async {
    if (!await file.exists() && await _backup.exists()) {
      await _backup.rename(file.path);
    }
    if (!await file.exists()) return null;
    final stat = await file.stat();
    if (stat.size > maxBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_JOURNAL_TOO_LARGE',
        'Remote worker lease journal exceeds its bounded persistence limit',
      );
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_JOURNAL_TOO_LARGE',
        'Remote worker lease journal exceeds its bounded persistence limit',
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

class WesiRemoteWorkerLeaseRecord {
  final String jobId;
  final String workerId;
  final String leaseId;
  final int generation;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final int lastInboundSequence;
  final bool assignmentAcked;

  const WesiRemoteWorkerLeaseRecord({
    required this.jobId,
    required this.workerId,
    required this.leaseId,
    required this.generation,
    required this.issuedAt,
    required this.expiresAt,
    this.lastInboundSequence = -1,
    this.assignmentAcked = false,
  });

  bool expiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  WesiRemoteWorkerLeaseRecord copyWith({
    DateTime? expiresAt,
    int? lastInboundSequence,
    bool? assignmentAcked,
  }) =>
      WesiRemoteWorkerLeaseRecord(
        jobId: jobId,
        workerId: workerId,
        leaseId: leaseId,
        generation: generation,
        issuedAt: issuedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        lastInboundSequence: lastInboundSequence ?? this.lastInboundSequence,
        assignmentAcked: assignmentAcked ?? this.assignmentAcked,
      );
}

/// Durable transport metadata for Stage-10 Remote Worker execution.
///
/// This store is deliberately not a second job queue/state machine. Canonical
/// job state remains in WesiDurableJobQueue; this journal only persists worker
/// affinity, lease generation/TTL and inbound replay sequence so reconnect and
/// Control Plane restart cannot accept stale remote results.
class WesiRemoteWorkerLeaseStore {
  static const int schemaVersion = 1;
  static const int maxRecords = 256;
  static const int maxJournalBytes = 512 * 1024;

  final WesiRemoteWorkerLeaseJournal journal;
  final Map<String, WesiRemoteWorkerLeaseRecord> _records =
      <String, WesiRemoteWorkerLeaseRecord>{};
  Future<void> _serial = Future<void>.value();
  bool _initialized = false;

  WesiRemoteWorkerLeaseStore({required this.journal});

  List<WesiRemoteWorkerLeaseRecord> get records {
    _ensureInitialized();
    final out = _records.values.toList(growable: false)
      ..sort((a, b) => a.jobId.compareTo(b.jobId));
    return List<WesiRemoteWorkerLeaseRecord>.unmodifiable(out);
  }

  WesiRemoteWorkerLeaseRecord? get(String jobId) {
    _ensureInitialized();
    return _records[jobId];
  }

  Future<void> restore() => _locked(() async {
        final raw = await journal.read();
        if (raw == null || raw.trim().isEmpty) {
          _records.clear();
          _initialized = true;
          return;
        }
        if (utf8.encode(raw).length > maxJournalBytes) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_LEASE_JOURNAL_TOO_LARGE',
            'Remote worker lease journal exceeds its bounded persistence limit',
          );
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_CORRUPT_LEASE_JOURNAL',
            'Remote worker lease journal root is invalid',
          );
        }
        final root = decoded.map((key, value) => MapEntry('$key', value));
        if (_int(root['schemaVersion']) != schemaVersion) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_LEASE_SCHEMA_UNSUPPORTED',
            'Remote worker lease journal schema is unsupported',
          );
        }
        final rawRecords = root['records'];
        if (rawRecords is! List || rawRecords.length > maxRecords) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_CORRUPT_LEASE_JOURNAL',
            'Remote worker lease journal record collection is invalid',
          );
        }
        final restored = <String, WesiRemoteWorkerLeaseRecord>{};
        for (final rawRecord in rawRecords) {
          if (rawRecord is! Map) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_CORRUPT_LEASE_JOURNAL',
              'Remote worker lease record is invalid',
            );
          }
          final record = _recordFromJson(
            rawRecord.map((key, value) => MapEntry('$key', value)),
          );
          if (restored.containsKey(record.jobId)) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_CORRUPT_LEASE_JOURNAL',
              'Remote worker lease journal contains duplicate job ids',
            );
          }
          restored[record.jobId] = record;
        }
        _records
          ..clear()
          ..addAll(restored);
        _initialized = true;
      });

  Future<WesiRemoteWorkerLeaseRecord> issue({
    required String jobId,
    required String workerId,
    required String leaseId,
    required DateTime issuedAt,
    required DateTime expiresAt,
  }) =>
      _locked(() async {
        _ensureInitialized();
        final previous = _records[jobId];
        final record = WesiRemoteWorkerLeaseRecord(
          jobId: jobId,
          workerId: workerId,
          leaseId: leaseId,
          generation: (previous?.generation ?? 0) + 1,
          issuedAt: issuedAt.toUtc(),
          expiresAt: expiresAt.toUtc(),
        );
        _validateRecord(record);
        await _replace(record);
        return record;
      });

  Future<WesiRemoteWorkerLeaseRecord> renew(
    String jobId, {
    required DateTime expiresAt,
  }) =>
      _locked(() async {
        final current = _require(jobId);
        final next = current.copyWith(expiresAt: expiresAt.toUtc());
        _validateRecord(next);
        await _replace(next);
        return next;
      });

  Future<WesiRemoteWorkerLeaseRecord> acceptInboundSequence(
    String jobId, {
    required int sequence,
  }) =>
      _locked(() async {
        final current = _require(jobId);
        if (sequence < 0 || sequence <= current.lastInboundSequence) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_REPLAYED_LEASE_SEQUENCE',
            'Remote worker lease sequence is stale or replayed',
          );
        }
        final next = current.copyWith(lastInboundSequence: sequence);
        await _replace(next);
        return next;
      });

  Future<WesiRemoteWorkerLeaseRecord> markAssignmentAcked(String jobId) =>
      _locked(() async {
        final current = _require(jobId);
        if (current.assignmentAcked) return current;
        final next = current.copyWith(assignmentAcked: true);
        await _replace(next);
        return next;
      });

  Future<void> remove(String jobId) => _locked(() async {
        _ensureInitialized();
        final previous = _records.remove(jobId);
        if (previous == null) return;
        try {
          await _persist();
        } catch (_) {
          _records[jobId] = previous;
          rethrow;
        }
      });

  WesiRemoteWorkerLeaseRecord _require(String jobId) {
    _ensureInitialized();
    final record = _records[jobId];
    if (record == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_NOT_FOUND',
        'Remote worker lease does not exist',
      );
    }
    return record;
  }

  Future<void> _replace(WesiRemoteWorkerLeaseRecord record) async {
    if (!_records.containsKey(record.jobId) && _records.length >= maxRecords) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_CAPACITY',
        'Remote worker lease journal capacity is exhausted',
      );
    }
    final previous = _records[record.jobId];
    _records[record.jobId] = record;
    try {
      await _persist();
    } catch (_) {
      if (previous == null) {
        _records.remove(record.jobId);
      } else {
        _records[record.jobId] = previous;
      }
      rethrow;
    }
  }

  Future<void> _persist() async {
    final ordered = _records.values.toList(growable: false)
      ..sort((a, b) => a.jobId.compareTo(b.jobId));
    final raw = jsonEncode(<String, dynamic>{
      'schemaVersion': schemaVersion,
      'records': ordered.map(_recordToJson).toList(growable: false),
    });
    if (utf8.encode(raw).length > maxJournalBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_JOURNAL_TOO_LARGE',
        'Remote worker lease journal exceeds its bounded persistence limit',
      );
    }
    await journal.write(raw);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_LEASE_STORE_NOT_RESTORED',
        'Restore the remote worker lease store before using it',
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

Map<String, dynamic> _recordToJson(WesiRemoteWorkerLeaseRecord value) =>
    <String, dynamic>{
      'jobId': value.jobId,
      'workerId': value.workerId,
      'leaseId': value.leaseId,
      'generation': value.generation,
      'issuedAt': value.issuedAt.toUtc().toIso8601String(),
      'expiresAt': value.expiresAt.toUtc().toIso8601String(),
      'lastInboundSequence': value.lastInboundSequence,
      'assignmentAcked': value.assignmentAcked,
    };

WesiRemoteWorkerLeaseRecord _recordFromJson(Map<String, dynamic> json) {
  final record = WesiRemoteWorkerLeaseRecord(
    jobId: _requiredString(json['jobId'], 128),
    workerId: _requiredString(json['workerId'], 128),
    leaseId: _requiredString(json['leaseId'], 96),
    generation: _int(json['generation']),
    issuedAt: _requiredDate(json['issuedAt']),
    expiresAt: _requiredDate(json['expiresAt']),
    lastInboundSequence: _int(json['lastInboundSequence']),
    assignmentAcked: json['assignmentAcked'] == true,
  );
  _validateRecord(record);
  return record;
}

void _validateRecord(WesiRemoteWorkerLeaseRecord value) {
  final jobPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
  final workerPattern = RegExp(r'^[A-Za-z0-9_-]{20,96}$');
  final leasePattern = RegExp(r'^[A-Za-z0-9_-]{20,96}$');
  final ttl = value.expiresAt.toUtc().difference(value.issuedAt.toUtc());
  if (!jobPattern.hasMatch(value.jobId) ||
      !workerPattern.hasMatch(value.workerId) ||
      !leasePattern.hasMatch(value.leaseId) ||
      value.generation < 1 ||
      value.lastInboundSequence < -1 ||
      ttl <= Duration.zero ||
      ttl > const Duration(hours: 24)) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_BAD_LEASE_RECORD',
      'Remote worker lease record is invalid',
    );
  }
}

String _requiredString(dynamic value, int maxLength) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_LEASE_JOURNAL',
      'Remote worker lease journal string is invalid',
    );
  }
  return value;
}

DateTime _requiredDate(dynamic value) {
  if (value is! String) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_LEASE_JOURNAL',
      'Remote worker lease journal timestamp is invalid',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_LEASE_JOURNAL',
      'Remote worker lease journal timestamp is invalid',
    );
  }
  return parsed.toUtc();
}

int _int(dynamic value) {
  if (value is! num || value.isNaN || value.isInfinite) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_LEASE_JOURNAL',
      'Remote worker lease journal integer is invalid',
    );
  }
  final integer = value.toInt();
  if (integer.toDouble() != value.toDouble()) {
    throw const WesiRemoteWorkerProtocolException(
      'WRW_CORRUPT_LEASE_JOURNAL',
      'Remote worker lease journal integer is invalid',
    );
  }
  return integer;
}
