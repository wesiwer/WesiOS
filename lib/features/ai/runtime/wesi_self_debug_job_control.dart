import 'wesi_job_coordinator.dart';
import 'wesi_resource_scheduler_models.dart';
import 'wesi_self_debug_checkpoint.dart';

/// Stage-9 control bridge over the Stage-8 durable job lifecycle.
///
/// This class never owns a second job state machine. It only observes/mutates
/// the existing [WesiJobCoordinator] and writes a Stage-8 checkpoint before a
/// safe pause or worker-loss transition.
class WesiSelfDebugJobControl implements WesiSelfDebugExecutionControl {
  final WesiJobCoordinator coordinator;
  final String jobId;

  const WesiSelfDebugJobControl({
    required this.coordinator,
    required this.jobId,
  });

  @override
  Future<void> guard(WesiSelfDebugCheckpointManager checkpoint) async {
    final job = _requireJob(checkpoint);
    switch (job.state) {
      case WesiScheduledJobState.running:
        return;
      case WesiScheduledJobState.pauseRequested:
        await _persistStage8Checkpoint(job, checkpoint);
        await coordinator.markPaused(jobId);
        throw _stop(
          checkpoint,
          'WSD_PAUSED',
          'Self-debug job paused after a durable checkpoint',
        );
      case WesiScheduledJobState.paused:
        throw _stop(
          checkpoint,
          'WSD_PAUSED',
          'Self-debug job is paused',
        );
      case WesiScheduledJobState.waitingForWorker:
        throw _stop(
          checkpoint,
          'WSD_WAITING_FOR_WORKER',
          'Self-debug job is waiting for its execution worker',
        );
      case WesiScheduledJobState.cancelling:
        await coordinator.markCancelled(jobId);
        throw _stop(
          checkpoint,
          'WSD_CANCELLED',
          'Self-debug job was cancelled',
          blocked: false,
        );
      case WesiScheduledJobState.cancelled:
        throw _stop(
          checkpoint,
          'WSD_CANCELLED',
          'Self-debug job is cancelled',
          blocked: false,
        );
      case WesiScheduledJobState.queued:
        throw _stop(
          checkpoint,
          'WSD_JOB_NOT_RUNNING',
          'Self-debug job must be dispatched before execution',
        );
      case WesiScheduledJobState.blocked:
        throw _stop(
          checkpoint,
          'WSD_JOB_BLOCKED',
          'Stage-8 scheduler job is blocked',
        );
      case WesiScheduledJobState.succeeded:
      case WesiScheduledJobState.failed:
        throw _stop(
          checkpoint,
          'WSD_JOB_TERMINAL',
          'Stage-8 scheduler job is already terminal',
        );
    }
  }

  @override
  Future<void> waitForWorker(
    WesiSelfDebugCheckpointManager checkpoint, {
    String reason = 'Execution worker is unavailable',
  }) async {
    final job = _requireJob(checkpoint);
    if (job.state != WesiScheduledJobState.running &&
        job.state != WesiScheduledJobState.pauseRequested) {
      throw _stop(
        checkpoint,
        'WSD_WORKER_LOSS_STATE',
        'Worker-loss transition is not valid from the current job state',
      );
    }
    await _persistStage8Checkpoint(job, checkpoint);
    await coordinator.waitForWorker(jobId, reason: reason);
  }

  WesiScheduledJob _requireJob(WesiSelfDebugCheckpointManager checkpoint) {
    final job = coordinator[jobId];
    if (job == null) {
      throw _stop(
        checkpoint,
        'WSD_JOB_NOT_FOUND',
        'Stage-8 durable job was not found',
      );
    }
    if (!job.requirements.checkpointable) {
      throw _stop(
        checkpoint,
        'WSD_JOB_NOT_CHECKPOINTABLE',
        'Self-debug execution requires a checkpointable Stage-8 job',
      );
    }
    return job;
  }

  Future<void> _persistStage8Checkpoint(
    WesiScheduledJob job,
    WesiSelfDebugCheckpointManager checkpoint,
  ) async {
    var current = job;
    var stage = current.currentStage;
    if (stage == null || !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(stage)) {
      current = await coordinator.updateProgress(
        jobId,
        progress: current.progress,
        stage: 'self_debug.checkpoint',
      );
      stage = current.currentStage;
    }
    if (stage == null || !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(stage)) {
      throw _stop(
        checkpoint,
        'WSD_JOB_STAGE_INVALID',
        'Stage-8 job stage cannot be checkpointed safely',
      );
    }
    final snapshot = checkpoint.snapshot;
    if (snapshot == null) {
      throw const WesiSelfDebugStop(
        'WSD_CHECKPOINT_NOT_BOUND',
        'Self-debug checkpoint must be bound before Stage-8 checkpointing',
      );
    }
    final safeJobId = jobId.length <= 88 ? jobId : jobId.substring(0, 88);
    await coordinator.checkpoint(
      jobId,
      checkpoint: WesiJobCheckpointRef(
        checkpointId: 'sd:$safeJobId:${snapshot.revision}',
        version: WesiSelfDebugCheckpointState.schemaVersion,
        stage: stage,
        progress: current.progress,
        createdAt: DateTime.now().toUtc(),
      ),
    );
  }

  WesiSelfDebugStop _stop(
    WesiSelfDebugCheckpointManager checkpoint,
    String code,
    String message, {
    bool blocked = true,
  }) {
    final snapshot = checkpoint.snapshot;
    return WesiSelfDebugStop(
      code,
      message,
      blocked: blocked,
      repairIteration: snapshot?.repairIteration ?? 0,
      toolCalls: snapshot?.toolCalls ?? 0,
    );
  }
}
