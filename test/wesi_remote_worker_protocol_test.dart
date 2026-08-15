import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_auth.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_pairing.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_registry.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

void main() {
  final now = DateTime.utc(2026, 8, 15, 16);

  test('pairing QR excludes poll secret and credential', () {
    final service = WesiRemoteWorkerPairingService(random: Random(7));
    final bootstrap = service.createTicket(
      ownerScope: 'owner-1',
      workerName: 'Workstation',
      deviceFingerprint: 'a' * 64,
      now: now,
    );
    final uri = bootstrap.ticket.toUri().toString();
    expect(uri, isNot(contains(bootstrap.pollSecret)));
    expect(uri, isNot(contains('credential')));
    final parsed = WesiWorkerPairingTicket.fromUri(
      Uri.parse(uri),
      now: now,
    );
    expect(parsed.workerId, bootstrap.ticket.workerId);
  });

  test('pairing claim and credential delivery are one-time', () {
    final service = WesiRemoteWorkerPairingService(random: Random(11));
    final bootstrap = service.createTicket(
      ownerScope: 'owner-1',
      workerName: 'Desktop',
      deviceFingerprint: 'b' * 64,
      now: now,
    );
    service.claim(
      ownerScope: 'owner-1',
      ticket: bootstrap.ticket,
      now: now.add(const Duration(seconds: 1)),
    );
    expect(
      () => service.claim(
        ownerScope: 'owner-1',
        ticket: bootstrap.ticket,
        now: now.add(const Duration(seconds: 2)),
      ),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
    final credential = service.pollCredential(
      ticketId: bootstrap.ticket.ticketId,
      pollSecret: bootstrap.pollSecret,
      now: now.add(const Duration(seconds: 2)),
    );
    expect(credential, isNotNull);
    expect(
      service.verifyCredentialSecret(
        credentialId: credential!.credentialId,
        workerId: credential.workerId,
        secret: credential.secret,
        now: now.add(const Duration(minutes: 1)),
      ),
      isTrue,
    );
    expect(
      () => service.pollCredential(
        ticketId: bootstrap.ticket.ticketId,
        pollSecret: bootstrap.pollSecret,
        now: now.add(const Duration(seconds: 3)),
      ),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
    service.revokeWorker(credential.workerId, now: now.add(const Duration(minutes: 2)));
    expect(
      service.verifyCredentialSecret(
        credentialId: credential.credentialId,
        workerId: credential.workerId,
        secret: credential.secret,
        now: now.add(const Duration(minutes: 3)),
      ),
      isFalse,
    );
  });

  test('pairing rejects wrong owner scope and expired QR', () {
    final service = WesiRemoteWorkerPairingService(random: Random(13));
    final bootstrap = service.createTicket(
      ownerScope: 'owner-1',
      workerName: 'Desktop',
      deviceFingerprint: 'c' * 64,
      now: now,
    );
    expect(
      () => service.claim(
        ownerScope: 'owner-2',
        ticket: bootstrap.ticket,
        now: now.add(const Duration(seconds: 1)),
      ),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
    expect(
      () => WesiWorkerPairingTicket.fromUri(
        bootstrap.ticket.toUri(),
        now: now.add(const Duration(minutes: 6)),
      ),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
  });

  test('HMAC signing rejects body tamper, stale request and replay', () {
    final credential = WesiWorkerCredential(
      credentialId: 'a' * 32,
      workerId: 'b' * 32,
      secret: 'super-secret-worker-key',
      issuedAt: now,
      expiresAt: now.add(const Duration(days: 1)),
    );
    final signer = WesiRemoteWorkerRequestSigner(random: Random(17));
    final body = utf8.encode('{"ok":true}');
    final request = signer.sign(
      credential: credential,
      method: 'POST',
      path: '/api/wesi/ai/workers/heartbeat',
      body: body,
      now: now,
    );
    expect(
      WesiRemoteWorkerRequestSigner.verify(
        request: request,
        secret: credential.secret,
        method: 'POST',
        path: '/api/wesi/ai/workers/heartbeat',
        body: body,
        now: now.add(const Duration(seconds: 10)),
      ),
      isTrue,
    );
    expect(
      WesiRemoteWorkerRequestSigner.verify(
        request: request,
        secret: credential.secret,
        method: 'POST',
        path: '/api/wesi/ai/workers/heartbeat',
        body: utf8.encode('{"ok":false}'),
        now: now,
      ),
      isFalse,
    );
    expect(
      WesiRemoteWorkerRequestSigner.verify(
        request: request,
        secret: credential.secret,
        method: 'POST',
        path: '/api/wesi/ai/workers/heartbeat',
        body: body,
        now: now.add(const Duration(minutes: 3)),
      ),
      isFalse,
    );
    final replay = WesiWorkerReplayGuard();
    expect(replay.accept(request.credentialId, request.nonce, now: now), isTrue);
    expect(replay.accept(request.credentialId, request.nonce, now: now), isFalse);
  });

  test('heartbeat feeds Stage 8 worker profile and expires offline', () {
    final registry = WesiRemoteWorkerRegistry(heartbeatTtl: const Duration(seconds: 30));
    final profile = _profile('w' * 32, now);
    final json = WesiRemoteWorkerHeartbeat(profile: profile, sentAt: now).toJson();
    final parsed = WesiRemoteWorkerHeartbeat.fromJson(json);
    registry.applyHeartbeat(parsed, now: now);
    final live = registry.schedulerWorkers(now: now.add(const Duration(seconds: 10))).single;
    expect(live.status, WesiWorkerStatus.online);
    expect(live.role, WesiWorkerRole.remoteWorker);
    expect(live.trust, WesiWorkerTrust.paired);
    final stale = registry.schedulerWorkers(now: now.add(const Duration(seconds: 40))).single;
    expect(stale.status, WesiWorkerStatus.offline);
    expect(stale.appForeground, isFalse);
  });

  test('mailbox is idempotent and worker sequence rejects replay', () {
    final registry = WesiRemoteWorkerRegistry();
    registry.applyHeartbeat(
      WesiRemoteWorkerHeartbeat(profile: _profile('x' * 32, now), sentAt: now),
      now: now,
    );
    final message = WesiRemoteJobMessage(
      messageId: 'msg-1',
      jobId: 'job-1',
      kind: WesiRemoteJobMessageKind.assignment,
      sequence: 1,
      createdAt: now,
    );
    registry.enqueueToWorker('x' * 32, message);
    registry.enqueueToWorker('x' * 32, message);
    expect(registry.poll('x' * 32), hasLength(1));
    registry.ack('x' * 32, 'msg-1');
    expect(registry.poll('x' * 32), isEmpty);

    final progress = WesiRemoteJobMessage(
      messageId: 'progress-1',
      jobId: 'job-1',
      kind: WesiRemoteJobMessageKind.progress,
      sequence: 3,
      createdAt: now,
    );
    registry.acceptWorkerMessage('x' * 32, progress);
    expect(
      () => registry.acceptWorkerMessage('x' * 32, progress),
      throwsA(isA<WesiRemoteWorkerProtocolException>()),
    );
  });
}

WesiWorkerResourceProfile _profile(String id, DateTime now) =>
    WesiWorkerResourceProfile(
      id: id,
      name: 'Desktop worker',
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
      availableRamMb: 10000,
      totalGpuVramMb: 8192,
      freeGpuVramMb: 7000,
      freeDiskMb: 100000,
      capabilities: const <WesiLocalCapability>{WesiLocalCapability.flutter},
      installedPacks: const <WesiRuntimePackId>{WesiRuntimePackId.developer},
      lastSeenAt: now,
    );
