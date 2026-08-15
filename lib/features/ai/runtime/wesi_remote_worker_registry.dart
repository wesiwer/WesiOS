import 'dart:collection';

import 'wesi_remote_worker_models.dart';
import 'wesi_resource_scheduler_models.dart';

class WesiRemoteWorkerRegistry {
  final Duration heartbeatTtl;
  final int maxWorkers;
  final int maxPendingMessagesPerWorker;
  final Map<String, WesiWorkerResourceProfile> _profiles =
      <String, WesiWorkerResourceProfile>{};
  final Map<String, Queue<WesiRemoteJobMessage>> _mailboxes =
      <String, Queue<WesiRemoteJobMessage>>{};
  final Map<String, int> _lastWorkerSequence = <String, int>{};
  final Set<String> _ackedMessageIds = <String>{};

  WesiRemoteWorkerRegistry({
    this.heartbeatTtl = const Duration(seconds: 45),
    this.maxWorkers = 16,
    this.maxPendingMessagesPerWorker = 128,
  });

  void applyHeartbeat(WesiRemoteWorkerHeartbeat heartbeat, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final profile = heartbeat.profile;
    if (current.difference(heartbeat.sentAt.toUtc()).abs() >
        const Duration(minutes: 2)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_STALE_HEARTBEAT',
        'Heartbeat timestamp is outside the accepted window',
      );
    }
    if (!profile.remoteWorker ||
        profile.trust != WesiWorkerTrust.paired ||
        !profile.resourceSnapshotSane) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_HEARTBEAT',
        'Remote worker heartbeat is not trusted',
      );
    }
    if (!_profiles.containsKey(profile.id) && _profiles.length >= maxWorkers) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_WORKER_LIMIT',
        'Remote worker limit reached',
      );
    }
    _profiles[profile.id] = WesiWorkerResourceProfile(
      id: profile.id,
      name: profile.name,
      platform: profile.platform,
      status: profile.status,
      trust: WesiWorkerTrust.paired,
      role: WesiWorkerRole.remoteWorker,
      policyAllowed: profile.policyAllowed,
      appForeground: profile.appForeground,
      backgroundExecutionAllowed: profile.backgroundExecutionAllowed,
      cpuCores: profile.cpuCores,
      cpuLoadPercent: profile.cpuLoadPercent,
      totalRamMb: profile.totalRamMb,
      availableRamMb: profile.availableRamMb,
      gpuName: profile.gpuName,
      totalGpuVramMb: profile.totalGpuVramMb,
      freeGpuVramMb: profile.freeGpuVramMb,
      freeDiskMb: profile.freeDiskMb,
      thermalState: profile.thermalState,
      powerMode: profile.powerMode,
      capabilities: profile.capabilities,
      installedPacks: profile.installedPacks,
      activeLightJobs: profile.activeLightJobs,
      activeCpuJobs: profile.activeCpuJobs,
      activeHeavyJobs: profile.activeHeavyJobs,
      activeGpuJobs: profile.activeGpuJobs,
      lastSeenAt: current,
    );
  }

  List<WesiWorkerResourceProfile> schedulerWorkers({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    return _profiles.values.map((profile) {
      final lastSeen = profile.lastSeenAt;
      final fresh = lastSeen != null && current.difference(lastSeen) <= heartbeatTtl;
      if (fresh) return profile;
      return WesiWorkerResourceProfile(
        id: profile.id,
        name: profile.name,
        platform: profile.platform,
        status: WesiWorkerStatus.offline,
        trust: profile.trust,
        role: profile.role,
        policyAllowed: profile.policyAllowed,
        appForeground: false,
        backgroundExecutionAllowed: false,
        cpuCores: profile.cpuCores,
        cpuLoadPercent: profile.cpuLoadPercent,
        totalRamMb: profile.totalRamMb,
        availableRamMb: profile.availableRamMb,
        gpuName: profile.gpuName,
        totalGpuVramMb: profile.totalGpuVramMb,
        freeGpuVramMb: profile.freeGpuVramMb,
        freeDiskMb: profile.freeDiskMb,
        thermalState: profile.thermalState,
        powerMode: profile.powerMode,
        capabilities: profile.capabilities,
        installedPacks: profile.installedPacks,
        activeLightJobs: profile.activeLightJobs,
        activeCpuJobs: profile.activeCpuJobs,
        activeHeavyJobs: profile.activeHeavyJobs,
        activeGpuJobs: profile.activeGpuJobs,
        lastSeenAt: profile.lastSeenAt,
      );
    }).toList(growable: false);
  }

  void enqueueToWorker(String workerId, WesiRemoteJobMessage message) {
    if (!_profiles.containsKey(workerId)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_UNKNOWN_WORKER',
        'Remote worker is not registered',
      );
    }
    _validateMessage(message);
    final queue = _mailboxes.putIfAbsent(
      workerId,
      () => Queue<WesiRemoteJobMessage>(),
    );
    if (queue.length >= maxPendingMessagesPerWorker) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_MAILBOX_FULL',
        'Remote worker mailbox is full',
      );
    }
    if (queue.any((entry) => entry.messageId == message.messageId) ||
        _ackedMessageIds.contains(message.messageId)) {
      return;
    }
    queue.add(message);
  }

  List<WesiRemoteJobMessage> poll(String workerId, {int limit = 16}) {
    if (limit < 1 || limit > 32) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_POLL_LIMIT',
        'Remote worker poll limit is invalid',
      );
    }
    final queue = _mailboxes[workerId];
    if (queue == null || queue.isEmpty) return const <WesiRemoteJobMessage>[];
    return queue.take(limit).toList(growable: false);
  }

  void ack(String workerId, String messageId) {
    final queue = _mailboxes[workerId];
    if (queue == null) return;
    queue.removeWhere((message) => message.messageId == messageId);
    _ackedMessageIds.add(messageId);
    if (_ackedMessageIds.length > 4096) {
      _ackedMessageIds.remove(_ackedMessageIds.first);
    }
  }

  void acceptWorkerMessage(String workerId, WesiRemoteJobMessage message) {
    _validateMessage(message);
    final previous = _lastWorkerSequence[workerId] ?? -1;
    if (message.sequence <= previous) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_REPLAYED_SEQUENCE',
        'Remote worker message sequence is stale or replayed',
      );
    }
    _lastWorkerSequence[workerId] = message.sequence;
  }

  void revoke(String workerId) {
    _profiles.remove(workerId);
    _mailboxes.remove(workerId);
    _lastWorkerSequence.remove(workerId);
  }

  static void _validateMessage(WesiRemoteJobMessage message) {
    final idPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
    if (!idPattern.hasMatch(message.messageId) ||
        !idPattern.hasMatch(message.jobId) ||
        message.sequence < 0 ||
        message.payload.length > 64) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_JOB_MESSAGE',
        'Remote job message is invalid',
      );
    }
  }
}
