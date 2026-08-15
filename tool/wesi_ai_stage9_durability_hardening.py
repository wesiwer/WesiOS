from pathlib import Path


def replace_once(text: str, old: str, new: str, label: str) -> str:
    if old not in text:
        raise SystemExit(f'{label}: needle not found')
    return text.replace(old, new, 1)


# Artifact descriptor: bind deliverable build artifacts to objective verification.
path = Path('lib/features/ai/runtime/wesi_artifact_models.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "  final String? mimeType;\n\n  const WesiArtifactDescriptor({\n",
    "  final String? mimeType;\n\n  /// Optional objective verification step that must have succeeded before\n  /// this artifact can be validated/delivered. APK/EXE require build proof.\n  final String? requiredSuccessfulStepId;\n\n  const WesiArtifactDescriptor({\n",
    'artifact proof field',
)
text = replace_once(
    text,
    "    this.displayName,\n    this.mimeType,\n  });\n",
    "    this.displayName,\n    this.mimeType,\n    this.requiredSuccessfulStepId,\n  });\n",
    'artifact proof constructor',
)
text = replace_once(
    text,
    "        if (descriptor.mimeType != null) 'mimeType': descriptor.mimeType,\n",
    "        if (descriptor.mimeType != null) 'mimeType': descriptor.mimeType,\n        if (descriptor.requiredSuccessfulStepId != null)\n          'requiredSuccessfulStepId': descriptor.requiredSuccessfulStepId,\n",
    'artifact proof json',
)
path.write_text(text, encoding='utf-8')

# Artifact validator: pin file identity across builtin/external validation.
path = Path('lib/features/ai/runtime/wesi_artifact_validator.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "    final builtin = await _validateBuiltin(\n      descriptor.kind,\n      canonicalPath,\n      stat.size,\n    );\n",
    "    final digestBefore = await sha256.bind(File(canonicalPath).openRead()).first;\n\n    final builtin = await _validateBuiltin(\n      descriptor.kind,\n      canonicalPath,\n      stat.size,\n    );\n",
    'validator pre-hash',
)
text = replace_once(
    text,
    "    final digest = await sha256.bind(File(canonicalPath).openRead()).first;\n    final artifact = WesiValidatedArtifact(\n      descriptor: descriptor,\n      canonicalPath: canonicalPath,\n      sizeBytes: stat.size,\n      sha256Hex: digest.toString(),\n",
    "    String canonicalAfter;\n    try {\n      canonicalAfter = p.normalize(await file.resolveSymbolicLinks());\n    } on FileSystemException {\n      return const WesiArtifactValidationResult.failure(\n        'ARTIFACT_CHANGED_DURING_VALIDATION',\n        'Artifact path changed during validation',\n      );\n    }\n    final statAfter = await FileStat.stat(canonicalAfter);\n    if (canonicalAfter != canonicalPath ||\n        statAfter.type != FileSystemEntityType.file ||\n        statAfter.size != stat.size) {\n      return const WesiArtifactValidationResult.failure(\n        'ARTIFACT_CHANGED_DURING_VALIDATION',\n        'Artifact identity changed during validation',\n      );\n    }\n    final digestAfter = await sha256.bind(File(canonicalAfter).openRead()).first;\n    if (digestAfter.toString() != digestBefore.toString()) {\n      return const WesiArtifactValidationResult.failure(\n        'ARTIFACT_CHANGED_DURING_VALIDATION',\n        'Artifact contents changed during validation',\n      );\n    }\n    final artifact = WesiValidatedArtifact(\n      descriptor: descriptor,\n      canonicalPath: canonicalAfter,\n      sizeBytes: statAfter.size,\n      sha256Hex: digestAfter.toString(),\n",
    'validator post-hash',
)
path.write_text(text, encoding='utf-8')

# Delivery: same validated artifact is idempotent after a crash/restart.
path = Path('lib/features/ai/runtime/wesi_artifact_delivery.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "    if (await File(finalPath).exists()) {\n      return const WesiArtifactDeliveryResult.failure(\n        'ARTIFACT_DELIVERY_COLLISION',\n        'Artifact delivery target already exists',\n      );\n    }\n",
    "    if (await File(finalPath).exists()) {\n      final existingDigest = await sha256.bind(File(finalPath).openRead()).first;\n      if (existingDigest.toString() == artifact.sha256Hex) {\n        return WesiArtifactDeliveryResult.success(deliveryRef: finalPath);\n      }\n      return const WesiArtifactDeliveryResult.failure(\n        'ARTIFACT_DELIVERY_COLLISION',\n        'Artifact delivery target already exists with different contents',\n      );\n    }\n",
    'idempotent delivery',
)
path.write_text(text, encoding='utf-8')

# Stage-8 progress stage must be checkpoint-token safe (no human text/spaces).
path = Path('lib/features/ai/runtime/wesi_self_debug_job_observer.dart')
text = path.read_text(encoding='utf-8')
old = "  String _stageFor(WesiSelfDebugProgress progress) {\n    final iteration =\n        progress.repairIteration > 0 ? ' #${progress.repairIteration}' : '';\n    return '${progress.phase.name}$iteration: ${progress.message}';\n  }\n"
new = "  String _stageFor(WesiSelfDebugProgress progress) {\n    final iteration =\n        progress.repairIteration > 0 ? '.i${progress.repairIteration}' : '';\n    return 'self_debug.${progress.phase.name}$iteration';\n  }\n"
text = replace_once(text, old, new, 'safe Stage-8 observer stage')
path.write_text(text, encoding='utf-8')

# Self-debug engine: durable checkpoints, control guards, redaction, build proof.
path = Path('lib/features/ai/runtime/wesi_self_debug_engine.dart')
text = path.read_text(encoding='utf-8')
text = replace_once(
    text,
    "import 'dart:async';\n\n",
    "import 'dart:async';\nimport 'dart:convert';\n\nimport 'package:crypto/crypto.dart';\n\n",
    'engine imports',
)
text = replace_once(
    text,
    "import 'wesi_local_runtime_models.dart';\n",
    "import 'wesi_local_runtime_models.dart';\nimport 'wesi_self_debug_checkpoint.dart';\nimport 'wesi_self_debug_redactor.dart';\n",
    'engine local imports',
)
text = replace_once(
    text,
    "  final WesiSelfDebugLimits limits;\n  final WesiSelfDebugObserver? observer;\n\n  const WesiSelfDebugEngine({\n",
    "  final WesiSelfDebugLimits limits;\n  final WesiSelfDebugObserver? observer;\n  final WesiSelfDebugCheckpointManager? checkpoint;\n  final WesiSelfDebugExecutionControl? executionControl;\n  final WesiSelfDebugRedactor redactor;\n\n  const WesiSelfDebugEngine({\n",
    'engine fields',
)
text = replace_once(
    text,
    "    this.limits = const WesiSelfDebugLimits(),\n    this.observer,\n  });\n\n  Future<WesiSelfDebugResult> run({\n    required WesiSelfDebugRequest request,\n    required WesiLocalRuntimeContext runtimeContext,\n  }) async {\n",
    "    this.limits = const WesiSelfDebugLimits(),\n    this.observer,\n    this.checkpoint,\n    this.executionControl,\n    this.redactor = const WesiSelfDebugRedactor(),\n  });\n\n  Future<WesiSelfDebugResult> run({\n    required WesiSelfDebugRequest request,\n    required WesiLocalRuntimeContext runtimeContext,\n  }) async {\n    try {\n      return await _runInternal(\n        request: request,\n        runtimeContext: runtimeContext,\n      );\n    } on WesiSelfDebugStop catch (stop) {\n      return WesiSelfDebugResult(\n        ok: false,\n        blocked: stop.blocked,\n        code: stop.code,\n        message: stop.message,\n        repairIterations: stop.repairIteration,\n        toolCalls: stop.toolCalls,\n      );\n    }\n  }\n\n  Future<WesiSelfDebugResult> _runInternal({\n    required WesiSelfDebugRequest request,\n    required WesiLocalRuntimeContext runtimeContext,\n  }) async {\n",
    'engine run wrapper',
)
text = replace_once(
    text,
    "    final startedAt = DateTime.now();\n",
    "    final startedAt = DateTime.now();\n    if (executionControl != null && checkpoint == null) {\n      return _terminalFailure(\n        'WSD_DURABILITY_CONFIG',\n        'Stage-8 execution control requires a durable Stage-9 checkpoint',\n      );\n    }\n",
    'durability config guard',
)
text = replace_once(
    text,
    "    final plan = await planner.createPlan(request);\n    final planError = _validatePlan(plan);\n    if (planError != null) return planError;\n\n    final initial = await _runSteps(\n",
    "    final plan = await planner.createPlan(request);\n    final planError = _validatePlan(plan);\n    if (planError != null) return planError;\n\n    final checkpointTarget = checkpoint;\n    if (checkpointTarget != null) {\n      await checkpointTarget.bindPlan(\n        requestId: request.id,\n        planFingerprint: _planFingerprint(plan),\n      );\n      final recovered = checkpointTarget.snapshot!;\n      toolCalls = recovered.toolCalls;\n      repairIteration = recovered.repairIteration;\n      await executionControl?.guard(checkpointTarget);\n    }\n\n    final initial = await _runSteps(\n",
    'bind plan checkpoint',
)
text = replace_once(
    text,
    "      currentToolCalls: toolCalls,\n      repairIteration: repairIteration,\n    );\n    toolCalls = initial.toolCalls;\n\n    var needsRepair = !initial.ok;\n",
    "      currentToolCalls: toolCalls,\n      repairIteration: 0,\n    );\n    toolCalls = initial.toolCalls;\n\n    var needsRepair = !initial.ok;\n",
    'stable initial step cycle',
)
text = replace_once(
    text,
    "      repairIteration++;\n      await _progress(\n",
    "      repairIteration++;\n      if (checkpointTarget != null) {\n        await checkpointTarget.updatePosition(\n          phase: WesiSelfDebugPhase.diagnosing.name,\n          repairIteration: repairIteration,\n          toolCalls: toolCalls,\n        );\n      }\n      await _progress(\n",
    'diagnosing checkpoint',
)
text = replace_once(
    text,
    "      final repairIds = <String>{};\n      for (final step in proposal.repairSteps) {\n",
    "      final repairIds = <String>{};\n      for (final step in proposal.repairSteps) {\n",
    'repair validation anchor',
)
text = replace_once(
    text,
    "      final repair = await _runSteps(\n        proposal.repairSteps,\n",
    "      if (checkpointTarget != null) {\n        await checkpointTarget.bindRepair(\n          iteration: repairIteration,\n          fingerprint: _repairFingerprint(proposal.repairSteps),\n        );\n      }\n      final repair = await _runSteps(\n        proposal.repairSteps,\n",
    'repair fingerprint binding',
)
# Success clears only after objective artifact delivery succeeded.
text = replace_once(
    text,
    "          await _progress(\n            WesiSelfDebugPhase.succeeded,\n            'Verified result delivered',\n            repairIteration,\n            toolCalls,\n          );\n          return WesiSelfDebugResult(\n",
    "          await _progress(\n            WesiSelfDebugPhase.succeeded,\n            'Verified result delivered',\n            repairIteration,\n            toolCalls,\n          );\n          await checkpointTarget?.clear();\n          return WesiSelfDebugResult(\n",
    'clear checkpoint on success',
)
# Plan proof validation.
text = replace_once(
    text,
    "    final artifactIds = <String>{};\n    for (final artifact in plan.artifacts) {\n      if (!artifactIds.add(artifact.id)) {\n",
    "    final verificationById = <String, WesiDebugStep>{\n      for (final step in plan.verificationSteps) step.id: step,\n    };\n    final artifactIds = <String>{};\n    for (final artifact in plan.artifacts) {\n      if (!artifactIds.add(artifact.id)) {\n",
    'verification proof index',
)
text = replace_once(
    text,
    "      }\n    }\n    if (plan.verificationSteps.isEmpty) {\n",
    "      }\n      final proofId = artifact.requiredSuccessfulStepId;\n      if (proofId != null) {\n        final proof = verificationById[proofId];\n        if (proof == null) {\n          return _terminalFailure(\n            'WSD_ARTIFACT_PROOF_UNKNOWN',\n            'Artifact proof step is not part of objective verification',\n          );\n        }\n        if ((artifact.kind == WesiArtifactKind.apk ||\n                artifact.kind == WesiArtifactKind.windowsExecutable) &&\n            proof.call.tool != WesiLocalToolNames.flutterBuild) {\n          return _terminalFailure(\n            'WSD_BUILD_PROOF_INVALID',\n            'APK/Windows artifacts require a successful Flutter build proof',\n          );\n        }\n      } else if (artifact.kind == WesiArtifactKind.apk ||\n          artifact.kind == WesiArtifactKind.windowsExecutable) {\n        return _terminalFailure(\n          'WSD_BUILD_PROOF_REQUIRED',\n          'APK/Windows artifacts cannot be delivered without build proof',\n        );\n      }\n    }\n    if (plan.verificationSteps.isEmpty) {\n",
    'artifact build proof validation',
)
# Replace the core step loop with durable skip/in-flight semantics.
old = """    var toolCalls = currentToolCalls;
    for (final step in steps) {
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
      toolCalls++;
      await _progress(phase, step.label, repairIteration, toolCalls);
      final result = await executor.execute(step.call, runtimeContext);
      evidence.add(_evidence(step, result));
      if (!result.ok) return _StepRun(false, toolCalls);
    }
    return _StepRun(true, toolCalls);
"""
new = """    var toolCalls = currentToolCalls;
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
"""
text = replace_once(text, old, new, 'durable step loop')
# Artifact proof check and phase checkpoint.
text = replace_once(
    text,
    "    await _progress(\n      WesiSelfDebugPhase.validatingArtifacts,\n",
    "    final checkpointTarget = checkpoint;\n    if (checkpointTarget != null) {\n      await checkpointTarget.updatePosition(\n        phase: WesiSelfDebugPhase.validatingArtifacts.name,\n        repairIteration: repairIteration,\n        toolCalls: toolCalls,\n      );\n      await executionControl?.guard(checkpointTarget);\n    }\n    await _progress(\n      WesiSelfDebugPhase.validatingArtifacts,\n",
    'artifact phase checkpoint',
)
text = replace_once(
    text,
    "    final out = <WesiValidatedArtifact>[];\n    for (final descriptor in descriptors) {\n      final result = await artifactValidator.validate(\n",
    "    final out = <WesiValidatedArtifact>[];\n    for (final descriptor in descriptors) {\n      final proofId = descriptor.requiredSuccessfulStepId;\n      if (proofId != null) {\n        WesiDebugEvidence? latest;\n        for (final item in evidence.reversed) {\n          if (item.stepId == proofId) {\n            latest = item;\n            break;\n          }\n        }\n        if (latest == null || !latest.ok) {\n          evidence.add(WesiDebugEvidence(\n            stepId: 'artifact:${descriptor.id}',\n            tool: 'artifact.build-proof',\n            ok: false,\n            code: 'ARTIFACT_PROOF_FAILED',\n            exitCode: latest?.exitCode,\n            summary: 'Required objective build/verification proof did not succeed',\n          ));\n          return _ArtifactRun(false, out);\n        }\n      }\n      final result = await artifactValidator.validate(\n",
    'artifact proof runtime check',
)
text = replace_once(
    text,
    "    await _progress(\n      WesiSelfDebugPhase.delivering,\n",
    "    final checkpointTarget = checkpoint;\n    if (checkpointTarget != null) {\n      await checkpointTarget.updatePosition(\n        phase: WesiSelfDebugPhase.delivering.name,\n        repairIteration: repairIteration,\n        toolCalls: toolCalls,\n      );\n      await executionControl?.guard(checkpointTarget);\n    }\n    await _progress(\n      WesiSelfDebugPhase.delivering,\n",
    'delivery phase checkpoint',
)
# Redact before bounding.
text = replace_once(
    text,
    "  String _bound(String value) {\n    final clean = value.replaceAll('\\u0000', '');\n",
    "  String _bound(String value) {\n    final clean = redactor.redact(value);\n",
    'secret redaction',
)
# Fingerprint helpers before wallExpired.
anchor = "  bool _wallExpired(DateTime startedAt) =>\n"
helpers = r'''  String _planFingerprint(WesiSelfDebugPlan plan) => _fingerprint(<String, dynamic>{
        'execution': plan.executionSteps.map(_stepFingerprintPayload).toList(),
        'verification': plan.verificationSteps.map(_stepFingerprintPayload).toList(),
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

'''
text = replace_once(text, anchor, helpers + anchor, 'fingerprint helpers')
path.write_text(text, encoding='utf-8')

print('Stage 9 durability/security hardening patch applied')
