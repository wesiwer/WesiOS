import 'wesi_job_queue.dart';
import 'wesi_resource_scheduler.dart';
import 'wesi_resource_scheduler_models.dart';

/// Trusted Stage-8 bridge between durable job state and worker selection.
///
/// The coordinator deliberately does not own a second in-memory queue. All job
/// mutations go through [WesiDurableJobQueue], so restart recovery, checkpoint
/// rules and scheduling observe the same source of truth.
class WesiJobCoordinator {
  final WesiResourceScheduler scheduler;
  final WesiDurableJobQueue queue;

  const WesiJobCoordinator({
    required this.queue,
    this.scheduler = const WesiResourceScheduler(),
  });

  Future<void> restore() => queue.restore();

  List<WesiScheduledJob> get jobs => queue.jobs;

  WesiScheduledJob? operator [](String id) => queue.get(id);

  Future<WesiScheduledJob> enqueue({
    required String id,
    required WesiJobRequirements requirements,
    WesiJobPriority priority = WesiJobPriority.normal,
    DateTime? now,
  }) =>
      queue.enqueue(
        id: id,
        requirements: requirements,
        priority: priority,
        now: now,
      );

  /// Selects the first schedulable queued job in priority/FIFO order.
  ///
  /// A blocked job is not mutated here: resource/worker availability can be
  /// transient. Callers can surface [selection.blocker] while the queue remains
  /// durable and eligible for a later retry.
  WesiDispatchDecision nextDecision({
    required List<WesiWorkerResourceProfile> workers,
  }) {
    final queued = queue.jobs
        .where((job) => job.state == WesiScheduledJobState.queued)
        .toList(growable: false)
      ..sort(_compareQueuedJobs);
    if (queued.isEmpty) {
      throw const WesiSchedulerPolicyException(
        'WS_QUEUE_EMPTY',
        'There are no queued jobs',
      );
    }

    WesiWorkerSelection? firstBlocked;
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
      firstBlocked ??= selection;
    }
    return WesiDispatchDecision(
      job: queued.first,
      selection: firstBlocked ??
          const WesiWorkerSelection.blocked(
            WesiSchedulerBlockerCode.noWorkers,
            'No worker is currently available.',
          ),
    );
  }

  /// Atomically performs a scheduling decision and persists the selected job as
  /// running. If no worker is eligible, no job state is changed.
  Future<WesiDispatchDecision> dispatchNext({
    required List<WesiWorkerResourceProfile> workers,
    DateTime? now,
  }) async {
    final decision = nextDecision(workers: workers);
    final worker = decision.selection.worker;
    if (worker == null) return decision;
    final started = await queue.markRunning(
      decision.job.id,
      workerId: worker.id,
      now: now,
    );
    return WesiDispatchDecision(
      job: started,
      selection: decision.selection,
    );
  }

  Future<WesiScheduledJob> updateProgress(
    String jobId, {
    required double progress,
    required String stage,
    DateTime? now,
  }) =>
      queue.updateProgress(
        jobId,
        progress: progress,
        stage: stage,
        now: now,
      );

  Future<WesiScheduledJob> checkpoint(
    String jobId, {
    required WesiJobCheckpointRef checkpoint,
    DateTime? now,
  }) =>
      queue.checkpoint(
        jobId,
        checkpoint: checkpoint,
        now: now,
      );

  Future<WesiScheduledJob> requestPause(
    String jobId, {
    DateTime? now,
  }) =>
      queue.requestPause(jobId, now: now);

  Future<WesiScheduledJob> markPaused(
    String jobId, {
    DateTime? now,
  }) =>
      queue.markPaused(jobId, now: now);

  Future<WesiScheduledJob> waitForWorker(
    String jobId, {
    String reason = 'Execution worker is unavailable',
    DateTime? now,
  }) =>
      queue.waitForWorker(jobId, reason: reason, now: now);

  Future<WesiScheduledJob> resume(
    String jobId, {
    DateTime? now,
  }) =>
      queue.resume(jobId, now: now);

  Future<WesiScheduledJob> markBlocked(
    String jobId, {
    required WesiSchedulerBlockerCode code,
    required String message,
    DateTime? now,
  }) =>
      queue.block(
        jobId,
        code: 'WS_${code.name.toUpperCase()}',
        message: message,
        now: now,
      );

  Future<WesiScheduledJob> requestCancel(
    String jobId, {
    DateTime? now,
  }) =>
      queue.requestCancel(jobId, now: now);

  Future<WesiScheduledJob> markCancelled(
    String jobId, {
    DateTime? now,
  }) =>
      queue.markCancelled(jobId, now: now);

  Future<WesiScheduledJob> complete(
    String jobId, {
    DateTime? now,
  }) =>
      queue.succeed(jobId, now: now);

  Future<WesiScheduledJob> fail(
    String jobId, {
    required String failureCode,
    String message = 'Job failed',
    DateTime? now,
  }) =>
      queue.fail(
        jobId,
        code: failureCode,
        message: message,
        now: now,
      );

  WesiWorkerResourceProfile _withCoordinatorLoad(
    WesiWorkerResourceProfile worker,
  ) {
    var light = worker.activeLightJobs;
    var cpu = worker.activeCpuJobs;
    var heavy = worker.activeHeavyJobs;
    var gpu = worker.activeGpuJobs;
    for (final job in queue.jobs) {
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
          if (job.requirements.gpuRequired) gpu++;
      }
    }

    return WesiWorkerResourceProfile(
      id: worker.id,
      name: worker.name,
      platform: worker.platform,
      status: worker.status,
      trust: worker.trust,
      role: worker.role,
      policyAllowed: worker.policyAllowed,
      appForeground: worker.appForeground,
      backgroundExecutionAllowed: worker.backgroundExecutionAllowed,
      cpuCores: worker.cpuCores,
      cpuLoadPercent: worker.cpuLoadPercent,
      totalRamMb: worker.totalRamMb,
      availableRamMb: worker.availableRamMb,
      gpuName: worker.gpuName,
      totalGpuVramMb: worker.totalGpuVramMb,
      freeGpuVramMb: worker.freeGpuVramMb,
      freeDiskMb: worker.freeDiskMb,
      thermalState: worker.thermalState,
      powerMode: worker.powerMode,
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
    final priority = b.priority.index.compareTo(a.priority.index);
    if (priority != 0) return priority;
    final time = a.queuedAt.compareTo(b.queuedAt);
    if (time != 0) return time;
    return a.id.compareTo(b.id);
  }
}
