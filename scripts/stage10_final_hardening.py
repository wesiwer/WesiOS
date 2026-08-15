from pathlib import Path

# One-shot branch-local validator. The workflow removes this helper after a full
# successful analyze/test pass and commits only the validated product changes.
# Retriggered after clean-head PR regression exposed the uncommitted hardening.


def patch_controller() -> None:
    path = Path("lib/features/ai/runtime/wesi_remote_worker_controller.dart")
    text = path.read_text(encoding="utf-8")
    if "import 'wesi_local_runtime_models.dart';" not in text:
        text = text.replace(
            "import 'wesi_job_coordinator.dart';\n",
            "import 'wesi_job_coordinator.dart';\nimport 'wesi_local_runtime_models.dart';\n",
            1,
        )

    old_renew = """      if (lease == null || lease.expiredAt(current)) continue;
      await leases.renew(
"""
    new_renew = """      if (lease == null || lease.expiredAt(current)) continue;
      // Connectivity alone cannot prove that the assignment reached durable
      // worker storage. Do not keep an unacknowledged command alive forever.
      if (!lease.assignmentAcked) continue;
      await leases.renew(
"""
    if old_renew in text:
        text = text.replace(old_renew, new_renew, 1)
    elif "if (!lease.assignmentAcked) continue;" not in text:
        raise RuntimeError("assignment ACK guard patch point not found")

    old_loss = """      if (job.requirements.checkpointable && !checkpointCurrent) {
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

      await coordinator.waitForWorker(
"""
    new_loss = """      if (job.requirements.checkpointable && !checkpointCurrent) {
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

      // Non-checkpointable reads are safe to retry on the same paired worker.
      // State-changing work is fail-closed because a lost response cannot prove
      // whether its side effect already happened.
      final risk = WesiLocalCapabilityRegistry.get(job.requirements.toolName)?.risk;
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
"""
    if old_loss in text:
        text = text.replace(old_loss, new_loss, 1)
    elif "risk != WesiLocalRisk.read" not in text:
        raise RuntimeError("worker-loss risk patch point not found")

    path.write_text(text, encoding="utf-8")


def patch_bridge() -> None:
    path = Path("lib/features/ai/runtime/wesi_remote_worker_control_plane_bridge.dart")
    text = path.read_text(encoding="utf-8")
    old = """  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
    final result = await controller.dispatchNext(now: now);
    final workerId = result.decision.job.workerId;
    if (result.dispatched) {
      _requireExecution(result.decision.job.id);
      if (workerId != null) await flushOutbound(workerId);
    }
    return result;
  }
"""
    new = """  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
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
"""
    if old in text:
        text = text.replace(old, new, 1)
    elif "WRW_NO_REMOTE_JOB" not in text:
        raise RuntimeError("dispatchNext patch point not found")
    path.write_text(text, encoding="utf-8")


if __name__ == "__main__":
    patch_controller()
    patch_bridge()
