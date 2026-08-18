import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../../core/sync/sync_endpoint.dart';
import 'wesi_remote_worker_auth.dart';
import 'wesi_remote_worker_models.dart';

class WesiRemoteWorkerTransportException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const WesiRemoteWorkerTransportException(
    this.code,
    this.message, {
    this.statusCode,
  });

  @override
  String toString() => '$code: $message';
}

class WesiRemoteWorkerUserAuth {
  final String token;
  final String sessionId;

  const WesiRemoteWorkerUserAuth({
    required this.token,
    required this.sessionId,
  });
}

typedef WesiRemoteWorkerUserAuthProvider = WesiRemoteWorkerUserAuth Function();

/// Real Stage-10 transport between WesiOS devices through the small Control
/// Plane. The server stores only bounded pairing/heartbeat/mailbox metadata;
/// build/test/media execution still happens on the selected desktop worker.
class WesiRemoteWorkerHttpTransport {
  final Uri baseUri;
  final WesiRemoteWorkerUserAuthProvider userAuthProvider;
  final http.Client client;
  final WesiRemoteWorkerRequestSigner signer;
  final Duration timeout;
  final bool _ownsClient;

  WesiRemoteWorkerHttpTransport({
    required this.baseUri,
    required this.userAuthProvider,
    http.Client? client,
    WesiRemoteWorkerRequestSigner? signer,
    this.timeout = const Duration(seconds: 20),
  })  : client = client ?? http.Client(),
        signer = signer ?? WesiRemoteWorkerRequestSigner(),
        _ownsClient = client == null {
    if (baseUri.scheme != 'https' &&
        !(baseUri.scheme == 'http' && _isLoopback(baseUri.host))) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_INSECURE_CONTROL_PLANE',
        'Remote Worker Control Plane requires HTTPS',
      );
    }
  }

  factory WesiRemoteWorkerHttpTransport.fromSyncEndpoint({
    http.Client? client,
    WesiRemoteWorkerRequestSigner? signer,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final base = Uri.parse(SyncEndpoint.url);
    return WesiRemoteWorkerHttpTransport(
      baseUri: base,
      client: client,
      signer: signer,
      timeout: timeout,
      userAuthProvider: () {
        final session = SyncEndpoint.session;
        final token = session?['token'];
        final sessionId = SyncEndpoint.sessionId;
        if (!SyncEndpoint.isConnected ||
            token is! String ||
            token.isEmpty ||
            sessionId == null ||
            sessionId.isEmpty) {
          throw const WesiRemoteWorkerTransportException(
            'WRW_NOT_SIGNED_IN',
            'Sign in to WesiOS before managing Wesi Workers',
          );
        }
        return WesiRemoteWorkerUserAuth(
          token: token,
          sessionId: sessionId,
        );
      },
    );
  }

  Future<WesiWorkerPairingBootstrap> createPairing({
    required String workerName,
    required String deviceFingerprint,
    String? lanHint,
  }) async {
    final json = await _userPost(
      '/api/wesi/ai/workers/pairing/create',
      <String, dynamic>{
        'workerName': workerName,
        'deviceFingerprint': deviceFingerprint,
        if (lanHint != null && lanHint.trim().isNotEmpty)
          'lanHint': lanHint.trim(),
      },
    );
    final ticket = _ticketFromServer(json['ticket']);
    final pollSecret = '${json['pollSecret'] ?? ''}'.trim();
    if (pollSecret.length < 32 || pollSecret.length > 256) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_PAIRING_RESPONSE',
        'Control Plane returned an invalid pairing bootstrap',
      );
    }
    return WesiWorkerPairingBootstrap(
      ticket: ticket,
      pollSecret: pollSecret,
    );
  }

  Future<void> claimPairing(WesiWorkerPairingTicket ticket) async {
    await _userPost(
      '/api/wesi/ai/workers/pairing/claim',
      <String, dynamic>{'ticket': _ticketToServer(ticket)},
    );
  }

  /// Polls the one-time credential from the desktop that created the QR.
  /// The poll secret itself becomes the client-only credential secret; the
  /// server persists only the derived HMAC request key.
  Future<WesiWorkerCredential?> pollPairingCredential(
    WesiWorkerPairingBootstrap bootstrap, {
    DateTime? now,
  }) async {
    final response = await _publicPost(
      '/api/wesi/ai/workers/pairing/poll',
      <String, dynamic>{
        'ticketId': bootstrap.ticket.ticketId,
        'pollSecret': bootstrap.pollSecret,
      },
    );
    if (response['ready'] != true) return null;
    final raw = response['credential'];
    if (raw is! Map) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_PAIRING_RESPONSE',
        'Control Plane returned an invalid worker credential',
      );
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    final credentialId = '${map['credentialId'] ?? ''}'.trim();
    final workerId = '${map['workerId'] ?? ''}'.trim();
    final issuedAt = DateTime.tryParse('${map['issuedAt'] ?? ''}')?.toUtc();
    final expiresAt = DateTime.tryParse('${map['expiresAt'] ?? ''}')?.toUtc();
    if (!RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(credentialId) ||
        workerId != bootstrap.ticket.workerId ||
        issuedAt == null ||
        expiresAt == null ||
        !expiresAt.isAfter(issuedAt) ||
        expiresAt.isBefore((now ?? DateTime.now()).toUtc())) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_PAIRING_RESPONSE',
        'Control Plane returned an invalid worker credential',
      );
    }
    return WesiWorkerCredential(
      credentialId: credentialId,
      workerId: workerId,
      secret: bootstrap.pollSecret,
      issuedAt: issuedAt,
      expiresAt: expiresAt,
    );
  }

  Future<List<WesiRemoteWorkerHeartbeat>> listHeartbeats() async {
    final json = await _userGet('/api/wesi/ai/workers');
    final raw = json['heartbeats'];
    if (raw is! List) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_SERVER_RESPONSE',
        'Control Plane returned an invalid worker list',
      );
    }
    final out = <WesiRemoteWorkerHeartbeat>[];
    for (final item in raw) {
      if (item is! Map) continue;
      out.add(WesiRemoteWorkerHeartbeat.fromJson(
        item.map((key, value) => MapEntry('$key', value)),
      ));
    }
    return List<WesiRemoteWorkerHeartbeat>.unmodifiable(out);
  }

  Future<void> revokeWorker(String workerId) async {
    await _userPost(
      '/api/wesi/ai/workers/revoke',
      <String, dynamic>{'workerId': workerId},
    );
  }

  Future<void> enqueueToWorker(
    String workerId,
    WesiRemoteJobMessage message,
  ) async {
    await _userPost(
      '/api/wesi/ai/workers/mailbox/enqueue',
      <String, dynamic>{
        'workerId': workerId,
        'message': message.toJson(),
      },
    );
  }

  Future<List<WesiRemoteJobMessage>> pollWorkerEvents(
    String workerId, {
    int limit = 16,
  }) async {
    if (limit < 1 || limit > 32) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_POLL_LIMIT',
        'Remote worker event poll limit is invalid',
      );
    }
    final json = await _userPost(
      '/api/wesi/ai/workers/events/poll',
      <String, dynamic>{'workerId': workerId, 'limit': limit},
    );
    return _messagesFromServer(json['messages']);
  }

  Future<void> ackWorkerEvent(String workerId, String messageId) async {
    await _userPost(
      '/api/wesi/ai/workers/events/ack',
      <String, dynamic>{'workerId': workerId, 'messageId': messageId},
    );
  }

  Future<void> sendHeartbeat(
    WesiWorkerCredential credential,
    WesiRemoteWorkerHeartbeat heartbeat, {
    DateTime? now,
  }) async {
    if (heartbeat.profile.id != credential.workerId) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_WORKER_IDENTITY_MISMATCH',
        'Credential does not match heartbeat worker identity',
      );
    }
    await _workerPost(
      '/api/wesi/ai/workers/heartbeat',
      credential,
      heartbeat.toJson(),
      now: now,
    );
  }

  Future<List<WesiRemoteJobMessage>> pollWorkerMailbox(
    WesiWorkerCredential credential, {
    int limit = 16,
    DateTime? now,
  }) async {
    if (limit < 1 || limit > 32) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_POLL_LIMIT',
        'Remote worker mailbox poll limit is invalid',
      );
    }
    final json = await _workerPost(
      '/api/wesi/ai/workers/mailbox/poll',
      credential,
      <String, dynamic>{'limit': limit},
      now: now,
    );
    return _messagesFromServer(json['messages']);
  }

  Future<void> sendWorkerMessage(
    WesiWorkerCredential credential,
    WesiRemoteJobMessage message, {
    DateTime? now,
  }) async {
    await _workerPost(
      '/api/wesi/ai/workers/message',
      credential,
      <String, dynamic>{'message': message.toJson()},
      now: now,
    );
  }

  Future<Map<String, dynamic>> _workerPost(
    String path,
    WesiWorkerCredential credential,
    Map<String, dynamic> payload, {
    DateTime? now,
  }) async {
    final payloadJson = jsonEncode(payload);
    final signed = signer.sign(
      credential: credential,
      method: 'POST',
      path: path,
      body: utf8.encode(payloadJson),
      now: now,
    );
    final headers = <String, String>{
      'Content-Type': 'application/json',
      ...signed.toHeaders(),
    };
    return _send(
      () => client.post(
        _uri(path),
        headers: headers,
        body: jsonEncode(<String, dynamic>{'payloadJson': payloadJson}),
      ),
    );
  }

  Future<Map<String, dynamic>> _userPost(
    String path,
    Map<String, dynamic> body,
  ) async {
    final auth = userAuthProvider();
    return _send(
      () => client.post(
        _uri(path),
        headers: <String, String>{
          'Content-Type': 'application/json',
          'Authorization': auth.token,
          'X-WesiOS-Session': auth.sessionId,
        },
        body: jsonEncode(body),
      ),
    );
  }

  Future<Map<String, dynamic>> _publicPost(
    String path,
    Map<String, dynamic> body,
  ) =>
      _send(
        () => client.post(
          _uri(path),
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(body),
        ),
      );

  Future<Map<String, dynamic>> _userGet(String path) async {
    final auth = userAuthProvider();
    return _send(
      () => client.get(
        _uri(path),
        headers: <String, String>{
          'Authorization': auth.token,
          'X-WesiOS-Session': auth.sessionId,
        },
      ),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request,
  ) async {
    try {
      final response = await request().timeout(timeout);
      Map<String, dynamic> json;
      try {
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) throw const FormatException();
        json = decoded.map((key, value) => MapEntry('$key', value));
      } on FormatException {
        throw WesiRemoteWorkerTransportException(
          'WRW_BAD_SERVER_RESPONSE',
          'Control Plane returned invalid JSON',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          json['ok'] != true) {
        final code = '${json['code'] ?? 'WRW_REQUEST_FAILED'}';
        throw WesiRemoteWorkerTransportException(
          code,
          _messageFor(code),
          statusCode: response.statusCode,
        );
      }
      return json;
    } on WesiRemoteWorkerTransportException {
      rethrow;
    } on TimeoutException {
      throw const WesiRemoteWorkerTransportException(
        'WRW_NETWORK_TIMEOUT',
        'Remote Worker Control Plane request timed out',
      );
    } on http.ClientException {
      throw const WesiRemoteWorkerTransportException(
        'WRW_NETWORK_FAILED',
        'Remote Worker Control Plane is unavailable',
      );
    }
  }

  Uri _uri(String path) => baseUri.replace(path: path, query: null);

  void close() {
    if (_ownsClient) client.close();
  }

  static List<WesiRemoteJobMessage> _messagesFromServer(dynamic raw) {
    if (raw is! List) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_SERVER_RESPONSE',
        'Control Plane returned an invalid worker message collection',
      );
    }
    final out = <WesiRemoteJobMessage>[];
    for (final item in raw) {
      if (item is! Map) continue;
      out.add(
          _messageFromJson(item.map((key, value) => MapEntry('$key', value))));
    }
    return List<WesiRemoteJobMessage>.unmodifiable(out);
  }

  static WesiRemoteJobMessage _messageFromJson(Map<String, dynamic> json) {
    if (json['v'] != wesiRemoteWorkerProtocolVersion) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_SERVER_RESPONSE',
        'Remote worker message protocol version is invalid',
      );
    }
    WesiRemoteJobMessageKind? kind;
    for (final candidate in WesiRemoteJobMessageKind.values) {
      if (candidate.name == '${json['kind'] ?? ''}') {
        kind = candidate;
        break;
      }
    }
    final createdAt = DateTime.tryParse('${json['createdAt'] ?? ''}')?.toUtc();
    final sequence = json['sequence'];
    final payload = json['payload'];
    if (kind == null ||
        createdAt == null ||
        sequence is! num ||
        sequence.isNaN ||
        sequence.isInfinite ||
        sequence.toInt().toDouble() != sequence.toDouble() ||
        payload is! Map) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_SERVER_RESPONSE',
        'Remote worker message payload is invalid',
      );
    }
    final message = WesiRemoteJobMessage(
      messageId: '${json['messageId'] ?? ''}',
      jobId: '${json['jobId'] ?? ''}',
      kind: kind,
      sequence: sequence.toInt(),
      createdAt: createdAt,
      payload: payload.map((key, value) => MapEntry('$key', value)),
    );
    final idPattern = RegExp(r'^[A-Za-z0-9._:-]{1,128}$');
    if (!idPattern.hasMatch(message.messageId) ||
        !idPattern.hasMatch(message.jobId) ||
        message.sequence < 0 ||
        message.payload.length > 64) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_SERVER_RESPONSE',
        'Remote worker message envelope is invalid',
      );
    }
    return message;
  }

  static WesiWorkerPairingTicket _ticketFromServer(dynamic raw) {
    if (raw is! Map) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_PAIRING_RESPONSE',
        'Control Plane returned an invalid pairing ticket',
      );
    }
    final map = raw.map((key, value) => MapEntry('$key', value));
    final expiresAtMs = map['expiresAtMs'];
    if (expiresAtMs is! num ||
        expiresAtMs.isNaN ||
        expiresAtMs.isInfinite ||
        expiresAtMs.toInt().toDouble() != expiresAtMs.toDouble()) {
      throw const WesiRemoteWorkerTransportException(
        'WRW_BAD_PAIRING_RESPONSE',
        'Control Plane returned an invalid pairing expiry',
      );
    }
    final ticket = WesiWorkerPairingTicket(
      ticketId: '${map['ticketId'] ?? ''}',
      workerId: '${map['workerId'] ?? ''}',
      workerName: '${map['workerName'] ?? ''}',
      deviceFingerprint: '${map['deviceFingerprint'] ?? ''}',
      nonce: '${map['nonce'] ?? ''}',
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresAtMs.toInt(),
        isUtc: true,
      ),
      lanHint: map['lanHint'] == null ? null : '${map['lanHint']}',
    );
    ticket.validate();
    return ticket;
  }

  static Map<String, dynamic> _ticketToServer(WesiWorkerPairingTicket ticket) =>
      <String, dynamic>{
        'ticketId': ticket.ticketId,
        'workerId': ticket.workerId,
        'workerName': ticket.workerName,
        'deviceFingerprint': ticket.deviceFingerprint,
        'nonce': ticket.nonce,
        'expiresAtMs': ticket.expiresAt.toUtc().millisecondsSinceEpoch,
        if (ticket.lanHint != null) 'lanHint': ticket.lanHint,
      };

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  static String _messageFor(String code) => switch (code) {
        'WRW_UNAUTHORIZED' => 'Wesi Worker credential was rejected',
        'WRW_REPLAYED_REQUEST' => 'Replayed Wesi Worker request was rejected',
        'WRW_PAIRING_EXPIRED' => 'Wesi Worker pairing ticket expired',
        'WRW_PAIRING_REJECTED' => 'Wesi Worker pairing was rejected',
        'WRW_CREDENTIAL_ALREADY_DELIVERED' =>
          'Wesi Worker credential was already delivered',
        'WRW_WORKER_LIMIT' => 'Wesi Worker device limit was reached',
        _ => 'Remote Worker Control Plane request failed',
      };
}
