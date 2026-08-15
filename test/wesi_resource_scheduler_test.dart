import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

const _allCapabilities = <WesiLocalCapability>{
  WesiLocalCapability.filesystem,
  WesiLocalCapability.terminal,
  WesiLocalCapability.git,
  WesiLocalCapability.http,
  WesiLocalCapability.python,
  WesiLocalCapability.node,
  WesiLocalCapability.flutter,
  WesiLocalCapability.build,
  WesiLocalCapability.documents,
  WesiLocalCapability.media,
};

const _allPacks = <WesiRuntimePackId>{
  WesiRuntimePackId.core,
  WesiRuntimePackId.developer,
  WesiRuntimePackId.browser,
  WesiRuntimePackId.documents,
  WesiRuntimePackId.media,
};

WesiWorkerResourceProfile _worker({
  String id = 'local',
  WesiWorkerPlatform platform = WesiWorkerPlatform.windows,
  WesiWorkerStatus status = WesiWorkerStatus.online,
  WesiWorkerTrust trust = WesiWorkerTrust.local,
  WesiWorkerRole role = WesiWorkerRole.localDevice,
  bool policyAllowed = true,
  bool appForeground = true,
  bool backgroundExecutionAllowed = true,
  int cpuCores = 8,
  double cpuLoadPercent = 15,
  int totalRamMb = 16384,
  int availableRamMb = 12288,
  int totalGpuVramMb = 12288,
  int freeGpuVramMb = 10240,
  int freeDiskMb = 100000,
  WesiThermalState thermalState = WesiThermalState.nominal,
  WesiPowerMode powerMode = WesiPowerMode.normal,
  Set<WesiLocalCapability> capabilities = _allCapabilities,
  Set<WesiRuntimePackId> installedPacks = _allPacks,
  int activeLightJobs = 0,
  int activeCpuJobs = 0,
  int activeHeavyJobs = 0,
  int activeGpuJobs = 0,
}) =>
    WesiWorkerResourceProfile(
      id: id,
      name: id,
      platform: platform,
      status: status,
      trust: trust,
      role: role,
      policyAllowed: policyAllowed,
      appForeground: appForeground,
      backgroundExecutionAllowed: backgroundExecutionAllowed,
      cpuCores: cpuCores,
      cpuLoadPercent: cpuLoadPercent,
      totalRamMb: totalRamMb,
      availableRamMb: availableRamMb,
      gpuName: totalGpuVramMb > 0 ? 'GPU' : null,
      totalGpuVramMb: totalGpuVramMb,
      freeGpuVramMb: freeGpuVramMb,
      freeDiskMb: freeDiskMb,
      thermalState: thermalState,
      powerMode: powerMode,
      capabilities: capabilities,
      installedPacks: installedPacks,
      activeLightJobs: activeLightJobs,
      activeCpuJobs: activeCpuJobs,
      activeHeavyJobs: activeHeavyJobs,
      activeGpuJobs: activeGpuJobs,
    );

void main() {
  group('Adaptive execution classifier', () {
    test('uses the minimum sufficient L0-L4 path', () {
      expect(
        WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(),
        ),
        WesiWorkloadLevel.l0,
      );
      expect(
        WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(usesTools: true),
        ),
        WesiWorkloadLevel.l1,
      );
      expect(
        WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(requiresLocalRuntime: true),
        ),
        WesiWorkloadLevel.l2,
      );
      expect(
        WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(requiresSelfDebug: true),
        ),
        WesiWorkloadLevel.l3,
      );
      expect(
        WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(requiresBuild: true),
        ),
        WesiWorkloadLevel.l4,
      );
    });

    test('rejects invalid trusted facts and escalates progressively', () {
      expect(
        () => WesiAdaptiveExecutionClassifier.classify(
          const WesiAdaptiveExecutionFacts(estimatedSteps: -1),
        ),
        throwsA(
          isA<WesiSchedulerPolicyException>().having(
            (error) => error.code,
            'code',
            'WS_INVALID_FACTS',
          ),
        ),
      );
      expect(
        WesiAdaptiveExecutionClassifier.escalate(WesiWorkloadLevel.l1),
        WesiWorkloadLevel.l2,
      );
      expect(
        WesiAdaptiveExecutionClassifier.escalate(WesiWorkloadLevel.l4),
        WesiWorkloadLevel.l4,
      );
    });

    test('L3/L4 budgets require foreground execution', () {
      expect(
        WesiAdaptiveExecutionClassifier.budgetFor(WesiWorkloadLevel.l0)
            .localRuntimeAllowed,
        isFalse,
      );
      expect(
        WesiAdaptiveExecutionClassifier.budgetFor(WesiWorkloadLevel.l3)
            .foregroundPolicy,
        WesiForegroundPolicy.foregroundRequired,
      );
      expect(
        WesiAdaptiveExecutionClassifier.budgetFor(WesiWorkloadLevel.l4)
            .desktopWorkerRequired,
        isTrue,
      );
    });
  });

  group('Trusted workload registry', () {
    test('does not classify Local Runtime work as L0', () {
      expect(
        WesiTrustedWorkloadRegistry.require(WesiLocalToolNames.fsReadText)
            .level,
        WesiWorkloadLevel.l1,
      );
      expect(
        WesiTrustedWorkloadRegistry.require(WesiLocalToolNames.flutterAnalyze)
            .level,
        WesiWorkloadLevel.l2,
      );
      expect(
        WesiTrustedWorkloadRegistry.require(WesiLocalToolNames.flutterTest)
            .level,
        WesiWorkloadLevel.l3,
      );
      expect(
        WesiTrustedWorkloadRegistry.require(WesiLocalToolNames.flutterBuild)
            .level,
        WesiWorkloadLevel.l4,
      );
    });

    test('actual duration/GPU cost escalates lightweight base descriptors', () {
      final longPython = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
        estimatedDurationSeconds: 180,
      );
      expect(longPython.level, WesiWorkloadLevel.l3);
      expect(
          longPython.foregroundPolicy, WesiForegroundPolicy.foregroundRequired);

      final gpuPython = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
        extraFreeGpuVramMb: 4096,
      );
      expect(gpuPython.level, WesiWorkloadLevel.l4);
      expect(gpuPython.minFreeGpuVramMb, 4096);
    });

    test('Local Runtime target platforms cannot be widened to Android', () {
      expect(
        () => WesiTrustedWorkloadRegistry.requirementsFor(
          WesiLocalToolNames.pythonRun,
          allowedPlatforms: const <WesiWorkerPlatform>{
            WesiWorkerPlatform.android
          },
        ),
        throwsA(
          isA<WesiSchedulerPolicyException>().having(
            (error) => error.code,
            'code',
            'WS_INVALID_REQUIREMENTS',
          ),
        ),
      );
    });

    test('model-style negative resource relaxation is rejected', () {
      expect(
        () => WesiTrustedWorkloadRegistry.requirementsFor(
          WesiLocalToolNames.pythonRun,
          extraAvailableRamMb: -512,
        ),
        throwsA(
          isA<WesiSchedulerPolicyException>().having(
            (error) => error.code,
            'code',
            'WS_INVALID_REQUIREMENTS',
          ),
        ),
      );
    });
  });

  group('Resource scheduler', () {
    const scheduler = WesiResourceScheduler();

    test('selects a compatible trusted worker', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[_worker()],
      );
      expect(result.ok, isTrue);
      expect(result.worker!.id, 'local');
    });

    test('uses available RAM rather than total RAM', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(totalRamMb: 32768, availableRamMb: 4500),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.ram);
    });

    test('GPU job rejects 4 GB free VRAM and selects a valid 12 GB worker', () {
      final requirements = WesiTrustedWorkloadRegistry.gpuMediaRequirements(
        minFreeGpuVramMb: 8192,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(
            id: 'small-gpu',
            role: WesiWorkerRole.remoteWorker,
            trust: WesiWorkerTrust.paired,
            totalGpuVramMb: 8192,
            freeGpuVramMb: 4096,
          ),
          _worker(
            id: 'large-gpu',
            role: WesiWorkerRole.remoteWorker,
            trust: WesiWorkerTrust.paired,
            totalGpuVramMb: 16384,
            freeGpuVramMb: 12288,
          ),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.worker!.id, 'large-gpu');
    });

    test('heavy work never falls back to the control plane', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(
            id: 'control-plane',
            role: WesiWorkerRole.controlPlane,
            trust: WesiWorkerTrust.paired,
          ),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.policy);
    });

    test('L3/L4 require the execution worker to stay foregrounded', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterTest,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(appForeground: false, backgroundExecutionAllowed: true),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.foreground);
    });

    test('untrusted worker is fail-closed', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(trust: WesiWorkerTrust.untrusted),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.trust);
    });

    test('missing verified Runtime Pack blocks activation', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(installedPacks: const <WesiRuntimePackId>{
            WesiRuntimePackId.core
          }),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.runtimePacks);
    });

    test('high CPU load queues a heavy build instead of starting it', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[_worker(cpuLoadPercent: 90)],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.cpu);
    });

    test('serious thermal state blocks L4 work', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(thermalState: WesiThermalState.serious),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.thermal);
    });

    test('heavy concurrency is exclusive against CPU/heavy jobs', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[_worker(activeCpuJobs: 1)],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.concurrency);
    });

    test('remote-only job exposes the required offline-worker warning', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.flutterBuild,
        preference: WesiExecutionPreference.remoteOnly,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(
            id: 'paired-pc',
            role: WesiWorkerRole.remoteWorker,
            trust: WesiWorkerTrust.paired,
            status: WesiWorkerStatus.offline,
          ),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.requiresRemoteOnlineWarning, isTrue);
      expect(result.blocker, contains('Open WesiOS'));
    });

    test('corrupt resource telemetry is rejected before routing', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.pythonRun,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(totalRamMb: 4096, availableRamMb: 8192),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);
    });

    test('GPU telemetry cannot report free VRAM when total VRAM is zero', () {
      final requirements = WesiTrustedWorkloadRegistry.gpuMediaRequirements(
        minFreeGpuVramMb: 1024,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(totalGpuVramMb: 0, freeGpuVramMb: 4096),
        ],
      );
      expect(result.ok, isFalse);
      expect(result.blockerCode, WesiSchedulerBlockerCode.resourceSnapshot);
    });

    test('localPreferred stays local when both workers satisfy policy', () {
      final requirements = WesiTrustedWorkloadRegistry.requirementsFor(
        WesiLocalToolNames.gitStatus,
        preference: WesiExecutionPreference.localPreferred,
      );
      final result = scheduler.select(
        job: requirements,
        workers: <WesiWorkerResourceProfile>[
          _worker(id: 'local'),
          _worker(
            id: 'remote',
            role: WesiWorkerRole.remoteWorker,
            trust: WesiWorkerTrust.paired,
            cpuCores: 32,
            totalRamMb: 65536,
            availableRamMb: 60000,
          ),
        ],
      );
      expect(result.ok, isTrue);
      expect(result.worker!.id, 'local');
    });
  });
}
