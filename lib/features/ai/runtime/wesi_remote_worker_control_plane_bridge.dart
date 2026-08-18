import 'wesi_job_coordinator.dart';
import 'wesi_remote_worker_controller.dart';
import 'wesi_remote_worker_execution_store.dart';
import 'wesi_remote_worker_http_transport.dart';
import 'wesi_remote_worker_models.dart';
import 'wesi_remote_worker_registry.dart';
import 'wesi_resource_scheduler_models.dart';

/// Orchestrator-side bridge between the canonical Stage-8 job state and the
/// real Control Plane HTTP transport. It deliberately does not mirror job state
/// on the server: only worker heartbeats and bounded messages cross devices.
class WesiRemoteWorkerControlPlaneBridge {
  final WesiRemoteWorkerController controller;
  final WesiRemoteWorkerRegistry registry;
  final WesiRemoteExecutionStore executionStore;
  final WesiRemoteWorkerHttpTransport transport;

  const WesiRemoteWorkerControlPlaneBridge({
    required this.controller,
    required this.registry,
    required this.executionStore,
    required this.transport,
  });

  WesiJobCoordinator get coordinator => controller.coordinator;

  Future<void> restore() async {
    await controller.restore();
    await executionStore.restore();
  }

  Future<WesiScheduledJob> enqueue({
    required String jobId,
    required WesiJobRequirements requirements,
    required WesiRemoteExecutionRequest execution,
    WesiJobPriority priority = WesiJobPriority.normal,
    DateTime? now,
  }) async {
    execution.validate();
    if (execution.call.tool != requirements.toolName) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_TOOL_MISMATCH',
        'Remote execution tool does not match trusted job requirements',
      );
    }
    if (!requirements.remoteAllowed ||
        requirements.preference == WesiExecutionPreference.localOnly) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_REMOTE_EXECUTION_FORBIDDEN',
        'Trusted workload policy does not allow remote execution',
      );
    }
    await executionStore.put(jobId, execution);
    try {
      return await coordinator.enqueue(
        id: jobId,
        requirements: requirements,
        priority: priority,
        now: now,
      );
    } catch (_) {
      await executionStore.remove(jobId);
      rethrow;
    }
  }

  Future<WesiRemoteWorkerDispatchResult> dispatchJob(
    String jobId, {
    DateTime? now,
  }) async {
    _requireExecution(jobId);
    final result = await controller.dispatchJob(jobId, now: now);
    final workerId = result.decision.job.workerId;
    if (result.dispatched && workerId != null) {
      await flushOutbound(workerId);
    }
    return result;
  }

  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
    final candidates = coordinator.jobs
        .where((job) =>
            job.state == WesiScheduledJobState.queued &&
            job.requirements.remoteAllowed &&
            job.requirements.preference != WesiExecutionPreference.localOnly &&
            executionStore.get(job.id) != null)
        .toList(growable: false)
      ..sort((a, b) {
        final priority = b.priority.index.compareTo(a.priority.index);
        if (priority != 0) return priority;
        final queued = a.queuedAt.compareTo(b.queuedAt);
        if (queued != 0) return queued;
        return a.id.compareTo(b.id);
      });
    if (candidates.isEmpty) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_NO_REMOTE_JOB',
        'There is no queued remote job with a durable execution payload',
      );
    }

    WesiRemoteWorkerDispatchResult? firstBlocked;
    for (final job in candidates) {
      final result = await controller.dispatchJob(job.id, now: now);
      if (result.dispatched) {
        final workerId = result.decision.job.workerId;
        if (workerId != null) await flushOutbound(workerId);
        return result;
      }
      firstBlocked ??= result;
    }
    return firstBlocked!;
  }

  Future<WesiRemoteWorkerDispatchResult> resumeJob(
    String jobId, {
    DateTime? now,
  }) async {
    _requireExecution(jobId);
    final result = await controller.resumeJob(jobId, now: now);
    final workerId = result.decision.job.workerId;
    if (result.dispatched && workerId != null) {
      await flushOutbound(workerId);
    }
    return result;
  }

  /// One bounded synchronization pass suitable for foreground polling or a
  /// light background task. Heavy execution never occurs here or on the VPS.
  Future<void> sync({DateTime? now}) async {
    final current = (now ?? DateTime.now()).toUtc();
    final heartbeats = await transport.listHeartbeats();
    final workerIds = <String>{};

    for (final heartbeat in heartbeats) {
      workerIds.add(heartbeat.profile.id);
      if (current.difference(heartbeat.sentAt.toUtc()).abs() >
          const Duration(minutes: 2)) {
        continue;
      }
      await controller.acceptHeartbeat(
        authenticatedWorkerId: heartbeat.profile.id,
        heartbeat: heartbeat,
        now: current,
      );
    }
    for (final lease in controller.leases.records) {
      workerIds.add(lease.workerId);
    }

    for (final workerId in workerIds) {
      await flushOutbound(workerId);
      await syncInbound(workerId, now: current);
    }
    await controller.sweepExpiredLeases(now: current);
    await _cleanupTerminalPayloads();
  }

  Future<void> flushOutbound(String workerId) async {
    final pending = registry.poll(workerId, limit: 32);
    for (final message in pending) {
      var outgoing = message;
      if (message.kind == WesiRemoteJobMessageKind.assignment) {
        final execution = executionStore.get(message.jobId);
        final job = coordinator[message.jobId];
        if (execution == null || job == null || job.terminal) {
          registry.ack(workerId, message.messageId);
          if (job != null && !job.terminal) {
            await coordinator.fail(
              job.id,
              failureCode: 'WRW_EXECUTION_PAYLOAD_MISSING',
              message:
                  'Remote assignment was blocked because its durable execution payload is missing',
            );
            await controller.leases.remove(job.id);
          }
          continue;
        }
        if (execution.call.tool != job.requirements.toolName) {
          registry.ack(workerId, message.messageId);
          await coordinator.fail(
            job.id,
            failureCode: 'WRW_EXECUTION_TOOL_MISMATCH',
            message:
                'Remote assignment tool does not match trusted scheduling requirements',
          );
          await controller.leases.remove(job.id);
          await executionStore.remove(job.id);
          continue;
        }
        outgoing = WesiRemoteJobMessage(
          messageId: message.messageId,
          jobId: message.jobId,
          kind: message.kind,
          sequence: message.sequence,
          createdAt: message.createdAt,
          payload: <String, dynamic>{
            ...message.payload,
            'execution': execution.toJson(),
          },
        );
      }
      await transport.enqueueToWorker(workerId, outgoing);
      registry.ack(workerId, message.messageId);
    }
  }

  Future<void> syncInbound(
    String workerId, {
    DateTime? now,
  }) async {
    final current = (now ?? DateTime.now()).toUtc();
    final incoming = await transport.pollWorkerEvents(workerId, limit: 32);
    for (final message in incoming) {
      final before = coordinator[message.jobId];
      if (before == null || before.terminal) {
        await transport.ackWorkerEvent(workerId, message.messageId);
        if (before?.terminal == true) {
          await executionStore.remove(message.jobId);
        }
        continue;
      }
      try {
        final updated = await controller.acceptWorkerMessage(
          authenticatedWorkerId: workerId,
          message: message,
          now: current,
        );
        await transport.ackWorkerEvent(workerId, message.messageId);
        if (updated.terminal) await executionStore.remove(updated.id);
      } on WesiRemoteWorkerProtocolException catch (error) {
        final latest = coordinator[message.jobId];
        final alreadyApplied = latest?.terminal == true ||
            error.code == 'WRW_REPLAYED_LEASE_SEQUENCE';
        if (!alreadyApplied) rethrow;
        await transport.ackWorkerEvent(workerId, message.messageId);
        if (latest?.terminal == true) {
          await executionStore.remove(message.jobId);
        }
      }
    }
  }

  WesiRemoteExecutionRequest _requireExecution(String jobId) {
    final execution = executionStore.get(jobId);
    if (execution == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_EXECUTION_PAYLOAD_MISSING',
        'Remote job has no durable execution payload',
      );
    }
    return execution;
  }

  Future<void> _cleanupTerminalPayloads() async {
    for (final job in coordinator.jobs) {
      if (job.terminal && executionStore.get(job.id) != null) {
        await executionStore.remove(job.id);
      }
    }
  }
}
