import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'wesi_remote_worker_models.dart';

class WesiRemoteWorkerPairingRecord {
  final WesiWorkerPairingTicket ticket;
  final String ownerScope;
  final String pollSecretHash;
  final bool claimed;
  final bool credentialDelivered;
  final String? credentialId;
  final String? credentialSecretHash;
  final DateTime createdAt;
  final DateTime? claimedAt;
  final DateTime? revokedAt;

  const WesiRemoteWorkerPairingRecord({
    required this.ticket,
    required this.ownerScope,
    required this.pollSecretHash,
    required this.claimed,
    required this.credentialDelivered,
    required this.createdAt,
    this.credentialId,
    this.credentialSecretHash,
    this.claimedAt,
    this.revokedAt,
  });

  bool get revoked => revokedAt != null;

  WesiRemoteWorkerPairingRecord copyWith({
    bool? claimed,
    bool? credentialDelivered,
    String? credentialId,
    String? credentialSecretHash,
    DateTime? claimedAt,
    DateTime? revokedAt,
  }) =>
      WesiRemoteWorkerPairingRecord(
        ticket: ticket,
        ownerScope: ownerScope,
        pollSecretHash: pollSecretHash,
        claimed: claimed ?? this.claimed,
        credentialDelivered: credentialDelivered ?? this.credentialDelivered,
        createdAt: createdAt,
        credentialId: credentialId ?? this.credentialId,
        credentialSecretHash: credentialSecretHash ?? this.credentialSecretHash,
        claimedAt: claimedAt ?? this.claimedAt,
        revokedAt: revokedAt ?? this.revokedAt,
      );
}

class WesiRemoteWorkerPairingService {
  final Random _random;
  final Duration ticketTtl;
  final Duration credentialTtl;
  final Map<String, WesiRemoteWorkerPairingRecord> _records =
      <String, WesiRemoteWorkerPairingRecord>{};
  final Map<String, WesiWorkerCredential> _pendingCredentials =
      <String, WesiWorkerCredential>{};

  WesiRemoteWorkerPairingService({
    Random? random,
    this.ticketTtl = const Duration(minutes: 5),
    this.credentialTtl = const Duration(days: 90),
  }) : _random = random ?? Random.secure();

  WesiWorkerPairingBootstrap createTicket({
    required String ownerScope,
    required String workerName,
    required String deviceFingerprint,
    String? lanHint,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    if (ownerScope.trim().isEmpty || ownerScope.length > 160) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_SCOPE',
        'Pairing owner scope is invalid',
      );
    }
    _purge(current);
    final ticket = WesiWorkerPairingTicket(
      ticketId: _randomId(24),
      workerId: _randomId(24),
      workerName: workerName.trim(),
      deviceFingerprint: deviceFingerprint.trim().toLowerCase(),
      nonce: _randomId(24),
      expiresAt: current.add(ticketTtl),
      lanHint: lanHint,
    );
    ticket.validate(now: current);
    final pollSecret = _randomId(32);
    _records[ticket.ticketId] = WesiRemoteWorkerPairingRecord(
      ticket: ticket,
      ownerScope: ownerScope,
      pollSecretHash: _hashSecret(pollSecret),
      claimed: false,
      credentialDelivered: false,
      createdAt: current,
    );
    return WesiWorkerPairingBootstrap(ticket: ticket, pollSecret: pollSecret);
  }

  void claim({
    required String ownerScope,
    required WesiWorkerPairingTicket ticket,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    ticket.validate(now: current);
    final record = _records[ticket.ticketId];
    if (record == null ||
        record.revoked ||
        record.ownerScope != ownerScope ||
        record.claimed ||
        record.ticket.workerId != ticket.workerId ||
        record.ticket.nonce != ticket.nonce ||
        record.ticket.deviceFingerprint != ticket.deviceFingerprint) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_PAIRING_REJECTED',
        'Pairing ticket cannot be claimed',
      );
    }
    final credential = WesiWorkerCredential(
      credentialId: _randomId(24),
      workerId: record.ticket.workerId,
      secret: _randomId(48),
      issuedAt: current,
      expiresAt: current.add(credentialTtl),
    );
    _pendingCredentials[record.ticket.ticketId] = credential;
    _records[record.ticket.ticketId] = record.copyWith(
      claimed: true,
      claimedAt: current,
      credentialId: credential.credentialId,
      credentialSecretHash: _hashSecret(credential.secret),
    );
  }

  WesiWorkerCredential? pollCredential({
    required String ticketId,
    required String pollSecret,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    _purge(current);
    final record = _records[ticketId];
    if (record == null ||
        record.revoked ||
        !_constantTimeEquals(record.pollSecretHash, _hashSecret(pollSecret))) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_PAIRING_REJECTED',
        'Pairing poll secret is invalid',
      );
    }
    if (!record.claimed) return null;
    if (record.credentialDelivered) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_CREDENTIAL_ALREADY_DELIVERED',
        'Device credential is one-time delivery',
      );
    }
    final credential = _pendingCredentials.remove(ticketId);
    if (credential == null) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_PAIRING_STATE_INVALID',
        'Pairing state is inconsistent',
      );
    }
    _records[ticketId] = record.copyWith(credentialDelivered: true);
    return credential;
  }

  bool verifyCredentialSecret({
    required String credentialId,
    required String workerId,
    required String secret,
    DateTime? now,
  }) {
    final current = (now ?? DateTime.now()).toUtc();
    for (final record in _records.values) {
      if (record.revoked ||
          record.credentialId != credentialId ||
          record.ticket.workerId != workerId ||
          record.credentialSecretHash == null) {
        continue;
      }
      if (record.claimedAt == null ||
          current.difference(record.claimedAt!) > credentialTtl) {
        return false;
      }
      return _constantTimeEquals(
        record.credentialSecretHash!,
        _hashSecret(secret),
      );
    }
    return false;
  }

  void revokeWorker(String workerId, {DateTime? now}) {
    final current = (now ?? DateTime.now()).toUtc();
    for (final entry in _records.entries.toList()) {
      if (entry.value.ticket.workerId == workerId && !entry.value.revoked) {
        _records[entry.key] = entry.value.copyWith(revokedAt: current);
        _pendingCredentials.remove(entry.key);
      }
    }
  }

  void _purge(DateTime now) {
    for (final entry in _records.entries.toList()) {
      if (!entry.value.claimed && entry.value.ticket.expiredAt(now)) {
        _records.remove(entry.key);
        _pendingCredentials.remove(entry.key);
      }
    }
  }

  String _randomId(int bytes) {
    final data = Uint8List(bytes);
    for (var i = 0; i < bytes; i++) {
      data[i] = _random.nextInt(256);
    }
    return base64Url.encode(data).replaceAll('=', '');
  }

  static String _hashSecret(String value) =>
      sha256.convert(utf8.encode(value)).toString();

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
