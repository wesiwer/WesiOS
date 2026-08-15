import 'wesi_local_runtime_models.dart';
import 'wesi_runtime_pack_models.dart';

enum WesiWorkloadLevel { l0, l1, l2, l3, l4 }

enum WesiWorkerPlatform { android, ios, windows, linux, macos, unknown }

enum WesiWorkerStatus { offline, online, busy, paused }

enum WesiWorkerTrust { local, paired, untrusted }

enum WesiWorkerRole { localDevice, remoteWorker, controlPlane }

enum WesiThermalState { unknown, nominal, fair, serious, critical }

enum WesiPowerMode { unknown, normal, lowPower, charging }

enum WesiExecutionPreference {
  automatic,
  localPreferred,
  localOnly,
  remotePreferred,
  remoteOnly,
}

enum WesiForegroundPolicy { foregroundRequired, backgroundAllowed }

enum WesiJobPriority { low, normal, high, urgent }

enum WesiScheduledJobState {
  queued,
  running,
  pauseRequested,
  paused,
  waitingForWorker,
  cancelling,
  cancelled,
  succeeded,
  failed,
  blocked,
}

enum WesiSchedulerBlockerCode {
  noWorkers,
  offline,
  trust,
  policy,
  preference,
  platform,
  capabilities,
  runtimePacks,
  resourceSnapshot,
  cpu,
  ram,
  gpu,
  disk,
  thermal,
  foreground,
  concurrency,
}

enum WesiJobEventKind {
  queued,
  selected,
  started,
  progress,
  checkpointed,
  pauseRequested,
  paused,
  waitingForWorker,
  resumed,
  cancelRequested,
  cancelled,
  succeeded,
  failed,
  blocked,
}

class WesiSchedulerPolicyException implements Exception {
  final String code;
  final String message;

  const WesiSchedulerPolicyException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

/// Trusted orchestration facts used to choose the minimum sufficient L0-L4
/// execution path. These values are application-owned policy inputs and are not
/// deserialized directly from LLM tool arguments.
class WesiAdaptiveExecutionFacts {
  final bool mutatesState;
  final bool usesTools;
  final bool requiresLocalRuntime;
  final bool requiresValidation;
  final bool requiresBuild;
  final bool requiresBrowserAutomation;
  final bool requiresHeavyMedia;
  final bool requiresLargeFilePipeline;
  final bool requiresSelfDebug;
  final int estimatedSteps;
  final int estimatedDurationSeconds;
  final int estimatedPeakRamMb;
  final int estimatedGpuVramMb;
  final int requestedSubagents;

  const WesiAdaptiveExecutionFacts({
    this.mutatesState = false,
    this.usesTools = false,
    this.requiresLocalRuntime = false,
    this.requiresValidation = false,
    this.requiresBuild = false,
    this.requiresBrowserAutomation = false,
    this.requiresHeavyMedia = false,
    this.requiresLargeFilePipeline = false,
    this.requiresSelfDebug = false,
    this.estimatedSteps = 0,
    this.estimatedDurationSeconds = 0,
    this.estimatedPeakRamMb = 0,
    this.estimatedGpuVramMb = 0,
    this.requestedSubagents = 0,
  });
}

class WesiExecutionBudget {
  final WesiWorkloadLevel level;
  final WesiForegroundPolicy foregroundPolicy;
  final int maxParallelJobs;
  final int maxActiveSubagents;
  final int maxRepairIterations;
  final Duration maxWallClock;
  final bool localRuntimeAllowed;
  final bool desktopWorkerRequired;

  const WesiExecutionBudget({
    required this.level,
    required this.foregroundPolicy,
    required this.maxParallelJobs,
    required this.maxActiveSubagents,
    required this.maxRepairIterations,
    required this.maxWallClock,
    required this.localRuntimeAllowed,
    required this.desktopWorkerRequired,
  });
}

class WesiTrustedWorkloadDescriptor {
  final String toolName;
  final WesiWorkloadLevel level;
  final WesiForegroundPolicy foregroundPolicy;
  final Set<WesiLocalCapability> requiredCapabilities;
  final Set<WesiRuntimePackId> requiredPacks;
  final int minCpuCores;
  final double maxCpuLoadPercent;
  final int minAvailableRamMb;
  final int minFreeGpuVramMb;
  final int minFreeDiskMb;
  final bool checkpointable;
  final bool remoteAllowed;
  final bool allowControlPlane;

  const WesiTrustedWorkloadDescriptor({
    required this.toolName,
    required this.level,
    required this.foregroundPolicy,
    required this.requiredCapabilities,
    this.requiredPacks = const <WesiRuntimePackId>{},
    this.minCpuCores = 1,
    this.maxCpuLoadPercent = 95,
    this.minAvailableRamMb = 0,
    this.minFreeGpuVramMb = 0,
    this.minFreeDiskMb = 0,
    this.checkpointable = false,
    this.remoteAllowed = true,
    this.allowControlPlane = false,
  });
}

class WesiJobRequirements {
  final String toolName;
  final WesiWorkloadLevel level;
  final Set<WesiLocalCapability> requiredCapabilities;
  final Set<WesiRuntimePackId> requiredPacks;
  final Set<WesiWorkerPlatform> allowedPlatforms;
  final int minCpuCores;
  final double maxCpuLoadPercent;
  final int minAvailableRamMb;
  final int minFreeGpuVramMb;
  final int minFreeDiskMb;
  final int estimatedDurationSeconds;
  final WesiExecutionPreference preference;
  final WesiForegroundPolicy foregroundPolicy;
  final bool checkpointable;
  final bool remoteAllowed;
  final bool allowControlPlane;

  const WesiJobRequirements({
    required this.toolName,
    required this.level,
    required this.requiredCapabilities,
    required this.requiredPacks,
    required this.allowedPlatforms,
    required this.minCpuCores,
    required this.maxCpuLoadPercent,
    required this.minAvailableRamMb,
    required this.minFreeGpuVramMb,
    required this.minFreeDiskMb,
    required this.estimatedDurationSeconds,
    required this.preference,
    required this.foregroundPolicy,
    required this.checkpointable,
    required this.remoteAllowed,
    required this.allowControlPlane,
  });

  bool get gpuRequired => minFreeGpuVramMb > 0;

  bool get heavy =>
      level == WesiWorkloadLevel.l3 || level == WesiWorkloadLevel.l4;
}

class WesiWorkerResourceProfile {
  final String id;
  final String name;
  final WesiWorkerPlatform platform;
  final WesiWorkerStatus status;
  final WesiWorkerTrust trust;
  final WesiWorkerRole role;
  final bool policyAllowed;
  final bool appForeground;
  final bool backgroundExecutionAllowed;
  final int cpuCores;
  final double cpuLoadPercent;
  final int totalRamMb;
  final int availableRamMb;
  final String? gpuName;
  final int totalGpuVramMb;
  final int freeGpuVramMb;
  final int freeDiskMb;
  final WesiThermalState thermalState;
  final WesiPowerMode powerMode;
  final Set<WesiLocalCapability> capabilities;
  final Set<WesiRuntimePackId> installedPacks;
  final int activeLightJobs;
  final int activeCpuJobs;
  final int activeHeavyJobs;
  final int activeGpuJobs;
  final DateTime? lastSeenAt;

  const WesiWorkerResourceProfile({
    required this.id,
    required this.name,
    required this.platform,
    required this.status,
    required this.trust,
    required this.role,
    required this.policyAllowed,
    required this.appForeground,
    required this.backgroundExecutionAllowed,
    required this.cpuCores,
    required this.cpuLoadPercent,
    required this.totalRamMb,
    required this.availableRamMb,
    required this.freeDiskMb,
    required this.capabilities,
    required this.installedPacks,
    this.gpuName,
    this.totalGpuVramMb = 0,
    this.freeGpuVramMb = 0,
    this.thermalState = WesiThermalState.unknown,
    this.powerMode = WesiPowerMode.unknown,
    this.activeLightJobs = 0,
    this.activeCpuJobs = 0,
    this.activeHeavyJobs = 0,
    this.activeGpuJobs = 0,
    this.lastSeenAt,
  });

  bool get online =>
      status == WesiWorkerStatus.online || status == WesiWorkerStatus.busy;

  bool get localDevice => role == WesiWorkerRole.localDevice;

  bool get remoteWorker => role == WesiWorkerRole.remoteWorker;

  bool get controlPlane => role == WesiWorkerRole.controlPlane;

  bool get desktop =>
      platform == WesiWorkerPlatform.windows ||
      platform == WesiWorkerPlatform.linux ||
      platform == WesiWorkerPlatform.macos;

  bool supportsCapabilities(Set<WesiLocalCapability> required) =>
      required.every(capabilities.contains);

  bool supportsPacks(Set<WesiRuntimePackId> required) =>
      required.every(installedPacks.contains);

  bool get trusted =>
      trust == WesiWorkerTrust.local || trust == WesiWorkerTrust.paired;

  bool get resourceSnapshotSane =>
      cpuCores > 0 &&
      cpuLoadPercent >= 0 &&
      cpuLoadPercent <= 100 &&
      totalRamMb >= 0 &&
      availableRamMb >= 0 &&
      availableRamMb <= totalRamMb &&
      totalGpuVramMb >= 0 &&
      freeGpuVramMb >= 0 &&
      freeGpuVramMb <= totalGpuVramMb &&
      freeDiskMb >= 0 &&
      activeLightJobs >= 0 &&
      activeCpuJobs >= 0 &&
      activeHeavyJobs >= 0 &&
      activeGpuJobs >= 0;

  int get totalActiveJobs =>
      activeLightJobs + activeCpuJobs + activeHeavyJobs + activeGpuJobs;
}

class WesiSchedulerConcurrencyPolicy {
  final int maxLightJobsPerWorker;
  final int maxCpuJobsPerWorker;
  final int maxHeavyJobsPerWorker;
  final int maxGpuJobsPerWorker;
  final int maxTotalJobsPerWorker;
  final int reserveRamMb;
  final int reserveGpuVramMb;
  final int reserveDiskMb;

  const WesiSchedulerConcurrencyPolicy({
    this.maxLightJobsPerWorker = 4,
    this.maxCpuJobsPerWorker = 2,
    this.maxHeavyJobsPerWorker = 1,
    this.maxGpuJobsPerWorker = 1,
    this.maxTotalJobsPerWorker = 6,
    this.reserveRamMb = 1024,
    this.reserveGpuVramMb = 512,
    this.reserveDiskMb = 2048,
  });
}

class WesiWorkerSelection {
  final WesiWorkerResourceProfile? worker;
  final WesiSchedulerBlockerCode? blockerCode;
  final String? blocker;
  final bool requiresRemoteOnlineWarning;

  const WesiWorkerSelection._({
    this.worker,
    this.blockerCode,
    this.blocker,
    this.requiresRemoteOnlineWarning = false,
  });

  const WesiWorkerSelection.ok(WesiWorkerResourceProfile worker)
      : this._(worker: worker);

  const WesiWorkerSelection.blocked(
    WesiSchedulerBlockerCode code,
    String message, {
    bool remoteWarning = false,
  }) : this._(
          blockerCode: code,
          blocker: message,
          requiresRemoteOnlineWarning: remoteWarning,
        );

  bool get ok => worker != null;
}

class WesiJobCheckpointRef {
  final String checkpointId;
  final int version;
  final String stage;
  final double progress;
  final DateTime createdAt;

  const WesiJobCheckpointRef({
    required this.checkpointId,
    required this.version,
    required this.stage,
    required this.progress,
    required this.createdAt,
  });

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(checkpointId) ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(stage) ||
        version < 1 ||
        progress < 0 ||
        progress > 1) {
      throw const WesiSchedulerPolicyException(
        'WS_BAD_CHECKPOINT',
        'Checkpoint reference is invalid',
      );
    }
  }
}

class WesiJobEvent {
  final WesiJobEventKind kind;
  final DateTime at;
  final String message;

  const WesiJobEvent({
    required this.kind,
    required this.at,
    required this.message,
  });
}

class WesiScheduledJob {
  final String id;
  final WesiJobRequirements requirements;
  final WesiJobPriority priority;
  final WesiScheduledJobState state;
  final DateTime queuedAt;
  final DateTime updatedAt;
  final String? workerId;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final double progress;
  final String? currentStage;
  final WesiJobCheckpointRef? checkpoint;
  final String? failureCode;
  final List<WesiJobEvent> events;

  const WesiScheduledJob({
    required this.id,
    required this.requirements,
    required this.priority,
    required this.state,
    required this.queuedAt,
    required this.updatedAt,
    required this.progress,
    required this.events,
    this.workerId,
    this.startedAt,
    this.finishedAt,
    this.currentStage,
    this.checkpoint,
    this.failureCode,
  });

  bool get terminal =>
      state == WesiScheduledJobState.cancelled ||
      state == WesiScheduledJobState.succeeded ||
      state == WesiScheduledJobState.failed;

  WesiScheduledJob copyWith({
    WesiScheduledJobState? state,
    DateTime? updatedAt,
    Object? workerId = _unset,
    Object? startedAt = _unset,
    Object? finishedAt = _unset,
    double? progress,
    Object? currentStage = _unset,
    Object? checkpoint = _unset,
    Object? failureCode = _unset,
    List<WesiJobEvent>? events,
  }) {
    return WesiScheduledJob(
      id: id,
      requirements: requirements,
      priority: priority,
      state: state ?? this.state,
      queuedAt: queuedAt,
      updatedAt: updatedAt ?? this.updatedAt,
      workerId:
          identical(workerId, _unset) ? this.workerId : workerId as String?,
      startedAt: identical(startedAt, _unset)
          ? this.startedAt
          : startedAt as DateTime?,
      finishedAt: identical(finishedAt, _unset)
          ? this.finishedAt
          : finishedAt as DateTime?,
      progress: progress ?? this.progress,
      currentStage: identical(currentStage, _unset)
          ? this.currentStage
          : currentStage as String?,
      checkpoint: identical(checkpoint, _unset)
          ? this.checkpoint
          : checkpoint as WesiJobCheckpointRef?,
      failureCode: identical(failureCode, _unset)
          ? this.failureCode
          : failureCode as String?,
      events: events ?? this.events,
    );
  }
}

class WesiDispatchDecision {
  final WesiScheduledJob job;
  final WesiWorkerSelection selection;

  const WesiDispatchDecision({
    required this.job,
    required this.selection,
  });
}

const Object _unset = Object();
