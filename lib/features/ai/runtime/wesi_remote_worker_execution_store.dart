import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wesi_local_runtime_models.dart';
import 'wesi_remote_worker_models.dart';

class WesiRemoteExecutionRequest {
  final String workspaceId;
  final WesiLocalToolCall call;
  final bool destructiveConfirmed;

  const WesiRemoteExecutionRequest({
    required this.workspaceId,
    required this.call,
    this.destructiveConfirmed = false,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'workspaceId': workspaceId,
        'call': <String, dynamic>{
          'id': call.id,
          'tool': call.tool,
          'arguments': call.arguments,
        },
        'destructiveConfirmed': destructiveConfirmed,
      };

  factory WesiRemoteExecutionRequest.fromJson(Map<String, dynamic> json) {
    final rawCall = json['call'];
    if (rawCall is! Map) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_EXECUTION_REQUEST',
        'Remote execution request is missing its typed tool call',
      );
    }
    final callMap = rawCall.map((key, value) => MapEntry('$key', value));
    final rawArguments = callMap['arguments'];
    if (rawArguments is! Map) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_EXECUTION_REQUEST',
        'Remote execution arguments are invalid',
      );
    }
    final request = WesiRemoteExecutionRequest(
      workspaceId: '${json['workspaceId'] ?? ''}',
      call: WesiLocalToolCall(
        id: '${callMap['id'] ?? ''}',
        tool: '${callMap['tool'] ?? ''}',
        arguments: rawArguments.map((key, value) => MapEntry('$key', value)),
      ),
      destructiveConfirmed: json['destructiveConfirmed'] == true,
    );
    request.validate();
    return request;
  }

  void validate() {
    final idPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
    if (!idPattern.hasMatch(workspaceId) ||
        !idPattern.hasMatch(call.id) ||
        WesiLocalCapabilityRegistry.get(call.tool) == null ||
        call.encodedArgumentBytes > 64 * 1024) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_EXECUTION_REQUEST',
        'Remote execution request violates the typed local runtime contract',
      );
    }
    final encoded = utf8.encode(jsonEncode(toJson()));
    if (encoded.length > 128 * 1024) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_REQUEST_TOO_LARGE',
        'Remote execution request exceeds its bounded transport limit',
      );
    }
  }
}

abstract class WesiRemoteExecutionJournal {
  Future<String?> read();

  Future<void> write(String value);
}

class WesiMemoryRemoteExecutionJournal implements WesiRemoteExecutionJournal {
  String? value;

  WesiMemoryRemoteExecutionJournal([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class WesiFileRemoteExecutionJournal implements WesiRemoteExecutionJournal {
  final File file;
  final int maxBytes;

  const WesiFileRemoteExecutionJournal(
    this.file, {
    this.maxBytes = WesiRemoteExecutionStore.maxJournalBytes,
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
        'WRW_EXECUTION_JOURNAL_TOO_LARGE',
        'Remote execution journal exceeds its bounded persistence limit',
      );
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_JOURNAL_TOO_LARGE',
        'Remote execution journal exceeds its bounded persistence limit',
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

/// Durable job payload sidecar. Canonical job state still lives exclusively in
/// WesiDurableJobQueue; this store exists because Stage-8 requirements describe
/// scheduling needs, not the actual typed tool arguments required by a remote
/// desktop after a Control Plane/app restart.
class WesiRemoteExecutionStore {
  static const int schemaVersion = 1;
  static const int maxEntries = 256;
  static const int maxJournalBytes = 2 * 1024 * 1024;

  final WesiRemoteExecutionJournal journal;
  final Map<String, WesiRemoteExecutionRequest> _entries =
      <String, WesiRemoteExecutionRequest>{};
  Future<void> _serial = Future<void>.value();
  bool _initialized = false;

  WesiRemoteExecutionStore({required this.journal});

  WesiRemoteExecutionRequest? get(String jobId) {
    _ensureInitialized();
    return _entries[jobId];
  }

  Future<void> restore() => _locked(() async {
        final raw = await journal.read();
        if (raw == null || raw.trim().isEmpty) {
          _entries.clear();
          _initialized = true;
          return;
        }
        if (utf8.encode(raw).length > maxJournalBytes) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_EXECUTION_JOURNAL_TOO_LARGE',
            'Remote execution journal exceeds its bounded persistence limit',
          );
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_CORRUPT_EXECUTION_JOURNAL',
            'Remote execution journal root is invalid',
          );
        }
        final root = decoded.map((key, value) => MapEntry('$key', value));
        if (root['schemaVersion'] != schemaVersion || root['entries'] is! Map) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_EXECUTION_SCHEMA_UNSUPPORTED',
            'Remote execution journal schema is unsupported',
          );
        }
        final entries = (root['entries'] as Map)
            .map((key, value) => MapEntry('$key', value));
        if (entries.length > maxEntries) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_CORRUPT_EXECUTION_JOURNAL',
            'Remote execution journal contains too many entries',
          );
        }
        final restored = <String, WesiRemoteExecutionRequest>{};
        for (final entry in entries.entries) {
          if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(entry.key) ||
              entry.value is! Map) {
            throw const WesiRemoteWorkerProtocolException(
              'WRW_CORRUPT_EXECUTION_JOURNAL',
              'Remote execution journal entry is invalid',
            );
          }
          restored[entry.key] = WesiRemoteExecutionRequest.fromJson(
            (entry.value as Map)
                .map((key, value) => MapEntry('$key', value)),
          );
        }
        _entries
          ..clear()
          ..addAll(restored);
        _initialized = true;
      });

  Future<void> put(String jobId, WesiRemoteExecutionRequest request) =>
      _locked(() async {
        _ensureInitialized();
        if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(jobId)) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_BAD_JOB_ID',
            'Remote execution job id is invalid',
          );
        }
        request.validate();
        if (!_entries.containsKey(jobId) && _entries.length >= maxEntries) {
          throw const WesiRemoteWorkerProtocolException(
            'WRW_EXECUTION_CAPACITY',
            'Remote execution journal capacity is exhausted',
          );
        }
        final previous = _entries[jobId];
        _entries[jobId] = request;
        try {
          await _persist();
        } catch (_) {
          if (previous == null) {
            _entries.remove(jobId);
          } else {
            _entries[jobId] = previous;
          }
          rethrow;
        }
      });

  Future<void> remove(String jobId) => _locked(() async {
        _ensureInitialized();
        final previous = _entries.remove(jobId);
        if (previous == null) return;
        try {
          await _persist();
        } catch (_) {
          _entries[jobId] = previous;
          rethrow;
        }
      });

  Future<void> _persist() async {
    final encoded = jsonEncode(<String, dynamic>{
      'schemaVersion': schemaVersion,
      'entries': _entries.map(
        (key, value) => MapEntry(key, value.toJson()),
      ),
    });
    if (utf8.encode(encoded).length > maxJournalBytes) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_JOURNAL_TOO_LARGE',
        'Remote execution journal exceeds its bounded persistence limit',
      );
    }
    await journal.write(encoded);
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_STORE_NOT_RESTORED',
        'Restore the remote execution store before using it',
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
