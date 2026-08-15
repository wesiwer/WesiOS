import 'dart:convert';

import 'wesi_local_runtime_models.dart';
import 'wesi_resource_scheduler_models.dart';
import 'wesi_runtime_pack_models.dart';

const int wesiRemoteWorkerProtocolVersion = 1;

class WesiRemoteWorkerProtocolException implements Exception {
  final String code;
  final String message;

  const WesiRemoteWorkerProtocolException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class WesiWorkerPairingTicket {
  static const scheme = 'wesios';
  static const host = 'worker-pair';

  final String ticketId;
  final String workerId;
  final String workerName;
  final String deviceFingerprint;
  final String nonce;
  final DateTime expiresAt;
  final String? lanHint;

  const WesiWorkerPairingTicket({
    required this.ticketId,
    required this.workerId,
    required this.workerName,
    required this.deviceFingerprint,
    required this.nonce,
    required this.expiresAt,
    this.lanHint,
  });

  bool expiredAt(DateTime now) => !now.toUtc().isBefore(expiresAt.toUtc());

  void validate({DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    final idPattern = RegExp(r'^[A-Za-z0-9_-]{20,96}$');
    final fpPattern = RegExp(r'^[A-Fa-f0-9]{32,128}$');
    if (!idPattern.hasMatch(ticketId) ||
        !idPattern.hasMatch(workerId) ||
        !idPattern.hasMatch(nonce) ||
        !fpPattern.hasMatch(deviceFingerprint) ||
        workerName.trim().isEmpty ||
        workerName.length > 120 ||
        expiresAt.toUtc().difference(current) > const Duration(minutes: 15) ||
        expiredAt(current)) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PAIRING_TICKET',
        'Pairing ticket is invalid or expired',
      );
    }
    if (lanHint != null && lanHint!.length > 160) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PAIRING_TICKET',
        'LAN hint is too long',
      );
    }
  }

  Uri toUri({DateTime? now}) {
    validate(now: now);
    final encodedName =
        base64Url.encode(utf8.encode(workerName)).replaceAll('=', '');
    return Uri(
      scheme: scheme,
      host: host,
      queryParameters: <String, String>{
        'v': '$wesiRemoteWorkerProtocolVersion',
        'ticket': ticketId,
        'worker': workerId,
        'name': encodedName,
        'fp': deviceFingerprint.toLowerCase(),
        'nonce': nonce,
        'exp': expiresAt.toUtc().millisecondsSinceEpoch.toString(),
        if (lanHint != null && lanHint!.isNotEmpty) 'lan': lanHint!,
      },
    );
  }

  factory WesiWorkerPairingTicket.fromUri(Uri uri, {DateTime? now}) {
    if (uri.scheme != scheme ||
        uri.host != host ||
        uri.queryParameters['v'] != '$wesiRemoteWorkerProtocolVersion') {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PAIRING_TICKET',
        'Unsupported Wesi Worker QR',
      );
    }
    final encodedName = (uri.queryParameters['name'] ?? '').trim();
    final exp = int.tryParse(uri.queryParameters['exp'] ?? '');
    String name;
    try {
      final padding = '=' * ((4 - encodedName.length % 4) % 4);
      name = utf8.decode(base64Url.decode(encodedName + padding));
    } catch (_) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PAIRING_TICKET',
        'Pairing ticket name is invalid',
      );
    }
    if (exp == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_PAIRING_TICKET',
        'Pairing ticket expiry is invalid',
      );
    }
    final ticket = WesiWorkerPairingTicket(
      ticketId: (uri.queryParameters['ticket'] ?? '').trim(),
      workerId: (uri.queryParameters['worker'] ?? '').trim(),
      workerName: name,
      deviceFingerprint: (uri.queryParameters['fp'] ?? '').trim(),
      nonce: (uri.queryParameters['nonce'] ?? '').trim(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      lanHint: uri.queryParameters['lan'],
    );
    ticket.validate(now: now);
    return ticket;
  }
}

/// Returned only to the desktop that requested the pairing ticket.
/// [pollSecret] MUST NOT be encoded in QR, logs or user-visible telemetry.
class WesiWorkerPairingBootstrap {
  final WesiWorkerPairingTicket ticket;
  final String pollSecret;

  const WesiWorkerPairingBootstrap({
    required this.ticket,
    required this.pollSecret,
  });
}

/// Device secret is client-only. Server persistence stores only a derived hash.
class WesiWorkerCredential {
  final String credentialId;
  final String workerId;
  final String secret;
  final DateTime issuedAt;
  final DateTime? expiresAt;

  const WesiWorkerCredential({
    required this.credentialId,
    required this.workerId,
    required this.secret,
    required this.issuedAt,
    this.expiresAt,
  });

  bool expiredAt(DateTime now) =>
      expiresAt != null && !now.toUtc().isBefore(expiresAt!.toUtc());
}

class WesiRemoteWorkerHeartbeat {
  final WesiWorkerResourceProfile profile;
  final DateTime sentAt;

  const WesiRemoteWorkerHeartbeat({
    required this.profile,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': wesiRemoteWorkerProtocolVersion,
        'sentAt': sentAt.toUtc().toIso8601String(),
        'worker': <String, dynamic>{
          'id': profile.id,
          'name': profile.name,
          'platform': profile.platform.name,
          'status': profile.status.name,
          'policyAllowed': profile.policyAllowed,
          'appForeground': profile.appForeground,
          'backgroundExecutionAllowed': profile.backgroundExecutionAllowed,
          'cpuCores': profile.cpuCores,
          'cpuLoadPercent': profile.cpuLoadPercent,
          'totalRamMb': profile.totalRamMb,
          'availableRamMb': profile.availableRamMb,
          'gpuName': profile.gpuName,
          'totalGpuVramMb': profile.totalGpuVramMb,
          'freeGpuVramMb': profile.freeGpuVramMb,
          'freeDiskMb': profile.freeDiskMb,
          'thermalState': profile.thermalState.name,
          'powerMode': profile.powerMode.name,
          'capabilities': profile.capabilities.map((e) => e.name).toList()
            ..sort(),
          'installedPacks': profile.installedPacks.map((e) => e.name).toList()
            ..sort(),
          'activeLightJobs': profile.activeLightJobs,
          'activeCpuJobs': profile.activeCpuJobs,
          'activeHeavyJobs': profile.activeHeavyJobs,
          'activeGpuJobs': profile.activeGpuJobs,
        },
      };

  factory WesiRemoteWorkerHeartbeat.fromJson(Map<String, dynamic> json) {
    if (json['v'] != wesiRemoteWorkerProtocolVersion ||
        json['worker'] is! Map) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_HEARTBEAT',
        'Heartbeat payload is invalid',
      );
    }
    final raw = Map<String, dynamic>.from(json['worker'] as Map);
    T enumByName<T extends Enum>(List<T> values, Object? value) {
      final name = '$value';
      for (final candidate in values) {
        if (candidate.name == name) return candidate;
      }
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_HEARTBEAT',
        'Heartbeat contains an unknown enum value',
      );
    }

    Set<WesiLocalCapability> capabilities() {
      final input = raw['capabilities'];
      if (input is! List || input.length > 64) {
        throw const WesiRemoteWorkerProtocolException(
          'WRW_BAD_HEARTBEAT',
          'Heartbeat capabilities are invalid',
        );
      }
      return input
          .map((e) => enumByName(WesiLocalCapability.values, e))
          .toSet();
    }

    Set<WesiRuntimePackId> packs() {
      final input = raw['installedPacks'];
      if (input is! List || input.length > 16) {
        throw const WesiRemoteWorkerProtocolException(
          'WRW_BAD_HEARTBEAT',
          'Heartbeat packs are invalid',
        );
      }
      return input.map((e) => enumByName(WesiRuntimePackId.values, e)).toSet();
    }

    int intValue(String key) => (raw[key] as num?)?.toInt() ?? -1;
    double doubleValue(String key) => (raw[key] as num?)?.toDouble() ?? -1;
    final id = '${raw['id'] ?? ''}'.trim();
    final name = '${raw['name'] ?? ''}'.trim();
    if (!RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(id) ||
        name.isEmpty ||
        name.length > 120) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_HEARTBEAT',
        'Worker identity is invalid',
      );
    }
    final profile = WesiWorkerResourceProfile(
      id: id,
      name: name,
      platform: enumByName(WesiWorkerPlatform.values, raw['platform']),
      status: enumByName(WesiWorkerStatus.values, raw['status']),
      trust: WesiWorkerTrust.paired,
      role: WesiWorkerRole.remoteWorker,
      policyAllowed: raw['policyAllowed'] == true,
      appForeground: raw['appForeground'] == true,
      backgroundExecutionAllowed: raw['backgroundExecutionAllowed'] == true,
      cpuCores: intValue('cpuCores'),
      cpuLoadPercent: doubleValue('cpuLoadPercent'),
      totalRamMb: intValue('totalRamMb'),
      availableRamMb: intValue('availableRamMb'),
      gpuName: raw['gpuName'] == null ? null : '${raw['gpuName']}',
      totalGpuVramMb: intValue('totalGpuVramMb'),
      freeGpuVramMb: intValue('freeGpuVramMb'),
      freeDiskMb: intValue('freeDiskMb'),
      thermalState: enumByName(WesiThermalState.values, raw['thermalState']),
      powerMode: enumByName(WesiPowerMode.values, raw['powerMode']),
      capabilities: capabilities(),
      installedPacks: packs(),
      activeLightJobs: intValue('activeLightJobs'),
      activeCpuJobs: intValue('activeCpuJobs'),
      activeHeavyJobs: intValue('activeHeavyJobs'),
      activeGpuJobs: intValue('activeGpuJobs'),
      lastSeenAt: DateTime.tryParse('${json['sentAt'] ?? ''}')?.toUtc(),
    );
    if (!profile.resourceSnapshotSane || !profile.desktop) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_HEARTBEAT',
        'Worker resource snapshot is invalid',
      );
    }
    return WesiRemoteWorkerHeartbeat(
      profile: profile,
      sentAt: profile.lastSeenAt ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

enum WesiRemoteJobMessageKind {
  assignment,
  progress,
  checkpoint,
  result,
  cancel,
  pause,
  resume,
  ack,
}

class WesiRemoteJobMessage {
  final String messageId;
  final String jobId;
  final WesiRemoteJobMessageKind kind;
  final int sequence;
  final DateTime createdAt;
  final Map<String, dynamic> payload;

  const WesiRemoteJobMessage({
    required this.messageId,
    required this.jobId,
    required this.kind,
    required this.sequence,
    required this.createdAt,
    this.payload = const <String, dynamic>{},
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'v': wesiRemoteWorkerProtocolVersion,
        'messageId': messageId,
        'jobId': jobId,
        'kind': kind.name,
        'sequence': sequence,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'payload': payload,
      };
}
