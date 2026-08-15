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

const _workerA = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _workerB = 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  final now = DateTime.utc(2026, 8, 15, 16, 20);

  test('dispatch lease survives Control Plane restart and reissues assignment',
      () async {
    final jobJournal = WesiMemoryJobJournal();
    final leaseJournal = WesiMemoryRemoteWorkerLeaseJournal();
    final first = await _harness(
      jobJournal: jobJournal,
      leaseJournal: leaseJournal,
      randomSeed: 7,
    );
    await first.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await _enqueueBuild(first.coordinator, 'restart-job', now);

    final dispatched = await first.controller.dispatchNext(now: now);
    expect(dispatched.dispatched, isTrue);
    expect(dispatched.assignmentQueued, isTrue);
    expect(dispatched.decision.job.state, WesiScheduledJobState.running);
    expect(dispatched.decision.job.workerId, _workerA);
    final lease = dispatched.lease!;
    final assignment = first.registry
        .poll(_workerA)
        .singleWhere((m) => m.kind == WesiRemoteJobMessageKind.assignment);
    expect(assignment.jobId, 'restart-job');
    expect(assignment.payload['leaseId'], lease.leaseId);
    expect(assignment.payload['generation'], 1);

    await first.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: lease,
        kind: WesiRemoteJobMessageKind.ack,
        sequence: 1,
        now: now.add(const Duration(seconds: 1)),
        extra: <String, dynamic>{'ackedMessageId': assignment.messageId},
      ),
      now: now.add(const Duration(seconds: 1)),
    );
    expect(first.leases.get('restart-job')!.assignmentAcked, isTrue);

    final second = await _harness(
      jobJournal: jobJournal,
      leaseJournal: leaseJournal,
      randomSeed: 99,
    );
    await second.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now.add(const Duration(seconds: 5))),
      now: now.add(const Duration(seconds: 5)),
    );

    final restored = second.coordinator['restart-job']!;
    expect(restored.state, WesiScheduledJobState.running);
    expect(restored.workerId, _workerA);
    final restoredLease = second.leases.get('restart-job')!;
    expect(restoredLease.leaseId, lease.leaseId);
    expect(restoredLease.generation, lease.generation);
    final replayedAssignment = second.registry
        .poll(_workerA)
        .singleWhere((m) => m.kind == WesiRemoteJobMessageKind.assignment);
    expect(replayedAssignment.messageId, assignment.messageId);
    expect(replayedAssignment.payload['leaseId'], lease.leaseId);
  });

  test('checkpointed worker loss waits and reconnect creates a new generation',
      () async {
    final harness = await _harness(randomSeed: 11);
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await _enqueueBuild(harness.coordinator, 'resume-job', now);
    final first = await harness.controller.dispatchNext(now: now);
    final oldLease = first.lease!;

    final checkpointed = await harness.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: oldLease,
        kind: WesiRemoteJobMessageKind.checkpoint,
        sequence: 1,
        now: now.add(const Duration(seconds: 5)),
        extra: const <String, dynamic>{
          'checkpointId': 'cp-tests',
          'version': 1,
          'stage': 'tests',
          'progress': 0.5,
        },
      ),
      now: now.add(const Duration(seconds: 5)),
    );
    expect(checkpointed.checkpoint!.stage, 'tests');

    await harness.controller.sweepExpiredLeases(
      now: now.add(const Duration(seconds: 46)),
    );
    expect(
      harness.coordinator['resume-job']!.state,
      WesiScheduledJobState.waitingForWorker,
    );
    expect(harness.coordinator['resume-job']!.workerId, isNull);

    final reconnectAt = now.add(const Duration(seconds: 47));
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, reconnectAt),
      now: reconnectAt,
    );
    final resumed = await harness.controller.resumeWaitingForWorker(
      _workerA,
      now: reconnectAt,
    );
    expect(resumed, hasLength(1));
    final newLease = resumed.single.lease!;
    expect(newLease.generation, oldLease.generation + 1);
    expect(newLease.leaseId, isNot(oldLease.leaseId));
    expect(resumed.single.decision.job.workerId, _workerA);
    expect(resumed.single.decision.job.checkpoint!.stage, 'tests');

    expect(
      () => harness.controller.acceptWorkerMessage(
        authenticatedWorkerId: _workerA,
        message: _inbound(
          lease: oldLease,
          kind: WesiRemoteJobMessageKind.result,
          sequence: 2,
          now: reconnectAt,
          extra: const <String, dynamic>{'success': true},
        ),
        now: reconnectAt,
      ),
      throwsA(
        isA<WesiRemoteWorkerProtocolException>()
            .having((e) => e.code, 'code', 'WRW_STALE_LEASE'),
      ),
    );

    final completed = await harness.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: newLease,
        kind: WesiRemoteJobMessageKind.result,
        sequence: 1,
        now: reconnectAt.add(const Duration(seconds: 1)),
        extra: const <String, dynamic>{'success': true},
      ),
      now: reconnectAt.add(const Duration(seconds: 1)),
    );
    expect(completed.state, WesiScheduledJobState.succeeded);
    expect(harness.leases.get('resume-job'), isNull);
  });

  test('paused job remains pinned to the same remote workspace worker',
      () async {
    final harness = await _harness(
      randomSeed: 13,
      heartbeatTtl: const Duration(seconds: 15),
    );
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerB,
      heartbeat: _heartbeat(_workerB, now),
      now: now,
    );
    await _enqueueBuild(harness.coordinator, 'pause-job', now);
    final dispatched = await harness.controller.dispatchNext(now: now);
    expect(dispatched.decision.job.workerId, _workerA);
    final lease = dispatched.lease!;

    final pauseRequested = await harness.controller.requestPause(
      'pause-job',
      now: now.add(const Duration(seconds: 1)),
    );
    expect(pauseRequested.state, WesiScheduledJobState.pauseRequested);
    expect(
      harness.registry
          .poll(_workerA)
          .any((m) => m.kind == WesiRemoteJobMessageKind.pause),
      isTrue,
    );

    final paused = await harness.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: lease,
        kind: WesiRemoteJobMessageKind.checkpoint,
        sequence: 1,
        now: now.add(const Duration(seconds: 2)),
        extra: const <String, dynamic>{
          'checkpointId': 'cp-pause',
          'version': 1,
          'stage': 'build',
          'progress': 0.4,
        },
      ),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(paused.state, WesiScheduledJobState.paused);
    expect(paused.workerId, isNull);

    final later = now.add(const Duration(seconds: 20));
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerB,
      heartbeat: _heartbeat(_workerB, later),
      now: later,
    );
    final blocked = await harness.controller.resumeJob(
      'pause-job',
      now: later,
    );
    expect(blocked.dispatched, isFalse);
    expect(blocked.decision.selection.blockerCode,
        WesiSchedulerBlockerCode.offline);
    expect(
        harness.coordinator['pause-job']!.state, WesiScheduledJobState.queued);

    final workerReturns = later.add(const Duration(seconds: 1));
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, workerReturns),
      now: workerReturns,
    );
    final resumed = await harness.controller.dispatchJob(
      'pause-job',
      now: workerReturns,
    );
    expect(resumed.dispatched, isTrue);
    expect(resumed.decision.job.workerId, _workerA);
    expect(resumed.lease!.generation, lease.generation + 1);
  });

  test('uncheckpointed heavy worker loss fails closed instead of replaying',
      () async {
    final harness = await _harness(randomSeed: 17);
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await _enqueueBuild(harness.coordinator, 'unsafe-job', now);
    await harness.controller.dispatchNext(now: now);

    final affected = await harness.controller.sweepExpiredLeases(
      now: now.add(const Duration(seconds: 46)),
    );
    expect(affected, contains('unsafe-job'));
    final failed = harness.coordinator['unsafe-job']!;
    expect(failed.state, WesiScheduledJobState.failed);
    expect(failed.failureCode, 'WRW_WORKER_LOST_UNCHECKPOINTED');
    expect(harness.leases.get('unsafe-job'), isNull);
  });

  test('cancel acknowledgement terminates job and invalidates its lease',
      () async {
    final harness = await _harness(randomSeed: 19);
    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await _enqueueBuild(harness.coordinator, 'cancel-job', now);
    final dispatched = await harness.controller.dispatchNext(now: now);
    final lease = dispatched.lease!;
    await harness.controller.requestCancel(
      'cancel-job',
      now: now.add(const Duration(seconds: 1)),
    );
    final cancel = harness.registry
        .poll(_workerA)
        .singleWhere((m) => m.kind == WesiRemoteJobMessageKind.cancel);

    final cancelled = await harness.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: lease,
        kind: WesiRemoteJobMessageKind.ack,
        sequence: 1,
        now: now.add(const Duration(seconds: 2)),
        extra: <String, dynamic>{'ackedMessageId': cancel.messageId},
      ),
      now: now.add(const Duration(seconds: 2)),
    );
    expect(cancelled.state, WesiScheduledJobState.cancelled);
    expect(harness.leases.get('cancel-job'), isNull);

    expect(
      () => harness.controller.acceptWorkerMessage(
        authenticatedWorkerId: _workerA,
        message: _inbound(
          lease: lease,
          kind: WesiRemoteJobMessageKind.result,
          sequence: 2,
          now: now.add(const Duration(seconds: 3)),
          extra: const <String, dynamic>{'success': true},
        ),
        now: now.add(const Duration(seconds: 3)),
      ),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
  });

  test('authenticated identity and durable lease sequence reject spoof/replay',
      () async {
    final harness = await _harness(randomSeed: 23);
    expect(
      () => harness.controller.acceptHeartbeat(
        authenticatedWorkerId: _workerB,
        heartbeat: _heartbeat(_workerA, now),
        now: now,
      ),
      throwsA(
        isA<WesiRemoteWorkerProtocolException>().having(
          (e) => e.code,
          'code',
          'WRW_WORKER_IDENTITY_MISMATCH',
        ),
      ),
    );

    await harness.controller.acceptHeartbeat(
      authenticatedWorkerId: _workerA,
      heartbeat: _heartbeat(_workerA, now),
      now: now,
    );
    await _enqueueBuild(harness.coordinator, 'replay-job', now);
    final dispatched = await harness.controller.dispatchNext(now: now);
    final lease = dispatched.lease!;
    await harness.controller.acceptWorkerMessage(
      authenticatedWorkerId: _workerA,
      message: _inbound(
        lease: lease,
        kind: WesiRemoteJobMessageKind.progress,
        sequence: 5,
        now: now.add(const Duration(seconds: 1)),
        extra: const <String, dynamic>{
          'progress': 0.2,
          'stage': 'analyze',
        },
      ),
      now: now.add(const Duration(seconds: 1)),
    );
    expect(harness.coordinator['replay-job']!.progress, 0.2);

    expect(
      () => harness.controller.acceptWorkerMessage(
        authenticatedWorkerId: _workerA,
        message: _inbound(
          lease: lease,
          kind: WesiRemoteJobMessageKind.progress,
          sequence: 5,
          now: now.add(const Duration(seconds: 2)),
          extra: const <String, dynamic>{
            'progress': 0.3,
            'stage': 'tests',
          },
        ),
        now: now.add(const Duration(seconds: 2)),
      ),
      throwsA(
        isA<WesiRemoteWorkerProtocolException>().having(
          (e) => e.code,
          'code',
          'WRW_REPLAYED_LEASE_SEQUENCE',
        ),
      ),
    );
  });
}

class _Harness {
  final WesiJobCoordinator coordinator;
  final WesiRemoteWorkerRegistry registry;
  final WesiRemoteWorkerLeaseStore leases;
  final WesiRemoteWorkerController controller;

  const _Harness({
    required this.coordinator,
    required this.registry,
    required this.leases,
    required this.controller,
  });
}

Future<_Harness> _harness({
  WesiMemoryJobJournal? jobJournal,
  WesiMemoryRemoteWorkerLeaseJournal? leaseJournal,
  int randomSeed = 1,
  Duration heartbeatTtl = const Duration(seconds: 30),
}) async {
  final queue = WesiDurableJobQueue(
    journal: jobJournal ?? WesiMemoryJobJournal(),
  );
  final coordinator = WesiJobCoordinator(queue: queue);
  final registry = WesiRemoteWorkerRegistry(heartbeatTtl: heartbeatTtl);
  final leases = WesiRemoteWorkerLeaseStore(
    journal: leaseJournal ?? WesiMemoryRemoteWorkerLeaseJournal(),
  );
  final controller = WesiRemoteWorkerController(
    coordinator: coordinator,
    registry: registry,
    leases: leases,
    leaseTtl: const Duration(seconds: 45),
    random: Random(randomSeed),
  );
  await controller.restore();
  return _Harness(
    coordinator: coordinator,
    registry: registry,
    leases: leases,
    controller: controller,
  );
}

Future<void> _enqueueBuild(
  WesiJobCoordinator coordinator,
  String id,
  DateTime now,
) =>
    coordinator.enqueue(
      id: id,
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
        preference: WesiExecutionPreference.remoteOnly,
      ),
      now: now,
    );

WesiRemoteWorkerHeartbeat _heartbeat(String workerId, DateTime now) =>
    WesiRemoteWorkerHeartbeat(
      profile: WesiWorkerResourceProfile(
        id: workerId,
        name: 'Stage 10 desktop worker',
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
        thermalState: WesiThermalState.nominal,
        powerMode: WesiPowerMode.normal,
        capabilities: const <WesiLocalCapability>{
          WesiLocalCapability.filesystem,
          WesiLocalCapability.git,
          WesiLocalCapability.python,
          WesiLocalCapability.flutter,
          WesiLocalCapability.build,
        },
        installedPacks: const <WesiRuntimePackId>{
          WesiRuntimePackId.core,
          WesiRuntimePackId.developer,
        },
        lastSeenAt: now,
      ),
      sentAt: now,
    );

WesiRemoteJobMessage _inbound({
  required WesiRemoteWorkerLeaseRecord lease,
  required WesiRemoteJobMessageKind kind,
  required int sequence,
  required DateTime now,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) =>
    WesiRemoteJobMessage(
      messageId: 'in-${lease.generation}-${kind.name}-$sequence',
      jobId: lease.jobId,
      kind: kind,
      sequence: sequence,
      createdAt: now,
      payload: <String, dynamic>{
        'leaseId': lease.leaseId,
        'generation': lease.generation,
        ...extra,
      },
    );
