import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'wesi_job_coordinator.dart';
import 'wesi_local_runtime_models.dart';
import 'wesi_remote_worker_lease_store.dart';
import 'wesi_remote_worker_models.dart';
import 'wesi_remote_worker_registry.dart';
import 'wesi_resource_scheduler_models.dart';

class WesiRemoteWorkerDispatchResult {
  final WesiDispatchDecision decision;
  final WesiRemoteWorkerLeaseRecord? lease;
  final bool assignmentQueued;

  const WesiRemoteWorkerDispatchResult({
    required this.decision,
    this.lease,
    this.assignmentQueued = false,
  });

  bool get dispatched => decision.selection.ok && lease != null;
}

/// Stage-10 Remote Worker lifecycle bridge.
///
/// Canonical job state remains owned by [WesiJobCoordinator] and its durable
/// queue. This controller adds only authenticated remote-worker transport,
/// durable lease/affinity metadata, reconnect reconciliation and fail-closed
/// worker-loss handling. Heavy work is never executed by the Control Plane.
class WesiRemoteWorkerController {
  final WesiJobCoordinator coordinator;
  final WesiRemoteWorkerRegistry registry;
  final WesiRemoteWorkerLeaseStore leases;
  final Duration leaseTtl;
  final Random _random;

  WesiRemoteWorkerController({
    required this.coordinator,
    required this.registry,
    required this.leases,
    this.leaseTtl = const Duration(seconds: 75),
    Random? random,
  }) : _random = random ?? Random.secure() {
    if (leaseTtl.inSeconds < 30 || leaseTtl.inMinutes > 10) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_LEASE_TTL',
        'Remote worker lease TTL must be between 30 seconds and 10 minutes',
      );
    }
  }

  Future<void> restore() async {
    await coordinator.restore();
    await leases.restore();
  }

  /// Applies an already-authenticated heartbeat. The credential/HMAC layer must
  /// supply [authenticatedWorkerId]; a body cannot claim a different worker.
  Future<void> acceptHeartbeat({
    required String authenticatedWorkerId,
    required WesiRemoteWorkerHeartbeat heartbeat,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    if (authenticatedWorkerId != heartbeat.profile.id) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_WORKER_IDENTITY_MISMATCH',
        'Authenticated worker does not match heartbeat identity',
      );
    }

    // Expired leases are resolved before a late heartbeat can revive them.
    await sweepExpiredLeases(now: current);
    registry.applyHeartbeat(heartbeat, now: current);

    for (final job in coordinator.jobs) {
      if (!_active(job) || job.workerId != authenticatedWorkerId) continue;
      final lease = leases.get(job.id);
      if (lease == null || lease.expiredAt(current)) continue;
      // A heartbeat proves connectivity, not durable receipt of the command.
      // Do not keep a lost/unacknowledged assignment alive forever.
      if (!lease.assignmentAcked) continue;
      await leases.renew(
        job.id,
        expiresAt: current.add(leaseTtl),
      );
    }

    await reconcileActiveAssignments(
      workerId: authenticatedWorkerId,
      now: current,
    );
  }

  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final queued = coordinator.jobs
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
      final selection = _selectForJob(job, now: current);
      if (selection.ok) {
        return _startSelected(job, selection, now: current);
      }
      firstBlocked ??= selection;
    }

    return WesiRemoteWorkerDispatchResult(
      decision: WesiDispatchDecision(
        job: queued.first,
        selection: firstBlocked ??
            const WesiWorkerSelection.blocked(
              WesiSchedulerBlockerCode.noWorkers,
              'No remote Wesi Worker is currently available.',
              remoteWarning: true,
            ),
      ),
    );
  }

  Future<WesiRemoteWorkerDispatchResult> dispatchJob(
    String jobId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final job = coordinator[jobId];
    if (job == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_JOB_NOT_FOUND',
        'Remote worker job does not exist',
      );
    }
    if (job.state != WesiScheduledJobState.queued) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_JOB_NOT_QUEUED',
        'Remote worker job is not queued',
      );
    }
    final selection = _selectForJob(job, now: current);
    if (!selection.ok) {
      return WesiRemoteWorkerDispatchResult(
        decision: WesiDispatchDecision(job: job, selection: selection),
      );
    }
    return _startSelected(job, selection, now: current);
  }

  Future<WesiRemoteWorkerDispatchResult> resumeJob(
    String jobId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final job = coordinator[jobId];
    if (job == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_JOB_NOT_FOUND',
        'Remote worker job does not exist',
      );
    }
    if (job.state != WesiScheduledJobState.paused &&
        job.state != WesiScheduledJobState.waitingForWorker &&
        job.state != WesiScheduledJobState.blocked) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_JOB_NOT_RESUMABLE',
        'Remote worker job is not resumable',
      );
    }
    await coordinator.resume(jobId, now: current);
    return dispatchJob(jobId, now: current);
  }

  /// Resumes only jobs whose durable affinity points to the reconnecting worker.
  Future<List<WesiRemoteWorkerDispatchResult>> resumeWaitingForWorker(
    String workerId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final waiting = coordinator.jobs.where((job) {
      if (job.state != WesiScheduledJobState.waitingForWorker) return false;
      return leases.get(job.id)?.workerId == workerId;
    }).toList(growable: false)
      ..sort(_compareQueuedJobs);

    final results = <WesiRemoteWorkerDispatchResult>[];
    for (final job in waiting) {
      await coordinator.resume(job.id, now: current);
      results.add(await dispatchJob(job.id, now: current));
    }
    return List<WesiRemoteWorkerDispatchResult>.unmodifiable(results);
  }

  Future<WesiScheduledJob> requestPause(
    String jobId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final job = _requireJob(jobId);
    final lease = _requireActiveLease(job, now: current);
    final updated = await coordinator.requestPause(jobId, now: current);
    _enqueueControl(
      lease,
      WesiRemoteJobMessageKind.pause,
      now: current,
    );
    return updated;
  }

  Future<WesiScheduledJob> requestCancel(
    String jobId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final before = _requireJob(jobId);
    final lease = leases.get(jobId);
    final updated = await coordinator.requestCancel(jobId, now: current);
    if (updated.state == WesiScheduledJobState.cancelled) {
      if (lease != null) await leases.remove(jobId);
      return updated;
    }
    if (!_active(before) || lease == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_ACTIVE_LEASE_REQUIRED',
        'Active remote execution is missing its lease',
      );
    }
    _validateLeaseForJob(before, lease, now: current);
    _enqueueControl(
      lease,
      WesiRemoteJobMessageKind.cancel,
      now: current,
    );
    return updated;
  }

  /// Accepts a message only after the caller authenticated the worker transport.
  /// Lease identity/generation and a durable per-generation sequence are checked
  /// again here so stale execution from an older connection cannot mutate jobs.
  Future<WesiScheduledJob> acceptWorkerMessage({
    required String authenticatedWorkerId,
    required WesiRemoteJobMessage message,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    _validateInboundEnvelope(message);
    final job = _requireJob(message.jobId);
    final lease = leases.get(job.id);
    if (lease == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_ACTIVE_LEASE_REQUIRED',
        'Remote worker message has no active lease',
      );
    }
    if (authenticatedWorkerId != lease.workerId ||
        job.workerId != authenticatedWorkerId) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_WORKER_IDENTITY_MISMATCH',
        'Remote worker message does not own this running job',
      );
    }
    _validateLeasePayload(message, lease, now: current);
    await leases.acceptInboundSequence(
      job.id,
      sequence: message.sequence,
    );

    switch (message.kind) {
      case WesiRemoteJobMessageKind.ack:
        return _acceptAck(job, lease, message, now: current);
      case WesiRemoteJobMessageKind.progress:
        return _acceptProgress(job, message, now: current);
      case WesiRemoteJobMessageKind.checkpoint:
        return _acceptCheckpoint(job, message, now: current);
      case WesiRemoteJobMessageKind.result:
        return _acceptResult(job, message, now: current);
      case WesiRemoteJobMessageKind.assignment:
      case WesiRemoteJobMessageKind.cancel:
      case WesiRemoteJobMessageKind.pause:
      case WesiRemoteJobMessageKind.resume:
        throw const WesiRemoteWorkerProtocolException(
          'WRW_BAD_INBOUND_MESSAGE_KIND',
          'This remote job message kind is Control Plane to worker only',
        );
    }
  }

  /// Reissues idempotent assignment/control messages after Control Plane restart
  /// or mailbox loss. Message ids are deterministic per lease generation.
  Future<void> reconcileActiveAssignments({
    String? workerId,
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    for (final job in coordinator.jobs) {
      if (!_active(job) || job.workerId == null) continue;
      if (workerId != null && job.workerId != workerId) continue;
      final worker = _workerById(job.workerId!, now: current);
      if (worker == null || !worker.online) continue;

      var lease = leases.get(job.id);
      if (lease == null) {
        lease = await leases.issue(
          jobId: job.id,
          workerId: job.workerId!,
          leaseId: _randomId(24),
          issuedAt: current,
          expiresAt: current.add(leaseTtl),
        );
      }
      if (lease.workerId != job.workerId || lease.expiredAt(current)) continue;

      switch (job.state) {
        case WesiScheduledJobState.running:
          _enqueueAssignment(job, lease, now: current);
        case WesiScheduledJobState.pauseRequested:
          _enqueueControl(
            lease,
            WesiRemoteJobMessageKind.pause,
            now: current,
          );
        case WesiScheduledJobState.cancelling:
          _enqueueControl(
            lease,
            WesiRemoteJobMessageKind.cancel,
            now: current,
          );
        case WesiScheduledJobState.queued:
        case WesiScheduledJobState.paused:
        case WesiScheduledJobState.waitingForWorker:
        case WesiScheduledJobState.cancelled:
        case WesiScheduledJobState.succeeded:
        case WesiScheduledJobState.failed:
        case WesiScheduledJobState.blocked:
          break;
      }
    }
  }

  /// Resolves lease expiry fail-closed. A checkpointable job may enter
  /// waiting_for_worker only when its checkpoint matches current progress/stage;
  /// otherwise automatic replay could duplicate writes/destructive side effects.
  Future<List<String>> sweepExpiredLeases({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final affected = <String>[];
    for (final lease in leases.records.toList(growable: false)) {
      if (!lease.expiredAt(current)) continue;
      final job = coordinator[lease.jobId];
      if (job == null || job.terminal) {
        await leases.remove(lease.jobId);
        continue;
      }
      if (!_active(job)) continue;
      affected.add(job.id);

      if (job.workerId != lease.workerId) {
        await coordinator.fail(
          job.id,
          failureCode: 'WRW_LEASE_WORKER_MISMATCH',
          message: 'Remote worker lease no longer matches active job ownership',
          now: current,
        );
        await leases.remove(job.id);
        continue;
      }

      if (job.state == WesiScheduledJobState.cancelling) {
        await coordinator.markCancelled(job.id, now: current);
        await leases.remove(job.id);
        continue;
      }

      final checkpointCurrent = _checkpointCurrent(job);
      if (job.state == WesiScheduledJobState.pauseRequested) {
        if (checkpointCurrent) {
          await coordinator.markPaused(job.id, now: current);
        } else {
          await coordinator.fail(
            job.id,
            failureCode: 'WRW_WORKER_LOST_UNCHECKPOINTED',
            message:
                'Remote worker disappeared before a durable pause checkpoint was saved',
            now: current,
          );
          await leases.remove(job.id);
        }
        continue;
      }

      if (job.requirements.checkpointable && !checkpointCurrent) {
        await coordinator.fail(
          job.id,
          failureCode: 'WRW_WORKER_LOST_UNCHECKPOINTED',
          message:
              'Remote worker disappeared before a current durable checkpoint was saved',
          now: current,
        );
        await leases.remove(job.id);
        continue;
      }

      // Only non-checkpointable READ work is safe to replay after an unknown
      // worker loss. WRITE/DESTRUCTIVE work may already have changed state.
      final risk =
          WesiLocalCapabilityRegistry.get(job.requirements.toolName)?.risk;
      if (!job.requirements.checkpointable && risk != WesiLocalRisk.read) {
        await coordinator.fail(
          job.id,
          failureCode: 'WRW_WORKER_LOST_UNCHECKPOINTED',
          message:
              'Remote worker disappeared during non-checkpointable state-changing work',
          now: current,
        );
        await leases.remove(job.id);
        continue;
      }

      await coordinator.waitForWorker(
        job.id,
        reason:
            'Remote worker lease expired; reopen WesiOS on the paired computer to continue',
        now: current,
      );
    }
    return List<String>.unmodifiable(affected);
  }

  WesiWorkerSelection _selectForJob(
    WesiScheduledJob job, {
    required DateTime now,
  }) {
    final workers = registry.schedulerWorkers(now: now);
    final affinity = leases.get(job.id)?.workerId;
    final candidates = affinity == null
        ? workers
        : workers.where((worker) => worker.id == affinity).toList();
    if (affinity != null && candidates.isEmpty) {
      return const WesiWorkerSelection.blocked(
        WesiSchedulerBlockerCode.offline,
        'The paired execution worker required by this job is unavailable. Open WesiOS on that computer to continue.',
        remoteWarning: true,
      );
    }
    final effective =
        candidates.map(_withCoordinatorLoad).toList(growable: false);
    return coordinator.scheduler.select(
      job: job.requirements,
      workers: effective,
    );
  }

  Future<WesiRemoteWorkerDispatchResult> _startSelected(
    WesiScheduledJob job,
    WesiWorkerSelection selection, {
    required DateTime now,
  }) async {
    final worker = selection.worker;
    if (worker == null || !worker.remoteWorker) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_REMOTE_WORKER_REQUIRED',
        'Stage-10 controller can dispatch only to registered remote workers',
      );
    }

    final started = await coordinator.queue.markRunning(
      job.id,
      workerId: worker.id,
      now: now,
    );

    late final WesiRemoteWorkerLeaseRecord lease;
    try {
      lease = await leases.issue(
        jobId: job.id,
        workerId: worker.id,
        leaseId: _randomId(24),
        issuedAt: now,
        expiresAt: now.add(leaseTtl),
      );
    } catch (_) {
      await coordinator.fail(
        job.id,
        failureCode: 'WRW_LEASE_PERSIST_FAILED',
        message: 'Remote execution could not persist its durable lease',
        now: now,
      );
      rethrow;
    }

    var queued = true;
    try {
      _enqueueAssignment(started, lease, now: now);
    } on WesiRemoteWorkerProtocolException {
      // Keep the durable running job + lease. Reconciliation can safely retry a
      // deterministic assignment after mailbox/heartbeat recovery.
      queued = false;
    }

    return WesiRemoteWorkerDispatchResult(
      decision: WesiDispatchDecision(job: started, selection: selection),
      lease: lease,
      assignmentQueued: queued,
    );
  }

  Future<WesiScheduledJob> _acceptAck(
    WesiScheduledJob job,
    WesiRemoteWorkerLeaseRecord lease,
    WesiRemoteJobMessage message, {
    required DateTime now,
  }) async {
    final ackedMessageId = '${message.payload['ackedMessageId'] ?? ''}'.trim();
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(ackedMessageId)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_ACK',
        'Remote worker acknowledgement is invalid',
      );
    }
    registry.ack(lease.workerId, ackedMessageId);

    if (ackedMessageId ==
        _messageId(WesiRemoteJobMessageKind.assignment, lease)) {
      await leases.markAssignmentAcked(job.id);
    }
    if (job.state == WesiScheduledJobState.cancelling &&
        ackedMessageId == _messageId(WesiRemoteJobMessageKind.cancel, lease)) {
      final cancelled = await coordinator.markCancelled(job.id, now: now);
      await leases.remove(job.id);
      return cancelled;
    }
    return coordinator[job.id]!;
  }

  Future<WesiScheduledJob> _acceptProgress(
    WesiScheduledJob job,
    WesiRemoteJobMessage message, {
    required DateTime now,
  }) async {
    if (job.state != WesiScheduledJobState.running &&
        job.state != WesiScheduledJobState.pauseRequested) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_JOB_STATE',
        'Remote progress is not valid for the current job state',
      );
    }
    final rawProgress = message.payload['progress'];
    final stage = '${message.payload['stage'] ?? ''}'.trim();
    if (rawProgress is! num ||
        rawProgress.isNaN ||
        rawProgress.isInfinite ||
        stage.isEmpty ||
        stage.length > 128) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PROGRESS',
        'Remote worker progress payload is invalid',
      );
    }
    return coordinator.updateProgress(
      job.id,
      progress: rawProgress.toDouble(),
      stage: stage,
      now: now,
    );
  }

  Future<WesiScheduledJob> _acceptCheckpoint(
    WesiScheduledJob job,
    WesiRemoteJobMessage message, {
    required DateTime now,
  }) async {
    if (job.state != WesiScheduledJobState.running &&
        job.state != WesiScheduledJobState.pauseRequested) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_JOB_STATE',
        'Remote checkpoint is not valid for the current job state',
      );
    }
    final checkpointId = '${message.payload['checkpointId'] ?? ''}'.trim();
    final version = message.payload['version'];
    final stage = '${message.payload['stage'] ?? ''}'.trim();
    final progress = message.payload['progress'];
    if (version is! num ||
        version.isNaN ||
        version.isInfinite ||
        version.toInt().toDouble() != version.toDouble() ||
        progress is! num ||
        progress.isNaN ||
        progress.isInfinite) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_CHECKPOINT',
        'Remote worker checkpoint payload is invalid',
      );
    }
    final checkpoint = WesiJobCheckpointRef(
      checkpointId: checkpointId,
      version: version.toInt(),
      stage: stage,
      progress: progress.toDouble(),
      createdAt: now,
    );
    var updated = await coordinator.checkpoint(
      job.id,
      checkpoint: checkpoint,
      now: now,
    );
    if (job.state == WesiScheduledJobState.pauseRequested) {
      updated = await coordinator.markPaused(job.id, now: now);
    }
    return updated;
  }

  Future<WesiScheduledJob> _acceptResult(
    WesiScheduledJob job,
    WesiRemoteJobMessage message, {
    required DateTime now,
  }) async {
    final success = message.payload['success'];
    if (success is! bool) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_RESULT',
        'Remote worker result payload is invalid',
      );
    }
    if (job.state == WesiScheduledJobState.cancelling) {
      final cancelled = await coordinator.markCancelled(job.id, now: now);
      await leases.remove(job.id);
      return cancelled;
    }
    if (job.state != WesiScheduledJobState.running) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_JOB_STATE',
        'Remote worker result is not valid for the current job state',
      );
    }
    if (success) {
      final completed = await coordinator.complete(job.id, now: now);
      await leases.remove(job.id);
      return completed;
    }
    final rawMessage =
        '${message.payload['message'] ?? 'Remote execution failed'}'
            .replaceAll(RegExp(r'[\r\n\t\u0000]'), ' ')
            .trim();
    final safeMessage =
        rawMessage.length <= 512 ? rawMessage : rawMessage.substring(0, 512);
    final failed = await coordinator.fail(
      job.id,
      failureCode: 'WRW_REMOTE_EXECUTION_FAILED',
      message: safeMessage.isEmpty ? 'Remote execution failed' : safeMessage,
      now: now,
    );
    await leases.remove(job.id);
    return failed;
  }

  void _validateInboundEnvelope(WesiRemoteJobMessage message) {
    final idPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
    if (!idPattern.hasMatch(message.messageId) ||
        !idPattern.hasMatch(message.jobId) ||
        message.sequence < 0 ||
        message.payload.length > 64) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_JOB_MESSAGE',
        'Remote worker message envelope is invalid',
      );
    }
  }

  void _validateLeasePayload(
    WesiRemoteJobMessage message,
    WesiRemoteWorkerLeaseRecord lease, {
    required DateTime now,
  }) {
    final leaseId = '${message.payload['leaseId'] ?? ''}'.trim();
    final generation = message.payload['generation'];
    if (lease.expiredAt(now) ||
        leaseId != lease.leaseId ||
        generation is! num ||
        generation.toInt().toDouble() != generation.toDouble() ||
        generation.toInt() != lease.generation) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_STALE_LEASE',
        'Remote worker message belongs to an expired or superseded lease',
      );
    }
  }

  WesiScheduledJob _requireJob(String jobId) {
    final job = coordinator[jobId];
    if (job == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_JOB_NOT_FOUND',
        'Remote worker job does not exist',
      );
    }
    return job;
  }

  WesiRemoteWorkerLeaseRecord _requireActiveLease(
    WesiScheduledJob job, {
    required DateTime now,
  }) {
    final lease = leases.get(job.id);
    if (lease == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_ACTIVE_LEASE_REQUIRED',
        'Active remote execution is missing its lease',
      );
    }
    _validateLeaseForJob(job, lease, now: now);
    return lease;
  }

  void _validateLeaseForJob(
    WesiScheduledJob job,
    WesiRemoteWorkerLeaseRecord lease, {
    required DateTime now,
  }) {
    if (job.workerId == null ||
        job.workerId != lease.workerId ||
        lease.expiredAt(now)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_STALE_LEASE',
        'Remote worker lease is expired or does not own the active job',
      );
    }
  }

  void _enqueueAssignment(
    WesiScheduledJob job,
    WesiRemoteWorkerLeaseRecord lease, {
    required DateTime now,
  }) {
    final checkpoint = job.checkpoint;
    registry.enqueueToWorker(
      lease.workerId,
      WesiRemoteJobMessage(
        messageId: _messageId(WesiRemoteJobMessageKind.assignment, lease),
        jobId: job.id,
        kind: WesiRemoteJobMessageKind.assignment,
        sequence: _outboundSequence(
          WesiRemoteJobMessageKind.assignment,
          lease.generation,
        ),
        createdAt: now,
        payload: <String, dynamic>{
          'leaseId': lease.leaseId,
          'generation': lease.generation,
          'leaseExpiresAt': lease.expiresAt.toUtc().toIso8601String(),
          'toolName': job.requirements.toolName,
          'level': job.requirements.level.name,
          'foregroundRequired': job.requirements.foregroundPolicy ==
              WesiForegroundPolicy.foregroundRequired,
          if (checkpoint != null)
            'checkpoint': <String, dynamic>{
              'checkpointId': checkpoint.checkpointId,
              'version': checkpoint.version,
              'stage': checkpoint.stage,
              'progress': checkpoint.progress,
            },
        },
      ),
    );
  }

  void _enqueueControl(
    WesiRemoteWorkerLeaseRecord lease,
    WesiRemoteJobMessageKind kind, {
    required DateTime now,
  }) {
    if (kind != WesiRemoteJobMessageKind.pause &&
        kind != WesiRemoteJobMessageKind.cancel &&
        kind != WesiRemoteJobMessageKind.resume) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_CONTROL_MESSAGE',
        'Unsupported remote worker control message',
      );
    }
    registry.enqueueToWorker(
      lease.workerId,
      WesiRemoteJobMessage(
        messageId: _messageId(kind, lease),
        jobId: lease.jobId,
        kind: kind,
        sequence: _outboundSequence(kind, lease.generation),
        createdAt: now,
        payload: <String, dynamic>{
          'leaseId': lease.leaseId,
          'generation': lease.generation,
          'leaseExpiresAt': lease.expiresAt.toUtc().toIso8601String(),
        },
      ),
    );
  }

  WesiWorkerResourceProfile? _workerById(
    String workerId, {
    required DateTime now,
  }) {
    for (final worker in registry.schedulerWorkers(now: now)) {
      if (worker.id == workerId) return worker;
    }
    return null;
  }

  WesiWorkerResourceProfile _withCoordinatorLoad(
    WesiWorkerResourceProfile worker,
  ) {
    var light = worker.activeLightJobs;
    var cpu = worker.activeCpuJobs;
    var heavy = worker.activeHeavyJobs;
    var gpu = worker.activeGpuJobs;
    for (final job in coordinator.jobs) {
      if (job.workerId != worker.id || !_active(job)) continue;
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

  String _messageId(
    WesiRemoteJobMessageKind kind,
    WesiRemoteWorkerLeaseRecord lease,
  ) {
    final input = '${kind.name}|${lease.jobId}|${lease.workerId}|'
        '${lease.leaseId}|${lease.generation}';
    final digest = sha256.convert(utf8.encode(input)).toString();
    return 'wrw-${digest.substring(0, 48)}';
  }

  int _outboundSequence(WesiRemoteJobMessageKind kind, int generation) {
    final suffix = switch (kind) {
      WesiRemoteJobMessageKind.assignment => 1,
      WesiRemoteJobMessageKind.pause => 2,
      WesiRemoteJobMessageKind.cancel => 3,
      WesiRemoteJobMessageKind.resume => 4,
      WesiRemoteJobMessageKind.progress => 5,
      WesiRemoteJobMessageKind.checkpoint => 6,
      WesiRemoteJobMessageKind.result => 7,
      WesiRemoteJobMessageKind.ack => 8,
    };
    return generation * 10 + suffix;
  }

  String _randomId(int bytes) {
    final data = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      data[i] = _random.nextInt(256);
    }
    return base64Url.encode(data).replaceAll('=', '');
  }

  static bool _active(WesiScheduledJob job) =>
      job.state == WesiScheduledJobState.running ||
      job.state == WesiScheduledJobState.pauseRequested ||
      job.state == WesiScheduledJobState.cancelling;

  static bool _checkpointCurrent(WesiScheduledJob job) {
    final checkpoint = job.checkpoint;
    return checkpoint != null &&
        checkpoint.progress == job.progress &&
        checkpoint.stage == job.currentStage;
  }

  static int _compareQueuedJobs(WesiScheduledJob a, WesiScheduledJob b) {
    final priority = b.priority.index.compareTo(a.priority.index);
    if (priority != 0) return priority;
    final queued = a.queuedAt.compareTo(b.queuedAt);
    if (queued != 0) return queued;
    return a.id.compareTo(b.id);
  }
}
