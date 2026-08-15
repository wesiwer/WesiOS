from pathlib import Path
import subprocess

OLD = "a05d67f553121e73b5e794425bbf4606dc287280"
FILES = [
    "lib/features/ai/runtime/wesi_remote_worker_agent.dart",
    "lib/features/ai/runtime/wesi_remote_worker_auth.dart",
    "lib/features/ai/runtime/wesi_remote_worker_control_plane_bridge.dart",
    "lib/features/ai/runtime/wesi_remote_worker_controller.dart",
    "lib/features/ai/runtime/wesi_remote_worker_execution_store.dart",
    "lib/features/ai/runtime/wesi_remote_worker_http_transport.dart",
    "lib/features/ai/runtime/wesi_remote_worker_lease_store.dart",
    "lib/features/ai/runtime/wesi_remote_worker_models.dart",
    "lib/features/ai/runtime/wesi_remote_worker_pairing.dart",
    "lib/features/ai/runtime/wesi_remote_worker_receipt_store.dart",
    "lib/features/ai/runtime/wesi_remote_worker_registry.dart",
    "server/pb_hooks/wesi_ai_remote_worker.pb.js",
    "server/pb_hooks/wesi_ai_remote_worker_lib.js",
    "server/wesi-ai-stream/remote_worker_protocol.test.mjs",
    "test/wesi_remote_worker_agent_test.dart",
    "test/wesi_remote_worker_controller_test.dart",
    "test/wesi_remote_worker_hardening_test.dart",
    "test/wesi_remote_worker_http_transport_test.dart",
    "test/wesi_remote_worker_pause_lifecycle_test.dart",
    "test/wesi_remote_worker_protocol_test.dart",
]

for name in FILES:
    path = Path(name)
    path.parent.mkdir(parents=True, exist_ok=True)
    data = subprocess.check_output(["git", "show", f"{OLD}:{name}"])
    path.write_bytes(data)


def replace_once(path: str, old: str, new: str, marker: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise RuntimeError(f"missing patch anchor: {path}: {marker}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")

controller = "lib/features/ai/runtime/wesi_remote_worker_controller.dart"
text = Path(controller).read_text(encoding="utf-8")
if "import 'wesi_local_runtime_models.dart';" not in text:
    text = text.replace(
        "import 'wesi_job_coordinator.dart';\n",
        "import 'wesi_job_coordinator.dart';\nimport 'wesi_local_runtime_models.dart';\n",
        1,
    )
Path(controller).write_text(text, encoding="utf-8")

replace_once(
    controller,
    """      if (lease == null || lease.expiredAt(current)) continue;
      await leases.renew(
""",
    """      if (lease == null || lease.expiredAt(current)) continue;
      // A heartbeat proves connectivity, not durable receipt of the command.
      // Do not keep a lost/unacknowledged assignment alive forever.
      if (!lease.assignmentAcked) continue;
      await leases.renew(
""",
    "if (!lease.assignmentAcked) continue;",
)

replace_once(
    controller,
    """      if (job.requirements.checkpointable && !checkpointCurrent) {
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
""",
    """      if (job.requirements.checkpointable && !checkpointCurrent) {
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
""",
    "risk != WesiLocalRisk.read",
)

bridge = "lib/features/ai/runtime/wesi_remote_worker_control_plane_bridge.dart"
replace_once(
    bridge,
    """  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
    final result = await controller.dispatchNext(now: now);
    final workerId = result.decision.job.workerId;
    if (result.dispatched) {
      _requireExecution(result.decision.job.id);
      if (workerId != null) await flushOutbound(workerId);
    }
    return result;
  }
""",
    """  Future<WesiRemoteWorkerDispatchResult> dispatchNext({DateTime? now}) async {
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
""",
    "WRW_NO_REMOTE_JOB",
)

# Keep a regression that specifically protects the bridge ordering invariant.
hardening = Path("test/wesi_remote_worker_hardening_test.dart")
h = hardening.read_text(encoding="utf-8")
if "dispatchNext never starts a job without durable execution payload" not in h:
    if "import 'dart:math';\n" in h and "import 'dart:io';" not in h:
        h = h.replace("import 'dart:math';\n", "import 'dart:io';\nimport 'dart:math';\n", 1)
    anchor = "  test('heartbeat cannot keep an unacknowledged assignment lease alive', () async {"
    test_block = """  test('dispatchNext never starts a job without durable execution payload', () {
    final source = File(
      'lib/features/ai/runtime/wesi_remote_worker_control_plane_bridge.dart',
    ).readAsStringSync();
    expect(source, contains('executionStore.get(job.id) != null'));
    expect(source, contains('WRW_NO_REMOTE_JOB'));
  });

"""
    if anchor not in h:
        raise RuntimeError("hardening test anchor missing")
    h = h.replace(anchor, test_block + anchor, 1)
    hardening.write_text(h, encoding="utf-8")

print(f"ported {len(FILES)} Stage-10 files and applied final hardening")
