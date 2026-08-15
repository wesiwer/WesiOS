import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_job_queue.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

void main() {
  test('Stage 8 rejects internally inconsistent GPU telemetry', () {
    const worker = WesiWorkerResourceProfile(
      id: 'gpu-worker',
      name: 'GPU worker',
      platform: WesiWorkerPlatform.windows,
      status: WesiWorkerStatus.online,
      trust: WesiWorkerTrust.local,
      role: WesiWorkerRole.localDevice,
      policyAllowed: true,
      appForeground: true,
      backgroundExecutionAllowed: true,
      cpuCores: 8,
      cpuLoadPercent: 10,
      totalRamMb: 16384,
      availableRamMb: 12000,
      totalGpuVramMb: 0,
      freeGpuVramMb: 4096,
      freeDiskMb: 100000,
      capabilities: <WesiLocalCapability>{},
      installedPacks: <WesiRuntimePackId>{},
    );
    expect(worker.resourceSnapshotSane, isFalse);
  });

  test('Stage 8 never uses a stale checkpoint after later progress', () async {
    final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
    await queue.restore();
    final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
      WesiLocalToolNames.flutterTest,
    );
    await queue.enqueue(id: 'acceptance-job', requirements: requirements);
    await queue.markRunning('acceptance-job', workerId: 'desktop');
    await queue.checkpoint(
      'acceptance-job',
      checkpoint: WesiJobCheckpointRef(
        checkpointId: 'checkpoint-old',
        version: 1,
        stage: 'compile',
        progress: 0.4,
        createdAt: DateTime.utc(2026, 8, 15),
      ),
    );
    await queue.updateProgress('acceptance-job', progress: 0.8, stage: 'tests');
    await expectLater(
      queue.waitForWorker('acceptance-job'),
      throwsA(
        isA<WesiJobQueueException>().having(
          (error) => error.code,
          'code',
          'WJQ_CHECKPOINT_REQUIRED',
        ),
      ),
    );
    expect(queue.get('acceptance-job')!.state, WesiScheduledJobState.running);
  });
}
