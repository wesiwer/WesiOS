import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_auth.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_http_transport.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

void main() {
  test('user pairing transport applies WesiOS auth and never puts poll secret in ticket',
      () async {
    late http.Request captured;
    final now = DateTime.now().toUtc();
    final client = MockClient((request) async {
      captured = request;
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'ticket': <String, dynamic>{
            'ticketId': 't' * 32,
            'workerId': 'w' * 32,
            'workerName': 'Desktop',
            'deviceFingerprint': 'a' * 64,
            'nonce': 'n' * 32,
            'expiresAtMs': now.add(const Duration(minutes: 5)).millisecondsSinceEpoch,
            'lanHint': null,
          },
          'pollSecret': 's' * 64,
        }),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    });
    final transport = _transport(client);
    final bootstrap = await transport.createPairing(
      workerName: 'Desktop',
      deviceFingerprint: 'a' * 64,
    );

    expect(captured.url.path, '/api/wesi/ai/workers/pairing/create');
    expect(captured.headers['authorization'], 'pb-token');
    expect(captured.headers['x-wesios-session'], 'session-123');
    expect(bootstrap.pollSecret, 's' * 64);
    final uri = bootstrap.ticket.toUri().toString();
    expect(uri, isNot(contains(bootstrap.pollSecret)));
    expect(uri, isNot(contains('credential')));
  });

  test('worker heartbeat is HMAC signed over payloadJson and not user auth', () async {
    final now = DateTime.utc(2026, 8, 15, 17);
    final credential = WesiWorkerCredential(
      credentialId: 'c' * 32,
      workerId: 'w' * 32,
      secret: 'worker-bootstrap-secret-' * 3,
      issuedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(days: 1)),
    );
    final heartbeat = _heartbeat(credential.workerId, now);
    var verified = false;
    final client = MockClient((request) async {
      expect(request.url.path, '/api/wesi/ai/workers/heartbeat');
      expect(request.headers.containsKey('authorization'), isFalse);
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
      final decoded = jsonDecode(payloadJson) as Map<String, dynamic>;
      expect(decoded['worker']['id'], credential.workerId);
      return http.Response('{"ok":true}', 200);
    });
    final transport = _transport(client);
    await transport.sendHeartbeat(credential, heartbeat, now: now);
    expect(verified, isTrue);
  });

  test('worker mailbox parses authenticated assignment messages', () async {
    final now = DateTime.utc(2026, 8, 15, 17);
    final credential = WesiWorkerCredential(
      credentialId: 'c' * 32,
      workerId: 'w' * 32,
      secret: 'worker-bootstrap-secret-' * 3,
      issuedAt: now.subtract(const Duration(minutes: 1)),
      expiresAt: now.add(const Duration(days: 1)),
    );
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{
              'v': 1,
              'messageId': 'assignment-1',
              'jobId': 'job-1',
              'kind': 'assignment',
              'sequence': 11,
              'createdAt': now.toIso8601String(),
              'payload': <String, dynamic>{
                'leaseId': 'l' * 32,
                'generation': 1,
              },
            },
          ],
        }),
        200,
      );
    });
    final transport = _transport(client);
    final messages = await transport.pollWorkerMailbox(
      credential,
      now: now,
    );
    expect(messages, hasLength(1));
    expect(messages.single.kind, WesiRemoteJobMessageKind.assignment);
    expect(messages.single.jobId, 'job-1');
  });

  test('user worker list converts server heartbeats into trusted remote profiles',
      () async {
    final now = DateTime.utc(2026, 8, 15, 17);
    final heartbeat = _heartbeat('w' * 32, now);
    final client = MockClient((request) async {
      return http.Response(
        jsonEncode(<String, dynamic>{
          'ok': true,
          'heartbeats': <Map<String, dynamic>>[heartbeat.toJson()],
        }),
        200,
      );
    });
    final transport = _transport(client);
    final result = await transport.listHeartbeats();
    expect(result, hasLength(1));
    expect(result.single.profile.remoteWorker, isTrue);
    expect(result.single.profile.trust, WesiWorkerTrust.paired);
  });
}

WesiRemoteWorkerHttpTransport _transport(http.Client client) =>
    WesiRemoteWorkerHttpTransport(
      baseUri: Uri.parse('https://api.wesi.test'),
      client: client,
      signer: WesiRemoteWorkerRequestSigner(random: _FixedRandom()),
      userAuthProvider: () => const WesiRemoteWorkerUserAuth(
        token: 'pb-token',
        sessionId: 'session-123',
      ),
    );

WesiRemoteWorkerHeartbeat _heartbeat(String workerId, DateTime now) =>
    WesiRemoteWorkerHeartbeat(
      profile: WesiWorkerResourceProfile(
        id: workerId,
        name: 'Desktop',
        platform: WesiWorkerPlatform.windows,
        status: WesiWorkerStatus.online,
        trust: WesiWorkerTrust.paired,
        role: WesiWorkerRole.remoteWorker,
        policyAllowed: true,
        appForeground: true,
        backgroundExecutionAllowed: true,
        cpuCores: 8,
        cpuLoadPercent: 20,
        totalRamMb: 16384,
        availableRamMb: 12000,
        totalGpuVramMb: 8192,
        freeGpuVramMb: 7000,
        freeDiskMb: 100000,
        capabilities: const <WesiLocalCapability>{WesiLocalCapability.build},
        installedPacks: const <WesiRuntimePackId>{WesiRuntimePackId.developer},
        lastSeenAt: now,
      ),
      sentAt: now,
    );

class _FixedRandom implements dynamic {
  int _value = 1;

  int nextInt(int max) {
    final value = _value % max;
    _value++;
    return value;
  }

  bool nextBool() => true;

  double nextDouble() => 0.5;
}
