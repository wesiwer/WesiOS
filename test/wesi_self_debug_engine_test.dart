import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wesios/features/ai/runtime/wesi_artifact_models.dart';
import 'package:wesios/features/ai/runtime/wesi_artifact_validator.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_executor.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_self_debug_engine.dart';

void main() {
  test('repairs failed verification, re-tests and only then delivers',
      () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'result.txt')).writeAsString('verified');

    final executor = _ScriptedExecutor(<WesiLocalToolResult>[
      WesiLocalToolResult.success(message: 'initial edit'),
      WesiLocalToolResult.failure(
        'TEST_FAILED',
        'tests failed',
        stderr: 'expected 2, got 1',
      ),
      WesiLocalToolResult.success(message: 'repair applied'),
      WesiLocalToolResult.success(message: 'tests passed'),
    ]);
    final planner = _Planner(
      plan: WesiSelfDebugPlan(
        executionSteps: <WesiDebugStep>[
          _step('edit', WesiLocalToolNames.fsWriteText),
        ],
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.flutterTest),
        ],
        artifacts: const <WesiArtifactDescriptor>[
          WesiArtifactDescriptor(
            id: 'result',
            relativePath: 'result.txt',
            kind: WesiArtifactKind.text,
          ),
        ],
      ),
      repairs: <WesiRepairProposal>[
        WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('repair-1', WesiLocalToolNames.fsWriteText),
          ],
        ),
      ],
    );
    final sink = _DeliverySink();
    final engine = WesiSelfDebugEngine(
      executor: executor,
      planner: planner,
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: sink,
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(id: 'job-1', goal: 'fix project'),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.ok, isTrue);
    expect(result.repairIterations, 1);
    expect(result.toolCalls, 4);
    expect(result.artifacts, hasLength(1));
    expect(sink.deliveries, 1);
    expect(executor.calls, 4);
  });

  test('repeated objective failure becomes blocker instead of infinite loop',
      () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));

    final executor = _ScriptedExecutor(<WesiLocalToolResult>[
      WesiLocalToolResult.failure('TEST_FAILED', 'same failure'),
      WesiLocalToolResult.success(message: 'repair applied'),
      WesiLocalToolResult.failure('TEST_FAILED', 'same failure'),
    ]);
    final planner = _Planner(
      plan: WesiSelfDebugPlan(
        verificationSteps: <WesiDebugStep>[
          _step('verify', WesiLocalToolNames.flutterTest),
        ],
      ),
      repairs: <WesiRepairProposal>[
        WesiRepairProposal(
          repairSteps: <WesiDebugStep>[
            _step('repair-1', WesiLocalToolNames.fsWriteText),
          ],
        ),
      ],
    );
    final engine = WesiSelfDebugEngine(
      executor: executor,
      planner: planner,
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: _DeliverySink(),
      limits: const WesiSelfDebugLimits(maxRepeatedFailureFingerprint: 1),
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(id: 'job-2', goal: 'fix tests'),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.ok, isFalse);
    expect(result.blocked, isTrue);
    expect(result.code, 'WSD_REPEATED_FAILURE');
    expect(result.toolCalls, 3);
  });

  test('does not report success when artifact delivery fails', () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));
    await File(p.join(root.path, 'result.txt')).writeAsString('verified');

    final engine = WesiSelfDebugEngine(
      executor: _ScriptedExecutor(<WesiLocalToolResult>[
        WesiLocalToolResult.success(message: 'tests passed'),
      ]),
      planner: _Planner(
        plan: WesiSelfDebugPlan(
          verificationSteps: <WesiDebugStep>[
            _step('verify', WesiLocalToolNames.flutterTest),
          ],
          artifacts: const <WesiArtifactDescriptor>[
            WesiArtifactDescriptor(
              id: 'result',
              relativePath: 'result.txt',
              kind: WesiArtifactKind.text,
            ),
          ],
        ),
      ),
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: _DeliverySink(fail: true),
      limits: const WesiSelfDebugLimits(maxDeliveryAttempts: 1),
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(id: 'job-3', goal: 'deliver result'),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.ok, isFalse);
    expect(result.blocked, isTrue);
    expect(result.code, 'DELIVERY_DOWN');
  });

  test('requires objective verification before executing a plan', () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));
    final executor = _ScriptedExecutor(<WesiLocalToolResult>[]);
    final engine = WesiSelfDebugEngine(
      executor: executor,
      planner: _Planner(
        plan: WesiSelfDebugPlan(
          executionSteps: <WesiDebugStep>[
            _step('edit', WesiLocalToolNames.fsWriteText),
          ],
        ),
      ),
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: _DeliverySink(),
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(
        id: 'job-no-verify',
        goal: 'do not trust an unverified result',
      ),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.ok, isFalse);
    expect(result.code, 'WSD_VERIFICATION_REQUIRED');
    expect(executor.calls, 0);
  });

  test('rejects unknown repair tool before executor call', () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));
    final executor = _ScriptedExecutor(<WesiLocalToolResult>[
      WesiLocalToolResult.failure('TEST_FAILED', 'tests failed'),
    ]);
    final engine = WesiSelfDebugEngine(
      executor: executor,
      planner: _Planner(
        plan: WesiSelfDebugPlan(
          verificationSteps: <WesiDebugStep>[
            _step('verify', WesiLocalToolNames.flutterTest),
          ],
        ),
        repairs: const <WesiRepairProposal>[
          WesiRepairProposal(
            repairSteps: <WesiDebugStep>[
              WesiDebugStep(
                id: 'unsafe-repair',
                label: 'unsafe repair',
                call: WesiLocalToolCall(
                  id: 'unsafe-repair-call',
                  tool: 'local.root.shell',
                ),
              ),
            ],
          ),
        ],
      ),
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: _DeliverySink(),
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(
        id: 'job-unsafe-repair',
        goal: 'reject unsafe repair',
      ),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.ok, isFalse);
    expect(result.blocked, isTrue);
    expect(result.code, 'WSD_UNKNOWN_TOOL');
    expect(executor.calls, 1);
  });

  test('rejects unknown local tool before execution', () async {
    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');
    addTearDown(() => root.delete(recursive: true));
    final executor = _ScriptedExecutor(<WesiLocalToolResult>[]);
    final engine = WesiSelfDebugEngine(
      executor: executor,
      planner: _Planner(
        plan: const WesiSelfDebugPlan(
          executionSteps: <WesiDebugStep>[
            WesiDebugStep(
              id: 'bad',
              label: 'bad tool',
              call: WesiLocalToolCall(id: 'bad-call', tool: 'local.root.shell'),
            ),
          ],
        ),
      ),
      artifactValidator: const WesiArtifactValidator(),
      deliverySink: _DeliverySink(),
    );

    final result = await engine.run(
      request: const WesiSelfDebugRequest(id: 'job-4', goal: 'unsafe'),
      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),
    );

    expect(result.code, 'WSD_UNKNOWN_TOOL');
    expect(executor.calls, 0);
  });
}

WesiDebugStep _step(String id, String tool) => WesiDebugStep(
      id: id,
      label: id,
      call: WesiLocalToolCall(id: 'call-$id', tool: tool),
    );

class _ScriptedExecutor extends WesiLocalRuntimeExecutor {
  final List<WesiLocalToolResult> results;
  int calls = 0;

  _ScriptedExecutor(this.results);

  @override
  Future<WesiLocalToolResult> execute(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    if (calls >= results.length) {
      throw StateError('Unexpected executor call');
    }
    return results[calls++];
  }
}

class _Planner implements WesiSelfDebugPlanner {
  final WesiSelfDebugPlan plan;
  final List<WesiRepairProposal> repairs;
  int repairCalls = 0;

  _Planner({required this.plan, this.repairs = const <WesiRepairProposal>[]});

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
    if (repairCalls >= repairs.length) {
      return const WesiRepairProposal.blocked(
        'NO_REPAIR',
        'No repair available',
      );
    }
    return repairs[repairCalls++];
  }
}

class _DeliverySink implements WesiArtifactDeliverySink {
  final bool fail;
  int deliveries = 0;

  _DeliverySink({this.fail = false});

  @override
  Future<WesiArtifactDeliveryResult> deliver(
    WesiValidatedArtifact artifact,
  ) async {
    deliveries++;
    if (fail) {
      return const WesiArtifactDeliveryResult.failure(
        'DELIVERY_DOWN',
        'delivery unavailable',
      );
    }
    return WesiArtifactDeliveryResult.success(
      deliveryRef: 'delivered://${artifact.descriptor.id}',
    );
  }
}
