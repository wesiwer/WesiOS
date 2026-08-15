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

# The Stage-7 integration patch intentionally switches the staging directory
# only at verification time. Its broad idempotence guard can leave the old
# pre-verification swap call behind, while the helper itself is renamed. Remove
# that stale call explicitly so post-install verification remains rollback-safe.
text = text.replace(
    '      await _replaceDirectoryAtomically(staging, packRoot);\n\n',
    '',
    1,
)
if '_replaceDirectoryAtomically(' in text:
    raise SystemExit('stale atomic replacement call remains')
if '_switchDirectoryForVerification(' not in text:
    raise SystemExit('verification-time atomic switch helper missing')

# Managed executable paths must be discovered only after staging has been
# atomically moved into the final pack root. Looking at packRoot before the
# switch produces an empty map for a first install and makes the mandatory
# post-install scan fail even though the artifact is present.
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

# Add a regression that exercises the real Ed25519 verifier instead of only
# fake accept/reject implementations.
test = ROOT / 'test/wesi_runtime_pack_test.dart'
test_text = test.read_text(encoding='utf-8')
if "package:cryptography/cryptography.dart" not in test_text:
    test_text = test_text.replace(
        "import 'package:crypto/crypto.dart';\n",
        "import 'package:crypto/crypto.dart';\nimport 'package:cryptography/cryptography.dart';\n",
        1,
    )
marker = "  group('Pack planning and artifact policy', () {\n"
regression = r'''  test('real Ed25519 descriptor verification accepts valid and rejects tampered payload', () async {
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
if regression not in test_text:
    if marker not in test_text:
        raise SystemExit('test insertion anchor missing')
    test_text = test_text.replace(marker, regression + marker, 1)
# utf8/base64 are used by the real verifier regression.
if "import 'dart:convert';" not in test_text:
    test_text = test_text.replace("import 'dart:io';\n", "import 'dart:convert';\nimport 'dart:io';\n", 1)
test.write_text(test_text, encoding='utf-8')

print('Stage 7 compile/security fix applied')
