import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_job_coordinator.dart';
import 'package:wesios/features/ai/runtime/wesi_job_queue.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

WesiWorkerResourceProfile _worker({
  String id = 'desktop',
  WesiWorkerStatus status = WesiWorkerStatus.online,
  int activeCpuJobs = 0,
}) =>
    WesiWorkerResourceProfile(
      id: id,
      name: id,
      platform: WesiWorkerPlatform.windows,
      status: status,
      trust: WesiWorkerTrust.local,
      role: WesiWorkerRole.localDevice,
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
      activeCpuJobs: activeCpuJobs,
    );

void main() {
  test('coordinator dispatch persists through the durable queue', () async {
    final journal = WesiMemoryJobJournal();
    final queue = WesiDurableJobQueue(journal: journal);
    final coordinator = WesiJobCoordinator(queue: queue);
    await coordinator.restore();
    await coordinator.enqueue(
      id: 'python-job',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      ),
    );

    final decision = await coordinator.dispatchNext(
      workers: <WesiWorkerResourceProfile>[_worker()],
    );
    expect(decision.selection.ok, isTrue);
    expect(decision.job.state, WesiScheduledJobState.running);
    expect(decision.job.workerId, 'desktop');

    final restoredQueue = WesiDurableJobQueue(journal: journal);
    await restoredQueue.restore();
    expect(
      restoredQueue.get('python-job')!.state,
      WesiScheduledJobState.running,
    );
    expect(restoredQueue.get('python-job')!.workerId, 'desktop');
  });

  test('blocked scheduling decision does not corrupt queued state', () async {
    final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
    final coordinator = WesiJobCoordinator(queue: queue);
    await coordinator.restore();
    await coordinator.enqueue(
      id: 'build-job',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      ),
    );

    final decision = await coordinator.dispatchNext(
      workers: <WesiWorkerResourceProfile>[
        _worker(status: WesiWorkerStatus.offline),
      ],
    );
    expect(decision.selection.ok, isFalse);
    expect(coordinator['build-job']!.state, WesiScheduledJobState.queued);
  });

  test('checkpointed worker loss resumes from the same durable checkpoint', () async {
    final journal = WesiMemoryJobJournal();
    final queue = WesiDurableJobQueue(journal: journal);
    final coordinator = WesiJobCoordinator(queue: queue);
    await coordinator.restore();
    await coordinator.enqueue(
      id: 'python-job',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      ),
    );
    await coordinator.dispatchNext(
      workers: <WesiWorkerResourceProfile>[_worker()],
    );
    await coordinator.checkpoint(
      'python-job',
      checkpoint: WesiJobCheckpointRef(
        checkpointId: 'cp-1',
        version: 1,
        stage: 'tests',
        progress: 0.6,
        createdAt: DateTime.utc(2026, 8, 15),
      ),
    );
    final waiting = await coordinator.waitForWorker(
      'python-job',
      reason: 'heartbeat expired',
    );
    expect(waiting.state, WesiScheduledJobState.waitingForWorker);
    expect(waiting.workerId, isNull);

    final restoredQueue = WesiDurableJobQueue(journal: journal);
    final restored = WesiJobCoordinator(queue: restoredQueue);
    await restored.restore();
    expect(restored['python-job']!.checkpoint!.progress, 0.6);

    final resumed = await restored.resume('python-job');
    expect(resumed.state, WesiScheduledJobState.queued);
    expect(resumed.checkpoint!.stage, 'tests');
  });

  test('coordinator load participates in concurrency decisions', () async {
    final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
    final coordinator = WesiJobCoordinator(queue: queue);
    await coordinator.restore();
    await coordinator.enqueue(
      id: 'first',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      ),
      priority: WesiJobPriority.high,
    );
    await coordinator.enqueue(
      id: 'second',
      requirements: WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      ),
    );
    await coordinator.dispatchNext(
      workers: <WesiWorkerResourceProfile>[_worker()],
    );

    final next = coordinator.nextDecision(
      workers: <WesiWorkerResourceProfile>[_worker()],
    );
    expect(next.job.id, 'second');
    expect(next.selection.ok, isFalse);
    expect(next.selection.blockerCode, WesiSchedulerBlockerCode.concurrency);
  });
}
