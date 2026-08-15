import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'wesi_artifact_models.dart';
import 'wesi_artifact_validator.dart';
import 'wesi_local_runtime_executor.dart';
import 'wesi_local_runtime_models.dart';
import 'wesi_self_debug_checkpoint.dart';
import 'wesi_self_debug_redactor.dart';

enum WesiSelfDebugPhase {
  planning,
  executing,
  verifying,
  diagnosing,
  repairing,
  validatingArtifacts,
  delivering,
  succeeded,
  blocked,
  failed,
}

class WesiSelfDebugLimits {
  final int maxPlanSteps;
  final int maxVerificationSteps;
  final int maxRepairStepsPerIteration;
  final int maxRepairIterations;
  final int maxToolCalls;
  final int maxArtifacts;
  final int maxRepeatedFailureFingerprint;
  final int maxEvidenceChars;
  final Duration maxWallTime;
  final int maxDeliveryAttempts;

  const WesiSelfDebugLimits({
    this.maxPlanSteps = 32,
    this.maxVerificationSteps = 16,
    this.maxRepairStepsPerIteration = 16,
    this.maxRepairIterations = 5,
    this.maxToolCalls = 96,
    this.maxArtifacts = 16,
    this.maxRepeatedFailureFingerprint = 2,
    this.maxEvidenceChars = 16000,
    this.maxWallTime = const Duration(minutes: 45),
    this.maxDeliveryAttempts = 2,
  });
}

class WesiSelfDebugRequest {
  final String id;
  final String goal;

  const WesiSelfDebugRequest({required this.id, required this.goal});
}

class WesiDebugStep {
  final String id;
  final String label;
  final WesiLocalToolCall call;

  const WesiDebugStep({
    required this.id,
    required this.label,
    required this.call,
  });
}

class WesiSelfDebugPlan {
  final List<WesiDebugStep> executionSteps;
  final List<WesiDebugStep> verificationSteps;
  final List<WesiArtifactDescriptor> artifacts;

  const WesiSelfDebugPlan({
    this.executionSteps = const <WesiDebugStep>[],
    this.verificationSteps = const <WesiDebugStep>[],
    this.artifacts = const <WesiArtifactDescriptor>[],
  });
}

class WesiDebugEvidence {
  final String stepId;
  final String tool;
  final bool ok;
  final String code;
  final int? exitCode;
  final String summary;

  const WesiDebugEvidence({
    required this.stepId,
    required this.tool,
    required this.ok,
    required this.code,
    required this.exitCode,
    required this.summary,
  });
}

class WesiRepairProposal {
  final bool blocked;
  final String? blockerCode;
  final String? blockerMessage;
  final List<WesiDebugStep> repairSteps;

  const WesiRepairProposal({
    this.blocked = false,
    this.blockerCode,
    this.blockerMessage,
    this.repairSteps = const <WesiDebugStep>[],
  });

  const WesiRepairProposal.blocked(String code, String message)
      : this(
          blocked: true,
          blockerCode: code,
          blockerMessage: message,
        );
}

abstract class WesiSelfDebugPlanner {
  Future<WesiSelfDebugPlan> createPlan(WesiSelfDebugRequest request);

  Future<WesiRepairProposal> proposeRepair({
    required WesiSelfDebugRequest request,
    required WesiSelfDebugPlan plan,
    required int iteration,
    required List<WesiDebugEvidence> evidence,
  });
}

class WesiSelfDebugProgress {
  final WesiSelfDebugPhase phase;
  final String message;
  final int repairIteration;
  final int toolCalls;

  const WesiSelfDebugProgress({
    required this.phase,
    required this.message,
    required this.repairIteration,
    required this.toolCalls,
  });
}

abstract class WesiSelfDebugObserver {
  Future<void> onProgress(WesiSelfDebugProgress progress);
}

class WesiSelfDebugResult {
  final bool ok;
  final bool blocked;
  final String code;
  final String message;
  final int repairIterations;
  final int toolCalls;
  final List<WesiDebugEvidence> evidence;
  final List<WesiValidatedArtifact> artifacts;
  final Map<String, String> deliveryRefs;

  const WesiSelfDebugResult({
    required this.ok,
    required this.blocked,
    required this.code,
    required this.message,
    required this.repairIterations,
    required this.toolCalls,
    this.evidence = const <WesiDebugEvidence>[],
    this.artifacts = const <WesiValidatedArtifact>[],
    this.deliveryRefs = const <String, String>{},
  });
}

class WesiSelfDebugEngine {
  final WesiLocalRuntimeExecutor executor;
  final WesiSelfDebugPlanner planner;
  final WesiArtifactValidator artifactValidator;
  final WesiArtifactDeliverySink deliverySink;
  final WesiSelfDebugLimits limits;
  final WesiSelfDebugObserver? observer;
  final WesiSelfDebugCheckpointManager? checkpoint;
  final WesiSelfDebugExecutionControl? executionControl;
  final WesiSelfDebugRedactor redactor;

  const WesiSelfDebugEngine({
    required this.executor,
    required this.planner,
    required this.artifactValidator,
    required this.deliverySink,
    this.limits = const WesiSelfDebugLimits(),
    this.observer,
    this.checkpoint,
    this.executionControl,
    this.redactor = const WesiSelfDebugRedactor(),
  });

  Future<WesiSelfDebugResult> run({
    required WesiSelfDebugRequest request,
    required WesiLocalRuntimeContext runtimeContext,
  }) async {
    try {
      return await _runInternal(
        request: request,
        runtimeContext: runtimeContext,
      );
    } on WesiSelfDebugStop catch (stop) {
      return WesiSelfDebugResult(
        ok: false,
        blocked: stop.blocked,
        code: stop.code,
        message: stop.message,
        repairIterations: stop.repairIteration,
        toolCalls: stop.toolCalls,
      );
    }
  }

  Future<WesiSelfDebugResult> _runInternal({
    required WesiSelfDebugRequest request,
    required WesiLocalRuntimeContext runtimeContext,
  }) async {
    final startedAt = DateTime.now();
    if (executionControl != null && checkpoint == null) {
      return _terminalFailure(
        'WSD_DURABILITY_CONFIG',
        'Stage-8 execution control requires a durable Stage-9 checkpoint',
      );
    }
    if (request.id.trim().isEmpty || request.id.length > 128) {
      return _terminalFailure(
          'WSD_BAD_REQUEST', 'Self-debug request id is invalid');
    }
    if (request.goal.trim().isEmpty || request.goal.length > 16000) {
      return _terminalFailure('WSD_BAD_GOAL', 'Self-debug goal is invalid');
    }

    var toolCalls = 0;
    var repairIteration = 0;
    final evidence = <WesiDebugEvidence>[];
    final failureFingerprints = <String, int>{};

    await _progress(WesiSelfDebugPhase.planning, 'Planning execution',
        repairIteration, toolCalls);
    final plan = await planner.createPlan(request);
    final planError = _validatePlan(plan);
    if (planError != null) return planError;

    final checkpointTarget = checkpoint;
    if (checkpointTarget != null) {
      await checkpointTarget.bindPlan(
        requestId: request.id,
        planFingerprint: _planFingerprint(plan),
      );
      final recovered = checkpointTarget.snapshot!;
      toolCalls = recovered.toolCalls;
      repairIteration = recovered.repairIteration;
      await executionControl?.guard(checkpointTarget);
    }

    final initial = await _runSteps(
      plan.executionSteps,
      phase: WesiSelfDebugPhase.executing,
      runtimeContext: runtimeContext,
      evidence: evidence,
      startedAt: startedAt,
      currentToolCalls: toolCalls,
      repairIteration: 0,
    );
    toolCalls = initial.toolCalls;

    var needsRepair = !initial.ok;
    while (true) {
      if (!needsRepair) {
        final verification = await _runSteps(
          plan.verificationSteps,
          phase: WesiSelfDebugPhase.verifying,
          runtimeContext: runtimeContext,
          evidence: evidence,
          startedAt: startedAt,
          currentToolCalls: toolCalls,
          repairIteration: repairIteration,
        );
        toolCalls = verification.toolCalls;
        needsRepair = !verification.ok;
      }

      List<WesiValidatedArtifact> validatedArtifacts =
          const <WesiValidatedArtifact>[];
      if (!needsRepair) {
        final validation = await _validateArtifacts(
          plan.artifacts,
          runtimeContext.workspaceRoot,
          evidence,
          repairIteration,
          toolCalls,
        );
        validatedArtifacts = validation.artifacts;
        needsRepair = !validation.ok;
        if (!needsRepair) {
          final delivery = await _deliverArtifacts(
            validatedArtifacts,
            repairIteration,
            toolCalls,
          );
          if (!delivery.ok) {
            return WesiSelfDebugResult(
              ok: false,
              blocked: true,
              code: delivery.code,
              message: delivery.message,
              repairIterations: repairIteration,
              toolCalls: toolCalls,
              evidence: List<WesiDebugEvidence>.unmodifiable(evidence),
              artifacts: validatedArtifacts,
              deliveryRefs: delivery.refs,
            );
          }
          await _progress(
            WesiSelfDebugPhase.succeeded,
            'Verified result delivered',
            repairIteration,
            toolCalls,
          );
          await checkpointTarget?.clear();
          return WesiSelfDebugResult(
            ok: true,
            blocked: false,
            code: 'OK',
            message: 'Self-debug task completed and verified',
            repairIterations: repairIteration,
            toolCalls: toolCalls,
            evidence: List<WesiDebugEvidence>.unmodifiable(evidence),
            artifacts: validatedArtifacts,
            deliveryRefs: delivery.refs,
          );
        }
      }

      if (_wallExpired(startedAt)) {
        return _blocked(
          'WSD_WALL_TIME_EXCEEDED',
          'Self-debug wall-time limit reached',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      if (repairIteration >= limits.maxRepairIterations) {
        return _blocked(
          'WSD_REPAIR_LIMIT',
          'Self-debug repair iteration limit reached',
          repairIteration,
          toolCalls,
          evidence,
        );
      }

      final fingerprint = _failureFingerprint(evidence);
      final repeated = (failureFingerprints[fingerprint] ?? 0) + 1;
      failureFingerprints[fingerprint] = repeated;
      if (repeated > limits.maxRepeatedFailureFingerprint) {
        return _blocked(
          'WSD_REPEATED_FAILURE',
          'The same objective failure repeated without progress',
          repairIteration,
          toolCalls,
          evidence,
        );
      }

      repairIteration++;
      if (checkpointTarget != null) {
        await checkpointTarget.updatePosition(
          phase: WesiSelfDebugPhase.diagnosing.name,
          repairIteration: repairIteration,
          toolCalls: toolCalls,
        );
      }
      await _progress(
        WesiSelfDebugPhase.diagnosing,
        'Diagnosing failed verification',
        repairIteration,
        toolCalls,
      );
      final proposal = await planner.proposeRepair(
        request: request,
        plan: plan,
        iteration: repairIteration,
        evidence: _boundedEvidence(evidence),
      );
      if (proposal.blocked) {
        return _blocked(
          proposal.blockerCode ?? 'WSD_OBJECTIVE_BLOCKER',
          proposal.blockerMessage ?? 'Planner reported an objective blocker',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      if (proposal.repairSteps.isEmpty ||
          proposal.repairSteps.length > limits.maxRepairStepsPerIteration) {
        return _blocked(
          'WSD_BAD_REPAIR_PLAN',
          'Repair proposal is empty or exceeds the bounded step limit',
          repairIteration,
          toolCalls,
          evidence,
        );
      }
      final repairIds = <String>{};
      for (final step in proposal.repairSteps) {
        if (step.id.trim().isEmpty || !repairIds.add(step.id)) {
          return _blocked(
            'WSD_BAD_REPAIR_PLAN',
            'Repair proposal contains empty or duplicate step ids',
            repairIteration,
            toolCalls,
            evidence,
          );
        }
        if (WesiLocalCapabilityRegistry.get(step.call.tool) == null) {
          return _blocked(
            'WSD_UNKNOWN_TOOL',
            'Repair proposal contains an unknown local tool',
            repairIteration,
            toolCalls,
            evidence,
          );
        }
      }
      if (checkpointTarget != null) {
        await checkpointTarget.bindRepair(
          iteration: repairIteration,
          fingerprint: _repairFingerprint(proposal.repairSteps),
        );
      }
      final repair = await _runSteps(
        proposal.repairSteps,
        phase: WesiSelfDebugPhase.repairing,
        runtimeContext: runtimeContext,
        evidence: evidence,
        startedAt: startedAt,
        currentToolCalls: toolCalls,
        repairIteration: repairIteration,
      );
      toolCalls = repair.toolCalls;
      needsRepair = !repair.ok;
    }
  }

  WesiSelfDebugResult? _validatePlan(WesiSelfDebugPlan plan) {
    if (plan.executionSteps.length > limits.maxPlanSteps ||
        plan.verificationSteps.length > limits.maxVerificationSteps ||
        plan.artifacts.length > limits.maxArtifacts) {
      return _terminalFailure(
        'WSD_PLAN_LIMIT',
        'Self-debug plan exceeds bounded limits',
      );
    }
    final ids = <String>{};
    for (final step in <WesiDebugStep>[
      ...plan.executionSteps,
      ...plan.verificationSteps,
    ]) {
      if (step.id.trim().isEmpty || !ids.add(step.id)) {
        return _terminalFailure(
          'WSD_PLAN_INVALID',
          'Self-debug plan contains empty or duplicate step ids',
        );
      }
      if (WesiLocalCapabilityRegistry.get(step.call.tool) == null) {
        return _terminalFailure(
          'WSD_UNKNOWN_TOOL',
          'Self-debug plan contains an unknown local tool',
        );
      }
    }
    final verificationById = <String, WesiDebugStep>{
      for (final step in plan.verificationSteps) step.id: step,
    };
    final artifactIds = <String>{};
    for (final artifact in plan.artifacts) {
      if (!artifactIds.add(artifact.id)) {
        return _terminalFailure(
          'WSD_ARTIFACT_DUPLICATE',
          'Self-debug plan contains duplicate artifact ids',
        );
      }
      final proofId = artifact.requiredSuccessfulStepId;
      if (proofId != null) {
        final proof = verificationById[proofId];
        if (proof == null) {
          return _terminalFailure(
            'WSD_ARTIFACT_PROOF_UNKNOWN',
            'Artifact proof step is not part of objective verification',
          );
        }
        if ((artifact.kind == WesiArtifactKind.apk ||
                artifact.kind == WesiArtifactKind.windowsExecutable) &&
            proof.call.tool != WesiLocalToolNames.flutterBuild) {
          return _terminalFailure(
            'WSD_BUILD_PROOF_INVALID',
            'APK/Windows artifacts require a successful Flutter build proof',
          );
        }
      } else if (artifact.kind == WesiArtifactKind.apk ||
          artifact.kind == WesiArtifactKind.windowsExecutable) {
        return _terminalFailure(
          'WSD_BUILD_PROOF_REQUIRED',
          'APK/Windows artifacts cannot be delivered without build proof',
        );
      }
    }
    if (plan.verificationSteps.isEmpty) {
      return _terminalFailure(
        'WSD_VERIFICATION_REQUIRED',
        'Self-debug plan must contain objective verification before success',
      );
    }
    return null;
  }

  Future<_StepRun> _runSteps(
    List<WesiDebugStep> steps, {
    required WesiSelfDebugPhase phase,
    required WesiLocalRuntimeContext runtimeContext,
    required List<WesiDebugEvidence> evidence,
    required DateTime startedAt,
    required int currentToolCalls,
    required int repairIteration,
  }) async {
    var toolCalls = currentToolCalls;
    final checkpointTarget = checkpoint;
    for (final step in steps) {
      final stepKey = '${phase.name}:$repairIteration:${step.id}';
      final persisted = checkpointTarget?.outcomeFor(stepKey);
      if (persisted != null) {
        final restored = WesiDebugEvidence(
          stepId: step.id,
          tool: step.call.tool,
          ok: persisted.ok,
          code: persisted.code,
          exitCode: persisted.exitCode,
          summary: persisted.summary,
        );
        evidence.add(restored);
        if (!persisted.ok) return _StepRun(false, toolCalls);
        continue;
      }
      if (_wallExpired(startedAt)) {
        evidence.add(const WesiDebugEvidence(
          stepId: 'runtime-limit',
          tool: 'self-debug.wall-time',
          ok: false,
          code: 'WSD_WALL_TIME_EXCEEDED',
          exitCode: null,
          summary: 'Self-debug wall-time limit reached',
        ));
        return _StepRun(false, toolCalls);
      }
      if (toolCalls >= limits.maxToolCalls) {
        evidence.add(const WesiDebugEvidence(
          stepId: 'runtime-limit',
          tool: 'self-debug.tool-budget',
          ok: false,
          code: 'WSD_TOOL_CALL_LIMIT',
          exitCode: null,
          summary: 'Self-debug tool-call limit reached',
        ));
        return _StepRun(false, toolCalls);
      }
      if (checkpointTarget != null) {
        await checkpointTarget.updatePosition(
          phase: phase.name,
          repairIteration: repairIteration,
          toolCalls: toolCalls,
        );
        await executionControl?.guard(checkpointTarget);
      }
      final meta = WesiLocalCapabilityRegistry.get(step.call.tool)!;
      toolCalls++;
      if (checkpointTarget != null) {
        await checkpointTarget.beforeStep(
          key: stepKey,
          stepId: step.id,
          risk: meta.risk,
          phase: phase.name,
          repairIteration: repairIteration,
          toolCalls: toolCalls,
        );
      }
      await _progress(phase, step.label, repairIteration, toolCalls);
      final result = await executor.execute(step.call, runtimeContext);
      final item = _evidence(step, result);
      evidence.add(item);
      if (checkpointTarget != null) {
        await checkpointTarget.afterStep(
          outcome: WesiSelfDebugPersistedOutcome(
            key: stepKey,
            ok: item.ok,
            code: item.code,
            exitCode: item.exitCode,
            summary: item.summary,
          ),
          toolCalls: toolCalls,
        );
        await executionControl?.guard(checkpointTarget);
      }
      if (!result.ok) return _StepRun(false, toolCalls);
    }
    return _StepRun(true, toolCalls);
  }

  Future<_ArtifactRun> _validateArtifacts(
    List<WesiArtifactDescriptor> descriptors,
    String workspaceRoot,
    List<WesiDebugEvidence> evidence,
    int repairIteration,
    int toolCalls,
  ) async {
    final checkpointTarget = checkpoint;
    if (checkpointTarget != null) {
      await checkpointTarget.updatePosition(
        phase: WesiSelfDebugPhase.validatingArtifacts.name,
        repairIteration: repairIteration,
        toolCalls: toolCalls,
      );
      await executionControl?.guard(checkpointTarget);
    }
    await _progress(
      WesiSelfDebugPhase.validatingArtifacts,
      'Validating artifacts',
      repairIteration,
      toolCalls,
    );
    final out = <WesiValidatedArtifact>[];
    for (final descriptor in descriptors) {
      final proofId = descriptor.requiredSuccessfulStepId;
      if (proofId != null) {
        WesiDebugEvidence? latest;
        for (final item in evidence.reversed) {
          if (item.stepId == proofId) {
            latest = item;
            break;
          }
        }
        if (latest == null || !latest.ok) {
          evidence.add(WesiDebugEvidence(
            stepId: 'artifact:${descriptor.id}',
            tool: 'artifact.build-proof',
            ok: false,
            code: 'ARTIFACT_PROOF_FAILED',
            exitCode: latest?.exitCode,
            summary:
                'Required objective build/verification proof did not succeed',
          ));
          return _ArtifactRun(false, out);
        }
      }
      final result = await artifactValidator.validate(
        descriptor: descriptor,
        workspaceRoot: workspaceRoot,
      );
      if (!result.ok || result.artifact == null) {
        evidence.add(WesiDebugEvidence(
          stepId: 'artifact:${descriptor.id}',
          tool: 'artifact.validate',
          ok: false,
          code: result.code,
          exitCode: null,
          summary: _bound(result.message),
        ));
        return _ArtifactRun(false, out);
      }
      out.add(result.artifact!);
    }
    return _ArtifactRun(true, List<WesiValidatedArtifact>.unmodifiable(out));
  }

  Future<_DeliveryRun> _deliverArtifacts(
    List<WesiValidatedArtifact> artifacts,
    int repairIteration,
    int toolCalls,
  ) async {
    final checkpointTarget = checkpoint;
    if (checkpointTarget != null) {
      await checkpointTarget.updatePosition(
        phase: WesiSelfDebugPhase.delivering.name,
        repairIteration: repairIteration,
        toolCalls: toolCalls,
      );
      await executionControl?.guard(checkpointTarget);
    }
    await _progress(
      WesiSelfDebugPhase.delivering,
      'Delivering validated artifacts',
      repairIteration,
      toolCalls,
    );
    final refs = <String, String>{};
    for (final artifact in artifacts) {
      WesiArtifactDeliveryResult? last;
      for (var attempt = 0; attempt < limits.maxDeliveryAttempts; attempt++) {
        last = await deliverySink.deliver(artifact);
        if (last.ok) break;
      }
      if (last == null || !last.ok) {
        return _DeliveryRun(
          false,
          last?.code ?? 'WSD_DELIVERY_FAILED',
          last?.message ?? 'Artifact delivery failed',
          refs,
        );
      }
      if (last.deliveryRef != null)
        refs[artifact.descriptor.id] = last.deliveryRef!;
    }
    return _DeliveryRun(true, 'OK', 'Artifacts delivered', refs);
  }

  WesiDebugEvidence _evidence(WesiDebugStep step, WesiLocalToolResult result) {
    final chunks = <String>[
      result.message,
      if (result.stderr != null && result.stderr!.trim().isNotEmpty)
        result.stderr!,
      if (!result.ok &&
          result.stdout != null &&
          result.stdout!.trim().isNotEmpty)
        result.stdout!,
    ];
    return WesiDebugEvidence(
      stepId: step.id,
      tool: step.call.tool,
      ok: result.ok,
      code: result.code,
      exitCode: result.exitCode,
      summary: _bound(chunks.join('\n')),
    );
  }

  List<WesiDebugEvidence> _boundedEvidence(List<WesiDebugEvidence> evidence) {
    var remaining = limits.maxEvidenceChars;
    final out = <WesiDebugEvidence>[];
    for (final item in evidence.reversed) {
      if (remaining <= 0) break;
      final summary = item.summary.length <= remaining
          ? item.summary
          : item.summary.substring(0, remaining);
      out.add(WesiDebugEvidence(
        stepId: item.stepId,
        tool: item.tool,
        ok: item.ok,
        code: item.code,
        exitCode: item.exitCode,
        summary: summary,
      ));
      remaining -= summary.length;
    }
    return List<WesiDebugEvidence>.unmodifiable(out.reversed);
  }

  String _failureFingerprint(List<WesiDebugEvidence> evidence) {
    final failed = evidence.lastWhere((item) => !item.ok);
    final summary = failed.summary.length <= 256
        ? failed.summary
        : failed.summary.substring(0, 256);
    return '${failed.tool}|${failed.code}|$summary';
  }

  String _bound(String value) {
    final clean = redactor.redact(value);
    if (clean.length <= 4096) return clean;
    return '${clean.substring(0, 4096)}…';
  }

  String _planFingerprint(WesiSelfDebugPlan plan) =>
      _fingerprint(<String, dynamic>{
        'execution': plan.executionSteps.map(_stepFingerprintPayload).toList(),
        'verification':
            plan.verificationSteps.map(_stepFingerprintPayload).toList(),
        'artifacts': plan.artifacts
            .map((artifact) => <String, dynamic>{
                  'id': artifact.id,
                  'relativePath': artifact.relativePath,
                  'kind': artifact.kind.name,
                  'maxBytes': artifact.maxBytes,
                  'displayName': artifact.displayName,
                  'mimeType': artifact.mimeType,
                  'requiredSuccessfulStepId': artifact.requiredSuccessfulStepId,
                })
            .toList(),
      });

  String _repairFingerprint(List<WesiDebugStep> steps) =>
      _fingerprint(steps.map(_stepFingerprintPayload).toList());

  Map<String, dynamic> _stepFingerprintPayload(WesiDebugStep step) =>
      <String, dynamic>{
        'id': step.id,
        'label': step.label,
        'tool': step.call.tool,
        'arguments': _canonicalize(step.call.arguments),
      };

  String _fingerprint(dynamic value) {
    final canonical = jsonEncode(_canonicalize(value));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  dynamic _canonicalize(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return <String, dynamic>{
        for (final key in keys) key: _canonicalize(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalize).toList();
    return value;
  }

  bool _wallExpired(DateTime startedAt) =>
      DateTime.now().difference(startedAt) > limits.maxWallTime;

  Future<void> _progress(
    WesiSelfDebugPhase phase,
    String message,
    int repairIteration,
    int toolCalls,
  ) async {
    final target = observer;
    if (target == null) return;
    await target.onProgress(WesiSelfDebugProgress(
      phase: phase,
      message: message,
      repairIteration: repairIteration,
      toolCalls: toolCalls,
    ));
  }

  WesiSelfDebugResult _blocked(
    String code,
    String message,
    int repairIterations,
    int toolCalls,
    List<WesiDebugEvidence> evidence,
  ) =>
      WesiSelfDebugResult(
        ok: false,
        blocked: true,
        code: code,
        message: message,
        repairIterations: repairIterations,
        toolCalls: toolCalls,
        evidence: List<WesiDebugEvidence>.unmodifiable(evidence),
      );

  WesiSelfDebugResult _terminalFailure(String code, String message) =>
      WesiSelfDebugResult(
        ok: false,
        blocked: false,
        code: code,
        message: message,
        repairIterations: 0,
        toolCalls: 0,
      );
}

class _StepRun {
  final bool ok;
  final int toolCalls;

  const _StepRun(this.ok, this.toolCalls);
}

class _ArtifactRun {
  final bool ok;
  final List<WesiValidatedArtifact> artifacts;

  const _ArtifactRun(this.ok, this.artifacts);
}

class _DeliveryRun {
  final bool ok;
  final String code;
  final String message;
  final Map<String, String> refs;

  const _DeliveryRun(this.ok, this.code, this.message, this.refs);
}
