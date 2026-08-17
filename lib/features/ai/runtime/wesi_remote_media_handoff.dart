import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../../core/sync/sync_endpoint.dart';
import 'wesi_remote_worker_auth.dart';
import 'wesi_remote_worker_http_transport.dart';
import 'wesi_remote_worker_models.dart';

class WesiRemoteMediaHandoffException implements Exception {
  final String code;
  final String message;
  final int? statusCode;

  const WesiRemoteMediaHandoffException(
    this.code,
    this.message, {
    this.statusCode,
  });

  @override
  String toString() => '$code: $message';
}

class WesiRemoteMediaFileMeta {
  final String name;
  final String mimeType;
  final int byteSize;
  final String sha256Hex;
  final int chunkSize;
  final int chunkCount;

  const WesiRemoteMediaFileMeta({
    required this.name,
    required this.mimeType,
    required this.byteSize,
    required this.sha256Hex,
    required this.chunkSize,
    required this.chunkCount,
  });

  int expectedChunkBytes(int index) {
    if (index < 0 || index >= chunkCount) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_CHUNK',
        'Remote media chunk index is invalid',
      );
    }
    final remaining = byteSize - index * chunkSize;
    return remaining < chunkSize ? remaining : chunkSize;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'mimeType': mimeType,
        'byteSize': byteSize,
        'sha256': sha256Hex,
      };

  factory WesiRemoteMediaFileMeta.fromJson(Map<String, dynamic> json) {
    final name = '${json['name'] ?? ''}'.trim();
    final mimeType = '${json['mimeType'] ?? ''}'.trim().toLowerCase();
    final byteSize = _strictInt(json['byteSize']);
    final sha256Hex = '${json['sha256'] ?? ''}'.trim().toLowerCase();
    final chunkSize = _strictInt(json['chunkSize']);
    final chunkCount = _strictInt(json['chunkCount']);
    if (name.isEmpty ||
        name.length > 180 ||
        !WesiRemoteMediaHandoffTransport.allowedMimeTypes.contains(mimeType) ||
        byteSize <= 0 ||
        byteSize > WesiRemoteMediaHandoffTransport.maxFileBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256Hex) ||
        chunkSize != WesiRemoteMediaHandoffTransport.chunkBytes ||
        chunkCount != (byteSize + chunkSize - 1) ~/ chunkSize ||
        chunkCount < 1 ||
        chunkCount > WesiRemoteMediaHandoffTransport.maxChunks) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_SERVER_RESPONSE',
        'Control Plane returned invalid remote media metadata',
      );
    }
    return WesiRemoteMediaFileMeta(
      name: name,
      mimeType: mimeType,
      byteSize: byteSize,
      sha256Hex: sha256Hex,
      chunkSize: chunkSize,
      chunkCount: chunkCount,
    );
  }
}

class WesiRemoteMediaHandoff {
  final String handoffId;
  final String jobId;
  final String direction;
  final String status;
  final int chunkSize;
  final int maxByteSize;
  final DateTime expiresAt;
  final WesiRemoteMediaFileMeta? file;

  const WesiRemoteMediaHandoff({
    required this.handoffId,
    required this.jobId,
    required this.direction,
    required this.status,
    required this.chunkSize,
    required this.maxByteSize,
    required this.expiresAt,
    this.file,
  });

  bool get ready => status == 'ready';

  factory WesiRemoteMediaHandoff.fromJson(Map<String, dynamic> json) {
    final handoffId = '${json['handoffId'] ?? ''}'.trim();
    final jobId = '${json['jobId'] ?? ''}'.trim();
    final direction = '${json['direction'] ?? ''}'.trim();
    final status = '${json['status'] ?? ''}'.trim();
    final chunkSize = _strictInt(json['chunkSize']);
    final maxByteSize = _strictInt(json['maxByteSize']);
    final expiresAt = DateTime.tryParse('${json['expiresAt'] ?? ''}')?.toUtc();
    final rawFile = json['file'];
    final file = rawFile is Map
        ? WesiRemoteMediaFileMeta.fromJson(
            rawFile.map((key, value) => MapEntry('$key', value)),
          )
        : null;
    if (!RegExp(r'^wrm_[A-Za-z0-9_-]{20,80}$').hasMatch(handoffId) ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(jobId) ||
        !const <String>{'input', 'output'}.contains(direction) ||
        !const <String>{
          'uploading',
          'ready',
          'awaiting_worker',
          'consumed',
        }.contains(status) ||
        chunkSize != WesiRemoteMediaHandoffTransport.chunkBytes ||
        maxByteSize <= 0 ||
        maxByteSize > WesiRemoteMediaHandoffTransport.maxFileBytes ||
        expiresAt == null ||
        (direction == 'input' && file == null)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_SERVER_RESPONSE',
        'Control Plane returned invalid remote media handoff state',
      );
    }
    return WesiRemoteMediaHandoff(
      handoffId: handoffId,
      jobId: jobId,
      direction: direction,
      status: status,
      chunkSize: chunkSize,
      maxByteSize: maxByteSize,
      expiresAt: expiresAt,
      file: file,
    );
  }
}

/// Bounded Stage-14 media transfer layered on the existing Stage-10 trust
/// boundary. The Control Plane only stores temporary chunks; it never executes
/// FFmpeg or a media model. User requests use normal WesiOS auth, while desktop
/// worker requests reuse the existing per-device HMAC credential.
class WesiRemoteMediaHandoffTransport {
  static const int chunkBytes = 256 * 1024;
  static const int maxFileBytes = 1024 * 1024 * 1024;
  static const int maxChunks = maxFileBytes ~/ chunkBytes;

  static const Set<String> allowedMimeTypes = <String>{
    'image/png',
    'image/jpeg',
    'image/webp',
    'audio/mpeg',
    'audio/mp3',
    'audio/wav',
    'audio/x-wav',
    'audio/flac',
    'audio/ogg',
    'audio/mp4',
    'audio/aac',
    'video/mp4',
    'video/webm',
    'video/quicktime',
    'video/x-matroska',
    'application/zip',
    'text/plain',
    'text/vtt',
    'application/x-subrip',
  };

  final Uri baseUri;
  final WesiRemoteWorkerUserAuthProvider userAuthProvider;
  final http.Client client;
  final WesiRemoteWorkerRequestSigner signer;
  final Duration timeout;
  final bool _ownsClient;

  WesiRemoteMediaHandoffTransport({
    required this.baseUri,
    required this.userAuthProvider,
    http.Client? client,
    WesiRemoteWorkerRequestSigner? signer,
    this.timeout = const Duration(seconds: 30),
  })  : client = client ?? http.Client(),
        signer = signer ?? WesiRemoteWorkerRequestSigner(),
        _ownsClient = client == null {
    final loopback = baseUri.host == 'localhost' ||
        baseUri.host == '127.0.0.1' ||
        baseUri.host == '::1';
    if (baseUri.scheme != 'https' && !(baseUri.scheme == 'http' && loopback)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_INSECURE_CONTROL_PLANE',
        'Remote media handoff requires HTTPS',
      );
    }
  }

  factory WesiRemoteMediaHandoffTransport.fromWorkerTransport(
    WesiRemoteWorkerHttpTransport transport,
  ) =>
      WesiRemoteMediaHandoffTransport(
        baseUri: transport.baseUri,
        userAuthProvider: transport.userAuthProvider,
        client: transport.client,
        signer: transport.signer,
        timeout: transport.timeout,
      );

  factory WesiRemoteMediaHandoffTransport.fromSyncEndpoint({
    http.Client? client,
    WesiRemoteWorkerRequestSigner? signer,
    Duration timeout = const Duration(seconds: 30),
  }) {
    final base = Uri.parse(SyncEndpoint.url);
    return WesiRemoteMediaHandoffTransport(
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
          throw const WesiRemoteMediaHandoffException(
            'WRM_NOT_SIGNED_IN',
            'Sign in to WesiOS before using a remote media worker',
          );
        }
        return WesiRemoteWorkerUserAuth(
          token: token,
          sessionId: sessionId,
        );
      },
    );
  }

  Future<WesiRemoteMediaHandoff> createInput({
    required String jobId,
    required String name,
    required String mimeType,
    required int byteSize,
    required String sha256Hex,
  }) async {
    _validateJobId(jobId);
    final file = _validateLocalMeta(
      name: name,
      mimeType: mimeType,
      byteSize: byteSize,
      sha256Hex: sha256Hex,
    );
    final json = await _userJson(
      'POST',
      '/api/wesi/ai/workers/media-handoffs',
      <String, dynamic>{
        'jobId': jobId,
        'direction': 'input',
        'file': file.toJson(),
      },
    );
    return _handoffFromResponse(json, expectedJobId: jobId, direction: 'input');
  }

  Future<WesiRemoteMediaHandoff> createOutput({
    required String jobId,
    required int maxByteSize,
  }) async {
    _validateJobId(jobId);
    if (maxByteSize <= 0 || maxByteSize > maxFileBytes) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_FILE_SIZE_INVALID',
        'Remote media output limit is invalid',
      );
    }
    final json = await _userJson(
      'POST',
      '/api/wesi/ai/workers/media-handoffs',
      <String, dynamic>{
        'jobId': jobId,
        'direction': 'output',
        'maxByteSize': maxByteSize,
      },
    );
    return _handoffFromResponse(json, expectedJobId: jobId, direction: 'output');
  }

  Future<void> uploadInputChunk(
    WesiRemoteMediaHandoff handoff,
    int index,
    Uint8List bytes,
  ) async {
    if (handoff.direction != 'input' || handoff.status != 'uploading') {
      throw const WesiRemoteMediaHandoffException(
        'WRM_HANDOFF_STATE_INVALID',
        'Remote media input handoff is not uploadable',
      );
    }
    final file = handoff.file!;
    if (bytes.lengthInBytes != file.expectedChunkBytes(index)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_CHUNK_SIZE_MISMATCH',
        'Remote media input chunk has an invalid size',
      );
    }
    await _userBytes(
      'PUT',
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/chunks/$index',
      bytes,
    );
  }

  Future<WesiRemoteMediaHandoff> completeInput(
    WesiRemoteMediaHandoff handoff,
  ) async {
    if (handoff.direction != 'input' || handoff.status != 'uploading') {
      throw const WesiRemoteMediaHandoffException(
        'WRM_HANDOFF_STATE_INVALID',
        'Remote media input handoff cannot be completed',
      );
    }
    final json = await _userJson(
      'POST',
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/complete',
      const <String, dynamic>{},
    );
    return _handoffFromResponse(
      json,
      expectedJobId: handoff.jobId,
      direction: 'input',
    );
  }

  Future<WesiRemoteMediaHandoff> status(String handoffId) async {
    _validateHandoffId(handoffId);
    final json = await _userJson(
      'GET',
      '/api/wesi/ai/workers/media-handoffs/$handoffId',
      null,
    );
    return _handoffFromResponse(json);
  }

  Future<Uint8List> downloadOutputChunk(
    WesiRemoteMediaHandoff handoff,
    int index,
  ) async {
    if (handoff.direction != 'output' || !handoff.ready || handoff.file == null) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_HANDOFF_STATE_INVALID',
        'Remote media output is not ready',
      );
    }
    final expected = handoff.file!.expectedChunkBytes(index);
    final json = await _userJson(
      'GET',
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/chunks/$index',
      null,
    );
    return _boundedBase64(json['dataBase64'], expected);
  }

  Future<void> deleteHandoff(String handoffId) async {
    _validateHandoffId(handoffId);
    await _userJson(
      'DELETE',
      '/api/wesi/ai/workers/media-handoffs/$handoffId',
      null,
    );
  }

  Future<({WesiRemoteMediaHandoff handoff, Uint8List bytes})>
      workerDownloadInputChunk({
    required WesiWorkerCredential credential,
    required String handoffId,
    required String jobId,
    required int index,
    DateTime? now,
  }) async {
    _validateHandoffId(handoffId);
    _validateJobId(jobId);
    final json = await _workerJson(
      '/api/wesi/ai/workers/media-handoffs/$handoffId/worker/input/$index',
      credential,
      <String, dynamic>{'jobId': jobId},
      now: now,
    );
    final handoff = _handoffFromResponse(
      json,
      expectedJobId: jobId,
      direction: 'input',
    );
    final file = handoff.file;
    if (file == null || !handoff.ready) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_SERVER_RESPONSE',
        'Control Plane returned an incomplete media input handoff',
      );
    }
    final bytes = _boundedBase64(json['dataBase64'], file.expectedChunkBytes(index));
    return (handoff: handoff, bytes: bytes);
  }

  Future<WesiRemoteMediaHandoff> workerStartOutput({
    required WesiWorkerCredential credential,
    required WesiRemoteMediaHandoff handoff,
    required WesiRemoteMediaFileMeta file,
    DateTime? now,
  }) async {
    if (handoff.direction != 'output' || handoff.status != 'awaiting_worker') {
      throw const WesiRemoteMediaHandoffException(
        'WRM_HANDOFF_STATE_INVALID',
        'Remote media output handoff cannot be started',
      );
    }
    _validateLocalMeta(
      name: file.name,
      mimeType: file.mimeType,
      byteSize: file.byteSize,
      sha256Hex: file.sha256Hex,
      maxBytes: handoff.maxByteSize,
    );
    final json = await _workerJson(
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/worker/output/start',
      credential,
      <String, dynamic>{
        'jobId': handoff.jobId,
        'file': file.toJson(),
      },
      now: now,
    );
    return _handoffFromResponse(
      json,
      expectedJobId: handoff.jobId,
      direction: 'output',
    );
  }

  Future<void> workerUploadOutputChunk({
    required WesiWorkerCredential credential,
    required WesiRemoteMediaHandoff handoff,
    required int index,
    required Uint8List bytes,
    DateTime? now,
  }) async {
    if (handoff.direction != 'output' ||
        handoff.status != 'uploading' ||
        handoff.file == null ||
        bytes.lengthInBytes != handoff.file!.expectedChunkBytes(index)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_CHUNK_SIZE_MISMATCH',
        'Remote media output chunk is invalid',
      );
    }
    await _workerJson(
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/worker/output/chunk',
      credential,
      <String, dynamic>{
        'jobId': handoff.jobId,
        'index': index,
        'dataBase64': base64Encode(bytes),
      },
      now: now,
    );
  }

  Future<WesiRemoteMediaHandoff> workerCompleteOutput({
    required WesiWorkerCredential credential,
    required WesiRemoteMediaHandoff handoff,
    DateTime? now,
  }) async {
    if (handoff.direction != 'output' || handoff.status != 'uploading') {
      throw const WesiRemoteMediaHandoffException(
        'WRM_HANDOFF_STATE_INVALID',
        'Remote media output handoff cannot be completed',
      );
    }
    final json = await _workerJson(
      '/api/wesi/ai/workers/media-handoffs/${handoff.handoffId}/worker/output/complete',
      credential,
      <String, dynamic>{'jobId': handoff.jobId},
      now: now,
    );
    return _handoffFromResponse(
      json,
      expectedJobId: handoff.jobId,
      direction: 'output',
    );
  }

  Future<Map<String, dynamic>> _workerJson(
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
    return _send(
      () => client.post(
        _uri(path),
        headers: <String, String>{
          'Content-Type': 'application/json',
          ...signed.toHeaders(),
        },
        body: jsonEncode(<String, dynamic>{'payloadJson': payloadJson}),
      ),
    );
  }

  Future<Map<String, dynamic>> _userJson(
    String method,
    String path,
    Map<String, dynamic>? body,
  ) async {
    final auth = userAuthProvider();
    final headers = <String, String>{
      'Authorization': auth.token,
      'X-WesiOS-Session': auth.sessionId,
      if (body != null) 'Content-Type': 'application/json',
    };
    return _send(() {
      final uri = _uri(path);
      return switch (method) {
        'POST' => client.post(uri, headers: headers, body: jsonEncode(body ?? const {})),
        'GET' => client.get(uri, headers: headers),
        'DELETE' => client.delete(uri, headers: headers),
        _ => throw const WesiRemoteMediaHandoffException(
            'WRM_BAD_REQUEST_TARGET',
            'Unsupported remote media request method',
          ),
      };
    });
  }

  Future<void> _userBytes(
    String method,
    String path,
    Uint8List bytes,
  ) async {
    if (method != 'PUT' || bytes.isEmpty || bytes.lengthInBytes > chunkBytes) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_CHUNK',
        'Remote media binary request is invalid',
      );
    }
    final auth = userAuthProvider();
    await _send(
      () => client.put(
        _uri(path),
        headers: <String, String>{
          'Authorization': auth.token,
          'X-WesiOS-Session': auth.sessionId,
          'Content-Type': 'application/octet-stream',
        },
        body: bytes,
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
        throw WesiRemoteMediaHandoffException(
          'WRM_BAD_SERVER_RESPONSE',
          'Control Plane returned invalid remote media JSON',
          statusCode: response.statusCode,
        );
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          json['ok'] != true) {
        final code = '${json['code'] ?? 'WRM_REQUEST_FAILED'}';
        throw WesiRemoteMediaHandoffException(
          code,
          'Remote media handoff request failed',
          statusCode: response.statusCode,
        );
      }
      return json;
    } on WesiRemoteMediaHandoffException {
      rethrow;
    } on TimeoutException {
      throw const WesiRemoteMediaHandoffException(
        'WRM_NETWORK_TIMEOUT',
        'Remote media handoff timed out',
      );
    } on http.ClientException {
      throw const WesiRemoteMediaHandoffException(
        'WRM_NETWORK_FAILED',
        'Remote media handoff Control Plane is unavailable',
      );
    }
  }

  WesiRemoteMediaHandoff _handoffFromResponse(
    Map<String, dynamic> json, {
    String? expectedJobId,
    String? direction,
  }) {
    final raw = json['handoff'];
    if (raw is! Map) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_SERVER_RESPONSE',
        'Control Plane omitted remote media handoff state',
      );
    }
    final handoff = WesiRemoteMediaHandoff.fromJson(
      raw.map((key, value) => MapEntry('$key', value)),
    );
    if ((expectedJobId != null && handoff.jobId != expectedJobId) ||
        (direction != null && handoff.direction != direction)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_SERVER_RESPONSE',
        'Control Plane returned mismatched remote media handoff state',
      );
    }
    return handoff;
  }

  static WesiRemoteMediaFileMeta _validateLocalMeta({
    required String name,
    required String mimeType,
    required int byteSize,
    required String sha256Hex,
    int maxBytes = maxFileBytes,
  }) {
    final cleanName = name.trim();
    final cleanMime = mimeType.split(';').first.trim().toLowerCase();
    final digest = sha256Hex.trim().toLowerCase();
    if (cleanName.isEmpty ||
        cleanName.length > 180 ||
        !allowedMimeTypes.contains(cleanMime) ||
        byteSize <= 0 ||
        byteSize > maxBytes ||
        maxBytes <= 0 ||
        maxBytes > maxFileBytes ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(digest)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_FILE_META',
        'Remote media file metadata is invalid',
      );
    }
    return WesiRemoteMediaFileMeta(
      name: cleanName,
      mimeType: cleanMime,
      byteSize: byteSize,
      sha256Hex: digest,
      chunkSize: chunkBytes,
      chunkCount: (byteSize + chunkBytes - 1) ~/ chunkBytes,
    );
  }

  static Uint8List _boundedBase64(Object? raw, int expectedBytes) {
    final text = '${raw ?? ''}'.trim();
    if (expectedBytes <= 0 || expectedBytes > chunkBytes || text.isEmpty) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_BASE64',
        'Remote media chunk payload is invalid',
      );
    }
    try {
      final bytes = base64Decode(text);
      if (bytes.lengthInBytes != expectedBytes || base64Encode(bytes) != text) {
        throw const FormatException();
      }
      return bytes;
    } on FormatException {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_BASE64',
        'Remote media chunk payload is invalid',
      );
    }
  }

  static void _validateJobId(String jobId) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(jobId)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_JOB_ID',
        'Remote media job id is invalid',
      );
    }
  }

  static void _validateHandoffId(String handoffId) {
    if (!RegExp(r'^wrm_[A-Za-z0-9_-]{20,80}$').hasMatch(handoffId)) {
      throw const WesiRemoteMediaHandoffException(
        'WRM_BAD_HANDOFF_ID',
        'Remote media handoff id is invalid',
      );
    }
  }

  Uri _uri(String path) => baseUri.replace(path: path, query: null);

  void close() {
    if (_ownsClient) client.close();
  }
}

int _strictInt(Object? value) {
  if (value is! num || value.isNaN || value.isInfinite) return -1;
  final integer = value.toInt();
  return integer.toDouble() == value.toDouble() ? integer : -1;
}
