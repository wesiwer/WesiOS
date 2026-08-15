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

const workerId = 'wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww';
const credentialId = 'cccccccccccccccccccccccccccccccc';
const leaseId = 'llllllllllllllllllllllllllllllll';

void main() {
  final now = DateTime.utc(2026, 8, 15, 17, 30);

  test('desktop agent executes assignment once and returns durable result', () async {
    final sent = <Map<String, dynamic>>[];
    final assignment = _assignment(now);
    var mailboxPolls = 0;
    final client = MockClient((request) async {
      if (request.url.path == '/api/wesi/ai/workers/heartbeat') {
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/api/wesi/ai/workers/mailbox/poll') {
        mailboxPolls++;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'messages': mailboxPolls == 1
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
    final receipts = WesiRemoteWorkerReceiptStore(
      journal: WesiMemoryRemoteWorkerReceiptJournal(),
    );
    final handler = _CountingHandler();
    final agent = _agent(client, receipts, handler);

    await agent.tick(now: now);
    await agent.drain();

    expect(handler.calls, 1);
    expect(sent.map((item) => item['kind']), containsAll(<String>[
      'ack',
      'progress',
      'result',
    ]));
    final result = sent.lastWhere((item) => item['kind'] == 'result');
    expect(result['payload']['success'], isTrue);
    expect(result['payload']['code'], 'OK');
    final receipt = receipts.get(assignment.messageId)!;
    expect(receipt.state, WesiRemoteWorkerReceiptState.completed);
    expect(receipt.resultMessage, isNotNull);
  });

  test('started receipt after restart blocks automatic duplicate execution', () async {
    final assignment = _assignment(now);
    final journal = WesiMemoryRemoteWorkerReceiptJournal();
    final seed = WesiRemoteWorkerReceiptStore(journal: journal);
    await seed.restore();
    await seed.markStarted(
      assignmentMessageId: assignment.messageId,
      jobId: assignment.jobId,
      leaseId: leaseId,
      generation: 1,
      now: now.subtract(const Duration(seconds: 5)),
    );

    final sent = <Map<String, dynamic>>[];
    final client = MockClient((request) async {
      if (request.url.path == '/api/wesi/ai/workers/heartbeat') {
        return http.Response('{"ok":true}', 200);
      }
      if (request.url.path == '/api/wesi/ai/workers/mailbox/poll') {
        return http.Response(
          jsonEncode(<String, dynamic>{
            'ok': true,
            'messages': <Map<String, dynamic>>[assignment.toJson()],
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
    final restored = WesiRemoteWorkerReceiptStore(journal: journal);
    final handler = _CountingHandler();
    final agent = _agent(client, restored, handler);

    await agent.tick(now: now);
    await agent.drain();

    expect(handler.calls, 0);
    final result = sent.lastWhere((item) => item['kind'] == 'result');
    expect(result['payload']['success'], isFalse);
    expect(result['payload']['code'], 'WRW_EXECUTION_RECOVERY_REQUIRED');
    expect(
      restored.get(assignment.messageId)!.state,
      WesiRemoteWorkerReceiptState.completed,
    );
  });
}

WesiRemoteWorkerAgent _agent(
  http.Client client,
  WesiRemoteWorkerReceiptStore receipts,
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
      credentialId: credentialId,
      workerId: workerId,
      secret: 'worker-secret-' * 4,
      issuedAt: DateTime.utc(2026, 8, 15),
      expiresAt: DateTime.utc(2026, 8, 16),
    ),
    receipts: receipts,
    executionHandler: handler,
    profileProvider: (busy) async => WesiWorkerResourceProfile(
      id: workerId,
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
      'leaseId': leaseId,
      'generation': 1,
      'execution': execution.toJson(),
    },
  );
}

class _CountingHandler implements WesiRemoteWorkerExecutionHandler {
  int calls = 0;

  @override
  Future<WesiRemoteWorkerExecutionOutcome> execute(
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control,
  ) async {
    calls++;
    return const WesiRemoteWorkerExecutionOutcome(
      disposition: WesiRemoteWorkerExecutionDisposition.succeeded,
      code: 'OK',
      message: 'Build complete',
      stdout: 'done',
    );
  }
}
