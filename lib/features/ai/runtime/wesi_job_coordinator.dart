import 'dart:collection';

import 'wesi_resource_scheduler.dart';
import 'wesi_resource_scheduler_models.dart';

class WesiJobCoordinator {
  static const int _maxEvents = 200;
  static const int _maxMessageLength = 512;
  static const int _maxStageLength = 160;

  final WesiResourceScheduler scheduler;
  final Map<String, WesiScheduledJob> _jobs = <String, WesiScheduledJob>{};

  WesiJobCoordinator({
    this.scheduler = const WesiResourceScheduler(),
  });

  UnmodifiableListView<WesiScheduledJob> get jobs =>
      UnmodifiableListView<WesiScheduledJob>(
        _jobs.values.toList(growable: false)
          ..sort((a, b) => a.queuedAt.compareTo(b.queuedAt)),
      );

  WesiScheduledJob? operator [](String id) => _jobs[id];

  WesiScheduledJob enqueue({
    required String id,
    required WesiJobRequirements requirements,
    WesiJobPriority priority = WesiJobPriority.normal,
    DateTime? now,
  }) {
    _validateJobId(id);
    if (_jobs.containsKey(id)) {
      throw const WesiSchedulerPolicyException(
        'WS_DUPLICATE_JOB',
        'Job id already exists',
      );
    }
    final at = now ?? DateTime.now().toUtc();
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
    _jobs[id] = job;
    return job;
  }

  WesiDispatchDecision nextDecision({
    required List<WesiWorkerResourceProfile> workers,
    DateTime? now,
  }) {
    final queued = _jobs.values
        .where((job) => job.state == WesiScheduledJobState.queued)
        .toList(growable: false)
      ..sort(_compareQueuedJobs);
    if (queued.isEmpty) {
      throw const WesiSchedulerPolicyException(
        'WS_QUEUE_EMPTY',
        'There are no queued jobs',
      );
    }

    WesiWorkerSelection? lastBlocked;
    for (final job in queued) {
      final effective = workers
          .map((worker) => _withCoordinatorLoad(worker))
          .toList(growable: false);
      final selection = scheduler.select(
        job: job.requirements,
        workers: effective,
      );
      if (selection.ok) {
        return WesiDispatchDecision(job: job, selection: selection);
      }
      lastBlocked = selection;
    }
    return WesiDispatchDecision(
      job: queued.first,
      selection: lastBlocked ??
          const WesiWorkerSelection.blocked(
            WesiSchedulerBlockerCode.noWorkers,
            'No worker is currently available.',
          ),
    );
  }

  WesiScheduledJob start(
    String jobId,
    String workerId, {
    DateTime? now,
  }) {
    final job = _require(jobId);
    _requireState(job, const <WesiScheduledJobState>{WesiScheduledJobState.queued});
    if (workerId.trim().isEmpty || workerId.length > 160) {
      throw const WesiSchedulerPolicyException(
        'WS_BAD_WORKER_ID',
        'Worker id is invalid',
      );
    }
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.running,
        updatedAt: at,
        workerId: workerId,
        startedAt: at,
        finishedAt: null,
        failureCode: null,
        events: _appendEvent(
          job,
          WesiJobEventKind.started,
          at,
          'Job started',
        ),
      ),
    );
  }

  WesiScheduledJob updateProgress(
    String jobId, {
    required double progress,
    required String stage,
    DateTime? now,
  }) {
    final job = _require(jobId);
    _requireState(
      job,
      const <WesiScheduledJobState>{
        WesiScheduledJobState.running,
        WesiScheduledJobState.pauseRequested,
      },
    );
    if (!progress.isFinite || progress < 0 || progress > 1) {
      throw const WesiSchedulerPolicyException(
        'WS_BAD_PROGRESS',
        'Progress must be between 0 and 1',
      );
    }
    final cleanStage = _sanitize(stage, _maxStageLength, 'stage');
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        progress: progress,
        currentStage: cleanStage,
        updatedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.progress,
          at,
          'Progress ${(progress * 100).round()}%: $cleanStage',
        ),
      ),
    );
  }

  WesiScheduledJob requestPause(String jobId, {DateTime? now}) {
    final job = _require(jobId);
    _requireState(job, const <WesiScheduledJobState>{WesiScheduledJobState.running});
    if (!job.requirements.checkpointable) {
      throw const WesiSchedulerPolicyException(
        'WS_NOT_CHECKPOINTABLE',
        'This workload cannot be safely paused',
      );
    }
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.pauseRequested,
        updatedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.pauseRequested,
          at,
          'Pause requested',
        ),
      ),
    );
  }

  WesiScheduledJob markPaused(
    String jobId,
    WesiJobCheckpointRef checkpoint, {
    DateTime? now,
  }) {
    checkpoint.validate();
    final job = _require(jobId);
    _requireState(
      job,
      const <WesiScheduledJobState>{WesiScheduledJobState.pauseRequested},
    );
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.paused,
        checkpoint: checkpoint,
        updatedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.checkpointed,
          at,
          'Checkpoint saved',
          thenKind: WesiJobEventKind.paused,
          thenMessage: 'Job paused',
        ),
      ),
    );
  }

  WesiScheduledJob resume(String jobId, {DateTime? now}) {
    final job = _require(jobId);
    _requireState(job, const <WesiScheduledJobState>{WesiScheduledJobState.paused});
    if (job.checkpoint == null) {
      throw const WesiSchedulerPolicyException(
        'WS_CHECKPOINT_REQUIRED',
        'Paused job does not have a verified checkpoint',
      );
    }
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.queued,
        updatedAt: at,
        workerId: null,
        startedAt: null,
        finishedAt: null,
        events: _appendEvent(
          job,
          WesiJobEventKind.resumed,
          at,
          'Job resumed and queued',
        ),
      ),
    );
  }

  WesiScheduledJob requestCancel(String jobId, {DateTime? now}) {
    final job = _require(jobId);
    if (job.terminal) return job;
    final at = now ?? DateTime.now().toUtc();
    if (job.state == WesiScheduledJobState.queued ||
        job.state == WesiScheduledJobState.paused ||
        job.state == WesiScheduledJobState.blocked) {
      return _store(
        job.copyWith(
          state: WesiScheduledJobState.cancelled,
          updatedAt: at,
          finishedAt: at,
          events: _appendEvent(
            job,
            WesiJobEventKind.cancelled,
            at,
            'Job cancelled before execution',
          ),
        ),
      );
    }
    _requireState(
      job,
      const <WesiScheduledJobState>{
        WesiScheduledJobState.running,
        WesiScheduledJobState.pauseRequested,
      },
    );
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.cancelling,
        updatedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.cancelRequested,
          at,
          'Cancellation requested',
        ),
      ),
    );
  }

  WesiScheduledJob markCancelled(String jobId, {DateTime? now}) {
    final job = _require(jobId);
    _requireState(
      job,
      const <WesiScheduledJobState>{WesiScheduledJobState.cancelling},
    );
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.cancelled,
        updatedAt: at,
        finishedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.cancelled,
          at,
          'Job cancelled',
        ),
      ),
    );
  }

  WesiScheduledJob complete(String jobId, {DateTime? now}) {
    final job = _require(jobId);
    _requireState(
      job,
      const <WesiScheduledJobState>{
        WesiScheduledJobState.running,
        WesiScheduledJobState.pauseRequested,
      },
    );
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.succeeded,
        progress: 1,
        updatedAt: at,
        finishedAt: at,
        failureCode: null,
        events: _appendEvent(
          job,
          WesiJobEventKind.succeeded,
          at,
          'Job completed',
        ),
      ),
    );
  }

  WesiScheduledJob fail(
    String jobId, {
    required String failureCode,
    String message = 'Job failed',
    DateTime? now,
  }) {
    final job = _require(jobId);
    if (job.terminal) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_STATE',
        'Terminal job cannot fail again',
      );
    }
    final cleanCode = _sanitize(failureCode, 128, 'failureCode');
    final cleanMessage = _sanitize(message, _maxMessageLength, 'message');
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.failed,
        updatedAt: at,
        finishedAt: at,
        failureCode: cleanCode,
        events: _appendEvent(
          job,
          WesiJobEventKind.failed,
          at,
          cleanMessage,
        ),
      ),
    );
  }

  WesiScheduledJob markBlocked(
    String jobId, {
    required String message,
    DateTime? now,
  }) {
    final job = _require(jobId);
    _requireState(job, const <WesiScheduledJobState>{WesiScheduledJobState.queued});
    final at = now ?? DateTime.now().toUtc();
    return _store(
      job.copyWith(
        state: WesiScheduledJobState.blocked,
        updatedAt: at,
        events: _appendEvent(
          job,
          WesiJobEventKind.blocked,
          at,
          _sanitize(message, _maxMessageLength, 'message'),
        ),
      ),
    );
  }

  WesiWorkerResourceProfile _withCoordinatorLoad(
    WesiWorkerResourceProfile worker,
  ) {
    var light = worker.activeLightJobs;
    var cpu = worker.activeCpuJobs;
    var heavy = worker.activeHeavyJobs;
    var gpu = worker.activeGpuJobs;
    for (final job in _jobs.values) {
      if (job.workerId != worker.id ||
          (job.state != WesiScheduledJobState.running &&
              job.state != WesiScheduledJobState.pauseRequested &&
              job.state != WesiScheduledJobState.cancelling)) {
        continue;
      }
      switch (job.requirements.level) {
        case WesiWorkloadLevel.l0:
        case WesiWorkloadLevel.l1:
          light++;
        case WesiWorkloadLevel.l2:
          cpu++;
        case WesiWorkloadLevel.l3:
          heavy++;
        case WesiWorkloadLevel.l4:
          heavy++;
          gpu++;
      }
    }
    return WesiWorkerResourceProfile(
      id: worker.id,
      name: worker.name,
      platform: worker.platform,
      status: worker.status,
      trust: worker.trust,
      localDevice: worker.localDevice,
      policyAllowed: worker.policyAllowed,
      appForeground: worker.appForeground,
      backgroundExecutionAllowed: worker.backgroundExecutionAllowed,
      cpuCores: worker.cpuCores,
      ramMb: worker.ramMb,
      gpuVramMb: worker.gpuVramMb,
      freeDiskMb: worker.freeDiskMb,
      capabilities: worker.capabilities,
      installedPacks: worker.installedPacks,
      activeLightJobs: light,
      activeCpuJobs: cpu,
      activeHeavyJobs: heavy,
      activeGpuJobs: gpu,
      lastSeenAt: worker.lastSeenAt,
    );
  }

  int _compareQueuedJobs(WesiScheduledJob a, WesiScheduledJob b) {
    final priority = _priorityWeight(b.priority).compareTo(_priorityWeight(a.priority));
    if (priority != 0) return priority;
    final time = a.queuedAt.compareTo(b.queuedAt);
    if (time != 0) return time;
    return a.id.compareTo(b.id);
  }

  int _priorityWeight(WesiJobPriority priority) {
    switch (priority) {
      case WesiJobPriority.low:
        return 0;
      case WesiJobPriority.normal:
        return 1;
      case WesiJobPriority.high:
        return 2;
      case WesiJobPriority.urgent:
        return 3;
    }
  }

  WesiScheduledJob _require(String id) {
    final job = _jobs[id];
    if (job == null) {
      throw const WesiSchedulerPolicyException(
        'WS_JOB_NOT_FOUND',
        'Job was not found',
      );
    }
    return job;
  }

  void _requireState(
    WesiScheduledJob job,
    Set<WesiScheduledJobState> allowed,
  ) {
    if (!allowed.contains(job.state)) {
      throw WesiSchedulerPolicyException(
        'WS_INVALID_STATE',
        'Job ${job.id} cannot transition from ${job.state.name}',
      );
    }
  }

  WesiScheduledJob _store(WesiScheduledJob job) {
    _jobs[job.id] = job;
    return job;
  }

  List<WesiJobEvent> _appendEvent(
    WesiScheduledJob job,
    WesiJobEventKind kind,
    DateTime at,
    String message, {
    WesiJobEventKind? thenKind,
    String? thenMessage,
  }) {
    final events = <WesiJobEvent>[...job.events];
    events.add(WesiJobEvent(
      kind: kind,
      at: at,
      message: _sanitize(message, _maxMessageLength, 'message'),
    ));
    if (thenKind != null) {
      events.add(WesiJobEvent(
        kind: thenKind,
        at: at,
        message: _sanitize(
          thenMessage ?? thenKind.name,
          _maxMessageLength,
          'message',
        ),
      ));
    }
    if (events.length > _maxEvents) {
      return events.sublist(events.length - _maxEvents);
    }
    return List<WesiJobEvent>.unmodifiable(events);
  }

  String _sanitize(String value, int maxLength, String field) {
    final clean = value
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
        .trim();
    if (clean.isEmpty || clean.length > maxLength) {
      throw WesiSchedulerPolicyException(
        'WS_BAD_METADATA',
        '$field is empty or exceeds its limit',
      );
    }
    return clean;
  }

  void _validateJobId(String id) {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(id)) {
      throw const WesiSchedulerPolicyException(
        'WS_BAD_JOB_ID',
        'Job id is invalid',
      );
    }
  }
}
