import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wesios/features/ai/runtime/wesi_local_runtime_executor.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_policy.dart';
import 'package:wesios/features/ai/runtime/wesi_local_workspace.dart';

class _FakeRunner implements WesiLocalProcessRunner {
  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;
  int calls = 0;

  @override
  Future<WesiLocalProcessOutcome> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    required int maxStdoutBytes,
    required int maxStderrBytes,
  }) async {
    calls++;
    this.executable = executable;
    this.arguments = arguments;
    this.workingDirectory = workingDirectory;
    this.environment = environment;
    return const WesiLocalProcessOutcome(
      exitCode: 0,
      stdout: 'ok',
      stderr: '',
      timedOut: false,
      stdoutTruncated: false,
      stderrTruncated: false,
      duration: Duration(milliseconds: 7),
    );
  }
}

Future<Directory> _workspace() =>
    Directory.systemTemp.createTemp('wesios-local-runtime-test-');

void main() {
  test('local capability registry is fail-closed and derives risk', () {
    expect(
      WesiLocalCapabilityRegistry.get(WesiLocalToolNames.fsReadText)?.risk,
      WesiLocalRisk.read,
    );
    expect(
      WesiLocalCapabilityRegistry.get(WesiLocalToolNames.fsDelete)?.risk,
      WesiLocalRisk.destructive,
    );
    expect(WesiLocalCapabilityRegistry.get('local.shell.raw'), isNull);
  });

  test('workspace path policy rejects traversal, absolute and internal state',
      () async {
    final root = await _workspace();
    addTearDown(() => root.delete(recursive: true));
    final context = WesiLocalRuntimeContext(workspaceRoot: root.path);

    expect(
      () => WesiLocalRuntimePolicy.lexicalWorkspacePath(context, '../secret'),
      throwsA(isA<WesiLocalRuntimePolicyException>()),
    );
    expect(
      () => WesiLocalRuntimePolicy.lexicalWorkspacePath(
          context, root.parent.path),
      throwsA(isA<WesiLocalRuntimePolicyException>()),
    );
    expect(
      () => WesiLocalRuntimePolicy.lexicalWorkspacePath(
        context,
        '.wesi/runtime_audit.jsonl',
      ),
      throwsA(
        isA<WesiLocalRuntimePolicyException>().having(
          (e) => e.code,
          'code',
          'WLR_INTERNAL_PATH_FORBIDDEN',
        ),
      ),
    );
  });

  test('symlink cannot escape workspace boundary', () async {
    if (Platform.isWindows) return;
    final root = await _workspace();
    final outside = await Directory.systemTemp.createTemp('wesios-outside-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final secret = File(p.join(outside.path, 'secret.txt'));
    await secret.writeAsString('secret');
    await Link(p.join(root.path, 'escape')).create(outside.path);
    final context = WesiLocalRuntimeContext(workspaceRoot: root.path);

    await expectLater(
      WesiLocalRuntimePolicy.resolveExistingPath(context, 'escape/secret.txt'),
      throwsA(
        isA<WesiLocalRuntimePolicyException>().having(
          (e) => e.code,
          'code',
          'WLR_SYMLINK_FORBIDDEN',
        ),
      ),
    );
  });

  test('file write/read is workspace-bound and delete needs confirmation',
      () async {
    final root = await _workspace();
    addTearDown(() => root.delete(recursive: true));
    const executor = WesiLocalRuntimeExecutor();
    final context = WesiLocalRuntimeContext(workspaceRoot: root.path);

    final write = await executor.execute(
      const WesiLocalToolCall(
        id: 'write-1',
        tool: WesiLocalToolNames.fsWriteText,
        arguments: <String, dynamic>{
          'path': 'docs/a.txt',
          'text': 'hello',
        },
      ),
      context,
    );
    expect(write.ok, isTrue);

    final read = await executor.execute(
      const WesiLocalToolCall(
        id: 'read-1',
        tool: WesiLocalToolNames.fsReadText,
        arguments: <String, dynamic>{'path': 'docs/a.txt'},
      ),
      context,
    );
    expect(read.ok, isTrue);
    expect(read.data['text'], 'hello');

    final deniedDelete = await executor.execute(
      const WesiLocalToolCall(
        id: 'delete-1',
        tool: WesiLocalToolNames.fsDelete,
        arguments: <String, dynamic>{'path': 'docs/a.txt'},
      ),
      context,
    );
    expect(deniedDelete.ok, isFalse);
    expect(deniedDelete.code, 'WLR_CONFIRMATION_REQUIRED');
    expect(await File(p.join(root.path, 'docs', 'a.txt')).exists(), isTrue);

    final allowedDelete = await executor.execute(
      const WesiLocalToolCall(
        id: 'delete-2',
        tool: WesiLocalToolNames.fsDelete,
        arguments: <String, dynamic>{'path': 'docs/a.txt'},
      ),
      context.copyWith(destructiveConfirmed: true),
    );
    expect(allowedDelete.ok, isTrue);
    expect(await File(p.join(root.path, 'docs', 'a.txt')).exists(), isFalse);
  });

  test('terminal cannot use arbitrary or unsandboxed executable bindings',
      () async {
    final root = await _workspace();
    addTearDown(() => root.delete(recursive: true));
    final fake = _FakeRunner();
    final executor = WesiLocalRuntimeExecutor(processRunner: fake);

    final unsandboxed = WesiLocalRuntimeContext(
      workspaceRoot: root.path,
      bindings: const WesiLocalRuntimeBindings(
        executables: <String, WesiLocalExecutableBinding>{
          'python': WesiLocalExecutableBinding(
            id: 'python',
            executablePath: '/trusted/python',
            sandboxed: false,
            allowArbitraryCode: true,
          ),
        },
        terminalAllowlist: <String>{'python'},
      ),
    );
    final denied = await executor.execute(
      const WesiLocalToolCall(
        id: 'terminal-1',
        tool: WesiLocalToolNames.terminalRun,
        arguments: <String, dynamic>{
          'binding': 'python',
          'args': <String>['--version'],
        },
      ),
      unsandboxed,
    );
    expect(denied.ok, isFalse);
    expect(denied.code, 'WLR_SANDBOX_REQUIRED');
    expect(fake.calls, 0);

    final sandboxed = WesiLocalRuntimeContext(
      workspaceRoot: root.path,
      bindings: const WesiLocalRuntimeBindings(
        executables: <String, WesiLocalExecutableBinding>{
          'python': WesiLocalExecutableBinding(
            id: 'python',
            executablePath: '/trusted/python',
            sandboxed: true,
            allowArbitraryCode: true,
          ),
        },
        environment: <String, String>{
          'PATH': '/trusted/bin',
          'AWS_SECRET_ACCESS_KEY': 'must-not-leak',
        },
        terminalAllowlist: <String>{'python'},
      ),
    );
    final allowed = await executor.execute(
      const WesiLocalToolCall(
        id: 'terminal-2',
        tool: WesiLocalToolNames.terminalRun,
        arguments: <String, dynamic>{
          'binding': 'python',
          'args': <String>['--version'],
        },
      ),
      sandboxed,
    );
    expect(allowed.ok, isTrue);
    expect(fake.calls, 1);
    expect(fake.executable, '/trusted/python');
    expect(fake.environment?['PATH'], '/trusted/bin');
    expect(fake.environment?.containsKey('AWS_SECRET_ACCESS_KEY'), isFalse);
    expect(fake.environment?['HOME'], startsWith(root.path));
  });

  test('process arguments cannot point outside workspace', () async {
    final root = await _workspace();
    addTearDown(() => root.delete(recursive: true));
    final context = WesiLocalRuntimeContext(workspaceRoot: root.path);

    expect(
      () => WesiLocalRuntimePolicy.validateArguments(
        <String>['--output=${root.parent.path}/leak.txt'],
        context,
      ),
      throwsA(
        isA<WesiLocalRuntimePolicyException>().having(
          (e) => e.code,
          'code',
          'WLR_ARGUMENT_PATH_ESCAPE',
        ),
      ),
    );
  });

  test('SSRF policy blocks private/special and IPv4-mapped loopback', () {
    expect(
      WesiLocalRuntimePolicy.isPrivateOrSpecialAddress(
        InternetAddress('127.0.0.1'),
      ),
      isTrue,
    );
    expect(
      WesiLocalRuntimePolicy.isPrivateOrSpecialAddress(
        InternetAddress('10.1.2.3'),
      ),
      isTrue,
    );
    expect(
      WesiLocalRuntimePolicy.isPrivateOrSpecialAddress(
        InternetAddress('::1'),
      ),
      isTrue,
    );
    expect(
      WesiLocalRuntimePolicy.isPrivateOrSpecialAddress(
        InternetAddress('::ffff:127.0.0.1'),
      ),
      isTrue,
    );
    expect(
      WesiLocalRuntimePolicy.isPrivateOrSpecialAddress(
        InternetAddress('8.8.8.8'),
      ),
      isFalse,
    );
  });

  test('HTTP credentials and secret headers are rejected', () async {
    final root = await _workspace();
    addTearDown(() => root.delete(recursive: true));
    final context = WesiLocalRuntimeContext(workspaceRoot: root.path);

    expect(
      () => WesiLocalRuntimePolicy.validateHttpUri(
        'https://user:pass@example.com/data',
        context,
      ),
      throwsA(isA<WesiLocalRuntimePolicyException>()),
    );
    expect(
      () => WesiLocalRuntimePolicy.sanitizeHttpHeaders(
        <String, String>{'Authorization': 'Bearer secret'},
      ),
      throwsA(
        isA<WesiLocalRuntimePolicyException>().having(
          (e) => e.code,
          'code',
          'WLR_SECRET_HEADER_FORBIDDEN',
        ),
      ),
    );
  });

  test('workspace service hashes caller ids and audit never stores arguments',
      () async {
    final support = await _workspace();
    addTearDown(() => support.delete(recursive: true));
    final service = WesiLocalWorkspaceService(
      supportDirectoryProvider: () async => support,
    );
    final workspace = await service.open(
      employeeId: 'employee/../../escape',
      workspaceId: 'project/../../escape',
    );
    expect(workspace.rootPath, startsWith(support.path));
    expect(workspace.rootPath, isNot(contains('..')));

    final session = WesiLocalRuntimeSession(workspace: workspace);
    final result = await session.execute(
      const WesiLocalToolCall(
        id: 'audit-1',
        tool: WesiLocalToolNames.fsWriteText,
        arguments: <String, dynamic>{
          'path': 'secret.txt',
          'text': 'TOP_SECRET_CONTENT',
        },
      ),
      workspace.context(),
    );
    expect(result.ok, isTrue);

    final audit =
        File(p.join(workspace.rootPath, '.wesi', 'runtime_audit.jsonl'));
    final raw = await audit.readAsString();
    expect(raw, contains('local.fs.write_text'));
    expect(raw, isNot(contains('TOP_SECRET_CONTENT')));
    expect(raw, isNot(contains('secret.txt')));
  });
}
