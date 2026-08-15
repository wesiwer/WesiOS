from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

manager = ROOT / 'lib/features/ai/runtime/wesi_runtime_pack_manager.dart'
text = manager.read_text(encoding='utf-8')
text = text.replace("import 'dart:typed_data';\n", '', 1)
text = text.replace(
    "import 'package:pointycastle/export.dart';\n",
    "import 'package:cryptography/cryptography.dart';\n",
    1,
)

pattern = re.compile(
    r"class WesiEd25519RuntimeSignatureVerifier[\s\S]*?(?=class WesiRuntimePackManager)",
)
replacement = '''class WesiEd25519RuntimeSignatureVerifier
    implements WesiRuntimeSignatureVerifier {
  final Map<String, List<int>> publicKeys;

  const WesiEd25519RuntimeSignatureVerifier(this.publicKeys);

  @override
  Future<bool> verifyDescriptor(WesiRuntimeArtifactDescriptor descriptor) async {
    final key = publicKeys[descriptor.signingKeyId];
    if (key == null || key.length != 32) return false;
    try {
      final signatureBytes = base64Decode(descriptor.signatureBase64);
      if (signatureBytes.length != 64) return false;
      final algorithm = Ed25519();
      final publicKey = SimplePublicKey(
        key,
        type: algorithm.keyPairType,
      );
      final signature = Signature(
        signatureBytes,
        publicKey: publicKey,
      );
      return algorithm.verify(
        utf8.encode(signaturePayload(descriptor)),
        signature: signature,
      );
    } catch (_) {
      return false;
    }
  }

  static String signaturePayload(WesiRuntimeArtifactDescriptor descriptor) =>
      <String>[
        'wesi-runtime-artifact-v1',
        descriptor.id,
        descriptor.platform.name,
        descriptor.downloadUri.toString(),
        descriptor.version,
        descriptor.sha256Hex.toLowerCase(),
        '${descriptor.downloadBytes}',
        '${descriptor.installedBytes}',
        descriptor.installKind.name,
        descriptor.installRelativePath,
        descriptor.executableRelativePath ?? '',
      ].join('\\n');
}

'''
text, count = pattern.subn(lambda match: replacement, text, count=1)
if count != 1:
    raise SystemExit('failed to replace Ed25519 verifier')

text = text.replace(
    '      await _replaceDirectoryAtomically(staging, packRoot);\n\n',
    '',
    1,
)
if '_replaceDirectoryAtomically(' in text:
    raise SystemExit('stale atomic replacement call remains')
if '_switchDirectoryForVerification(' not in text:
    raise SystemExit('verification-time atomic switch helper missing')

old_scan = '''      final managedPaths =
          await _managedPathsForPack(preview.plan.pack, packRoot);
      final verificationDependencies =
          <WesiRuntimeDependencySpec>[...preview.plan.pack.dependencies];
      final needsSandbox = preview.plan.pack.dependencies.any(
        (dependency) =>
            dependency.bindingSandboxProfile ==
            WesiLocalSandboxProfile.workspaceV1,
      );
      if (needsSandbox && preview.plan.pack.id != WesiRuntimePackId.core) {
        final corePack = WesiRuntimePackCatalog.byId(WesiRuntimePackId.core);
        final sandboxDependency = corePack.dependencies.firstWhere(
          (dependency) => dependency.id == 'wesi-sandbox',
        );
        verificationDependencies.add(sandboxDependency);
        final coreRoot = Directory(p.join(rootCanonical, WesiRuntimePackId.core.name));
        managedPaths.addAll(await _managedPathsForPack(corePack, coreRoot));
      }
      final backup = await _switchDirectoryForVerification(staging, packRoot);
      try {
        final verified = await scanner.scan(
          verificationDependencies,
          managedExecutablePaths: managedPaths,
        );
'''
new_scan = '''      final verificationDependencies =
          <WesiRuntimeDependencySpec>[...preview.plan.pack.dependencies];
      final needsSandbox = preview.plan.pack.dependencies.any(
        (dependency) =>
            dependency.bindingSandboxProfile ==
            WesiLocalSandboxProfile.workspaceV1,
      );
      final coreManagedPaths = <String, String>{};
      if (needsSandbox && preview.plan.pack.id != WesiRuntimePackId.core) {
        final corePack = WesiRuntimePackCatalog.byId(WesiRuntimePackId.core);
        final sandboxDependency = corePack.dependencies.firstWhere(
          (dependency) => dependency.id == 'wesi-sandbox',
        );
        verificationDependencies.add(sandboxDependency);
        final coreRoot =
            Directory(p.join(rootCanonical, WesiRuntimePackId.core.name));
        coreManagedPaths.addAll(
          await _managedPathsForPack(corePack, coreRoot),
        );
      }
      final backup = await _switchDirectoryForVerification(staging, packRoot);
      try {
        final managedPaths =
            await _managedPathsForPack(preview.plan.pack, packRoot);
        managedPaths.addAll(coreManagedPaths);
        final verified = await scanner.scan(
          verificationDependencies,
          managedExecutablePaths: managedPaths,
        );
'''
if old_scan not in text:
    raise SystemExit('post-install managed path ordering anchor missing')
text = text.replace(old_scan, new_scan, 1)
manager.write_text(text, encoding='utf-8')

# PATH entries used for system reuse must be absolute. Relative PATH components
# can resolve against the app working directory and let an untrusted local file
# impersonate a trusted system runtime during the scanner probe.
scanner = ROOT / 'lib/features/ai/runtime/wesi_environment_scanner.dart'
scanner_text = scanner.read_text(encoding='utf-8')
path_anchor = '''    for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
      final dir = directory.trim();
      if (dir.isEmpty) continue;
      for (final extension in extensions) {
'''
path_replacement = '''    for (final directory in pathValue.split(Platform.isWindows ? ';' : ':')) {
      final dir = directory.trim();
      if (dir.isEmpty || !p.isAbsolute(dir)) continue;
      for (final extension in extensions) {
'''
if path_anchor not in scanner_text:
    raise SystemExit('scanner PATH anchor missing')
scanner.write_text(scanner_text.replace(path_anchor, path_replacement, 1), encoding='utf-8')

# Add regressions for the real Ed25519 implementation, relative PATH rejection,
# and restoration of the previously active pack when post-install verification
# fails after the atomic switch.
test = ROOT / 'test/wesi_runtime_pack_test.dart'
test_text = test.read_text(encoding='utf-8')
if "package:cryptography/cryptography.dart" not in test_text:
    test_text = test_text.replace(
        "import 'package:crypto/crypto.dart';\n",
        "import 'package:crypto/crypto.dart';\nimport 'package:cryptography/cryptography.dart';\n",
        1,
    )
if "import 'dart:convert';" not in test_text:
    test_text = test_text.replace("import 'dart:io';\n", "import 'dart:convert';\nimport 'dart:io';\n", 1)

path_test_anchor = "    test('managed dependency wins over system and no-reuse spec stays managed', () async {\n"
path_test = r'''    test('relative PATH entries are ignored during system reuse scanning', () async {
      final root = await Directory.systemTemp.createTemp('wesi-relative-path-');
      addTearDown(() => root.delete(recursive: true));
      final executable = File(p.join(root.path, 'tool'));
      await executable.writeAsString('fake');
      final relative = p.relative(root.path, from: Directory.current.path);
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
        environment: <String, String>{'PATH': relative},
      );
      final detected = await scanner.scanDependency(_toolSpec());
      expect(detected.detected, isFalse);
      expect(runner.calls, isEmpty);
    });

'''
if path_test not in test_text:
    if path_test_anchor not in test_text:
        raise SystemExit('relative PATH test anchor missing')
    test_text = test_text.replace(path_test_anchor, path_test + path_test_anchor, 1)

crypto_marker = "  group('Pack planning and artifact policy', () {\n"
crypto_test = r'''  test('real Ed25519 descriptor verification accepts valid and rejects tampered payload', () async {
    final algorithm = Ed25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final unsigned = _descriptor(<int>[1, 2, 3]);
    final payload = WesiEd25519RuntimeSignatureVerifier.signaturePayload(unsigned);
    final signed = await algorithm.sign(
      utf8.encode(payload),
      keyPair: keyPair,
    );
    final descriptor = WesiRuntimeArtifactDescriptor(
      id: unsigned.id,
      platform: unsigned.platform,
      downloadUri: unsigned.downloadUri,
      sha256Hex: unsigned.sha256Hex,
      signingKeyId: unsigned.signingKeyId,
      signatureBase64: base64Encode(signed.bytes),
      downloadBytes: unsigned.downloadBytes,
      installedBytes: unsigned.installedBytes,
      installKind: unsigned.installKind,
      installRelativePath: unsigned.installRelativePath,
      executableRelativePath: unsigned.executableRelativePath,
      version: unsigned.version,
    );
    final verifier = WesiEd25519RuntimeSignatureVerifier(
      <String, List<int>>{'test-key': publicKey.bytes},
    );
    expect(await verifier.verifyDescriptor(descriptor), isTrue);

    final tampered = WesiRuntimeArtifactDescriptor(
      id: descriptor.id,
      platform: descriptor.platform,
      downloadUri: Uri.parse('https://runtime.example.invalid/tampered.zip'),
      sha256Hex: descriptor.sha256Hex,
      signingKeyId: descriptor.signingKeyId,
      signatureBase64: descriptor.signatureBase64,
      downloadBytes: descriptor.downloadBytes,
      installedBytes: descriptor.installedBytes,
      installKind: descriptor.installKind,
      installRelativePath: descriptor.installRelativePath,
      executableRelativePath: descriptor.executableRelativePath,
      version: descriptor.version,
    );
    expect(await verifier.verifyDescriptor(tampered), isFalse);
  });

'''
if crypto_test not in test_text:
    if crypto_marker not in test_text:
        raise SystemExit('crypto test anchor missing')
    test_text = test_text.replace(crypto_marker, crypto_test + crypto_marker, 1)

rollback_anchor = "    test('post-install scan is mandatory before a dependency becomes reusable', () async {\n"
rollback_test = r'''    test('failed post-install scan restores the previously active pack', () async {
      final bytes = _zip('bin/tool', const <int>[1, 2, 3]);
      final descriptor = _descriptor(bytes);
      final root = await Directory.systemTemp.createTemp('wesi-pack-rollback-');
      addTearDown(() => root.delete(recursive: true));
      final activeRoot = Directory(p.join(root.path, WesiRuntimePackId.core.name));
      await activeRoot.create(recursive: true);
      final sentinel = File(p.join(activeRoot.path, 'previous.txt'));
      await sentinel.writeAsString('previous-active-pack');

      final manager = WesiRuntimePackManager(
        runtimeRoot: root,
        scanner: WesiEnvironmentScanner(
          runner: _FakeProbeRunner(const <String, WesiRuntimeProbeOutcome>{}),
          platform: WesiRuntimePlatform.linux,
          environment: const <String, String>{'PATH': ''},
        ),
        artifactCatalog: WesiStaticRuntimeArtifactCatalog(
          <String, WesiRuntimeArtifactDescriptor>{
            'linux:tool-package': descriptor,
          },
        ),
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

      await expectLater(
        manager.installAndActivate(
          await manager.preview(plan),
          userConfirmed: true,
        ),
        throwsA(
          isA<WesiRuntimePackException>().having(
            (e) => e.code,
            'code',
            'WRP_POST_SCAN_FAILED',
          ),
        ),
      );
      expect(await sentinel.exists(), isTrue);
      expect(await sentinel.readAsString(), 'previous-active-pack');
      expect(
        await File(p.join(activeRoot.path, 'tool', 'bin', 'tool')).exists(),
        isFalse,
      );
    });

'''
if rollback_test not in test_text:
    if rollback_anchor not in test_text:
        raise SystemExit('rollback test anchor missing')
    test_text = test_text.replace(rollback_anchor, rollback_test + rollback_anchor, 1)

test.write_text(test_text, encoding='utf-8')

print('Stage 7 compile/security fix applied')
