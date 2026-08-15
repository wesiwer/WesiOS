from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding='utf-8')
    count = text.count(old)
    if count != 1:
        raise SystemExit(f'{path}: expected one anchor, found {count}: {old[:100]!r}')
    p.write_text(text.replace(old, new, 1), encoding='utf-8')


engine = 'lib/features/ai/runtime/wesi_self_debug_engine.dart'
replace_once(
    engine,
    '''    final artifactIds = <String>{};\n    for (final artifact in plan.artifacts) {\n      if (!artifactIds.add(artifact.id)) {\n        return _terminalFailure(\n          'WSD_ARTIFACT_DUPLICATE',\n          'Self-debug plan contains duplicate artifact ids',\n        );\n      }\n    }\n    return null;''',
    '''    final artifactIds = <String>{};\n    for (final artifact in plan.artifacts) {\n      if (!artifactIds.add(artifact.id)) {\n        return _terminalFailure(\n          'WSD_ARTIFACT_DUPLICATE',\n          'Self-debug plan contains duplicate artifact ids',\n        );\n      }\n    }\n    if (plan.verificationSteps.isEmpty) {\n      return _terminalFailure(\n        'WSD_VERIFICATION_REQUIRED',\n        'Self-debug plan must contain objective verification before success',\n      );\n    }\n    return null;''',
)
replace_once(
    engine,
    '''      if (proposal.repairSteps.isEmpty ||\n          proposal.repairSteps.length > limits.maxRepairStepsPerIteration) {\n        return _blocked(\n          'WSD_BAD_REPAIR_PLAN',\n          'Repair proposal is empty or exceeds the bounded step limit',\n          repairIteration,\n          toolCalls,\n          evidence,\n        );\n      }\n      final repair = await _runSteps(''',
    '''      if (proposal.repairSteps.isEmpty ||\n          proposal.repairSteps.length > limits.maxRepairStepsPerIteration) {\n        return _blocked(\n          'WSD_BAD_REPAIR_PLAN',\n          'Repair proposal is empty or exceeds the bounded step limit',\n          repairIteration,\n          toolCalls,\n          evidence,\n        );\n      }\n      final repairIds = <String>{};\n      for (final step in proposal.repairSteps) {\n        if (step.id.trim().isEmpty || !repairIds.add(step.id)) {\n          return _blocked(\n            'WSD_BAD_REPAIR_PLAN',\n            'Repair proposal contains empty or duplicate step ids',\n            repairIteration,\n            toolCalls,\n            evidence,\n          );\n        }\n        if (WesiLocalCapabilityRegistry.get(step.call.tool) == null) {\n          return _blocked(\n            'WSD_UNKNOWN_TOOL',\n            'Repair proposal contains an unknown local tool',\n            repairIteration,\n            toolCalls,\n            evidence,\n          );\n        }\n      }\n      final repair = await _runSteps(''',
)

tests = 'test/wesi_self_debug_engine_test.dart'
replace_once(
    tests,
    '''  test('rejects unknown local tool before execution', () async {''',
    '''  test('requires objective verification before executing a plan', () async {\n    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');\n    addTearDown(() => root.delete(recursive: true));\n    final executor = _ScriptedExecutor(<WesiLocalToolResult>[]);\n    final engine = WesiSelfDebugEngine(\n      executor: executor,\n      planner: _Planner(\n        plan: WesiSelfDebugPlan(\n          executionSteps: <WesiDebugStep>[\n            _step('edit', WesiLocalToolNames.fsWriteText),\n          ],\n        ),\n      ),\n      artifactValidator: const WesiArtifactValidator(),\n      deliverySink: _DeliverySink(),\n    );\n\n    final result = await engine.run(\n      request: const WesiSelfDebugRequest(\n        id: 'job-no-verify',\n        goal: 'do not trust an unverified result',\n      ),\n      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),\n    );\n\n    expect(result.ok, isFalse);\n    expect(result.code, 'WSD_VERIFICATION_REQUIRED');\n    expect(executor.calls, 0);\n  });\n\n  test('rejects unknown repair tool before executor call', () async {\n    final root = await Directory.systemTemp.createTemp('wesi-self-debug-');\n    addTearDown(() => root.delete(recursive: true));\n    final executor = _ScriptedExecutor(<WesiLocalToolResult>[\n      WesiLocalToolResult.failure('TEST_FAILED', 'tests failed'),\n    ]);\n    final engine = WesiSelfDebugEngine(\n      executor: executor,\n      planner: _Planner(\n        plan: WesiSelfDebugPlan(\n          verificationSteps: <WesiDebugStep>[\n            _step('verify', WesiLocalToolNames.flutterTest),\n          ],\n        ),\n        repairs: const <WesiRepairProposal>[\n          WesiRepairProposal(\n            repairSteps: <WesiDebugStep>[\n              WesiDebugStep(\n                id: 'unsafe-repair',\n                label: 'unsafe repair',\n                call: WesiLocalToolCall(\n                  id: 'unsafe-repair-call',\n                  tool: 'local.root.shell',\n                ),\n              ),\n            ],\n          ),\n        ],\n      ),\n      artifactValidator: const WesiArtifactValidator(),\n      deliverySink: _DeliverySink(),\n    );\n\n    final result = await engine.run(\n      request: const WesiSelfDebugRequest(\n        id: 'job-unsafe-repair',\n        goal: 'reject unsafe repair',\n      ),\n      runtimeContext: WesiLocalRuntimeContext(workspaceRoot: root.path),\n    );\n\n    expect(result.ok, isFalse);\n    expect(result.blocked, isTrue);\n    expect(result.code, 'WSD_UNKNOWN_TOOL');\n    expect(executor.calls, 1);\n  });\n\n  test('rejects unknown local tool before execution', () async {''',
)

doc = 'docs/WESI_AI_SELF_DEBUG_ARTIFACTS.md'
replace_once(
    doc,
    '''- re-runs the verification plan after every repair;''',
    '''- requires at least one objective verification step before execution can be reported successful;\n- re-runs the verification plan after every repair;\n- validates repair-step ids and Local Runtime tool names before any repair execution;''',
)

print('Stage 9 final fail-closed hardening applied')
