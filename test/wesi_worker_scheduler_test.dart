import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_worker_models.dart';
import 'package:wesios/features/ai/runtime/wesi_worker_scheduler.dart';

void main() {
  const scheduler = WesiWorkerScheduler();

  WesiWorkerProfile worker({
    required String id,
    required WesiWorkerPlatform platform,
    required bool local,
    WesiWorkerStatus status = WesiWorkerStatus.online,
    List<WesiWorkerCapability> capabilities = const <WesiWorkerCapability>[],
    int ramMb = 16384,
    int gpuVramMb = 0,
  }) => WesiWorkerProfile(
        id: id,
        name: id,
        platform: platform,
        status: status,
        cpuCores: local ? 8 : 12,
        ramMb: ramMb,
        gpuVramMb: gpuVramMb,
        capabilities: capabilities,
        installedPacks: const <WesiRuntimePackId>[],
        localDevice: local,
      );

  test('build job is routed to desktop worker instead of phone', () {
    final result = scheduler.select(
      job: const WesiJobRequirements(
        jobClass: WesiJobClass.build,
        capabilities: <WesiWorkerCapability>[
          WesiWorkerCapability.flutter,
          WesiWorkerCapability.androidBuild,
        ],
        minRamMb: 4096,
      ),
      workers: <WesiWorkerProfile>[
        worker(
          id: 'phone',
          platform: WesiWorkerPlatform.android,
          local: true,
          capabilities: const <WesiWorkerCapability>[
            WesiWorkerCapability.flutter,
            WesiWorkerCapability.androidBuild,
          ],
        ),
        worker(
          id: 'laptop',
          platform: WesiWorkerPlatform.windows,
          local: false,
          capabilities: const <WesiWorkerCapability>[
            WesiWorkerCapability.flutter,
            WesiWorkerCapability.androidBuild,
          ],
        ),
      ],
    );
    expect(result.ok, isTrue);
    expect(result.worker!.id, 'laptop');
  });

  test('remote-only job warns when paired desktop is offline', () {
    final result = scheduler.select(
      job: const WesiJobRequirements(
        jobClass: WesiJobClass.build,
        capabilities: <WesiWorkerCapability>[WesiWorkerCapability.windowsBuild],
        preference: WesiExecutionPreference.remoteOnly,
      ),
      workers: <WesiWorkerProfile>[
        worker(
          id: 'laptop',
          platform: WesiWorkerPlatform.windows,
          local: false,
          status: WesiWorkerStatus.offline,
          capabilities: const <WesiWorkerCapability>[WesiWorkerCapability.windowsBuild],
        ),
      ],
    );
    expect(result.ok, isFalse);
    expect(result.requiresRemoteOnlineWarning, isTrue);
    expect(result.blocker, contains('Откройте WesiOS'));
  });

  test('gpu job rejects worker with insufficient VRAM', () {
    final result = scheduler.select(
      job: const WesiJobRequirements(
        jobClass: WesiJobClass.gpu,
        capabilities: <WesiWorkerCapability>[WesiWorkerCapability.videoGeneration],
        minGpuVramMb: 8192,
      ),
      workers: <WesiWorkerProfile>[
        worker(
          id: 'rtx3050',
          platform: WesiWorkerPlatform.windows,
          local: false,
          gpuVramMb: 4096,
          capabilities: const <WesiWorkerCapability>[WesiWorkerCapability.videoGeneration],
        ),
      ],
    );
    expect(result.ok, isFalse);
  });
}
