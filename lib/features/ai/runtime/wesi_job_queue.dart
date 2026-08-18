import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'wesi_local_runtime_models.dart';
import 'wesi_resource_scheduler.dart';
import 'wesi_resource_scheduler_models.dart';
import 'wesi_runtime_pack_models.dart';

class WesiJobQueueException implements Exception {
  final String code;
  final String message;

  const WesiJobQueueException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

abstract class WesiJobJournal {
  Future<String?> read();

  Future<void> write(String value);
}

class WesiMemoryJobJournal implements WesiJobJournal {
  String? value;

  WesiMemoryJobJournal([this.value]);

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String value) async {
    this.value = value;
  }
}

class WesiFileJobJournal implements WesiJobJournal {
  final File file;
  final int maxBytes;

  const WesiFileJobJournal(
    this.file, {
    this.maxBytes = WesiDurableJobQueue.maxJournalBytes,
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
      throw const WesiJobQueueException(
        'WJQ_JOURNAL_TOO_LARGE',
        'Job journal exceeds the bounded persistence limit',
      );
    }
    return file.readAsString();
  }

  @override
  Future<void> write(String value) async {
    final bytes = utf8.encode(value);
    if (bytes.length > maxBytes) {
      throw const WesiJobQueueException(
        'WJQ_JOURNAL_TOO_LARGE',
        'Job journal exceeds the bounded persistence limit',
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

class WesiDurableJobQueue {
  static const int schemaVersion = 1;
  static const int maxJobs = 256;
  static const int maxEventsPerJob = 64;
  static const int maxJournalBytes = 2 * 1024 * 1024;

  final WesiJobJournal journal;
  final Map<String, WesiScheduledJob> _jobs = <String, WesiScheduledJob>{};
  Future<void> _serial = Future<void>.value();
  bool _initialized = false;

  WesiDurableJobQueue({required this.journal});

  List<WesiScheduledJob> get jobs {
    _ensureInitialized();
    final out = _jobs.values.toList(growable: false)
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    return List<WesiScheduledJob>.unmodifiable(out);
  }

  WesiScheduledJob? get(String id) {
    _ensureInitialized();
    return _jobs[id];
  }

  WesiScheduledJob? get nextQueued {
    _ensureInitialized();
    final pending = _jobs.values
        .where((job) => job.state == WesiScheduledJobState.queued)
        .toList();
    pending.sort((a, b) {
      final priority = b.priority.index.compareTo(a.priority.index);
      if (priority != 0) return priority;
      final queued = a.queuedAt.compareTo(b.queuedAt);
      if (queued != 0) return queued;
      return a.id.compareTo(b.id);
    });
    return pending.isEmpty ? null : pending.first;
  }

  Future<void> restore() => _locked(() async {
        final raw = await journal.read();
        if (raw == null || raw.trim().isEmpty) {
          _jobs.clear();
          _initialized = true;
          return;
        }
        if (utf8.encode(raw).length > maxJournalBytes) {
          throw const WesiJobQueueException(
            'WJQ_JOURNAL_TOO_LARGE',
            'Job journal exceeds the bounded persistence limit',
          );
        }
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          throw const WesiJobQueueException(
            'WJQ_CORRUPT_JOURNAL',
            'Job journal root is invalid',
          );
        }
        final root = decoded.map((key, value) => MapEntry('$key', value));
        if (_int(root['schemaVersion']) != schemaVersion) {
          throw const WesiJobQueueException(
            'WJQ_SCHEMA_UNSUPPORTED',
            'Job journal schema is unsupported',
          );
        }
        final rawJobs = root['jobs'];
        if (rawJobs is! List || rawJobs.length > maxJobs) {
          throw const WesiJobQueueException(
            'WJQ_CORRUPT_JOURNAL',
            'Job journal contains an invalid job collection',
          );
        }
        final restoredJobs = <String, WesiScheduledJob>{};
        for (final rawJob in rawJobs) {
          if (rawJob is! Map) {
            throw const WesiJobQueueException(
              'WJQ_CORRUPT_JOURNAL',
              'Job journal contains an invalid job record',
            );
          }
          final job = _jobFromJson(
            rawJob.map((key, value) => MapEntry('$key', value)),
          );
          if (restoredJobs.containsKey(job.id)) {
            throw const WesiJobQueueException(
              'WJQ_CORRUPT_JOURNAL',
              'Job journal contains duplicate job ids',
            );
          }
          restoredJobs[job.id] = job;
        }
        _jobs
          ..clear()
          ..addAll(restoredJobs);
        _initialized = true;
      });

  Future<WesiScheduledJob> enqueue({
    required String id,
    required WesiJobRequirements requirements,
    WesiJobPriority priority = WesiJobPriority.normal,
    DateTime? now,
  }) =>
      _locked(() async {
        _ensureInitialized();
        _validateId(id, 'job id');
        _validateRequirements(requirements);
        if (_jobs.containsKey(id)) {
          throw const WesiJobQueueException(
            'WJQ_DUPLICATE_JOB',
            'Job id already exists',
          );
        }
        if (_jobs.length >= maxJobs) {
          throw const WesiJobQueueException(
            'WJQ_CAPACITY',
            'Job journal capacity is exhausted',
          );
        }
        final at = (now ?? DateTime.now()).toUtc();
        final job = WesiScheduledJob(
          id: id,
          requirements: requirements,
          priority: priority,
          state: WesiScheduledJobState.queued,
          queuedAt: at,
          updatedAt: at,
          progress: 0,
          events: <WesiJobEvent>[
            WesiJobEvent(
              kind: WesiJobEventKind.queued,
              at: at,
              message: 'Job queued',
            ),
          ],
        );
        return _insert(job);
      });

  Future<WesiScheduledJob> markRunning(
    String id, {
    required String workerId,
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.queued) {
          throw _badTransition(job, 'running');
        }
        _validateId(workerId, 'worker id');
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.running,
          updatedAt: at,
          workerId: workerId,
          startedAt: job.startedAt ?? at,
          finishedAt: null,
          failureCode: null,
          events: _event(
            job,
            WesiJobEventKind.started,
            at,
            'Job started on worker $workerId',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> updateProgress(
    String id, {
    required double progress,
    required String stage,
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.running &&
            job.state != WesiScheduledJobState.pauseRequested) {
          throw _badTransition(job, 'progress');
        }
        if (progress < job.progress || progress < 0 || progress > 1) {
          throw const WesiJobQueueException(
            'WJQ_BAD_PROGRESS',
            'Job progress must be monotonic and within 0..1',
          );
        }
        _validateStage(stage);
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          updatedAt: at,
          progress: progress,
          currentStage: stage,
          events: _event(
            job,
            WesiJobEventKind.progress,
            at,
            'Progress ${(progress * 100).round()}% at $stage',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> checkpoint(
    String id, {
    required WesiJobCheckpointRef checkpoint,
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (!job.requirements.checkpointable) {
          throw const WesiJobQueueException(
            'WJQ_NOT_CHECKPOINTABLE',
            'This workload does not support safe checkpoints',
          );
        }
        if (job.state != WesiScheduledJobState.running &&
            job.state != WesiScheduledJobState.pauseRequested) {
          throw _badTransition(job, 'checkpoint');
        }
        checkpoint.validate();
        if (checkpoint.progress < job.progress) {
          throw const WesiJobQueueException(
            'WJQ_BAD_CHECKPOINT',
            'Checkpoint cannot move job progress backwards',
          );
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          updatedAt: at,
          progress: checkpoint.progress,
          currentStage: checkpoint.stage,
          checkpoint: checkpoint,
          events: _event(
            job,
            WesiJobEventKind.checkpointed,
            at,
            'Checkpoint ${checkpoint.checkpointId} saved',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> requestPause(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.running) {
          throw _badTransition(job, 'pauseRequested');
        }
        if (!job.requirements.checkpointable) {
          throw const WesiJobQueueException(
            'WJQ_NOT_CHECKPOINTABLE',
            'This workload cannot be paused safely',
          );
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.pauseRequested,
          updatedAt: at,
          events: _event(
            job,
            WesiJobEventKind.pauseRequested,
            at,
            'Pause requested',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> markPaused(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.pauseRequested) {
          throw _badTransition(job, 'paused');
        }
        if (!_checkpointMatchesCurrentState(job)) {
          throw const WesiJobQueueException(
            'WJQ_CHECKPOINT_REQUIRED',
            'A current checkpoint is required before pausing this job',
          );
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.paused,
          updatedAt: at,
          workerId: null,
          events: _event(
            job,
            WesiJobEventKind.paused,
            at,
            'Job paused at a durable checkpoint',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> waitForWorker(
    String id, {
    String reason = 'Execution worker is unavailable',
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.terminal ||
            job.state == WesiScheduledJobState.cancelling ||
            job.state == WesiScheduledJobState.waitingForWorker) {
          throw _badTransition(job, 'waitingForWorker');
        }
        if (job.requirements.checkpointable &&
            (job.state == WesiScheduledJobState.running ||
                job.state == WesiScheduledJobState.pauseRequested) &&
            !_checkpointMatchesCurrentState(job)) {
          throw const WesiJobQueueException(
            'WJQ_CHECKPOINT_REQUIRED',
            'Checkpointable running work must save a current checkpoint before losing its worker',
          );
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.waitingForWorker,
          updatedAt: at,
          workerId: null,
          events: _event(
            job,
            WesiJobEventKind.waitingForWorker,
            at,
            _safeMessage(reason),
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> resume(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.paused &&
            job.state != WesiScheduledJobState.waitingForWorker &&
            job.state != WesiScheduledJobState.blocked) {
          throw _badTransition(job, 'queued');
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.queued,
          updatedAt: at,
          workerId: null,
          finishedAt: null,
          failureCode: null,
          events: _event(
            job,
            WesiJobEventKind.resumed,
            at,
            'Job returned to the scheduler queue',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> block(
    String id, {
    required String code,
    required String message,
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.queued) {
          throw _badTransition(job, 'blocked');
        }
        _validateCode(code);
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.blocked,
          updatedAt: at,
          workerId: null,
          failureCode: code,
          events: _event(
            job,
            WesiJobEventKind.blocked,
            at,
            _safeMessage(message),
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> requestCancel(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.terminal || job.state == WesiScheduledJobState.cancelling) {
          throw _badTransition(job, 'cancelling');
        }
        final at = (now ?? DateTime.now()).toUtc();
        if (job.state != WesiScheduledJobState.running &&
            job.state != WesiScheduledJobState.pauseRequested) {
          final cancelled = job.copyWith(
            state: WesiScheduledJobState.cancelled,
            updatedAt: at,
            workerId: null,
            finishedAt: at,
            events: _event(
              job,
              WesiJobEventKind.cancelled,
              at,
              'Job cancelled before active execution',
            ),
          );
          return _replace(cancelled);
        }
        final next = job.copyWith(
          state: WesiScheduledJobState.cancelling,
          updatedAt: at,
          events: _event(
            job,
            WesiJobEventKind.cancelRequested,
            at,
            'Cancellation requested',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> markCancelled(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.cancelling) {
          throw _badTransition(job, 'cancelled');
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.cancelled,
          updatedAt: at,
          workerId: null,
          finishedAt: at,
          events: _event(
            job,
            WesiJobEventKind.cancelled,
            at,
            'Job cancelled',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> succeed(
    String id, {
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.running) {
          throw _badTransition(job, 'succeeded');
        }
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.succeeded,
          updatedAt: at,
          workerId: null,
          finishedAt: at,
          progress: 1,
          failureCode: null,
          events: _event(
            job,
            WesiJobEventKind.succeeded,
            at,
            'Job completed successfully',
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> fail(
    String id, {
    required String code,
    String message = 'Job failed',
    DateTime? now,
  }) =>
      _locked(() async {
        final job = _requireJob(id);
        if (job.state != WesiScheduledJobState.running &&
            job.state != WesiScheduledJobState.pauseRequested &&
            job.state != WesiScheduledJobState.cancelling) {
          throw _badTransition(job, 'failed');
        }
        _validateCode(code);
        final at = (now ?? DateTime.now()).toUtc();
        final next = job.copyWith(
          state: WesiScheduledJobState.failed,
          updatedAt: at,
          workerId: null,
          finishedAt: at,
          failureCode: code,
          events: _event(
            job,
            WesiJobEventKind.failed,
            at,
            _safeMessage(message),
          ),
        );
        return _replace(next);
      });

  Future<WesiScheduledJob> _insert(WesiScheduledJob job) async {
    _jobs[job.id] = job;
    try {
      await _persist();
      return job;
    } catch (_) {
      _jobs.remove(job.id);
      rethrow;
    }
  }

  Future<WesiScheduledJob> _replace(WesiScheduledJob job) async {
    final previous = _jobs[job.id];
    _jobs[job.id] = job;
    try {
      await _persist();
      return job;
    } catch (_) {
      if (previous == null) {
        _jobs.remove(job.id);
      } else {
        _jobs[job.id] = previous;
      }
      rethrow;
    }
  }

  Future<void> _persist() async {
    if (_jobs.length > maxJobs) {
      throw const WesiJobQueueException(
        'WJQ_CAPACITY',
        'Job journal capacity is exhausted',
      );
    }
    final ordered = _jobs.values.toList()
      ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt));
    final raw = jsonEncode(<String, dynamic>{
      'schemaVersion': schemaVersion,
      'jobs': ordered.map(_jobToJson).toList(growable: false),
    });
    if (utf8.encode(raw).length > maxJournalBytes) {
      throw const WesiJobQueueException(
        'WJQ_JOURNAL_TOO_LARGE',
        'Job journal exceeds the bounded persistence limit',
      );
    }
    await journal.write(raw);
  }

  WesiScheduledJob _requireJob(String id) {
    _ensureInitialized();
    final job = _jobs[id];
    if (job == null) {
      throw const WesiJobQueueException(
        'WJQ_JOB_NOT_FOUND',
        'Job does not exist',
      );
    }
    return job;
  }

  void _ensureInitialized() {
    if (!_initialized) {
      throw const WesiJobQueueException(
        'WJQ_NOT_RESTORED',
        'Restore the durable job queue before using it',
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

  static List<WesiJobEvent> _event(
    WesiScheduledJob job,
    WesiJobEventKind kind,
    DateTime at,
    String message,
  ) {
    final events = <WesiJobEvent>[
      ...job.events,
      WesiJobEvent(kind: kind, at: at, message: _safeMessage(message)),
    ];
    if (events.length <= maxEventsPerJob) return events;
    return events.sublist(events.length - maxEventsPerJob);
  }

  static WesiJobQueueException _badTransition(
    WesiScheduledJob job,
    String target,
  ) =>
      WesiJobQueueException(
        'WJQ_BAD_STATE',
        'Cannot transition ${job.id} from ${job.state.name} to $target',
      );
}

Map<String, dynamic> _jobToJson(WesiScheduledJob job) => <String, dynamic>{
      'id': job.id,
      'requirements': _requirementsToJson(job.requirements),
      'priority': job.priority.name,
      'state': job.state.name,
      'queuedAt': job.queuedAt.toUtc().toIso8601String(),
      'updatedAt': job.updatedAt.toUtc().toIso8601String(),
      if (job.workerId != null) 'workerId': job.workerId,
      if (job.startedAt != null)
        'startedAt': job.startedAt!.toUtc().toIso8601String(),
      if (job.finishedAt != null)
        'finishedAt': job.finishedAt!.toUtc().toIso8601String(),
      'progress': job.progress,
      if (job.currentStage != null) 'currentStage': job.currentStage,
      if (job.checkpoint != null)
        'checkpoint': _checkpointToJson(job.checkpoint!),
      if (job.failureCode != null) 'failureCode': job.failureCode,
      'events': job.events.map(_eventToJson).toList(growable: false),
    };

WesiScheduledJob _jobFromJson(Map<String, dynamic> json) {
  final id = _requiredString(json['id'], 128);
  _validateId(id, 'job id');
  final requirements =
      _requirementsFromJson(_requiredMap(json['requirements']));
  _validateRequirements(requirements);
  final priority = _requiredEnum(WesiJobPriority.values, json['priority']);
  final state = _requiredEnum(WesiScheduledJobState.values, json['state']);
  final queuedAt = _requiredDate(json['queuedAt']);
  final updatedAt = _requiredDate(json['updatedAt']);
  final workerId = _optionalString(json['workerId'], 128);
  if (workerId != null) _validateId(workerId, 'worker id');
  final startedAt = _optionalDate(json['startedAt']);
  final finishedAt = _optionalDate(json['finishedAt']);
  final progress = _number(json['progress']);
  if (progress < 0 || progress > 1) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted job progress is invalid',
    );
  }
  final currentStage = _optionalString(json['currentStage'], 128);
  if (currentStage != null) _validateStage(currentStage);
  final checkpointRaw = json['checkpoint'];
  final checkpoint = checkpointRaw == null
      ? null
      : _checkpointFromJson(_requiredMap(checkpointRaw));
  final failureCode = _optionalString(json['failureCode'], 128);
  if (failureCode != null) _validateCode(failureCode);
  final rawEvents = json['events'];
  if (rawEvents is! List ||
      rawEvents.length > WesiDurableJobQueue.maxEventsPerJob) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted job event collection is invalid',
    );
  }
  final events = rawEvents.map((raw) {
    if (raw is! Map) {
      throw const WesiJobQueueException(
        'WJQ_CORRUPT_JOURNAL',
        'Persisted job event is invalid',
      );
    }
    return _eventFromJson(raw.map((key, value) => MapEntry('$key', value)));
  }).toList(growable: false);

  final active = state == WesiScheduledJobState.running ||
      state == WesiScheduledJobState.pauseRequested ||
      state == WesiScheduledJobState.cancelling;
  if (active && (workerId == null || startedAt == null)) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Active job is missing its worker/start metadata',
    );
  }
  final workerMustBeReleased = state == WesiScheduledJobState.queued ||
      state == WesiScheduledJobState.paused ||
      state == WesiScheduledJobState.waitingForWorker ||
      state == WesiScheduledJobState.blocked ||
      state == WesiScheduledJobState.cancelled ||
      state == WesiScheduledJobState.succeeded ||
      state == WesiScheduledJobState.failed;
  if (workerMustBeReleased && workerId != null) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted job retains a worker outside active execution',
    );
  }
  final checkpointIsCurrent = checkpoint != null &&
      checkpoint.progress == progress &&
      checkpoint.stage == currentStage;
  if (state == WesiScheduledJobState.paused &&
      (!requirements.checkpointable || !checkpointIsCurrent)) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Paused job is missing its current checkpoint',
    );
  }
  if (state == WesiScheduledJobState.waitingForWorker &&
      requirements.checkpointable &&
      startedAt != null &&
      !checkpointIsCurrent) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Checkpointable waiting job is missing its current checkpoint',
    );
  }
  final terminal = state == WesiScheduledJobState.cancelled ||
      state == WesiScheduledJobState.succeeded ||
      state == WesiScheduledJobState.failed;
  if (terminal && finishedAt == null) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Terminal job is missing finishedAt',
    );
  }

  return WesiScheduledJob(
    id: id,
    requirements: requirements,
    priority: priority,
    state: state,
    queuedAt: queuedAt,
    updatedAt: updatedAt,
    workerId: workerId,
    startedAt: startedAt,
    finishedAt: finishedAt,
    progress: progress,
    currentStage: currentStage,
    checkpoint: checkpoint,
    failureCode: failureCode,
    events: events,
  );
}

Map<String, dynamic> _requirementsToJson(WesiJobRequirements value) =>
    <String, dynamic>{
      'toolName': value.toolName,
      'level': value.level.name,
      'requiredCapabilities':
          value.requiredCapabilities.map((item) => item.name).toList(),
      'requiredPacks': value.requiredPacks.map((item) => item.name).toList(),
      'allowedPlatforms':
          value.allowedPlatforms.map((item) => item.name).toList(),
      'minCpuCores': value.minCpuCores,
      'maxCpuLoadPercent': value.maxCpuLoadPercent,
      'minAvailableRamMb': value.minAvailableRamMb,
      'minFreeGpuVramMb': value.minFreeGpuVramMb,
      'minFreeDiskMb': value.minFreeDiskMb,
      'estimatedDurationSeconds': value.estimatedDurationSeconds,
      'preference': value.preference.name,
      'foregroundPolicy': value.foregroundPolicy.name,
      'checkpointable': value.checkpointable,
      'remoteAllowed': value.remoteAllowed,
      'allowControlPlane': value.allowControlPlane,
    };

WesiJobRequirements _requirementsFromJson(Map<String, dynamic> json) =>
    WesiJobRequirements(
      toolName: _requiredString(json['toolName'], 160),
      level: _requiredEnum(WesiWorkloadLevel.values, json['level']),
      requiredCapabilities: _requiredEnumSet(
          WesiLocalCapability.values, json['requiredCapabilities']),
      requiredPacks:
          _requiredEnumSet(WesiRuntimePackId.values, json['requiredPacks']),
      allowedPlatforms:
          _requiredEnumSet(WesiWorkerPlatform.values, json['allowedPlatforms']),
      minCpuCores: _int(json['minCpuCores']),
      maxCpuLoadPercent: _number(json['maxCpuLoadPercent']),
      minAvailableRamMb: _int(json['minAvailableRamMb']),
      minFreeGpuVramMb: _int(json['minFreeGpuVramMb']),
      minFreeDiskMb: _int(json['minFreeDiskMb']),
      estimatedDurationSeconds: _int(json['estimatedDurationSeconds']),
      preference:
          _requiredEnum(WesiExecutionPreference.values, json['preference']),
      foregroundPolicy:
          _requiredEnum(WesiForegroundPolicy.values, json['foregroundPolicy']),
      checkpointable: json['checkpointable'] == true,
      remoteAllowed: json['remoteAllowed'] == true,
      allowControlPlane: json['allowControlPlane'] == true,
    );

Map<String, dynamic> _checkpointToJson(WesiJobCheckpointRef value) =>
    <String, dynamic>{
      'checkpointId': value.checkpointId,
      'version': value.version,
      'stage': value.stage,
      'progress': value.progress,
      'createdAt': value.createdAt.toUtc().toIso8601String(),
    };

WesiJobCheckpointRef _checkpointFromJson(Map<String, dynamic> json) {
  final value = WesiJobCheckpointRef(
    checkpointId: _requiredString(json['checkpointId'], 128),
    version: _int(json['version']),
    stage: _requiredString(json['stage'], 128),
    progress: _number(json['progress']),
    createdAt: _requiredDate(json['createdAt']),
  );
  value.validate();
  return value;
}

Map<String, dynamic> _eventToJson(WesiJobEvent value) => <String, dynamic>{
      'kind': value.kind.name,
      'at': value.at.toUtc().toIso8601String(),
      'message': _safeMessage(value.message),
    };

WesiJobEvent _eventFromJson(Map<String, dynamic> json) => WesiJobEvent(
      kind: _requiredEnum(WesiJobEventKind.values, json['kind']),
      at: _requiredDate(json['at']),
      message: _requiredString(json['message'], 512),
    );

bool _checkpointMatchesCurrentState(WesiScheduledJob job) {
  final checkpoint = job.checkpoint;
  return checkpoint != null &&
      checkpoint.progress == job.progress &&
      checkpoint.stage == job.currentStage;
}

void _validateRequirements(WesiJobRequirements value) {
  if (value.toolName.trim().isEmpty ||
      value.toolName.length > 160 ||
      value.allowedPlatforms.isEmpty ||
      value.minCpuCores < 0 ||
      value.maxCpuLoadPercent <= 0 ||
      value.maxCpuLoadPercent > 100 ||
      value.minAvailableRamMb < 0 ||
      value.minFreeGpuVramMb < 0 ||
      value.minFreeDiskMb < 0 ||
      value.estimatedDurationSeconds < 0) {
    throw const WesiJobQueueException(
      'WJQ_BAD_REQUIREMENTS',
      'Job requirements are invalid',
    );
  }

  late final WesiTrustedWorkloadDescriptor trusted;
  try {
    trusted = WesiTrustedWorkloadRegistry.require(value.toolName);
  } on WesiSchedulerPolicyException {
    throw const WesiJobQueueException(
      'WJQ_BAD_REQUIREMENTS',
      'Persisted workload is not present in the trusted registry',
    );
  }

  const desktop = <WesiWorkerPlatform>{
    WesiWorkerPlatform.windows,
    WesiWorkerPlatform.linux,
    WesiWorkerPlatform.macos,
  };
  final weakened = value.level.index < trusted.level.index ||
      !value.requiredCapabilities.containsAll(trusted.requiredCapabilities) ||
      !value.requiredPacks.containsAll(trusted.requiredPacks) ||
      !value.allowedPlatforms.every(desktop.contains) ||
      value.minCpuCores < trusted.minCpuCores ||
      value.maxCpuLoadPercent > trusted.maxCpuLoadPercent ||
      value.minAvailableRamMb < trusted.minAvailableRamMb ||
      value.minFreeGpuVramMb < trusted.minFreeGpuVramMb ||
      value.minFreeDiskMb < trusted.minFreeDiskMb ||
      (value.level.index >= WesiWorkloadLevel.l3.index &&
          value.foregroundPolicy != WesiForegroundPolicy.foregroundRequired) ||
      (trusted.foregroundPolicy == WesiForegroundPolicy.foregroundRequired &&
          value.foregroundPolicy != WesiForegroundPolicy.foregroundRequired) ||
      value.checkpointable != trusted.checkpointable ||
      (value.remoteAllowed && !trusted.remoteAllowed) ||
      (value.allowControlPlane && !trusted.allowControlPlane);
  if (weakened) {
    throw const WesiJobQueueException(
      'WJQ_BAD_REQUIREMENTS',
      'Persisted workload requirements weaken trusted scheduling policy',
    );
  }
}

void _validateId(String value, String label) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw WesiJobQueueException(
      'WJQ_BAD_ID',
      '$label is invalid',
    );
  }
}

void _validateStage(String value) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw const WesiJobQueueException(
      'WJQ_BAD_STAGE',
      'Job stage id is invalid',
    );
  }
}

void _validateCode(String value) {
  if (!RegExp(r'^[A-Z0-9_:-]{1,128}$').hasMatch(value)) {
    throw const WesiJobQueueException(
      'WJQ_BAD_CODE',
      'Job status/failure code is invalid',
    );
  }
}

Map<String, dynamic> _requiredMap(dynamic value) {
  if (value is! Map) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted object is invalid',
    );
  }
  return value.map((key, item) => MapEntry('$key', item));
}

String _requiredString(dynamic value, int maxLength) {
  if (value is! String || value.isEmpty || value.length > maxLength) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted string is invalid',
    );
  }
  return value;
}

String? _optionalString(dynamic value, int maxLength) {
  if (value == null) return null;
  return _requiredString(value, maxLength);
}

DateTime _requiredDate(dynamic value) {
  if (value is! String) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted timestamp is invalid',
    );
  }
  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted timestamp is invalid',
    );
  }
  return parsed.toUtc();
}

DateTime? _optionalDate(dynamic value) =>
    value == null ? null : _requiredDate(value);

int _int(dynamic value) {
  if (value is! num) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted integer is invalid',
    );
  }
  return value.toInt();
}

double _number(dynamic value) {
  if (value is! num) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted number is invalid',
    );
  }
  return value.toDouble();
}

T _requiredEnum<T extends Enum>(List<T> values, dynamic raw) {
  if (raw is! String) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted enum is invalid',
    );
  }
  for (final value in values) {
    if (value.name == raw) return value;
  }
  throw const WesiJobQueueException(
    'WJQ_CORRUPT_JOURNAL',
    'Persisted enum is unknown',
  );
}

Set<T> _requiredEnumSet<T extends Enum>(List<T> values, dynamic raw) {
  if (raw is! List) {
    throw const WesiJobQueueException(
      'WJQ_CORRUPT_JOURNAL',
      'Persisted enum set is invalid',
    );
  }
  final out = <T>{};
  for (final item in raw) {
    out.add(_requiredEnum(values, item));
  }
  return Set<T>.unmodifiable(out);
}

String _safeMessage(String value) {
  final normalized = value.replaceAll(RegExp(r'[\r\n\t\u0000]'), ' ').trim();
  return normalized.length <= 512 ? normalized : normalized.substring(0, 512);
}
