import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wesios/features/ai/runtime/wesi_artifact_delivery.dart';
import 'package:wesios/features/ai/runtime/wesi_artifact_models.dart';
import 'package:wesios/features/ai/runtime/wesi_artifact_validator.dart';
import 'package:wesios/features/ai/runtime/wesi_job_coordinator.dart';
import 'package:wesios/features/ai/runtime/wesi_job_queue.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_executor.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler.dart';
import 'package:wesios/features/ai/runtime/wesi_resource_scheduler_models.dart';
import 'package:wesios/features/ai/runtime/wesi_self_debug_checkpoint.dart';
import 'package:wesios/features/ai/runtime/wesi_self_debug_engine.dart';
import 'package:wesios/features/ai/runtime/wesi_self_debug_job_control.dart';

void main() {
  group('Stage 9 durable self-debug', () {
    test('restart skips completed WRITE and safely retries interrupted READ',
        () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-restart-');
      addTearDown(() => root.delete(recursive: true));
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final plan = WesiSelfDebugPlan(
        executionSteps: <WesiDebugStep>[
          _step('write', WesiLocalToolNames.fsWriteText),
        ],
        verificationSteps: <WesiDebugStep>[
          _step('read-check', WesiLocalToolNames.fsReadText),
        ],
      );
      final firstExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.success(message: 'write complete'),
        () async => throw StateError('simulated process crash'),
      ]);
      final first = WesiSelfDebugEngine(
        executor: firstExecutor,
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );

      await expectLater(
        first.run(
          request:
              const WesiSelfDebugRequest(id: 'restart-job', goal: 'resume'),
          runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
        ),
        throwsA(isA<StateError>()),
      );
      expect(firstExecutor.tools, <String>[
        WesiLocalToolNames.fsWriteText,
        WesiLocalToolNames.fsReadText,
      ]);

      final secondExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.success(message: 'read verified'),
      ]);
      final second = WesiSelfDebugEngine(
        executor: secondExecutor,
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      final result = await second.run(
        request: const WesiSelfDebugRequest(id: 'restart-job', goal: 'resume'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );

      expect(result.ok, isTrue);
      expect(secondExecutor.tools, <String>[WesiLocalToolNames.fsReadText]);
      expect(journal.value, isNull);
    });

    test('restart resumes interrupted READ inside the same repair iteration',
        () async {
      final root =
          await Directory.systemTemp.createTemp('wesi-sd-repair-read-');
      addTearDown(() => root.delete(recursive: true));
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final plan = WesiSelfDebugPlan(
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.fsReadText),
        ],
      );
      final firstPlanner = _RepairPlanner(
        plan: plan,
        repair: WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('diagnostic-read', WesiLocalToolNames.fsReadText),
            _step('repair-write', WesiLocalToolNames.fsWriteText),
          ],
        ),
      );
      final firstExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async =>
            WesiLocalToolResult.failure('VERIFY_FAILED', 'needs repair'),
        () async => throw StateError('crash during repair read'),
      ]);
      final first = WesiSelfDebugEngine(
        executor: firstExecutor,
        planner: firstPlanner,
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      await expectLater(
        first.run(
          request: const WesiSelfDebugRequest(
            id: 'repair-read-job',
            goal: 'resume repair',
          ),
          runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
        ),
        throwsA(isA<StateError>()),
      );

      final secondExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.success(message: 'diagnostic read'),
        () async => WesiLocalToolResult.success(message: 'repair write'),
        () async => WesiLocalToolResult.success(message: 'verification passed'),
      ]);
      final secondPlanner = _RepairPlanner(
        plan: plan,
        repair: WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('diagnostic-read', WesiLocalToolNames.fsReadText),
            _step('repair-write', WesiLocalToolNames.fsWriteText),
          ],
        ),
      );
      final second = WesiSelfDebugEngine(
        executor: secondExecutor,
        planner: secondPlanner,
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      final result = await second.run(
        request: const WesiSelfDebugRequest(
          id: 'repair-read-job',
          goal: 'resume repair',
        ),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.ok, isTrue);
      expect(secondPlanner.repairCalls, 1);
      expect(secondExecutor.tools, <String>[
        WesiLocalToolNames.fsReadText,
        WesiLocalToolNames.fsWriteText,
        WesiLocalToolNames.fsReadText,
      ]);
    });

    test('restart never repeats an uncertain in-flight WRITE', () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-uncertain-');
      addTearDown(() => root.delete(recursive: true));
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final plan = WesiSelfDebugPlan(
        executionSteps: <WesiDebugStep>[
          _step('write', WesiLocalToolNames.fsWriteText),
        ],
        verificationSteps: <WesiDebugStep>[
          _step('read-check', WesiLocalToolNames.fsReadText),
        ],
      );
      final first = WesiSelfDebugEngine(
        executor: _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
          () async => throw StateError('crash during write'),
        ]),
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      await expectLater(
        first.run(
          request:
              const WesiSelfDebugRequest(id: 'uncertain-job', goal: 'write'),
          runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
        ),
        throwsA(isA<StateError>()),
      );

      final retryExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[]);
      final retry = WesiSelfDebugEngine(
        executor: retryExecutor,
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      final result = await retry.run(
        request: const WesiSelfDebugRequest(id: 'uncertain-job', goal: 'write'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.ok, isFalse);
      expect(result.blocked, isTrue);
      expect(result.code, 'WSD_UNCERTAIN_SIDE_EFFECT');
      expect(retryExecutor.tools, isEmpty);
    });

    test('Stage-8 cancellation stops all future self-debug steps', () async {
      final fixture =
          await _jobFixture(WesiLocalToolNames.flutterTest, 'cancel-job');
      addTearDown(fixture.dispose);
      await fixture.coordinator.requestCancel('cancel-job');
      final executor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[]);
      final manager = WesiSelfDebugCheckpointManager(
        journal: WesiMemorySelfDebugCheckpointJournal(),
      );
      final engine = WesiSelfDebugEngine(
        executor: executor,
        planner: _Planner(_verificationOnlyPlan()),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: manager,
        executionControl: WesiSelfDebugJobControl(
          coordinator: fixture.coordinator,
          jobId: 'cancel-job',
        ),
      );
      final result = await engine.run(
        request: const WesiSelfDebugRequest(id: 'cancel-job', goal: 'cancel'),
        runtimeContext:
            WesiLocalRuntimeContext(workspaceRoot: fixture.root.path),
      );
      expect(result.code, 'WSD_CANCELLED');
      expect(executor.tools, isEmpty);
      expect(fixture.queue.get('cancel-job')!.state,
          WesiScheduledJobState.cancelled);
    });

    test('pause checkpoints Stage 9 and resumes without losing the plan',
        () async {
      final fixture =
          await _jobFixture(WesiLocalToolNames.flutterTest, 'pause-job');
      addTearDown(fixture.dispose);
      await fixture.coordinator.requestPause('pause-job');
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final manager = WesiSelfDebugCheckpointManager(journal: journal);
      final control = WesiSelfDebugJobControl(
        coordinator: fixture.coordinator,
        jobId: 'pause-job',
      );
      final plan = WesiSelfDebugPlan(
        executionSteps: <WesiDebugStep>[
          _step('write', WesiLocalToolNames.fsWriteText),
        ],
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.fsReadText),
        ],
      );
      final pausedExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[]);
      final paused = WesiSelfDebugEngine(
        executor: pausedExecutor,
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: manager,
        executionControl: control,
      );
      final pausedResult = await paused.run(
        request: const WesiSelfDebugRequest(id: 'pause-job', goal: 'pause'),
        runtimeContext:
            WesiLocalRuntimeContext(workspaceRoot: fixture.root.path),
      );
      expect(pausedResult.code, 'WSD_PAUSED');
      expect(pausedExecutor.tools, isEmpty);
      expect(
          fixture.queue.get('pause-job')!.state, WesiScheduledJobState.paused);
      expect(fixture.queue.get('pause-job')!.checkpoint, isNotNull);
      expect(journal.value, isNotNull);

      await fixture.coordinator.resume('pause-job');
      await fixture.queue.markRunning('pause-job', workerId: 'desktop-2');
      final resumedExecutor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
        () async => WesiLocalToolResult.success(message: 'write'),
        () async => WesiLocalToolResult.success(message: 'verified'),
      ]);
      final resumed = WesiSelfDebugEngine(
        executor: resumedExecutor,
        planner: _Planner(plan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
        executionControl: control,
      );
      final result = await resumed.run(
        request: const WesiSelfDebugRequest(id: 'pause-job', goal: 'pause'),
        runtimeContext:
            WesiLocalRuntimeContext(workspaceRoot: fixture.root.path),
      );
      expect(result.ok, isTrue);
      expect(resumedExecutor.tools, <String>[
        WesiLocalToolNames.fsWriteText,
        WesiLocalToolNames.fsReadText,
      ]);
    });

    test('L4 worker loss checkpoints and becomes waitingForWorker', () async {
      final fixture =
          await _jobFixture(WesiLocalToolNames.flutterBuild, 'worker-job');
      addTearDown(fixture.dispose);
      final manager = WesiSelfDebugCheckpointManager(
        journal: WesiMemorySelfDebugCheckpointJournal(),
      );
      final control = WesiSelfDebugJobControl(
        coordinator: fixture.coordinator,
        jobId: 'worker-job',
      );
      final executor = _CallbackExecutor((call, context) async {
        await control.waitForWorker(manager, reason: 'desktop disappeared');
        return WesiLocalToolResult.success(
            message: 'step completed before disconnect');
      });
      final engine = WesiSelfDebugEngine(
        executor: executor,
        planner: _Planner(WesiSelfDebugPlan(
          executionSteps: <WesiDebugStep>[
            _step('work', WesiLocalToolNames.fsWriteText),
          ],
          verificationSteps: <WesiDebugStep>[
            _step('verify', WesiLocalToolNames.fsReadText),
          ],
        )),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: manager,
        executionControl: control,
      );
      final result = await engine.run(
        request: const WesiSelfDebugRequest(id: 'worker-job', goal: 'build'),
        runtimeContext:
            WesiLocalRuntimeContext(workspaceRoot: fixture.root.path),
      );
      expect(result.code, 'WSD_WAITING_FOR_WORKER');
      final job = fixture.queue.get('worker-job')!;
      expect(job.state, WesiScheduledJobState.waitingForWorker);
      expect(job.checkpoint, isNotNull);
    });

    test('changed plan after restart is rejected before another tool call',
        () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-plan-');
      addTearDown(() => root.delete(recursive: true));
      final journal = WesiMemorySelfDebugCheckpointJournal();
      final firstPlan = WesiSelfDebugPlan(
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.fsReadText),
        ],
      );
      final first = WesiSelfDebugEngine(
        executor: _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
          () async => throw StateError('crash'),
        ]),
        planner: _Planner(firstPlan),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      await expectLater(
        first.run(
          request: const WesiSelfDebugRequest(id: 'plan-job', goal: 'plan'),
          runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
        ),
        throwsA(isA<StateError>()),
      );
      final executor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[]);
      final changed = WesiSelfDebugEngine(
        executor: executor,
        planner: _Planner(WesiSelfDebugPlan(
          verificationSteps: <WesiDebugStep>[
            _step('verify-changed', WesiLocalToolNames.fsReadText),
          ],
        )),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
        checkpoint: WesiSelfDebugCheckpointManager(journal: journal),
      );
      final result = await changed.run(
        request: const WesiSelfDebugRequest(id: 'plan-job', goal: 'plan'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.code, 'WSD_PLAN_CHANGED_AFTER_RESTART');
      expect(executor.tools, isEmpty);
    });
  });

  group('Stage 9 proof/redaction/artifact hardening', () {
    test('failure evidence redacts credentials before planner/audit exposure',
        () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-redact-');
      addTearDown(() => root.delete(recursive: true));
      final secret = 'ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890';
      final api = 'sk-ABCDEFGHIJKLMNOPQRSTUV123456';
      final engine = WesiSelfDebugEngine(
        executor: _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
          () async => WesiLocalToolResult.failure(
                'FAILED',
                'token=super-secret',
                stderr: 'Authorization: Bearer bearer-secret $secret $api',
              ),
        ]),
        planner: _Planner(_verificationOnlyPlan()),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
      );
      final result = await engine.run(
        request: const WesiSelfDebugRequest(id: 'redact-job', goal: 'redact'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      final evidence = result.evidence.map((item) => item.summary).join('\n');
      expect(evidence, isNot(contains('super-secret')));
      expect(evidence, isNot(contains('bearer-secret')));
      expect(evidence, isNot(contains(secret)));
      expect(evidence, isNot(contains(api)));
      expect(evidence, contains('REDACTED'));
    });

    test('APK cannot be planned without successful flutterBuild proof',
        () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-proof-');
      addTearDown(() => root.delete(recursive: true));
      final executor =
          _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[]);
      final engine = WesiSelfDebugEngine(
        executor: executor,
        planner: _Planner(WesiSelfDebugPlan(
          verificationSteps: <WesiDebugStep>[
            _step('verify', WesiLocalToolNames.flutterTest),
          ],
          artifacts: const <WesiArtifactDescriptor>[
            WesiArtifactDescriptor(
              id: 'apk',
              relativePath: 'build/app.apk',
              kind: WesiArtifactKind.apk,
            ),
          ],
        )),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: _Sink(),
      );
      final result = await engine.run(
        request: const WesiSelfDebugRequest(id: 'proof-job', goal: 'apk'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.code, 'WSD_BUILD_PROOF_REQUIRED');
      expect(executor.tools, isEmpty);
    });

    test('failed build proof never reaches artifact delivery', () async {
      final root = await Directory.systemTemp.createTemp('wesi-sd-buildfail-');
      addTearDown(() => root.delete(recursive: true));
      final sink = _Sink();
      final engine = WesiSelfDebugEngine(
        executor: _SequenceExecutor(<Future<WesiLocalToolResult> Function()>[
          () async =>
              WesiLocalToolResult.failure('BUILD_FAILED', 'build failed'),
        ]),
        planner: _Planner(WesiSelfDebugPlan(
          verificationSteps: <WesiDebugStep>[
            _step('build-proof', WesiLocalToolNames.flutterBuild),
          ],
          artifacts: const <WesiArtifactDescriptor>[
            WesiArtifactDescriptor(
              id: 'apk',
              relativePath: 'build/app.apk',
              kind: WesiArtifactKind.apk,
              requiredSuccessfulStepId: 'build-proof',
            ),
          ],
        )),
        artifactValidator: const WesiArtifactValidator(),
        deliverySink: sink,
      );
      final result = await engine.run(
        request: const WesiSelfDebugRequest(id: 'buildfail-job', goal: 'apk'),
        runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
      );
      expect(result.ok, isFalse);
      expect(sink.deliveries, 0);
    });

    test('artifact mutation during external validation is rejected', () async {
      final root =
          await Directory.systemTemp.createTemp('wesi-artifact-toctou-');
      addTearDown(() => root.delete(recursive: true));
      final file = File(p.join(root.path, 'output.bin'));
      await file.writeAsString('before');
      final validator = WesiArtifactValidator(
        externalValidators: <WesiArtifactKind, WesiArtifactExternalValidator>{
          WesiArtifactKind.other: _MutatingValidator(file),
        },
      );
      final result = await validator.validate(
        descriptor: const WesiArtifactDescriptor(
          id: 'output',
          relativePath: 'output.bin',
          kind: WesiArtifactKind.other,
        ),
        workspaceRoot: root.path,
      );
      expect(result.ok, isFalse);
      expect(result.code, 'ARTIFACT_CHANGED_DURING_VALIDATION');
    });

    test('local delivery is idempotent for the same validated hash', () async {
      final root =
          await Directory.systemTemp.createTemp('wesi-artifact-source-');
      final delivery =
          await Directory.systemTemp.createTemp('wesi-artifact-delivery-');
      addTearDown(() async {
        await root.delete(recursive: true);
        await delivery.delete(recursive: true);
      });
      await File(p.join(root.path, 'result.txt')).writeAsString('stable');
      final validation = await const WesiArtifactValidator().validate(
        descriptor: const WesiArtifactDescriptor(
          id: 'result',
          relativePath: 'result.txt',
          kind: WesiArtifactKind.text,
        ),
        workspaceRoot: root.path,
      );
      expect(validation.ok, isTrue);
      final sink = WesiLocalArtifactDeliverySink(delivery);
      final first = await sink.deliver(validation.artifact!);
      final second = await sink.deliver(validation.artifact!);
      expect(first.ok, isTrue);
      expect(second.ok, isTrue);
      expect(second.deliveryRef, first.deliveryRef);
    });
  });
}

WesiDebugStep _step(String id, String tool) => WesiDebugStep(
      id: id,
      label: id,
      call: WesiLocalToolCall(id: 'call-$id', tool: tool),
    );

WesiSelfDebugPlan _verificationOnlyPlan() => WesiSelfDebugPlan(
      verificationSteps: <WesiDebugStep>[
        _step('verify', WesiLocalToolNames.fsReadText),
      ],
    );

class _Planner implements WesiSelfDebugPlanner {
  final WesiSelfDebugPlan plan;

  const _Planner(this.plan);

  @override
  Future<WesiSelfDebugPlan> createPlan(WesiSelfDebugRequest request) async =>
      plan;

  @override
  Future<WesiRepairProposal> proposeRepair({
    required WesiSelfDebugRequest request,
    required WesiSelfDebugPlan plan,
    required int iteration,
    required List<WesiDebugEvidence> evidence,
  }) async =>
      const WesiRepairProposal.blocked('NO_REPAIR', 'No repair available');
}

class _RepairPlanner implements WesiSelfDebugPlanner {
  final WesiSelfDebugPlan plan;
  final WesiRepairProposal repair;
  int repairCalls = 0;

  _RepairPlanner({required this.plan, required this.repair});

  @override
  Future<WesiSelfDebugPlan> createPlan(WesiSelfDebugRequest request) async =>
      plan;

  @override
  Future<WesiRepairProposal> proposeRepair({
    required WesiSelfDebugRequest request,
    required WesiSelfDebugPlan plan,
    required int iteration,
    required List<WesiDebugEvidence> evidence,
  }) async {
    repairCalls++;
    return repair;
  }
}

class _SequenceExecutor extends WesiLocalRuntimeExecutor {
  final List<Future<WesiLocalToolResult> Function()> sequence;
  final List<String> tools = <String>[];
  int _index = 0;

  _SequenceExecutor(this.sequence);

  @override
  Future<WesiLocalToolResult> execute(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    tools.add(call.tool);
    if (_index >= sequence.length) throw StateError('Unexpected executor call');
    return sequence[_index++]();
  }
}

class _CallbackExecutor extends WesiLocalRuntimeExecutor {
  final Future<WesiLocalToolResult> Function(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) callback;

  _CallbackExecutor(this.callback);

  @override
  Future<WesiLocalToolResult> execute(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) =>
      callback(call, context);
}

class _Sink implements WesiArtifactDeliverySink {
  int deliveries = 0;

  @override
  Future<WesiArtifactDeliveryResult> deliver(
    WesiValidatedArtifact artifact,
  ) async {
    deliveries++;
    return WesiArtifactDeliveryResult.success(
      deliveryRef: 'test://${artifact.descriptor.id}',
    );
  }
}

class _MutatingValidator implements WesiArtifactExternalValidator {
  final File file;

  const _MutatingValidator(this.file);

  @override
  Future<WesiArtifactExternalValidation> validate({
    required WesiArtifactDescriptor descriptor,
    required String canonicalPath,
  }) async {
    await file.writeAsString('after');
    return const WesiArtifactExternalValidation.success();
  }
}

class _JobFixture {
  final Directory root;
  final WesiDurableJobQueue queue;
  final WesiJobCoordinator coordinator;

  const _JobFixture(this.root, this.queue, this.coordinator);

  Future<void> dispose() => root.delete(recursive: true);
}

Future<_JobFixture> _jobFixture(String workloadTool, String jobId) async {
  final root = await Directory.systemTemp.createTemp('wesi-stage9-job-');
  final queue = WesiDurableJobQueue(journal: WesiMemoryJobJournal());
  await queue.restore();
  final coordinator = WesiJobCoordinator(queue: queue);
  final requirements =
      WesiTrustedWorkloadRegistry.requirementsFor(workloadTool);
  await coordinator.enqueue(id: jobId, requirements: requirements);
  await queue.markRunning(jobId, workerId: 'desktop');
  return _JobFixture(root, queue, coordinator);
}
