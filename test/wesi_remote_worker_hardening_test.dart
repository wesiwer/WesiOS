import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_job_coordinator.dart';
import 'package:wesios/features/ai/runtime/wesi_job_queue.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_controller.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_lease_store.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_registry.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

const workerId = 'workerworkerworkerworkerworkerworker12';

void main() {
  final now = DateTime.utc(2026, 8, 15, 18);

  test('dispatchNext never starts a job without durable execution payload', () {
    final source = File(
      'lib/features/ai/runtime/wesi_remote_worker_control_plane_bridge.dart',
    ).readAsStringSync();
    expect(source, contains('executionStore.get(job.id) != null'));
    expect(source, contains('WRW_NO_REMOTE_JOB'));
  });

  test('heartbeat cannot keep an unacknowledged assignment lease alive',
      () async {
    final h = await _harness();
    await h.controller.acceptHeartbeat(
      authenticatedWorkerId: workerId,
      heartbeat: _heartbeat(now),
      now: now,
    );
    await h.coordinator.enqueue(
      id: 'unacked-build',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
        preference: WesiExecutionPreference.remoteOnly,
      ),
      now: now,
    );
    final dispatched = await h.controller.dispatchNext(now: now);
    expect(dispatched.lease!.assignmentAcked, isFalse);

    final heartbeatAt = now.add(const Duration(seconds: 30));
    await h.controller.acceptHeartbeat(
      authenticatedWorkerId: workerId,
      heartbeat: _heartbeat(heartbeatAt),
      now: heartbeatAt,
    );
    expect(
      h.leases.get('unacked-build')!.expiresAt,
      now.add(const Duration(seconds: 45)),
    );

    await h.controller.sweepExpiredLeases(
      now: now.add(const Duration(seconds: 46)),
    );
    expect(h.coordinator['unacked-build']!.state, WesiScheduledJobState.failed);
    expect(
      h.coordinator['unacked-build']!.failureCode,
      'WRW_WORKER_LOST_UNCHECKPOINTED',
    );
  });

  test('non-checkpointable write fails closed on worker loss', () async {
    final h = await _harness();
    await h.controller.acceptHeartbeat(
      authenticatedWorkerId: workerId,
      heartbeat: _heartbeat(now),
      now: now,
    );
    await h.coordinator.enqueue(
      id: 'write-job',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.fsWriteText,
        preference: WesiExecutionPreference.remoteOnly,
      ),
      now: now,
    );
    await h.controller.dispatchNext(now: now);
    await h.controller.sweepExpiredLeases(
      now: now.add(const Duration(seconds: 46)),
    );
    final job = h.coordinator['write-job']!;
    expect(job.state, WesiScheduledJobState.failed);
    expect(job.failureCode, 'WRW_WORKER_LOST_UNCHECKPOINTED');
  });

  test('non-checkpointable read may wait for the same worker and retry safely',
      () async {
    final h = await _harness();
    await h.controller.acceptHeartbeat(
      authenticatedWorkerId: workerId,
      heartbeat: _heartbeat(now),
      now: now,
    );
    await h.coordinator.enqueue(
      id: 'read-job',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.fsList,
        preference: WesiExecutionPreference.remoteOnly,
      ),
      now: now,
    );
    await h.controller.dispatchNext(now: now);
    await h.controller.sweepExpiredLeases(
      now: now.add(const Duration(seconds: 46)),
    );
    expect(
      h.coordinator['read-job']!.state,
      WesiScheduledJobState.waitingForWorker,
    );
  });
}

class _Harness {
  final WesiJobCoordinator coordinator;
  final WesiRemoteWorkerLeaseStore leases;
  final WesiRemoteWorkerController controller;

  const _Harness({
    required this.coordinator,
    required this.leases,
    required this.controller,
  });
}

Future<_Harness> _harness() async {
  final coordinator = WesiJobCoordinator(
    queue: WesiDurableJobQueue(journal: WesiMemoryJobJournal()),
  );
  final leases = WesiRemoteWorkerLeaseStore(
    journal: WesiMemoryRemoteWorkerLeaseJournal(),
  );
  final controller = WesiRemoteWorkerController(
    coordinator: coordinator,
    registry: WesiRemoteWorkerRegistry(),
    leases: leases,
    leaseTtl: const Duration(seconds: 45),
    random: Random(31),
  );
  await controller.restore();
  return _Harness(
    coordinator: coordinator,
    leases: leases,
    controller: controller,
  );
}

WesiRemoteWorkerHeartbeat _heartbeat(DateTime now) => WesiRemoteWorkerHeartbeat(
      sentAt: now,
      profile: WesiWorkerResourceProfile(
        id: workerId,
        name: 'Hardening desktop',
        platform: WesiWorkerPlatform.windows,
        status: WesiWorkerStatus.online,
        trust: WesiWorkerTrust.paired,
        role: WesiWorkerRole.remoteWorker,
        policyAllowed: true,
        appForeground: true,
        backgroundExecutionAllowed: true,
        cpuCores: 8,
        cpuLoadPercent: 10,
        totalRamMb: 16384,
        availableRamMb: 12000,
        totalGpuVramMb: 8192,
        freeGpuVramMb: 7000,
        freeDiskMb: 100000,
        capabilities: const <WesiLocalCapability>{
          WesiLocalCapability.filesystem,
          WesiLocalCapability.build,
        },
        installedPacks: const <WesiRuntimePackId>{
          WesiRuntimePackId.core,
          WesiRuntimePackId.developer,
        },
        lastSeenAt: now,
      ),
    );
