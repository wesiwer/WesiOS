import 'wesi_local_runtime_models.dart';
import 'wesi_resource_scheduler_models.dart';
import 'wesi_runtime_pack_models.dart';

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
      level: WesiWorkloadLevel.l0,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.filesystem},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.fsReadText: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsReadText,
      level: WesiWorkloadLevel.l0,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.filesystem},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.gitStatus: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitStatus,
      level: WesiWorkloadLevel.l0,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 64,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.gitDiff: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitDiff,
      level: WesiWorkloadLevel.l0,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.fsWriteText: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsWriteText,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.filesystem},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 64,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.fsDelete: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.fsDelete,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.filesystem},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 64,
      minFreeDiskMb: 16,
    ),
    WesiLocalToolNames.gitAdd: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitAdd,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 128,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.gitCommit: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.gitCommit,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.git},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 128,
      minFreeDiskMb: 128,
    ),
    WesiLocalToolNames.httpGet: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.httpGet,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.http},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.httpPost: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.httpPost,
      level: WesiWorkloadLevel.l1,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.http},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.core},
      minRamMb: 128,
      minFreeDiskMb: 64,
    ),
    WesiLocalToolNames.terminalRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.terminalRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.terminal},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 1,
      minRamMb: 512,
      minFreeDiskMb: 256,
      checkpointable: false,
    ),
    WesiLocalToolNames.pythonRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.pythonRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.python},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 1,
      minRamMb: 1024,
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
      minRamMb: 1024,
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
      minRamMb: 2048,
      minFreeDiskMb: 2048,
      checkpointable: false,
    ),
    WesiLocalToolNames.documentRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.documentRun,
      level: WesiWorkloadLevel.l2,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.documents},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.documents},
      minCpuCores: 1,
      minRamMb: 1024,
      minFreeDiskMb: 1024,
      checkpointable: true,
    ),
    WesiLocalToolNames.flutterTest: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.flutterTest,
      level: WesiWorkloadLevel.l3,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.flutter},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 2,
      minRamMb: 3072,
      minFreeDiskMb: 4096,
      checkpointable: true,
    ),
    WesiLocalToolNames.flutterBuild: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.flutterBuild,
      level: WesiWorkloadLevel.l3,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.build},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.developer},
      minCpuCores: 2,
      minRamMb: 4096,
      minFreeDiskMb: 8192,
      checkpointable: true,
    ),
    WesiLocalToolNames.mediaRun: WesiTrustedWorkloadDescriptor(
      toolName: WesiLocalToolNames.mediaRun,
      level: WesiWorkloadLevel.l3,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      requiredCapabilities: <WesiLocalCapability>{WesiLocalCapability.media},
      requiredPacks: <WesiRuntimePackId>{WesiRuntimePackId.media},
      minCpuCores: 2,
      minRamMb: 4096,
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
    int extraRamMb = 0,
    int extraGpuVramMb = 0,
    int extraDiskMb = 0,
    int extraCpuCores = 0,
  }) {
    if (extraRamMb < 0 ||
        extraGpuVramMb < 0 ||
        extraDiskMb < 0 ||
        extraCpuCores < 0) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'Resource requirements can only be tightened, never reduced',
      );
    }
    final base = require(toolName);
    final platforms = allowedPlatforms ?? _desktop;
    if (platforms.isEmpty) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'At least one trusted target platform is required',
      );
    }
    return WesiJobRequirements(
      toolName: base.toolName,
      level: base.level,
      requiredCapabilities: base.requiredCapabilities,
      requiredPacks: base.requiredPacks,
      allowedPlatforms: Set<WesiWorkerPlatform>.unmodifiable(platforms),
      minCpuCores: base.minCpuCores + extraCpuCores,
      minRamMb: base.minRamMb + extraRamMb,
      minGpuVramMb: base.minGpuVramMb + extraGpuVramMb,
      minFreeDiskMb: base.minFreeDiskMb + extraDiskMb,
      preference: preference,
      foregroundPolicy: base.foregroundPolicy,
      checkpointable: base.checkpointable,
      remoteAllowed: base.remoteAllowed,
    );
  }

  static WesiJobRequirements gpuMediaRequirements({
    int minGpuVramMb = 8192,
    int minRamMb = 8192,
    int minFreeDiskMb = 16384,
    WesiExecutionPreference preference = WesiExecutionPreference.automatic,
  }) {
    if (minGpuVramMb <= 0 || minRamMb <= 0 || minFreeDiskMb <= 0) {
      throw const WesiSchedulerPolicyException(
        'WS_INVALID_REQUIREMENTS',
        'GPU workload resources must be positive',
      );
    }
    return WesiJobRequirements(
      toolName: WesiLocalToolNames.mediaRun,
      level: WesiWorkloadLevel.l4,
      requiredCapabilities: const <WesiLocalCapability>{WesiLocalCapability.media},
      requiredPacks: const <WesiRuntimePackId>{WesiRuntimePackId.media},
      allowedPlatforms: _desktop,
      minCpuCores: 4,
      minRamMb: minRamMb,
      minGpuVramMb: minGpuVramMb,
      minFreeDiskMb: minFreeDiskMb,
      preference: preference,
      foregroundPolicy: WesiForegroundPolicy.backgroundAllowed,
      checkpointable: true,
      remoteAllowed: true,
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
      if (!worker.localDevice) {
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

    final preferenceBlocks = job.preference == WesiExecutionPreference.remoteOnly ||
        job.preference == WesiExecutionPreference.localOnly;
    if (preferenceBlocks && eligible.isNotEmpty) {
      return WesiWorkerSelection.blocked(
        WesiSchedulerBlockerCode.preference,
        'Available workers do not satisfy the requested local/remote preference.',
        remoteWarning: job.preference == WesiExecutionPreference.remoteOnly,
      );
    }

    final code = _bestBlocker(blockers);
    final remoteWarning = !job.remoteAllowed
        ? false
        : (job.preference == WesiExecutionPreference.remoteOnly ||
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
    if (!job.remoteAllowed && !worker.localDevice) {
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
    if (worker.cpuCores < job.minCpuCores) return WesiSchedulerBlockerCode.cpu;
    if (worker.ramMb < job.minRamMb + concurrency.reserveRamMb) {
      return WesiSchedulerBlockerCode.ram;
    }
    if (worker.gpuVramMb < job.minGpuVramMb) {
      return WesiSchedulerBlockerCode.gpu;
    }
    if (worker.freeDiskMb < job.minFreeDiskMb + concurrency.reserveDiskMb) {
      return WesiSchedulerBlockerCode.disk;
    }
    if (!worker.appForeground &&
        (job.foregroundPolicy == WesiForegroundPolicy.foregroundRequired ||
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
        return eligible.where((worker) => !worker.localDevice).toList();
      case WesiExecutionPreference.localPreferred:
        final local = eligible.where((worker) => worker.localDevice).toList();
        return local.isNotEmpty ? local : eligible;
      case WesiExecutionPreference.remotePreferred:
        final remote = eligible.where((worker) => !worker.localDevice).toList();
        return remote.isNotEmpty ? remote : eligible;
      case WesiExecutionPreference.automatic:
        return eligible;
    }
  }

  bool _hasConcurrency(
    WesiJobRequirements job,
    WesiWorkerResourceProfile worker,
  ) {
    switch (job.level) {
      case WesiWorkloadLevel.l0:
      case WesiWorkloadLevel.l1:
        return worker.activeLightJobs < concurrency.maxLightJobsPerWorker;
      case WesiWorkloadLevel.l2:
        return worker.activeCpuJobs < concurrency.maxCpuJobsPerWorker;
      case WesiWorkloadLevel.l3:
        return worker.activeHeavyJobs < concurrency.maxHeavyJobsPerWorker;
      case WesiWorkloadLevel.l4:
        return worker.activeHeavyJobs < concurrency.maxHeavyJobsPerWorker &&
            worker.activeGpuJobs < concurrency.maxGpuJobsPerWorker;
    }
  }

  int _score(WesiWorkerResourceProfile worker, WesiJobRequirements job) {
    var score = 0;
    if (worker.status == WesiWorkerStatus.online) score += 200;
    if (worker.localDevice) score += 40;
    score += worker.cpuCores * 10;
    score += (worker.ramMb - concurrency.reserveRamMb) ~/ 512;
    score += (worker.freeDiskMb - concurrency.reserveDiskMb) ~/ 4096;
    if (job.gpuRequired) score += worker.gpuVramMb ~/ 256;
    score -= worker.totalActiveJobs * 50;
    switch (job.preference) {
      case WesiExecutionPreference.localPreferred:
        if (worker.localDevice) score += 1000;
      case WesiExecutionPreference.remotePreferred:
        if (!worker.localDevice) score += 1000;
      case WesiExecutionPreference.automatic:
      case WesiExecutionPreference.localOnly:
      case WesiExecutionPreference.remoteOnly:
        break;
    }
    return score;
  }

  WesiSchedulerBlockerCode _bestBlocker(
      Set<WesiSchedulerBlockerCode> blockers) {
    const order = <WesiSchedulerBlockerCode>[
      WesiSchedulerBlockerCode.trust,
      WesiSchedulerBlockerCode.policy,
      WesiSchedulerBlockerCode.runtimePacks,
      WesiSchedulerBlockerCode.capabilities,
      WesiSchedulerBlockerCode.platform,
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
      case WesiSchedulerBlockerCode.cpu:
        return 'Available workers do not have enough CPU capacity.';
      case WesiSchedulerBlockerCode.ram:
        return 'Available workers do not have enough RAM headroom.';
      case WesiSchedulerBlockerCode.gpu:
        return 'Available GPUs do not satisfy the VRAM requirement.';
      case WesiSchedulerBlockerCode.disk:
        return 'Available workers do not have enough free disk space.';
      case WesiSchedulerBlockerCode.foreground:
        return 'The worker must be foregrounded or allow background execution.';
      case WesiSchedulerBlockerCode.concurrency:
        return 'Worker concurrency limits are currently saturated.';
    }
  }
}
