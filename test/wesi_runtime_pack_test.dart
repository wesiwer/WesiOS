import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wesios/features/ai/runtime/wesi_environment_scanner.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_executor.dart';
import 'package:wesios/features/ai/runtime/wesi_local_runtime_models.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_manager.dart';
import 'package:wesios/features/ai/runtime/wesi_runtime_pack_models.dart';

class _FakeProbeRunner implements WesiRuntimeProbeRunner {
  final Map<String, WesiRuntimeProbeOutcome> outcomes;
  final List<List<String>> calls = <List<String>>[];

  _FakeProbeRunner(this.outcomes);

  @override
  Future<WesiRuntimeProbeOutcome> run({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
  }) async {
    calls.add(<String>[executable, ...arguments]);
    return outcomes[p.basename(executable)] ??
        const WesiRuntimeProbeOutcome(
          exitCode: 1,
          stdout: '',
          stderr: '',
          timedOut: false,
        );
  }
}

class _AcceptSignature implements WesiRuntimeSignatureVerifier {
  const _AcceptSignature();

  @override
  Future<bool> verifyDescriptor(WesiRuntimeArtifactDescriptor descriptor) async =>
      true;
}

class _RejectSignature implements WesiRuntimeSignatureVerifier {
  const _RejectSignature();

  @override
  Future<bool> verifyDescriptor(WesiRuntimeArtifactDescriptor descriptor) async =>
      false;
}

class _BytesDownloader implements WesiRuntimeDownloadClient {
  final List<int> bytes;
  int calls = 0;

  _BytesDownloader(this.bytes);

  @override
  Future<File> download(
    WesiRuntimeArtifactDescriptor descriptor,
    File destination,
  ) async {
    calls++;
    await destination.parent.create(recursive: true);
    return destination.writeAsBytes(bytes, flush: true);
  }
}

class _FakeLocalRunner implements WesiLocalProcessRunner {
  String? executable;
  List<String>? arguments;
  String? workingDirectory;

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
    this.executable = executable;
    this.arguments = List<String>.from(arguments);
    this.workingDirectory = workingDirectory;
    return const WesiLocalProcessOutcome(
      exitCode: 0,
      stdout: 'ok',
      stderr: '',
      timedOut: false,
      stdoutTruncated: false,
      stderrTruncated: false,
      duration: Duration(milliseconds: 2),
    );
  }
}

WesiRuntimeDependencySpec _toolSpec({
  String minimumVersion = '2.0.0',
  String? managedArtifactId = 'tool-package',
}) =>
    WesiRuntimeDependencySpec(
      id: 'tool',
      title: 'Tool',
      kind: WesiRuntimeDependencyKind.executable,
      minimumVersion: minimumVersion,
      platforms: const <WesiRuntimePlatform>[WesiRuntimePlatform.linux],
      managedArtifactId: managedArtifactId,
      description: 'test tool',
      probes: <WesiRuntimeProbe>[
        WesiRuntimeProbe(
          executableNames: const <String>['tool'],
          arguments: const <String>['--version'],
          versionPattern: RegExp(r'Tool\s+([0-9]+(?:\.[0-9]+)+)'),
        ),
      ],
    );

WesiRuntimePackSpec _pack(WesiRuntimeDependencySpec dependency) =>
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.core,
      title: 'Test Pack',
      description: 'test',
      capabilities: const <WesiLocalCapability>[],
      dependencies: <WesiRuntimeDependencySpec>[dependency],
    );

WesiRuntimeArtifactDescriptor _descriptor(
  List<int> bytes, {
  String hashOverride = '',
  WesiRuntimeInstallKind kind = WesiRuntimeInstallKind.zipArchive,
  String installRelativePath = 'tool',
  String? executableRelativePath = 'bin/tool',
}) =>
    WesiRuntimeArtifactDescriptor(
      id: 'tool-package',
      platform: WesiRuntimePlatform.linux,
      downloadUri: Uri.parse('https://runtime.example.invalid/tool.zip'),
      sha256Hex: hashOverride.isEmpty ? sha256.convert(bytes).toString() : hashOverride,
      signingKeyId: 'test-key',
      signatureBase64: 'AA==',
      downloadBytes: bytes.length,
      installedBytes: 1024 * 1024,
      installKind: kind,
      installRelativePath: installRelativePath,
      executableRelativePath: executableRelativePath,
      version: '2.4.0',
    );

List<int> _zip(String name, List<int> bytes) {
  final archive = Archive()..addFile(ArchiveFile(name, bytes.length, bytes));
  return ZipEncoder().encode(archive)!;
}

void main() {
  group('Environment Scanner', () {
    test('compares numeric versions without lexicographic mistakes', () {
      expect(WesiEnvironmentScanner.compareVersions('3.11.9', '3.9.20'), greaterThan(0));
      expect(WesiEnvironmentScanner.compareVersions('20.0.0', '20'), 0);
      expect(WesiEnvironmentScanner.compareVersions('17.0.1', '17.0.2'), lessThan(0));
    });

    test('reuses a compatible PATH dependency and executes fixed probe only', () async {
      final root = await Directory.systemTemp.createTemp('wesi-scan-');
      addTearDown(() => root.delete(recursive: true));
      final executable = File(p.join(root.path, 'tool'));
      await executable.writeAsString('fake');
      final runner = _FakeProbeRunner(<String, WesiRuntimeProbeOutcome>{
        'tool': const WesiRuntimeProbeOutcome(
          exitCode: 0,
          stdout: 'Tool 2.4.1',
          stderr: '',
          timedOut: false,
        ),
      });
      final scanner = WesiEnvironmentScanner(
        runner: runner,
        platform: WesiRuntimePlatform.linux,
        environment: <String, String>{'PATH': root.path},
      );
      final detected = await scanner.scanDependency(_toolSpec());
      expect(detected.detected, isTrue);
      expect(detected.compatible, isTrue);
      expect(detected.systemInstallation, isTrue);
      expect(detected.version, '2.4.1');
      expect(runner.calls, hasLength(1));
      expect(runner.calls.single.skip(1), <String>['--version']);
    });

    test('managed dependency wins over system and no-reuse spec stays managed', () async {
      final root = await Directory.systemTemp.createTemp('wesi-managed-');
      addTearDown(() => root.delete(recursive: true));
      final managed = File(p.join(root.path, 'wesi-sandbox'));
      await managed.writeAsString('fake');
      final runner = _FakeProbeRunner(<String, WesiRuntimeProbeOutcome>{
        'wesi-sandbox': const WesiRuntimeProbeOutcome(
          exitCode: 0,
          stdout: 'workspace-v1 1.2.0',
          stderr: '',
          timedOut: false,
        ),
      });
      final scanner = WesiEnvironmentScanner(
        runner: runner,
        platform: WesiRuntimePlatform.linux,
        environment: const <String, String>{'PATH': ''},
      );
      final spec = WesiRuntimeDependencySpec(
        id: 'sandbox',
        title: 'Sandbox',
        kind: WesiRuntimeDependencyKind.sandboxProvider,
        minimumVersion: '1.0.0',
        platforms: const <WesiRuntimePlatform>[WesiRuntimePlatform.linux],
        allowSystemReuse: false,
        description: 'sandbox',
        probes: <WesiRuntimeProbe>[
          WesiRuntimeProbe(
            executableNames: const <String>['wesi-sandbox'],
            arguments: const <String>['--contract-version'],
            versionPattern: RegExp(r'workspace-v1\s+([0-9]+(?:\.[0-9]+)+)'),
          ),
        ],
      );
      final detected = await scanner.scanDependency(
        spec,
        managedExecutablePath: managed.path,
      );
      expect(detected.detected, isTrue);
      expect(detected.systemInstallation, isFalse);
      expect(detected.compatible, isTrue);
    });
  });

  group('Pack planning and artifact policy', () {
    test('plan chooses reuse, upgrade, install and unsupported deterministically', () {
      final dependency = _toolSpec();
      final manager = WesiRuntimePackManager(
        runtimeRoot: Directory.systemTemp,
        scanner: WesiEnvironmentScanner(platform: WesiRuntimePlatform.linux),
        artifactCatalog: const WesiStaticRuntimeArtifactCatalog(<String, WesiRuntimeArtifactDescriptor>{}),
        signatureVerifier: const _AcceptSignature(),
      );
      WesiRuntimePackPlan planFor(WesiRuntimeDetectedDependency detected) =>
          manager.plan(
            _pack(dependency),
            WesiRuntimeScanSnapshot(
              platform: WesiRuntimePlatform.linux,
              scannedAt: DateTime.utc(2026),
              dependencies: <String, WesiRuntimeDetectedDependency>{'tool': detected},
            ),
          );

      expect(
        planFor(const WesiRuntimeDetectedDependency(
          dependencyId: 'tool',
          detected: true,
          version: '2.5.0',
          executablePath: '/tool',
          compatible: true,
          systemInstallation: true,
        )).items.single.action,
        WesiRuntimeDependencyAction.reuse,
      );
      expect(
        planFor(const WesiRuntimeDetectedDependency(
          dependencyId: 'tool',
          detected: true,
          version: '1.0.0',
          executablePath: '/tool',
          compatible: false,
          systemInstallation: true,
        )).items.single.action,
        WesiRuntimeDependencyAction.upgrade,
      );
      expect(
        planFor(WesiRuntimeDetectedDependency.missing('tool')).items.single.action,
        WesiRuntimeDependencyAction.install,
      );
      final unsupported = manager.plan(
        _pack(dependency),
        WesiRuntimeScanSnapshot(
          platform: WesiRuntimePlatform.windows,
          scannedAt: DateTime.utc(2026),
          dependencies: const <String, WesiRuntimeDetectedDependency>{},
        ),
      );
      expect(unsupported.items.single.action, WesiRuntimeDependencyAction.unsupported);
    });

    test('artifact descriptor rejects credentials, insecure URL and traversal', () {
      final base = _descriptor(const <int>[1]);
      expect(() => base.validateShape(), returnsNormally);
      final bad = WesiRuntimeArtifactDescriptor(
        id: base.id,
        platform: base.platform,
        downloadUri: Uri.parse('http://user:pass@example.com/a'),
        sha256Hex: base.sha256Hex,
        signingKeyId: base.signingKeyId,
        signatureBase64: base.signatureBase64,
        downloadBytes: base.downloadBytes,
        installedBytes: base.installedBytes,
        installKind: base.installKind,
        installRelativePath: '../escape',
        executableRelativePath: base.executableRelativePath,
        version: base.version,
      );
      expect(() => bad.validateShape(), throwsFormatException);
    });

    test('preview fails closed when catalog signature is rejected', () async {
      final bytes = _zip('bin/tool', const <int>[1, 2, 3]);
      final descriptor = _descriptor(bytes);
      final manager = WesiRuntimePackManager(
        runtimeRoot: Directory.systemTemp,
        scanner: WesiEnvironmentScanner(platform: WesiRuntimePlatform.linux),
        artifactCatalog: WesiStaticRuntimeArtifactCatalog(<String, WesiRuntimeArtifactDescriptor>{
          'linux:tool-package': descriptor,
        }),
        signatureVerifier: const _RejectSignature(),
      );
      final plan = manager.plan(
        _pack(_toolSpec()),
        WesiRuntimeScanSnapshot(
          platform: WesiRuntimePlatform.linux,
          scannedAt: DateTime.utc(2026),
          dependencies: <String, WesiRuntimeDetectedDependency>{
            'tool': WesiRuntimeDetectedDependency.missing('tool'),
          },
        ),
      );
      await expectLater(
        manager.preview(plan),
        throwsA(isA<WesiRuntimePackException>()
            .having((e) => e.code, 'code', 'WRP_SIGNATURE_INVALID')),
      );
    });
  });

  group('Verified installation', () {
    test('checksum mismatch aborts before extraction', () async {
      final bytes = _zip('bin/tool', const <int>[1, 2, 3]);
      final descriptor = _descriptor(bytes, hashOverride: '0' * 64);
      final root = await Directory.systemTemp.createTemp('wesi-pack-');
      addTearDown(() => root.delete(recursive: true));
      final runner = _FakeProbeRunner(const <String, WesiRuntimeProbeOutcome>{});
      final manager = WesiRuntimePackManager(
        runtimeRoot: root,
        scanner: WesiEnvironmentScanner(
          runner: runner,
          platform: WesiRuntimePlatform.linux,
          environment: const <String, String>{'PATH': ''},
        ),
        artifactCatalog: WesiStaticRuntimeArtifactCatalog(<String, WesiRuntimeArtifactDescriptor>{
          'linux:tool-package': descriptor,
        }),
        signatureVerifier: const _AcceptSignature(),
        downloader: _BytesDownloader(bytes),
      );
      final plan = manager.plan(
        _pack(_toolSpec()),
        WesiRuntimeScanSnapshot(
          platform: WesiRuntimePlatform.linux,
          scannedAt: DateTime.utc(2026),
          dependencies: <String, WesiRuntimeDetectedDependency>{
            'tool': WesiRuntimeDetectedDependency.missing('tool'),
          },
        ),
      );
      final preview = await manager.preview(plan);
      await expectLater(
        manager.installAndActivate(preview, userConfirmed: true),
        throwsA(isA<WesiRuntimePackException>()
            .having((e) => e.code, 'code', 'WRP_CHECKSUM_MISMATCH')),
      );
    });

    test('ZIP traversal is rejected and cannot escape managed runtime root', () async {
      final bytes = _zip('../escape', const <int>[1, 2, 3]);
      final descriptor = _descriptor(bytes);
      final root = await Directory.systemTemp.createTemp('wesi-pack-');
      addTearDown(() => root.delete(recursive: true));
      final manager = WesiRuntimePackManager(
        runtimeRoot: root,
        scanner: WesiEnvironmentScanner(
          runner: _FakeProbeRunner(const <String, WesiRuntimeProbeOutcome>{}),
          platform: WesiRuntimePlatform.linux,
          environment: const <String, String>{'PATH': ''},
        ),
        artifactCatalog: WesiStaticRuntimeArtifactCatalog(<String, WesiRuntimeArtifactDescriptor>{
          'linux:tool-package': descriptor,
        }),
        signatureVerifier: const _AcceptSignature(),
        downloader: _BytesDownloader(bytes),
      );
      final plan = manager.plan(
        _pack(_toolSpec()),
        WesiRuntimeScanSnapshot(
          platform: WesiRuntimePlatform.linux,
          scannedAt: DateTime.utc(2026),
          dependencies: <String, WesiRuntimeDetectedDependency>{
            'tool': WesiRuntimeDetectedDependency.missing('tool'),
          },
        ),
      );
      final preview = await manager.preview(plan);
      await expectLater(
        manager.installAndActivate(preview, userConfirmed: true),
        throwsA(isA<WesiRuntimePackException>()
            .having((e) => e.code, 'code', 'WRP_INSTALL_PATH_ESCAPE')),
      );
      expect(await File(p.join(root.parent.path, 'escape')).exists(), isFalse);
    });

    test('post-install scan is mandatory before a dependency becomes reusable', () async {
      final bytes = _zip('bin/tool', const <int>[1, 2, 3]);
      final descriptor = _descriptor(bytes);
      final root = await Directory.systemTemp.createTemp('wesi-pack-');
      addTearDown(() => root.delete(recursive: true));
      final runner = _FakeProbeRunner(<String, WesiRuntimeProbeOutcome>{
        'tool': const WesiRuntimeProbeOutcome(
          exitCode: 0,
          stdout: 'Tool 2.4.0',
          stderr: '',
          timedOut: false,
        ),
      });
      final downloader = _BytesDownloader(bytes);
      final manager = WesiRuntimePackManager(
        runtimeRoot: root,
        scanner: WesiEnvironmentScanner(
          runner: runner,
          platform: WesiRuntimePlatform.linux,
          environment: const <String, String>{'PATH': ''},
        ),
        artifactCatalog: WesiStaticRuntimeArtifactCatalog(<String, WesiRuntimeArtifactDescriptor>{
          'linux:tool-package': descriptor,
        }),
        signatureVerifier: const _AcceptSignature(),
        downloader: downloader,
      );
      final plan = manager.plan(
        _pack(_toolSpec()),
        WesiRuntimeScanSnapshot(
          platform: WesiRuntimePlatform.linux,
          scannedAt: DateTime.utc(2026),
          dependencies: <String, WesiRuntimeDetectedDependency>{
            'tool': WesiRuntimeDetectedDependency.missing('tool'),
          },
        ),
      );
      final activation = await manager.installAndActivate(
        await manager.preview(plan),
        userConfirmed: true,
      );
      expect(downloader.calls, 1);
      expect(activation.verifiedSnapshot.get('tool').compatible, isTrue);
      expect(runner.calls, isNotEmpty);
    });
  });

  group('workspaceV1 wrapper contract', () {
    test('executor invokes trusted wrapper with limits and target before model args', () async {
      final root = await Directory.systemTemp.createTemp('wesi-wrapper-');
      addTearDown(() => root.delete(recursive: true));
      final script = File(p.join(root.path, 'script.py'));
      await script.writeAsString('print(1)');
      final runner = _FakeLocalRunner();
      final executor = WesiLocalRuntimeExecutor(processRunner: runner);
      final result = await executor.execute(
        const WesiLocalToolCall(
          id: 'python-wrapper',
          tool: WesiLocalToolNames.pythonRun,
          arguments: <String, dynamic>{
            'script': 'script.py',
            'args': <String>['hello'],
          },
        ),
        WesiLocalRuntimeContext(
          workspaceRoot: root.path,
          limits: const WesiLocalRuntimeLimits(
            maxMemoryBytes: 512 * 1024 * 1024,
            maxWorkspaceBytes: 2 * 1024 * 1024 * 1024,
            maxCpuPercent: 70,
          ),
          bindings: const WesiLocalRuntimeBindings(
            executables: <String, WesiLocalExecutableBinding>{
              'python': WesiLocalExecutableBinding(
                id: 'python',
                executablePath: '/trusted/wesi-sandbox',
                sandboxTargetPath: '/trusted/python',
                sandboxProfile: WesiLocalSandboxProfile.workspaceV1,
                allowArbitraryCode: true,
              ),
            },
          ),
        ),
      );
      expect(result.ok, isTrue);
      expect(runner.executable, '/trusted/wesi-sandbox');
      expect(runner.arguments, containsAllInOrder(<String>[
        '--contract',
        'workspace-v1',
        '--workspace',
        root.path,
        '--memory-bytes',
        '${512 * 1024 * 1024}',
        '--workspace-bytes',
        '${2 * 1024 * 1024 * 1024}',
        '--cpu-percent',
        '70',
        '--network',
        'deny',
        '--target',
        '/trusted/python',
        '--',
        script.path,
        'hello',
      ]));
    });
  });
}
