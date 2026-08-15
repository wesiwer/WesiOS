import 'wesi_local_runtime_models.dart';
import 'wesi_resource_scheduler_models.dart';
import 'wesi_runtime_pack_models.dart';

class WesiAdaptiveExecutionClassifier {
  WesiAdaptiveExecutionClassifier._();

  static WesiWorkloadLevel classify(WesiAdaptiveExecutionFacts facts) {
    if (facts.estimatedSteps < 0 ||
        facts.estimatedDurationSeconds < 0 ||
        facts.estimatedPeakRamMb < 0 ||
        facts.estimatedGpuVramMb < 0 ||
        facts.requestedSubagents < 0) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_FACTS',
        'Adaptive execution facts cannot contain negative values',
      );
    }

    if (facts.requiresBuild ||
        facts.requiresBrowserAutomation ||
        facts.requiresHeavyMedia ||
        facts.requiresLargeFilePipeline ||
        facts.estimatedGpuVramMb > 0 ||
        facts.estimatedDurationSeconds >= 300 ||
        facts.estimatedPeakRamMb >= 8192) {
      return WesiWorkloadLevel.l4;
    }
    if (facts.requiresSelfDebug ||
        facts.requestedSubagents >= 2 ||
        facts.estimatedSteps >= 8 ||
        facts.estimatedDurationSeconds >= 120) {
      return WesiWorkloadLevel.l3;
    }
    if (facts.requiresLocalRuntime ||
        facts.requiresValidation ||
        facts.requestedSubagents == 1 ||
        facts.estimatedSteps >= 3 ||
        facts.estimatedDurationSeconds >= 30) {
      return WesiWorkloadLevel.l2;
    }
    if (facts.mutatesState || facts.usesTools || facts.estimatedSteps > 0) {
      return WesiWorkloadLevel.l1;
    }
    return WesiWorkloadLevel.l0;
  }

  static WesiExecutionBudget budgetFor(WesiWorkloadLevel level) {
    switch (level) {
      case WesiWorkloadLevel.l0:
        return const WesiExecutionBudget(
          level: WesiWorkloadLevel.l0,
          foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
          maxParallelJobs: 4,
          maxActiveSubagents: 0,
          maxRepairIterations: 0,
          maxWallClock: Duration(minutes: 2),
          localRuntimeAllowed: false,
          desktopWorkerRequired: false,
        );
      case WesiWorkloadLevel.l1:
        return const WesiExecutionBudget(
          level: WesiWorkloadLevel.l1,
          foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
          maxParallelJobs: 4,
          maxActiveSubagents: 0,
          maxRepairIterations: 0,
          maxWallClock: Duration(minutes: 5),
          localRuntimeAllowed: true,
          desktopWorkerRequired: false,
        );
      case WesiWorkloadLevel.l2:
        return const WesiExecutionBudget(
          level: WesiWorkloadLevel.l2,
          foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
          maxParallelJobs: 2,
          maxActiveSubagents: 1,
          maxRepairIterations: 1,
          maxWallClock: Duration(minutes: 20),
          localRuntimeAllowed: true,
          desktopWorkerRequired: false,
        );
      case WesiWorkloadLevel.l3:
        return const WesiExecutionBudget(
          level: WesiWorkloadLevel.l3,
          foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
          maxParallelJobs: 1,
          maxActiveSubagents: 2,
          maxRepairIterations: 3,
          maxWallClock: Duration(hours: 1),
          localRuntimeAllowed: true,
          desktopWorkerRequired: false,
        );
      case WesiWorkloadLevel.l4:
        return const WesiExecutionBudget(
          level: WesiWorkloadLevel.l4,
          foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
          maxParallelJobs: 1,
          maxActiveSubagents: 2,
          maxRepairIterations: 3,
          maxWallClock: Duration(hours: 2),
          localRuntimeAllowed: true,
          desktopWorkerRequired: true,
        );
    }
  }

  static WesiWorkloadLevel escalate(WesiWorkloadLevel current) {
    switch (current) {
      case WesiWorkloadLevel.l0:
        return WesiWorkloadLevel.l1;
      case WesiWorkloadLevel.l1:
        return WesiWorkloadLevel.l2;
      case WesiWorkloadLevel.l2:
        return WesiWorkloadLevel.l3;
      case WesiWorkloadLevel.l3:
      case WesiWorkloadLevel.l4:
        return WesiWorkloadLevel.l4;
    }
  }
}

class WesiTrustedWorkloadRegistry {
  WesiTrustedWorkloadRegistry._();

  static const Set<WesiWorkerPlatform> _desktop = <WesiWorkerPlatform>{
    WesiWorkerPlatform.windows,
    WesiWorkerPlatform.linux,
    WesiWorkerPlatform.macos,
  };

  static const Map<String, WesiTrustedWorkloadDescriptor> _tools =
      <String, WesiTrustedWorkloadDescriptor>{
    WesiLocalToolNames.fsList: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsList,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{
        WesiLocalCapability.filesystem
      },
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.fsReadText: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsReadText,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{
        WesiLocalCapability.filesystem
      },
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.gitStatus: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitStatus,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 64,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.gitDiff: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitDiff,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.fsWriteText: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsWriteText,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{
        WesiLocalCapability.filesystem
      },
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 64,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.fsDelete: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsDelete,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{
        WesiLocalCapability.filesystem
      },
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.gitAdd: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitAdd,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 128,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.gitCommit: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitCommit,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 128,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.httpGet: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.httpGet,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.http},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.httpPost: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.httpPost,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.http},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minAvailableRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.terminalRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.terminalRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.terminal},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 1,
      maxCpuLoadPercent: 90,
      minAvailableRamMb: 512,
      minFreeDiskMb: 256,
    ),
    WesiLocalToolNames.pythonRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.pythonRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.python},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 1,
      maxCpuLoadPercent: 90,
      minAvailableRamMb: 1024,
      minFreeDiskMb: 512,
      checkpointable: true,
    ),
    WesiLocalToolNames.nodeRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.nodeRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.node},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 1,
      maxCpuLoadPercent: 90,
      minAvailableRamMb: 1024,
      minFreeDiskMb: 512,
      checkpointable: true,
    ),
    WesiLocalToolNames.flutterAnalyze: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.flutterAnalyze,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.flutter},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 2,
      maxCpuLoadPercent: 85,
      minAvailableRamMb: 2048,
      minFreeDiskMb: 2048,
    ),
    WesiLocalToolNames.documentRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.documentRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{
        WesiLocalCapability.documents
      },
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.documents},
      minCpuCores: 1,
      maxCpuLoadPercent: 90,
      minAvailableRamMb: 1024,
      minFreeDiskMb: 1024,
      checkpointable: true,
    ),
    WesiLocalToolNames.flutterTest: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.flutterTest,
      level: WesiWorkloadLevel.l3,
      foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.flutter},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 2,
      maxCpuLoadPercent: 80,
      minAvailableRamMb: 3072,
      minFreeDiskMb: 4096,
      checkpointable: true,
    ),
    WesiLocalToolNames.flutterBuild: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.flutterBuild,
      level: WesiWorkloadLevel.l4,
      foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.build},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 2,
      maxCpuLoadPercent: 75,
      minAvailableRamMb: 4096,
      minFreeDiskMb: 8192,
      checkpointable: true,
    ),
    WesiLocalToolNames.mediaRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.mediaRun,
      level: WesiWorkloadLevel.l3,
      foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.media},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.media},
      minCpuCores: 2,
      maxCpuLoadPercent: 80,
      minAvailableRamMb: 4096,
      minFreeDiskMb: 8192,
      checkpointable: true,
    ),
  };

  static WesiTrustedWorkloadDescriptor require(String toolName) {
    final descriptor = _tools[toolName];
    if (descriptor == null) {
      throw WesiSchedulerPolicyException(
        'WS_UNKNOWN_WORKLOAD',
        'Unknown workload is not schedulable: $toolName',
      );
    }
    return descriptor;
  }

  static WesiJobRequirements requirementsFor(
    String toolName, {
    WesiExecutionPreference preference = WesiExecutionPreference.automatic,
    Set<WesiWorkerPlatform>? allowedPlatforms,
    int extraAvailableRamMb = 0,
    int extraFreeGpuVramMb = 0,
    int extraFreeDiskMb = 0,
    int extraCpuCores = 0,
    int estimatedDurationSeconds = 0,
  }) {
    if (extraAvailableRamMb < 0 ||
        extraFreeGpuVramMb < 0 ||
        extraFreeDiskMb < 0 ||
        extraCpuCores < 0 ||
        estimatedDurationSeconds < 0) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'Trusted resource requirements can only be tightened',
      );
    }
    final base = require(toolName);
    final platforms = allowedPlatforms ?? _desktop;
    if (platforms.isEmpty || !platforms.every(_desktop.contains)) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'Local Runtime workloads require a trusted desktop target platform',
      );
    }

    var level = base.level;
    if (extraFreeGpuVramMb > 0 || estimatedDurationSeconds >= 300) {
      level = WesiWorkloadLevel.l4;
    } else if (estimatedDurationSeconds >= 120 &&
        level.index < WesiWorkloadLevel.l3.index) {
      level = WesiWorkloadLevel.l3;
    }
    final foregroundPolicy = level.index >= WesiWorkloadLevel.l3.index
        ? WesiForegroundPolicy.foregroundRequired
        : base.foregroundPolicy;

    return WesiJobRequirements(
      toolName: base.toolName,
      level: level,
      requiredCapabilities: base.requiredCapabilities,
      requiredPacks: base.requiredPacks,
      allowedPlatforms: Set<WesiWorkerPlatform>.unmodifiable(platforms),
      minCpuCores: base.minCpuCores + extraCpuCores,
      maxCpuLoadPercent: base.maxCpuLoadPercent,
      minAvailableRamMb: base.minAvailableRamMb + extraAvailableRamMb,
      minFreeGpuVramMb: base.minFreeGpuVramMb + extraFreeGpuVramMb,
      minFreeDiskMb: base.minFreeDiskMb + extraFreeDiskMb,
      estimatedDurationSeconds: estimatedDurationSeconds,
      preference: preference,
      foregroundPolicy: foregroundPolicy,
      checkpointable: base.checkpointable,
      remoteAllowed: base.remoteAllowed,
      allowControlPlane: base.allowControlPlane,
    );
  }

  static WesiJobRequirements gpuMediaRequirements({
    int minFreeGpuVramMb = 8192,
    int minAvailableRamMb = 8192,
    int minFreeDiskMb = 16384,
    WesiExecutionPreference preference = WesiExecutionPreference.automatic,
  }) {
    if (minFreeGpuVramMb <= 0 || minAvailableRamMb <= 0 || minFreeDiskMb <= 0) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'GPU workload resources must be positive',
      );
    }
    return WesiJobRequirements(
      toolName: WesiLocalToolNames.mediaRun,
      level: WesiWorkloadLevel.l4,
      requiredCapabilities: const <WesiLocalCapability>{
        WesiLocalCapability.media
      },
      requiredPacks: const <WesiRuntimePackId>{WesiRuntimePackId.media},
      allowedPlatforms: _desktop,
      minCpuCores: 4,
      maxCpuLoadPercent: 75,
      minAvailableRamMb: minAvailableRamMb,
      minFreeGpuVramMb: minFreeGpuVramMb,
      minFreeDiskMb: minFreeDiskMb,
      estimatedDurationSeconds: 0,
      preference: preference,
      foregroundPolicy: WesiForegroundPolicy.foregroundRequired,
      checkpointable: true,
      remoteAllowed: true,
      allowControlPlane: false,
    );
  }
}

class WesiResourceScheduler {
  final WesiSchedulerConcurrencyPolicy concurrency;

  const WesiResourceScheduler({
    this.concurrency = const WesiSchedulerConcurrencyPolicy(),
  });

  WesiWorkerSelection select({
    required WesiJobRequirements job,
    required List<WesiWorkerResourceProfile> workers,
  }) {
    if (workers.isEmpty) {
      return const WesiWorkerSelection.blocked(
        WesiSchedulerBlockerCode.noWorkers,
        'No Wesi Worker is registered for this task.',
      );
    }

    final eligible = <WesiWorkerResourceProfile>[];
    final blockers = <WesiSchedulerBlockerCode>{};
    var hasRemote = false;
    var hasRemoteOffline = false;
    for (final worker in workers) {
      if (worker.remoteWorker) {
        hasRemote = true;
        if (!worker.online) hasRemoteOffline = true;
      }
      final blocker = _blockerFor(job, worker);
      if (blocker == null) {
        eligible.add(worker);
      } else {
        blockers.add(blocker);
      }
    }

    final preferred = _applyPreference(job, eligible);
    if (preferred.isNotEmpty) {
      preferred.sort((a, b) {
        final score = _score(b, job).compareTo(_score(a, job));
        if (score != 0) return score;
        return a.id.compareTo(b.id);
      });
      return WesiWorkerSelection.ok(preferred.first);
    }

    final preferenceBlocks =
        job.preference == WesiExecutionPreference.remoteOnly ||
            job.preference == WesiExecutionPreference.localOnly;
    if (preferenceBlocks && eligible.isNotEmpty) {
      return WesiWorkerSelection.blocked(
        WesiSchedulerBlockerCode.preference,
        'Available workers do not satisfy the requested local/remote preference.',
        remoteWarning: job.preference == WesiExecutionPreference.remoteOnly,
      );
    }

    final code = _bestBlocker(blockers);
    final remoteWarning = job.remoteAllowed &&
        (job.preference == WesiExecutionPreference.remoteOnly ||
            (hasRemote && hasRemoteOffline));
    return WesiWorkerSelection.blocked(
      code,
      _blockerMessage(code, remoteWarning: remoteWarning),
      remoteWarning: remoteWarning,
    );
  }

  WesiSchedulerBlockerCode? _blockerFor(
    WesiJobRequirements job,
    WesiWorkerResourceProfile worker,
  ) {
    if (!worker.online) return WesiSchedulerBlockerCode.offline;
    if (!worker.trusted) return WesiSchedulerBlockerCode.trust;
    if (!worker.policyAllowed) return WesiSchedulerBlockerCode.policy;
    if (worker.controlPlane && (!job.allowControlPlane || job.heavy)) {
      return WesiSchedulerBlockerCode.policy;
    }
    if (!job.remoteAllowed && worker.remoteWorker) {
      return WesiSchedulerBlockerCode.policy;
    }
    if (!job.allowedPlatforms.contains(worker.platform)) {
      return WesiSchedulerBlockerCode.platform;
    }
    if (!worker.supportsCapabilities(job.requiredCapabilities)) {
      return WesiSchedulerBlockerCode.capabilities;
    }
    if (!worker.supportsPacks(job.requiredPacks)) {
      return WesiSchedulerBlockerCode.runtimePacks;
    }
    if (!worker.resourceSnapshotSane) {
      return WesiSchedulerBlockerCode.resourceSnapshot;
    }
    if (worker.cpuCores < job.minCpuCores ||
        worker.cpuLoadPercent > job.maxCpuLoadPercent) {
      return WesiSchedulerBlockerCode.cpu;
    }
    if (worker.availableRamMb <
        job.minAvailableRamMb + concurrency.reserveRamMb) {
      return WesiSchedulerBlockerCode.ram;
    }
    if (job.gpuRequired &&
        worker.freeGpuVramMb <
            job.minFreeGpuVramMb + concurrency.reserveGpuVramMb) {
      return WesiSchedulerBlockerCode.gpu;
    }
    if (worker.freeDiskMb < job.minFreeDiskMb + concurrency.reserveDiskMb) {
      return WesiSchedulerBlockerCode.disk;
    }
    if (worker.thermalState == WesiThermalState.critical ||
        (job.level == WesiWorkloadLevel.l4 &&
            worker.thermalState == WesiThermalState.serious)) {
      return WesiSchedulerBlockerCode.thermal;
    }
    final heavyNeedsForeground =
        job.level == WesiWorkloadLevel.l3 || job.level == WesiWorkloadLevel.l4;
    if (!worker.appForeground &&
        (heavyNeedsForeground ||
            job.foregroundPolicy == WesiForegroundPolicy.foregroundRequired ||
            !worker.backgroundExecutionAllowed)) {
      return WesiSchedulerBlockerCode.foreground;
    }
    if (!_hasConcurrency(job, worker)) {
      return WesiSchedulerBlockerCode.concurrency;
    }
    return null;
  }

  List<WesiWorkerResourceProfile> _applyPreference(
    WesiJobRequirements job,
    List<WesiWorkerResourceProfile> eligible,
  ) {
    if (eligible.isEmpty) return const <WesiWorkerResourceProfile>[];
    switch (job.preference) {
      case WesiExecutionPreference.localOnly:
        return eligible.where((worker) => worker.localDevice).toList();
      case WesiExecutionPreference.remoteOnly:
        return eligible.where((worker) => worker.remoteWorker).toList();
      case WesiExecutionPreference.localPreferred:
        final local = eligible.where((worker) => worker.localDevice).toList();
        return local.isNotEmpty ? local : eligible;
      case WesiExecutionPreference.remotePreferred:
        final remote = eligible.where((worker) => worker.remoteWorker).toList();
        return remote.isNotEmpty ? remote : eligible;
      case WesiExecutionPreference.automatic:
        return eligible;
    }
  }

  bool _hasConcurrency(
    WesiJobRequirements job,
    WesiWorkerResourceProfile worker,
  ) {
    if (worker.totalActiveJobs >= concurrency.maxTotalJobsPerWorker)
      return false;
    switch (job.level) {
      case WesiWorkloadLevel.l0:
      case WesiWorkloadLevel.l1:
        return worker.activeLightJobs < concurrency.maxLightJobsPerWorker;
      case WesiWorkloadLevel.l2:
        return worker.activeCpuJobs < concurrency.maxCpuJobsPerWorker &&
            worker.activeHeavyJobs == 0 &&
            worker.activeGpuJobs == 0;
      case WesiWorkloadLevel.l3:
        return worker.activeHeavyJobs < concurrency.maxHeavyJobsPerWorker &&
            worker.activeCpuJobs == 0 &&
            worker.activeGpuJobs == 0;
      case WesiWorkloadLevel.l4:
        return worker.activeHeavyJobs == 0 &&
            worker.activeCpuJobs == 0 &&
            worker.activeGpuJobs < concurrency.maxGpuJobsPerWorker;
    }
  }

  int _score(WesiWorkerResourceProfile worker, WesiJobRequirements job) {
    var score = 0;
    if (worker.status == WesiWorkerStatus.online) score += 200;
    if (job.level.index <= WesiWorkloadLevel.l2.index && worker.localDevice) {
      score += 80;
    }
    if (job.level == WesiWorkloadLevel.l4 && worker.remoteWorker) score += 20;
    score += worker.cpuCores * 10;
    score += (worker.availableRamMb - concurrency.reserveRamMb) ~/ 256;
    score += (worker.freeDiskMb - concurrency.reserveDiskMb) ~/ 4096;
    score += ((100 - worker.cpuLoadPercent).clamp(0, 100)).round();
    if (job.gpuRequired) score += worker.freeGpuVramMb ~/ 256;
    score -= worker.totalActiveJobs * 60;
    if (worker.powerMode == WesiPowerMode.lowPower && job.heavy) score -= 200;
    if (worker.thermalState == WesiThermalState.fair) score -= 20;
    if (worker.thermalState == WesiThermalState.serious) score -= 100;
    switch (job.preference) {
      case WesiExecutionPreference.localPreferred:
        if (worker.localDevice) score += 1000;
      case WesiExecutionPreference.remotePreferred:
        if (worker.remoteWorker) score += 1000;
      case WesiExecutionPreference.automatic:
      case WesiExecutionPreference.localOnly:
      case WesiExecutionPreference.remoteOnly:
        break;
    }
    return score;
  }

  WesiSchedulerBlockerCode _bestBlocker(
    Set<WesiSchedulerBlockerCode> blockers,
  ) {
    const order = <WesiSchedulerBlockerCode>[
      WesiSchedulerBlockerCode.trust,
      WesiSchedulerBlockerCode.policy,
      WesiSchedulerBlockerCode.resourceSnapshot,
      WesiSchedulerBlockerCode.runtimePacks,
      WesiSchedulerBlockerCode.capabilities,
      WesiSchedulerBlockerCode.platform,
      WesiSchedulerBlockerCode.thermal,
      WesiSchedulerBlockerCode.gpu,
      WesiSchedulerBlockerCode.ram,
      WesiSchedulerBlockerCode.disk,
      WesiSchedulerBlockerCode.cpu,
      WesiSchedulerBlockerCode.foreground,
      WesiSchedulerBlockerCode.concurrency,
      WesiSchedulerBlockerCode.offline,
    ];
    for (final code in order) {
      if (blockers.contains(code)) return code;
    }
    return WesiSchedulerBlockerCode.noWorkers;
  }

  String _blockerMessage(
    WesiSchedulerBlockerCode code, {
    required bool remoteWarning,
  }) {
    if (remoteWarning && code == WesiSchedulerBlockerCode.offline) {
      return 'A suitable desktop Wesi Worker is offline. Open WesiOS on the paired computer and keep it available during execution.';
    }
    switch (code) {
      case WesiSchedulerBlockerCode.noWorkers:
        return 'No suitable Wesi Worker is available.';
      case WesiSchedulerBlockerCode.offline:
        return 'Suitable Wesi Workers are offline.';
      case WesiSchedulerBlockerCode.trust:
        return 'A worker exists but is not trusted/paired.';
      case WesiSchedulerBlockerCode.policy:
        return 'Execution is denied by worker or scheduling policy.';
      case WesiSchedulerBlockerCode.preference:
        return 'Worker preference cannot be satisfied.';
      case WesiSchedulerBlockerCode.platform:
        return 'No worker has a supported platform for this workload.';
      case WesiSchedulerBlockerCode.capabilities:
        return 'Required worker capabilities are unavailable.';
      case WesiSchedulerBlockerCode.runtimePacks:
        return 'Required Runtime Packs are not installed/verified.';
      case WesiSchedulerBlockerCode.resourceSnapshot:
        return 'Worker resource telemetry is invalid or incomplete.';
      case WesiSchedulerBlockerCode.cpu:
        return 'Available workers do not have enough CPU headroom.';
      case WesiSchedulerBlockerCode.ram:
        return 'Available workers do not have enough free RAM headroom.';
      case WesiSchedulerBlockerCode.gpu:
        return 'Available GPUs do not satisfy the free VRAM requirement.';
      case WesiSchedulerBlockerCode.disk:
        return 'Available workers do not have enough free disk space.';
      case WesiSchedulerBlockerCode.thermal:
        return 'Worker thermal state is unsafe for this workload.';
      case WesiSchedulerBlockerCode.foreground:
        return 'This workload requires WesiOS to remain open on the execution worker.';
      case WesiSchedulerBlockerCode.concurrency:
        return 'Worker concurrency limits are currently saturated.';
    }
  }
}
