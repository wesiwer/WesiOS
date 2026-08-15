import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_agent.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_execution_store.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_http_transport.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_models.dart';
import 'package:wesios/features/ai/runtime/wesi_remote_worker_receipt_store.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

const _workerId = 'wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww';
const _credentialId = 'cccccccccccccccccccccccccccccccc';
const _leaseId = 'llllllllllllllllllllllllllllllll';

void main() {
  final now = DateTime.utc(2026, 8, 15, 18);

  test('checkpointed pause acknowledges the pause control message', () async {
    final sent = <Map<String, dynamic>>[];
    var polls = 0;
    final assignment = _assignment(now);
    final pause = WesiRemoteJobMessage(
      messageId: 'pause-message-1',
      jobId: assignment.jobId,
      kind: WesiRemoteJobMessageKind.pause,
      sequence: 12,
      createdAt: now,
      payload: const <String, dynamic>{
        'leaseId': _leaseId,
        'generation': 1,
      },
    );
    final client = MockClient((request) async {
      if (request.url.path == '/api/wesi/ai/workers/heartbeat') {
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/api/wesi/ai/workers/mailbox/poll') {
        polls++;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'messages': polls == 1
                ? <Map<String, dynamic>>[assignment.toJson(), pause.toJson()]
                : <Map<String, dynamic>>[],
          }),
          200,
        );
      }
      if (request.url.path == '/api/wesi/ai/workers/message') {
        final outer = jsonDecode(request.body) as Map<String, dynamic>;
        final payload = jsonDecode(outer['payloadJson'] as String)
            as Map<String, dynamic>;
        sent.add(Map<String, dynamic>.from(payload['message'] as Map));
        return http.Response('{"ok":true}', 200);
      }
      fail('Unexpected path ${request.url.path}');
    });

    final agent = _agent(client, _CheckpointingPauseHandler());
    await agent.tick(now: now);
    await agent.drain();

    final checkpoint = sent.singleWhere((item) => item['kind'] == 'checkpoint');
    expect(checkpoint['sequence'], 3);
    expect(checkpoint['payload']['checkpointId'], 'checkpoint-1');

    final pauseAck = sent.singleWhere(
      (item) => item['kind'] == 'ack' &&
          item['payload']['ackedMessageId'] == pause.messageId,
    );
    expect(pauseAck['sequence'], 4);
  });

  test('unexpected handler pause fails closed instead of leaving job running', () async {
    final sent = <Map<String, dynamic>>[];
    final assignment = _assignment(now);
    var polls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/wesi/ai/workers/heartbeat') {
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/api/wesi/ai/workers/mailbox/poll') {
        polls++;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'messages': polls == 1
                ? <Map<String, dynamic>>[assignment.toJson()]
                : <Map<String, dynamic>>[],
          }),
          200,
        );
      }
      if (request.url.path == '/api/wesi/ai/workers/message') {
        final outer = jsonDecode(request.body) as Map<String, dynamic>;
        final payload = jsonDecode(outer['payloadJson'] as String)
            as Map<String, dynamic>;
        sent.add(Map<String, dynamic>.from(payload['message'] as Map));
        return http.Response('{"ok":true}', 200);
      }
      fail('Unexpected path ${request.url.path}');
    });

    final agent = _agent(client, const _UnexpectedPauseHandler());
    await agent.tick(now: now);
    await agent.drain();

    expect(sent.where((item) => item['kind'] == 'checkpoint'), isEmpty);
    final result = sent.singleWhere((item) => item['kind'] == 'result');
    expect(result['payload']['success'], isFalse);
    expect(result['payload']['code'], 'WRW_UNEXPECTED_PAUSE');
  });
}

WesiRemoteWorkerAgent _agent(
  http.Client client,
  WesiRemoteWorkerExecutionHandler handler,
) {
  final transport = WesiRemoteWorkerHttpTransport(
    baseUri: Uri.parse('https://api.wesi.test'),
    client: client,
    userAuthProvider: () => const WesiRemoteWorkerUserAuth(
      token: 'unused',
      sessionId: 'unused-session',
    ),
  );
  return WesiRemoteWorkerAgent(
    transport: transport,
    credential: WesiWorkerCredential(
      credentialId: _credentialId,
      workerId: _workerId,
      secret: 'worker-secret-' * 4,
      issuedAt: DateTime.utc(2026, 8, 15),
      expiresAt: DateTime.utc(2026, 8, 16),
    ),
    receipts: WesiRemoteWorkerReceiptStore(
      journal: WesiMemoryRemoteWorkerReceiptJournal(),
    ),
    executionHandler: handler,
    profileProvider: (busy) async => WesiWorkerResourceProfile(
      id: _workerId,
      name: 'Desktop Worker',
      platform: WesiWorkerPlatform.windows,
      status: busy ? WesiWorkerStatus.busy : WesiWorkerStatus.online,
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
      activeHeavyJobs: busy ? 1 : 0,
    ),
  );
}

WesiRemoteJobMessage _assignment(DateTime now) {
  const execution = WesiRemoteExecutionRequest(
    workspaceId: 'workspace-main',
    call: WesiLocalToolCall(
      id: 'tool-call-1',
      tool: WesiLocalToolNames.flutterBuild,
      arguments: <String, dynamic>{'target': 'apk'},
    ),
  );
  return WesiRemoteJobMessage(
    messageId: 'assignment-message-1',
    jobId: 'job-build-1',
    kind: WesiRemoteJobMessageKind.assignment,
    sequence: 11,
    createdAt: now,
    payload: <String, dynamic>{
      'leaseId': _leaseId,
      'generation': 1,
      'execution': execution.toJson(),
    },
  );
}

class _CheckpointingPauseHandler implements WesiRemoteWorkerExecutionHandler {
  @override
  Future<WesiRemoteWorkerExecutionOutcome> execute(
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control,
  ) async {
    while (!control.pauseRequested) {
      await Future<void>.delayed(Duration.zero);
    }
    return const WesiRemoteWorkerExecutionOutcome(
      disposition: WesiRemoteWorkerExecutionDisposition.paused,
      code: 'PAUSED',
      message: 'Checkpoint saved',
      checkpointId: 'checkpoint-1',
      checkpointVersion: 1,
      checkpointStage: 'build',
      checkpointProgress: 0.4,
    );
  }
}

class _UnexpectedPauseHandler implements WesiRemoteWorkerExecutionHandler {
  const _UnexpectedPauseHandler();

  @override
  Future<WesiRemoteWorkerExecutionOutcome> execute(
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control,
  ) async =>
      const WesiRemoteWorkerExecutionOutcome(
        disposition: WesiRemoteWorkerExecutionDisposition.paused,
        code: 'PAUSED',
        message: 'Unexpected pause',
        checkpointId: 'checkpoint-unexpected',
        checkpointVersion: 1,
        checkpointStage: 'build',
        checkpointProgress: 0.2,
      );
}
