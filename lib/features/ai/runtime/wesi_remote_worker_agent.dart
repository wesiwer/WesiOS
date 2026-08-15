import 'dart:async';
import 'dart:convert';

import 'wesi_local_runtime_executor.dart';
import 'wesi_local_runtime_models.dart';
import 'wesi_remote_worker_execution_store.dart';
import 'wesi_remote_worker_http_transport.dart';
import 'wesi_remote_worker_models.dart';
import 'wesi_remote_worker_receipt_store.dart';

class WesiRemoteWorkerExecutionControl {
  bool cancelRequested = false;
  bool pauseRequested = false;
  String? cancelMessageId;
  String? pauseMessageId;
}

enum WesiRemoteWorkerExecutionDisposition {
  succeeded,
  failed,
  cancelled,
  paused,
}

class WesiRemoteWorkerExecutionOutcome {
  final WesiRemoteWorkerExecutionDisposition disposition;
  final String code;
  final String message;
  final String? stdout;
  final String? stderr;
  final Map<String, dynamic> data;
  final String? checkpointId;
  final int checkpointVersion;
  final String? checkpointStage;
  final double? checkpointProgress;

  const WesiRemoteWorkerExecutionOutcome({
    required this.disposition,
    required this.code,
    required this.message,
    this.stdout,
    this.stderr,
    this.data = const <String, dynamic>{},
    this.checkpointId,
    this.checkpointVersion = 1,
    this.checkpointStage,
    this.checkpointProgress,
  });

  factory WesiRemoteWorkerExecutionOutcome.fromLocalResult(
    WesiLocalToolResult result,
  ) =>
      WesiRemoteWorkerExecutionOutcome(
        disposition: result.ok
            ? WesiRemoteWorkerExecutionDisposition.succeeded
            : WesiRemoteWorkerExecutionDisposition.failed,
        code: result.code,
        message: result.message,
        stdout: result.stdout,
        stderr: result.stderr,
        data: result.data,
      );

  void validate() {
    if (code.isEmpty || code.length > 128 || message.length > 1024) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_EXECUTION_OUTCOME',
        'Remote worker execution outcome is invalid',
      );
    }
    if (disposition == WesiRemoteWorkerExecutionDisposition.paused) {
      final progress = checkpointProgress;
      if (checkpointId == null ||
          checkpointStage == null ||
          checkpointVersion < 1 ||
          progress == null ||
          progress < 0 ||
          progress > 1) {
        throw const WesiRemoteWorkerProtocolException(
          'WRW_BAD_EXECUTION_OUTCOME',
          'Paused remote execution must include a durable checkpoint',
        );
      }
    }
  }
}

abstract class WesiRemoteWorkerExecutionHandler {
  Future<WesiRemoteWorkerExecutionOutcome> execute(
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control,
  );
}

typedef WesiRemoteWorkspaceResolver = Future<WesiLocalRuntimeContext> Function(
  String workspaceId,
);

/// Stage-6 Local Runtime adapter for normal Remote Worker assignments. The
/// process executor itself is not forcibly killed by this adapter; cooperative
/// multi-stage handlers may implement stronger pause/cancel semantics through
/// [WesiRemoteWorkerExecutionHandler].
class WesiLocalRuntimeRemoteExecutionHandler
    implements WesiRemoteWorkerExecutionHandler {
  final WesiLocalRuntimeExecutor executor;
  final WesiRemoteWorkspaceResolver workspaceResolver;

  const WesiLocalRuntimeRemoteExecutionHandler({
    required this.workspaceResolver,
    this.executor = const WesiLocalRuntimeExecutor(),
  });

  @override
  Future<WesiRemoteWorkerExecutionOutcome> execute(
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control,
  ) async {
    var context = await workspaceResolver(request.workspaceId);
    if (request.destructiveConfirmed && !context.destructiveConfirmed) {
      context = context.copyWith(destructiveConfirmed: true);
    }
    final result = await executor.execute(request.call, context);
    if (control.cancelRequested) {
      return const WesiRemoteWorkerExecutionOutcome(
        disposition: WesiRemoteWorkerExecutionDisposition.cancelled,
        code: 'WRW_CANCELLED_AFTER_SAFE_BOUNDARY',
        message: 'Remote execution reached a safe boundary after cancellation',
      );
    }
    if (control.pauseRequested) {
      return const WesiRemoteWorkerExecutionOutcome(
        disposition: WesiRemoteWorkerExecutionDisposition.failed,
        code: 'WRW_PAUSE_NOT_CHECKPOINTED',
        message:
            'This single local tool call could not produce a durable pause checkpoint',
      );
    }
    return WesiRemoteWorkerExecutionOutcome.fromLocalResult(result);
  }
}

typedef WesiRemoteWorkerProfileProvider =
    Future<WesiWorkerResourceProfile> Function(bool busy);

/// Desktop-side worker loop. Each assignment is receipt-journaled before any
/// tool call starts, providing at-most-once automatic execution across process
/// restarts. The small VPS only relays messages; all actual work is delegated to
/// [executionHandler] on this desktop.
class WesiRemoteWorkerAgent {
  final WesiRemoteWorkerHttpTransport transport;
  final WesiWorkerCredential credential;
  final WesiRemoteWorkerReceiptStore receipts;
  final WesiRemoteWorkerExecutionHandler executionHandler;
  final WesiRemoteWorkerProfileProvider profileProvider;
  final Map<String, _ActiveExecution> _active = <String, _ActiveExecution>{};
  bool _restored = false;

  WesiRemoteWorkerAgent({
    required this.transport,
    required this.credential,
    required this.receipts,
    required this.executionHandler,
    required this.profileProvider,
  });

  bool get busy => _active.isNotEmpty;

  Future<void> restore() async {
    if (_restored) return;
    await receipts.restore();
    _restored = true;
  }

  Future<void> tick({DateTime? now}) async {
    await restore();
    final current = (now ?? DateTime.now()).toUtc();
    final profile = await profileProvider(busy);
    if (profile.id != credential.workerId || !profile.remoteWorker) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_WORKER_IDENTITY_MISMATCH',
        'Desktop worker profile does not match its device credential',
      );
    }
    await transport.sendHeartbeat(
      credential,
      WesiRemoteWorkerHeartbeat(profile: profile, sentAt: current),
      now: current,
    );
    final messages = await transport.pollWorkerMailbox(
      credential,
      limit: 16,
      now: current,
    );
    for (final message in messages) {
      await _handle(message, now: current);
    }
  }

  Future<void> drain() async {
    while (_active.isNotEmpty) {
      final pending = _active.values.map((item) => item.future).toList();
      await Future.wait(pending);
    }
  }

  Future<void> _handle(
    WesiRemoteJobMessage message, {
    required DateTime now,
  }) async {
    switch (message.kind) {
      case WesiRemoteJobMessageKind.assignment:
        await _handleAssignment(message, now: now);
      case WesiRemoteJobMessageKind.cancel:
        await _requestCancel(message);
      case WesiRemoteJobMessageKind.pause:
        await _requestPause(message);
      case WesiRemoteJobMessageKind.resume:
        await _ackControl(message, sequence: 7, now: now);
      case WesiRemoteJobMessageKind.progress:
      case WesiRemoteJobMessageKind.checkpoint:
      case WesiRemoteJobMessageKind.result:
      case WesiRemoteJobMessageKind.ack:
        throw const WesiRemoteWorkerProtocolException(
          'WRW_BAD_WORKER_MAILBOX_KIND',
          'Worker mailbox contains a worker-to-Control-Plane message kind',
        );
    }
  }

  Future<void> _handleAssignment(
    WesiRemoteJobMessage assignment, {
    required DateTime now,
  }) async {
    final leaseId = '${assignment.payload['leaseId'] ?? ''}'.trim();
    final generationRaw = assignment.payload['generation'];
    final rawExecution = assignment.payload['execution'];
    if (!RegExp(r'^[A-Za-z0-9_-]{20,96}$').hasMatch(leaseId) ||
        generationRaw is! num ||
        generationRaw.toInt().toDouble() != generationRaw.toDouble() ||
        generationRaw.toInt() < 1 ||
        rawExecution is! Map) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_ASSIGNMENT',
        'Remote worker assignment is missing lease/execution metadata',
      );
    }
    final generation = generationRaw.toInt();
    final request = WesiRemoteExecutionRequest.fromJson(
      rawExecution.map((key, value) => MapEntry('$key', value)),
    );
    final existing = receipts.get(assignment.messageId);
    if (existing != null) {
      if (existing.jobId != assignment.jobId ||
          existing.leaseId != leaseId ||
          existing.generation != generation) {
        throw const WesiRemoteWorkerProtocolException(
          'WRW_RECEIPT_ID_COLLISION',
          'Remote assignment conflicts with its durable receipt',
        );
      }
      await _sendAssignmentAck(assignment, generation, leaseId, now: now);
      if (existing.state == WesiRemoteWorkerReceiptState.completed &&
          existing.resultMessage != null) {
        await transport.sendWorkerMessage(
          credential,
          existing.resultMessage!,
          now: now,
        );
        return;
      }
      if (_active.containsKey(assignment.jobId)) return;

      // A previous process persisted `started` but not a result. It is unknown
      // whether a write/destructive side effect happened, so automatic retry is
      // forbidden. Report fail-closed recovery instead.
      final recovery = _resultMessage(
        assignment,
        leaseId: leaseId,
        generation: generation,
        sequence: 3,
        now: now,
        outcome: const WesiRemoteWorkerExecutionOutcome(
          disposition: WesiRemoteWorkerExecutionDisposition.failed,
          code: 'WRW_EXECUTION_RECOVERY_REQUIRED',
          message:
              'Worker restarted during execution; assignment was not repeated automatically',
        ),
      );
      await receipts.markCompleted(assignment.messageId, recovery);
      await transport.sendWorkerMessage(credential, recovery, now: now);
      return;
    }

    await receipts.markStarted(
      assignmentMessageId: assignment.messageId,
      jobId: assignment.jobId,
      leaseId: leaseId,
      generation: generation,
      now: now,
    );
    await _sendAssignmentAck(assignment, generation, leaseId, now: now);
    await transport.sendWorkerMessage(
      credential,
      WesiRemoteJobMessage(
        messageId: '${assignment.messageId}:progress',
        jobId: assignment.jobId,
        kind: WesiRemoteJobMessageKind.progress,
        sequence: 2,
        createdAt: now,
        payload: <String, dynamic>{
          'leaseId': leaseId,
          'generation': generation,
          'progress': 0.01,
          'stage': 'remote_execution',
        },
      ),
      now: now,
    );

    final control = WesiRemoteWorkerExecutionControl();
    late final Future<void> future;
    future = _execute(
      assignment,
      request,
      control,
      leaseId: leaseId,
      generation: generation,
    ).whenComplete(() {
      _active.remove(assignment.jobId);
    });
    _active[assignment.jobId] = _ActiveExecution(control: control, future: future);
    unawaited(future);
  }

  Future<void> _execute(
    WesiRemoteJobMessage assignment,
    WesiRemoteExecutionRequest request,
    WesiRemoteWorkerExecutionControl control, {
    required String leaseId,
    required int generation,
  }) async {
    WesiRemoteWorkerExecutionOutcome outcome;
    try {
      outcome = await executionHandler.execute(request, control);
      outcome.validate();
    } catch (_) {
      outcome = const WesiRemoteWorkerExecutionOutcome(
        disposition: WesiRemoteWorkerExecutionDisposition.failed,
        code: 'WRW_WORKER_EXECUTION_FAILED',
        message: 'Remote worker safely stopped after an execution error',
      );
    }
    final completedAt = DateTime.now().toUtc();

    if (control.cancelRequested ||
        outcome.disposition == WesiRemoteWorkerExecutionDisposition.cancelled) {
      final result = _resultMessage(
        assignment,
        leaseId: leaseId,
        generation: generation,
        sequence: 4,
        now: completedAt,
        outcome: const WesiRemoteWorkerExecutionOutcome(
          disposition: WesiRemoteWorkerExecutionDisposition.cancelled,
          code: 'WRW_CANCELLED',
          message: 'Remote worker stopped at a cancellation boundary',
        ),
      );
      await receipts.markCompleted(assignment.messageId, result);
      final cancelId = control.cancelMessageId;
      if (cancelId != null) {
        await _sendAck(
          jobId: assignment.jobId,
          leaseId: leaseId,
          generation: generation,
          ackedMessageId: cancelId,
          sequence: 3,
          now: completedAt,
        );
      } else {
        await transport.sendWorkerMessage(credential, result, now: completedAt);
      }
      return;
    }

    if (outcome.disposition == WesiRemoteWorkerExecutionDisposition.paused) {
      await transport.sendWorkerMessage(
        credential,
        WesiRemoteJobMessage(
          messageId: '${assignment.messageId}:checkpoint',
          jobId: assignment.jobId,
          kind: WesiRemoteJobMessageKind.checkpoint,
          sequence: 3,
          createdAt: completedAt,
          payload: <String, dynamic>{
            'leaseId': leaseId,
            'generation': generation,
            'checkpointId': outcome.checkpointId,
            'version': outcome.checkpointVersion,
            'stage': outcome.checkpointStage,
            'progress': outcome.checkpointProgress,
          },
        ),
        now: completedAt,
      );
      return;
    }

    if (control.pauseRequested) {
      // No durable checkpoint means we must not pretend the job was paused.
      // The Control Plane lease will expire and the orchestrator will resolve
      // this fail-closed instead of silently replaying the tool call.
      return;
    }

    final result = _resultMessage(
      assignment,
      leaseId: leaseId,
      generation: generation,
      sequence: 3,
      now: completedAt,
      outcome: outcome,
    );
    await receipts.markCompleted(assignment.messageId, result);
    await transport.sendWorkerMessage(credential, result, now: completedAt);
  }

  Future<void> _requestCancel(WesiRemoteJobMessage message) async {
    final active = _active[message.jobId];
    if (active == null) {
      await _ackControl(message, sequence: 4, now: DateTime.now().toUtc());
      return;
    }
    active.control.cancelRequested = true;
    active.control.cancelMessageId = message.messageId;
  }

  Future<void> _requestPause(WesiRemoteJobMessage message) async {
    final active = _active[message.jobId];
    if (active == null) return;
    active.control.pauseRequested = true;
    active.control.pauseMessageId = message.messageId;
  }

  Future<void> _sendAssignmentAck(
    WesiRemoteJobMessage assignment,
    int generation,
    String leaseId, {
    required DateTime now,
  }) =>
      _sendAck(
        jobId: assignment.jobId,
        leaseId: leaseId,
        generation: generation,
        ackedMessageId: assignment.messageId,
        sequence: 1,
        now: now,
      );

  Future<void> _ackControl(
    WesiRemoteJobMessage message, {
    required int sequence,
    required DateTime now,
  }) async {
    final leaseId = '${message.payload['leaseId'] ?? ''}';
    final generation = message.payload['generation'];
    if (generation is! num || generation.toInt().toDouble() != generation.toDouble()) {
      throw const WesiRemoteWorkerProtocolException(
        'WRW_BAD_CONTROL_MESSAGE',
        'Remote worker control message is invalid',
      );
    }
    await _sendAck(
      jobId: message.jobId,
      leaseId: leaseId,
      generation: generation.toInt(),
      ackedMessageId: message.messageId,
      sequence: sequence,
      now: now,
    );
  }

  Future<void> _sendAck({
    required String jobId,
    required String leaseId,
    required int generation,
    required String ackedMessageId,
    required int sequence,
    required DateTime now,
  }) =>
      transport.sendWorkerMessage(
        credential,
        WesiRemoteJobMessage(
          messageId: '$ackedMessageId:ack',
          jobId: jobId,
          kind: WesiRemoteJobMessageKind.ack,
          sequence: sequence,
          createdAt: now,
          payload: <String, dynamic>{
            'leaseId': leaseId,
            'generation': generation,
            'ackedMessageId': ackedMessageId,
          },
        ),
        now: now,
      );

  WesiRemoteJobMessage _resultMessage(
    WesiRemoteJobMessage assignment, {
    required String leaseId,
    required int generation,
    required int sequence,
    required DateTime now,
    required WesiRemoteWorkerExecutionOutcome outcome,
  }) {
    final successful =
        outcome.disposition == WesiRemoteWorkerExecutionDisposition.succeeded;
    final data = _boundedData(outcome.data);
    return WesiRemoteJobMessage(
      messageId: '${assignment.messageId}:result',
      jobId: assignment.jobId,
      kind: WesiRemoteJobMessageKind.result,
      sequence: sequence,
      createdAt: now,
      payload: <String, dynamic>{
        'leaseId': leaseId,
        'generation': generation,
        'success': successful,
        'code': outcome.code,
        'message': _truncate(outcome.message, 1024),
        if (outcome.stdout != null) 'stdout': _truncate(outcome.stdout!, 32768),
        if (outcome.stderr != null) 'stderr': _truncate(outcome.stderr!, 32768),
        if (data.isNotEmpty) 'data': data,
      },
    );
  }

  static Map<String, dynamic> _boundedData(Map<String, dynamic> input) {
    if (input.isEmpty) return const <String, dynamic>{};
    try {
      final raw = jsonEncode(input);
      if (utf8.encode(raw).length <= 32768) return input;
    } catch (_) {}
    return const <String, dynamic>{};
  }

  static String _truncate(String value, int maxLength) =>
      value.length <= maxLength ? value : value.substring(0, maxLength);
}

class _ActiveExecution {
  final WesiRemoteWorkerExecutionControl control;
  final Future<void> future;

  const _ActiveExecution({required this.control, required this.future});
}
