import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_media_handoff.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_auth.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_http_transport.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_models.dart';

void main() {
  test('user input handoff uses WesiOS auth and bounded binary chunks', () async {
    final handoffId = 'wrm_${_repeat('h', 32)}';
    const jobId = 'job-media-1';
    final digest = _repeat('a', 64);
    var createSeen = false;
    var chunkSeen = false;
    final client = MockClient((request) async {
      if (request.method == 'POST' &&
          request.url.path == '/api/wesi/ai/workers/media-handoffs') {
        createSeen = true;
        expect(request.headers['authorization'], 'pb-token');
        expect(request.headers['x-wesios-session'], 'session-123');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['jobId'], jobId);
        expect(body['direction'], 'input');
        expect((body['file'] as Map)['sha256'], digest);
        return _jsonResponse(_handoffEnvelope(
          handoffId: handoffId,
          jobId: jobId,
          direction: 'input',
          status: 'uploading',
          file: _file(byteSize: 4, sha: digest),
        ));
      }
      if (request.method == 'PUT') {
        chunkSeen = true;
        expect(
          request.url.path,
          '/api/wesi/ai/workers/media-handoffs/$handoffId/chunks/0',
        );
        expect(request.headers['authorization'], 'pb-token');
        expect(request.bodyBytes, <int>[1, 2, 3, 4]);
        return _jsonResponse(<String, dynamic>{'ok': true, 'index': 0});
      }
      fail('unexpected request ${request.method} ${request.url.path}');
    });
    final transport = _transport(client);
    final handoff = await transport.createInput(
      jobId: jobId,
      name: 'voice.wav',
      mimeType: 'audio/wav',
      byteSize: 4,
      sha256Hex: digest,
    );
    await transport.uploadInputChunk(
      handoff,
      0,
      Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    expect(createSeen, isTrue);
    expect(chunkSeen, isTrue);
  });

  test('worker input download is HMAC signed for the exact handoff path',
      () async {
    final now = DateTime.utc(2026, 8, 17, 6);
    final credential = _credential(now);
    final handoffId = 'wrm_${_repeat('i', 32)}';
    const jobId = 'job-media-worker';
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    var verified = false;
    final client = MockClient((request) async {
      final outer = jsonDecode(request.body) as Map<String, dynamic>;
      final payloadJson = outer['payloadJson'] as String;
      final signed = WesiRemoteWorkerSignedRequest(
        credentialId: request.headers['x-wesi-worker-credential']!,
        workerId: request.headers['x-wesi-worker-id']!,
        timestampMs: int.parse(request.headers['x-wesi-worker-timestamp']!),
        nonce: request.headers['x-wesi-worker-nonce']!,
        bodySha256: request.headers['x-wesi-worker-body-sha256']!,
        signature: request.headers['x-wesi-worker-signature']!,
      );
      verified = WesiRemoteWorkerRequestSigner.verify(
        request: signed,
        secret: credential.secret,
        method: 'POST',
        path: request.url.path,
        body: utf8.encode(payloadJson),
        now: now,
      );
      expect(jsonDecode(payloadJson), <String, dynamic>{'jobId': jobId});
      return _jsonResponse(<String, dynamic>{
        ..._handoffEnvelope(
          handoffId: handoffId,
          jobId: jobId,
          direction: 'input',
          status: 'ready',
          file: _file(byteSize: 4, sha: _repeat('b', 64)),
        ),
        'index': 0,
        'dataBase64': base64Encode(bytes),
      });
    });
    final transport = _transport(
      client,
      signer: WesiRemoteWorkerRequestSigner(random: _FixedRandom()),
    );
    final result = await transport.workerDownloadInputChunk(
      credential: credential,
      handoffId: handoffId,
      jobId: jobId,
      index: 0,
      now: now,
    );
    expect(verified, isTrue);
    expect(result.bytes, bytes);
    expect(result.handoff.ready, isTrue);
  });

  test('worker output chunk contains bytes only and never a local path',
      () async {
    final now = DateTime.utc(2026, 8, 17, 6);
    final credential = _credential(now);
    final handoffId = 'wrm_${_repeat('o', 32)}';
    const jobId = 'job-media-output';
    final meta = WesiRemoteMediaFileMeta(
      name: 'result.wav',
      mimeType: 'audio/wav',
      byteSize: 4,
      sha256Hex: _repeat('c', 64),
      chunkSize: WesiRemoteMediaHandoffTransport.chunkBytes,
      chunkCount: 1,
    );
    final handoff = WesiRemoteMediaHandoff(
      handoffId: handoffId,
      jobId: jobId,
      direction: 'output',
      status: 'uploading',
      chunkSize: WesiRemoteMediaHandoffTransport.chunkBytes,
      maxByteSize: 1024,
      expiresAt: DateTime.utc(2030),
      file: meta,
    );
    final client = MockClient((request) async {
      final outer = jsonDecode(request.body) as Map<String, dynamic>;
      final payloadJson = outer['payloadJson'] as String;
      expect(payloadJson, isNot(contains(r'C:\')));
      expect(payloadJson, isNot(contains('/home/')));
      final payload = jsonDecode(payloadJson) as Map<String, dynamic>;
      expect(payload.keys.toSet(), <String>{'jobId', 'index', 'dataBase64'});
      expect(base64Decode(payload['dataBase64'] as String), <int>[7, 8, 9, 10]);
      return _jsonResponse(<String, dynamic>{'ok': true, 'index': 0});
    });
    final transport = _transport(
      client,
      signer: WesiRemoteWorkerRequestSigner(random: _FixedRandom()),
    );
    await transport.workerUploadOutputChunk(
      credential: credential,
      handoff: handoff,
      index: 0,
      bytes: Uint8List.fromList(<int>[7, 8, 9, 10]),
      now: now,
    );
  });

  test('invalid server file metadata is rejected fail closed', () async {
    final client = MockClient((request) async => _jsonResponse(
          _handoffEnvelope(
            handoffId: 'wrm_${_repeat('x', 32)}',
            jobId: 'job-bad-meta',
            direction: 'input',
            status: 'uploading',
            file: _file(byteSize: 4, sha: 'not-a-sha'),
          ),
        ));
    final transport = _transport(client);
    expect(
      () => transport.createInput(
        jobId: 'job-bad-meta',
        name: 'voice.wav',
        mimeType: 'audio/wav',
        byteSize: 4,
        sha256Hex: _repeat('d', 64),
      ),
      throwsA(isA<WesiRemoteMediaHandoffException>()),
    );
  });
}

WesiRemoteMediaHandoffTransport _transport(
  http.Client client, {
  WesiRemoteWorkerRequestSigner? signer,
}) =>
    WesiRemoteMediaHandoffTransport(
      baseUri: Uri.parse('https://api.wesi.test'),
      client: client,
      signer: signer,
      userAuthProvider: () => const WesiRemoteWorkerUserAuth(
        token: 'pb-token',
        sessionId: 'session-123',
      ),
    );

WesiWorkerCredential _credential(DateTime now) => WesiWorkerCredential(
      credentialId: _repeat('c', 32),
      workerId: _repeat('w', 32),
      secret: _repeat('remote-media-worker-secret-', 3),
      issuedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: DateTime.utc(2100),
    );

Map<String, dynamic> _file({required int byteSize, required String sha}) =>
    <String, dynamic>{
      'name': 'voice.wav',
      'mimeType': 'audio/wav',
      'byteSize': byteSize,
      'sha256': sha,
      'chunkSize': WesiRemoteMediaHandoffTransport.chunkBytes,
      'chunkCount':
          (byteSize + WesiRemoteMediaHandoffTransport.chunkBytes - 1) ~/
              WesiRemoteMediaHandoffTransport.chunkBytes,
    };

Map<String, dynamic> _handoffEnvelope({
  required String handoffId,
  required String jobId,
  required String direction,
  required String status,
  Map<String, dynamic>? file,
}) =>
    <String, dynamic>{
      'ok': true,
      'handoff': <String, dynamic>{
        'handoffId': handoffId,
        'jobId': jobId,
        'direction': direction,
        'status': status,
        'chunkSize': WesiRemoteMediaHandoffTransport.chunkBytes,
        'maxByteSize': WesiRemoteMediaHandoffTransport.maxFileBytes,
        'expiresAt': DateTime.utc(2030).toIso8601String(),
        'file': file,
      },
    };

http.Response _jsonResponse(Map<String, dynamic> json) => http.Response(
      jsonEncode(json),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );

String _repeat(String value, int count) => List<String>.filled(count, value).join();

class _FixedRandom implements Random {
  int _value = 1;

  @override
  int nextInt(int max) {
    final value = _value % max;
    _value++;
    return value;
  }

  @override
  bool nextBool() => true;

  @override
  double nextDouble() => 0.5;
}
