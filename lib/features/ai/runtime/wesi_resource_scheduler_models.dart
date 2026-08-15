import 'wesi_local_runtime_models.dart';
import 'wesi_runtime_pack_models.dart';

enum WesiWorkloadLevel { l0, l1, l2, l3, l4 }

enum WesiWorkerPlatform { android, ios, windows, linux, macos, unknown }

enum WesiWorkerStatus { offline, online, busy, paused }

enum WesiWorkerTrust { local, paired, untrusted }

enum WesiExecutionPreference {
  automatic,
  localPreferred,
  localOnly,
  remotePreferred,
  remoteOnly,
}

enum WesiForegroundPolicy {
  foregroundRequired,
  backgroundAllowed,
  backgroundPreferred,
}

enum WesiJobPriority { low, normal, high, urgent }

enum WesiScheduledJobState {
  queued,
  running,
  pauseRequested,
  paused,
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
  cpu,
  ram,
  gpu,
  disk,
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

class WesiTrustedWorkloadDescriptor {
  final String toolName;
  final WesiWorkloadLevel level;
  final WesiForegroundPolicy foregroundPolicy;
  final Set<WesiLocalCapability> requiredCapabilities;
  final Set<WesiRuntimePackId> requiredPacks;
  final int minCpuCores;
  final int minRamMb;
  final int minGpuVramMb;
  final int minFreeDiskMb;
  final bool checkpointable;
  final bool remoteAllowed;

  const WesiTrustedWorkloadDescriptor({
    required this.toolName,
    required this.level,
    required this.foregroundPolicy,
    required this.requiredCapabilities,
    this.requiredPacks = const <WesiRuntimePackId>{},
    this.minCpuCores = 1,
    this.minRamMb = 0,
    this.minGpuVramMb = 0,
    this.minFreeDiskMb = 0,
    this.checkpointable = false,
    this.remoteAllowed = true,
  });
}

class WesiJobRequirements {
  final String toolName;
  final WesiWorkloadLevel level;
  final Set<WesiLocalCapability> requiredCapabilities;
  final Set<WesiRuntimePackId> requiredPacks;
  final Set<WesiWorkerPlatform> allowedPlatforms;
  final int minCpuCores;
  final int minRamMb;
  final int minGpuVramMb;
  final int minFreeDiskMb;
  final WesiExecutionPreference preference;
  final WesiForegroundPolicy foregroundPolicy;
  final bool checkpointable;
  final bool remoteAllowed;

  const WesiJobRequirements({
    required this.toolName,
    required this.level,
    required this.requiredCapabilities,
    required this.requiredPacks,
    required this.allowedPlatforms,
    required this.minCpuCores,
    required this.minRamMb,
    required this.minGpuVramMb,
    required this.minFreeDiskMb,
    required this.preference,
    required this.foregroundPolicy,
    required this.checkpointable,
    required this.remoteAllowed,
  });

  bool get gpuRequired => minGpuVramMb > 0 || level == WesiWorkloadLevel.l4;
  bool get heavy => level == WesiWorkloadLevel.l3 || level == WesiWorkloadLevel.l4;
}

class WesiWorkerResourceProfile {
  final String id;
  final String name;
  final WesiWorkerPlatform platform;
  final WesiWorkerStatus status;
  final WesiWorkerTrust trust;
  final bool localDevice;
  final bool policyAllowed;
  final bool appForeground;
  final bool backgroundExecutionAllowed;
  final int cpuCores;
  final int ramMb;
  final int gpuVramMb;
  final int freeDiskMb;
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
    required this.localDevice,
    required this.policyAllowed,
    required this.appForeground,
    required this.backgroundExecutionAllowed,
    required this.cpuCores,
    required this.ramMb,
    required this.gpuVramMb,
    required this.freeDiskMb,
    required this.capabilities,
    required this.installedPacks,
    this.activeLightJobs = 0,
    this.activeCpuJobs = 0,
    this.activeHeavyJobs = 0,
    this.activeGpuJobs = 0,
    this.lastSeenAt,
  });

  bool get online =>
      status == WesiWorkerStatus.online || status == WesiWorkerStatus.busy;

  bool supportsCapabilities(Set<WesiLocalCapability> required) =>
      required.every(capabilities.contains);

  bool supportsPacks(Set<WesiRuntimePackId> required) =>
      required.every(installedPacks.contains);

  bool get trusted =>
      trust == WesiWorkerTrust.local || trust == WesiWorkerTrust.paired;

  int get totalActiveJobs =>
      activeLightJobs + activeCpuJobs + activeHeavyJobs + activeGpuJobs;
}

class WesiSchedulerConcurrencyPolicy {
  final int maxLightJobsPerWorker;
  final int maxCpuJobsPerWorker;
  final int maxHeavyJobsPerWorker;
  final int maxGpuJobsPerWorker;
  final int reserveRamMb;
  final int reserveDiskMb;

  const WesiSchedulerConcurrencyPolicy({
    this.maxLightJobsPerWorker = 4,
    this.maxCpuJobsPerWorker = 2,
    this.maxHeavyJobsPerWorker = 1,
    this.maxGpuJobsPerWorker = 1,
    this.reserveRamMb = 1024,
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
  final DateTime createdAt;

  const WesiJobCheckpointRef({
    required this.checkpointId,
    required this.version,
    required this.createdAt,
  });

  void validate() {
    if (!RegExp(r'^[A-Za-z0-9._-]{1,128}$').hasMatch(checkpointId) || version < 1) {
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
      workerId: identical(workerId, _unset) ? this.workerId : workerId as String?,
      startedAt:
          identical(startedAt, _unset) ? this.startedAt : startedAt as DateTime?,
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
