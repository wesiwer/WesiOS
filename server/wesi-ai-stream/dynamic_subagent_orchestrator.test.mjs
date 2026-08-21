import test from 'node:test';
import assert from 'node:assert/strict';
import {runDynamicSubagents} from './dynamic_subagent_orchestrator.mjs';

function prepared(overrides = {}) {
  return {
    requestId: 'req-stage13',
    persona: 'zane',
    route: 'pro',
    systemParts: ['base'],
    history: [],
    message: 'Проверь архитектуру и сборку',
    attachments: [],
    subagents: {
      enabled: true,
      maxAgents: 2,
      context: [{kind: 'user_request', label: 'request', text: 'Проверь архитектуру и сборку'}],
      grantedCapabilities: ['repo.read'],
      allowlistedCapabilities: ['repo.read'],
      destructiveCapabilities: ['repo.write'],
      allowedToolNames: ['repo.read'],
      toolDefinitions: [{name: 'repo.read', wesiCapability: {risk: 'READ'}}],
      maxToolTurns: 2,
      maxTotalToolTurns: 2,
      maxOutputChars: 9000,
      maxWorkspaceEdits: 4,
      deadlineMs: 45000,
      workspaceFiles: [{path: 'plan.md', content: 'base', revision: 0}],
    },
    ...overrides,
  };
}

function fetchResponse({json, text = '', status = 200} = {}) {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: async () => json,
    text: async () => text,
  };
}

test('planner may select zero agents', async () => {
  const result = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: async () => JSON.stringify({subagents: []}),
    invokeTool: async () => { throw new Error('must not run'); },
  });
  assert.equal(result.ok, true);
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'planner_selected_none');
});

test('planner cannot exceed maxAgents', async () => {
  let calls = 0;
  const result = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: async ({phase}) => {
      calls += 1;
      if (phase === 'subagent-plan') {
        return JSON.stringify({subagents: [
          {role: 'A', task: 'a'},
          {role: 'B', task: 'b'},
          {role: 'C', task: 'c'},
        ]});
      }
      return JSON.stringify({summary: 'done', findings: [], risks: [], recommendation: ''});
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(result.results.length, 2);
  assert.equal(calls, 3);
});

test('forbidden tool is never executed', async () => {
  let actualToolCalls = 0;
  let specialistTurn = 0;
  const result = await runDynamicSubagents({
    prepared: prepared(),
    invokeModel: async ({phase}) => {
      if (phase === 'subagent-plan') {
        return JSON.stringify({subagents: [{role: 'Reviewer', task: 'review', requestedCapabilities: ['repo.read', 'repo.write']}]});
      }
      specialistTurn += 1;
      if (specialistTurn === 1) return JSON.stringify({wesiTool: {name: 'repo.write', arguments: {}}});
      return JSON.stringify({summary: 'blocked safely', findings: [], risks: [], recommendation: ''});
    },
    invokeTool: async () => {
      actualToolCalls += 1;
      return {ok: true};
    },
  });
  assert.equal(actualToolCalls, 0);
  assert.equal(result.results[0].toolResults[0].code, 'FORBIDDEN');
});

test('shared tool budget is consumed across specialists', async () => {
  const p = prepared();
  p.subagents.maxTotalToolTurns = 1;
  let actualToolCalls = 0;
  const turns = new Map();
  const result = await runDynamicSubagents({
    prepared: p,
    invokeModel: async ({phase, spec}) => {
      if (phase === 'subagent-plan') {
        return JSON.stringify({subagents: [
          {role: 'A', task: 'a', requestedCapabilities: ['repo.read']},
          {role: 'B', task: 'b', requestedCapabilities: ['repo.read']},
        ]});
      }
      const n = (turns.get(spec.agentId) || 0) + 1;
      turns.set(spec.agentId, n);
      if (n === 1) return JSON.stringify({wesiTool: {name: 'repo.read', arguments: {path: 'x'}}});
      return JSON.stringify({summary: 'done', findings: [], risks: [], recommendation: ''});
    },
    invokeTool: async () => {
      actualToolCalls += 1;
      return {ok: true, result: {}};
    },
  });
  assert.equal(actualToolCalls, 1);
  assert.equal(result.remainingToolTurns, 0);
});

test('overlapping virtual workspace edits surface a revision conflict', async () => {
  const p = prepared();
  p.subagents.maxToolTurns = 0;
  let specialist = 0;
  const result = await runDynamicSubagents({
    prepared: p,
    invokeModel: async ({phase}) => {
      if (phase === 'subagent-plan') {
        return JSON.stringify({subagents: [
          {role: 'A', task: 'a', writablePaths: ['plan.md']},
          {role: 'B', task: 'b', writablePaths: ['plan.md']},
        ]});
      }
      specialist += 1;
      return JSON.stringify({
        summary: 'edit', findings: [], risks: [], recommendation: '',
        workspaceEdits: [{path: 'plan.md', operation: 'replace', content: `v${specialist}`, baseRevision: 0}],
      });
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(result.results[0].workspaceResult.applied.length, 1);
  assert.equal(result.results[1].workspaceResult.conflicts[0].code, 'REVISION_CONFLICT');
  assert.equal(result.workspace.files[0].content, 'v1');
});

test('provider prose around planner and specialist JSON is accepted', async () => {
  const p = prepared();
  p.subagents.maxToolTurns = 0;
  const result = await runDynamicSubagents({
    prepared: p,
    invokeModel: async ({phase}) => {
      if (phase === 'subagent-plan') {
        return 'План готов:\n```json\n{"subagents":[{"role":"QA Agent","task":"Проверь сборку"}]}\n```\nПродолжаю.';
      }
      return '<analysis>provider prelude</analysis>\nРезультат:\n{"summary":"checked","findings":[],"risks":[],"recommendation":"ok"}\nГотово.';
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(result.ok, true);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].spec.role, 'QA Agent');
  assert.equal(result.results[0].result.summary, 'checked');
});

test('manual named subagent bypasses planner and runs requested role', async () => {
  const p = prepared({message: 'Позови субагента «Security Reviewer» и поручи ему: Проверь авторизацию'});
  p.subagents.maxToolTurns = 0;
  let plannerCalls = 0;
  const events = [];
  const result = await runDynamicSubagents({
    prepared: p,
    emit: (event) => events.push(event),
    invokeModel: async ({phase, spec}) => {
      if (phase === 'subagent-plan') {
        plannerCalls += 1;
        throw new Error('planner must be bypassed');
      }
      assert.equal(spec.role, 'Security Reviewer');
      assert.equal(spec.task, 'Проверь авторизацию');
      return JSON.stringify({summary: 'security checked', findings: [], risks: [], recommendation: 'ok'});
    },
    invokeTool: async () => ({ok: true}),
  });
  assert.equal(plannerCalls, 0);
  assert.equal(result.results.length, 1);
  assert.equal(result.results[0].spec.role, 'Security Reviewer');
  assert.ok(events.some((event) => event.phase === 'planned' && event.name === 'Security Reviewer'));
});

test('Zane and Nirvana both plan and execute nested The Agency game-development profiles', async () => {
  const originalFetch = globalThis.fetch;
  const agencyTree = {
    tree: [
      {type: 'blob', path: 'game-development/unity/unity-architect.md', sha: 'sha-unity'},
      {type: 'blob', path: 'game-development/godot/godot-shader-developer.md', sha: 'sha-godot'},
      {type: 'blob', path: 'engineering/engineering-backend-architect.md', sha: 'sha-backend'},
      {type: 'blob', path: 'design/design-ui-designer.md', sha: 'sha-ui'},
    ],
  };

  globalThis.fetch = async (url) => {
    const target = String(url);
    if (target.includes('/git/trees/')) return fetchResponse({json: agencyTree});
    if (target.endsWith('/game-development/unity/unity-architect.md')) {
      return fetchResponse({text: '---\nname: Unity Architect\ndescription: Unity systems specialist\n---\nDesign modular Unity runtime architecture.'});
    }
    if (target.endsWith('/game-development/godot/godot-shader-developer.md')) {
      return fetchResponse({text: '---\nname: Godot Shader Developer\ndescription: Godot shader specialist\n---\nBuild efficient Godot shader systems.'});
    }
    throw new Error(`unexpected fetch: ${target}`);
  };

  try {
    const cases = [
      {
        persona: 'zane',
        message: 'Нужна архитектура Unity для игровой системы',
        role: 'Unity Architect',
        marker: 'Design modular Unity runtime architecture.',
      },
      {
        persona: 'nirvana',
        message: 'Нужен Godot shader для визуальной части игры',
        role: 'Godot Shader Developer',
        marker: 'Build efficient Godot shader systems.',
      },
    ];

    for (const item of cases) {
      const p = prepared({persona: item.persona, tier: 'pro', message: item.message});
      p.subagents.maxAgents = 1;
      p.subagents.maxToolTurns = 0;
      const result = await runDynamicSubagents({
        prepared: p,
        invokeModel: async ({phase, input, spec}) => {
          if (phase === 'subagent-plan') {
            assert.match(input.system, /WESI_AI_AGENCY_AGENT_CANDIDATES/);
            assert.ok(input.system.includes(`"name":"${item.role}"`));
            return JSON.stringify({subagents: [{role: item.role, task: item.message}]});
          }
          assert.equal(spec.role, item.role);
          assert.match(input.system, /WESI_AI_AGENCY_AGENT_ADAPTER/);
          assert.ok(input.system.includes(item.marker));
          return JSON.stringify({summary: `${item.role} completed`, findings: [], risks: [], recommendation: 'ok'});
        },
        invokeTool: async () => { throw new Error('tool must not run'); },
      });

      assert.equal(result.ok, true);
      assert.equal(result.results.length, 1);
      assert.equal(result.results[0].ok, true);
      assert.equal(result.results[0].spec.role, item.role);
      assert.equal(result.results[0].agency.repository, 'msitarzewski/agency-agents');
      assert.ok(result.results[0].agency.sourcePath.startsWith('game-development/'));
    }
  } finally {
    globalThis.fetch = originalFetch;
  }
});
