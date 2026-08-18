import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:cryptography/cryptography.dart';

import 'wesi_environment_scanner.dart';
import 'wesi_local_runtime_models.dart';
import 'wesi_local_runtime_policy.dart';
import 'wesi_runtime_pack_models.dart';
import 'wesi_runtime_pack_catalog.dart';

class WesiRuntimePackException implements Exception {
  final String code;
  final String message;

  const WesiRuntimePackException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

abstract class WesiRuntimeArtifactCatalog {
  Future<WesiRuntimeArtifactDescriptor?> resolve(
    String artifactId,
    WesiRuntimePlatform platform,
  );
}

class WesiStaticRuntimeArtifactCatalog implements WesiRuntimeArtifactCatalog {
  final Map<String, WesiRuntimeArtifactDescriptor> artifacts;

  const WesiStaticRuntimeArtifactCatalog(this.artifacts);

  String _key(String id, WesiRuntimePlatform platform) =>
      '${platform.name}:$id';

  @override
  Future<WesiRuntimeArtifactDescriptor?> resolve(
    String artifactId,
    WesiRuntimePlatform platform,
  ) async =>
      artifacts[_key(artifactId, platform)];
}

abstract class WesiRuntimeDownloadClient {
  Future<File> download(
    WesiRuntimeArtifactDescriptor descriptor,
    File destination,
  );
}

class WesiIoRuntimeDownloadClient implements WesiRuntimeDownloadClient {
  const WesiIoRuntimeDownloadClient();

  @override
  Future<File> download(
    WesiRuntimeArtifactDescriptor descriptor,
    File destination,
  ) async {
    descriptor.validateShape();
    final uri = descriptor.downloadUri;
    final addresses = await InternetAddress.lookup(uri.host);
    if (addresses.isEmpty ||
        addresses.any(WesiLocalRuntimePolicy.isPrivateOrSpecialAddress)) {
      throw const WesiRuntimePackException(
        'WRP_DOWNLOAD_SSRF_BLOCKED',
        'Runtime artifact destination is private or special',
      );
    }
    final address = addresses.first;
    final expectedHost = uri.host.toLowerCase();
    final expectedPort = uri.hasPort ? uri.port : 443;
    final client = HttpClient();
    client.findProxy = (_) => 'DIRECT';
    client.connectionTimeout = const Duration(seconds: 20);
    client.connectionFactory = (url, proxyHost, proxyPort) {
      final port = url.hasPort ? url.port : 443;
      if (proxyHost != null ||
          proxyPort != null ||
          url.scheme.toLowerCase() != 'https' ||
          url.host.toLowerCase() != expectedHost ||
          port != expectedPort) {
        throw const WesiRuntimePackException(
          'WRP_DOWNLOAD_TARGET_CHANGED',
          'Runtime artifact connection target changed after validation',
        );
      }
      return Socket.startConnect(address, port);
    };

    await destination.parent.create(recursive: true);
    final sink = destination.openWrite(mode: FileMode.writeOnly);
    var written = 0;
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.isRedirect) {
        throw const WesiRuntimePackException(
          'WRP_DOWNLOAD_REDIRECT_BLOCKED',
          'Signed runtime artifact URLs must not redirect',
        );
      }
      if (response.statusCode != HttpStatus.ok) {
        throw WesiRuntimePackException(
          'WRP_DOWNLOAD_STATUS',
          'Runtime artifact download failed with HTTP ${response.statusCode}',
        );
      }
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        written += chunk.length;
        if (written > descriptor.downloadBytes) {
          throw const WesiRuntimePackException(
            'WRP_DOWNLOAD_SIZE_MISMATCH',
            'Runtime artifact exceeds signed size',
          );
        }
        sink.add(chunk);
      }
      await sink.flush();
      if (written != descriptor.downloadBytes) {
        throw const WesiRuntimePackException(
          'WRP_DOWNLOAD_SIZE_MISMATCH',
          'Runtime artifact size does not match signed catalog',
        );
      }
      return destination;
    } finally {
      await sink.close();
      client.close(force: true);
    }
  }
}

abstract class WesiRuntimeSignatureVerifier {
  Future<bool> verifyDescriptor(WesiRuntimeArtifactDescriptor descriptor);
}

class WesiEd25519RuntimeSignatureVerifier
    implements WesiRuntimeSignatureVerifier {
  final Map<String, List<int>> publicKeys;

  const WesiEd25519RuntimeSignatureVerifier(this.publicKeys);

  @override
  Future<bool> verifyDescriptor(
      WesiRuntimeArtifactDescriptor descriptor) async {
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
      ].join('\n');
}

class WesiRuntimePackManager {
  final Directory runtimeRoot;
  final WesiEnvironmentScanner scanner;
  final WesiRuntimeArtifactCatalog artifactCatalog;
  final WesiRuntimeDownloadClient downloader;
  final WesiRuntimeSignatureVerifier signatureVerifier;

  const WesiRuntimePackManager({
    required this.runtimeRoot,
    required this.scanner,
    required this.artifactCatalog,
    required this.signatureVerifier,
    this.downloader = const WesiIoRuntimeDownloadClient(),
  });

  WesiRuntimePackPlan plan(
    WesiRuntimePackSpec pack,
    WesiRuntimeScanSnapshot snapshot,
  ) {
    final items = <WesiRuntimeDependencyPlanItem>[];
    for (final dependency in pack.dependencies) {
      final detected = snapshot.get(dependency.id);
      if (!dependency.supports(snapshot.platform)) {
        items.add(WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.unsupported,
          detected: detected,
          reason: 'Dependency is unsupported on ${snapshot.platform.name}.',
        ));
        continue;
      }
      if (detected.detected && detected.compatible) {
        items.add(WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.reuse,
          detected: detected,
          reason: detected.systemInstallation
              ? 'Compatible system installation will be reused.'
              : 'Compatible managed installation will be reused.',
        ));
        continue;
      }
      if (dependency.managedArtifactId == null) {
        items.add(WesiRuntimeDependencyPlanItem(
          dependency: dependency,
          action: WesiRuntimeDependencyAction.unsupported,
          detected: detected,
          reason: detected.detected
              ? 'Installed version is incompatible and no managed upgrade exists.'
              : 'Dependency is missing and no managed installer exists.',
        ));
        continue;
      }
      items.add(WesiRuntimeDependencyPlanItem(
        dependency: dependency,
        action: detected.detected
            ? WesiRuntimeDependencyAction.upgrade
            : WesiRuntimeDependencyAction.install,
        detected: detected,
        reason: detected.detected
            ? 'Installed version is below the required compatibility floor.'
            : 'Dependency is missing.',
      ));
    }
    return WesiRuntimePackPlan(
      pack: pack,
      platform: snapshot.platform,
      items: List<WesiRuntimeDependencyPlanItem>.unmodifiable(items),
    );
  }

  Future<WesiRuntimeInstallPreview> preview(WesiRuntimePackPlan plan) async {
    final artifacts = <WesiRuntimeArtifactDescriptor>[];
    var downloadBytes = 0;
    var installedBytes = 0;
    for (final item in plan.changes) {
      final artifactId = item.dependency.managedArtifactId;
      if (artifactId == null) continue;
      final descriptor =
          await artifactCatalog.resolve(artifactId, plan.platform);
      if (descriptor == null) {
        if (item.dependency.optional) continue;
        throw WesiRuntimePackException(
          'WRP_ARTIFACT_UNAVAILABLE',
          'No signed runtime artifact is available for ${item.dependency.id}',
        );
      }
      descriptor.validateShape();
      if (descriptor.id != artifactId || descriptor.platform != plan.platform) {
        throw const WesiRuntimePackException(
          'WRP_ARTIFACT_MISMATCH',
          'Runtime artifact does not match requested dependency/platform',
        );
      }
      if (!await signatureVerifier.verifyDescriptor(descriptor)) {
        throw const WesiRuntimePackException(
          'WRP_SIGNATURE_INVALID',
          'Runtime artifact catalog signature is invalid',
        );
      }
      artifacts.add(descriptor);
      downloadBytes += descriptor.downloadBytes;
      installedBytes += descriptor.installedBytes;
    }
    return WesiRuntimeInstallPreview(
      plan: plan,
      artifacts: List<WesiRuntimeArtifactDescriptor>.unmodifiable(artifacts),
      totalDownloadBytes: downloadBytes,
      totalInstalledBytes: installedBytes,
      requiresAdministrator: false,
      permissions: const <String>[
        'Write only inside WesiOS managed runtime directory',
        'Network only to signed HTTPS artifact URLs',
        'Post-install executable/version verification',
      ],
    );
  }

  Future<WesiRuntimePackActivation> installAndActivate(
    WesiRuntimeInstallPreview preview, {
    required bool userConfirmed,
  }) async {
    if (!userConfirmed) {
      throw const WesiRuntimePackException(
        'WRP_CONFIRMATION_REQUIRED',
        'Runtime Pack installation requires explicit user confirmation',
      );
    }
    if (!preview.plan.supported) {
      throw const WesiRuntimePackException(
        'WRP_PACK_UNSUPPORTED',
        'Runtime Pack contains unsupported required dependencies',
      );
    }

    await runtimeRoot.create(recursive: true);
    final rootCanonical = p.normalize(p.absolute(runtimeRoot.path));
    final packRoot =
        Directory(p.join(rootCanonical, preview.plan.pack.id.name));
    final staging = Directory(
      p.join(
        rootCanonical,
        '.stage-${preview.plan.pack.id.name}-${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}',
      ),
    );
    await staging.create(recursive: true);
    try {
      if (await packRoot.exists()) await _copyDirectory(packRoot, staging);
      for (final descriptor in preview.artifacts) {
        final downloadFile = File(
          p.join(staging.path, '.downloads', '${descriptor.id}.package'),
        );
        await downloader.download(descriptor, downloadFile);
        await _verifyDownloadedFile(descriptor, downloadFile);
        await _installArtifact(descriptor, downloadFile, staging);
        if (await downloadFile.exists()) await downloadFile.delete();
      }
      final downloads = Directory(p.join(staging.path, '.downloads'));
      if (await downloads.exists()) await downloads.delete(recursive: true);
      final verificationDependencies = <WesiRuntimeDependencySpec>[
        ...preview.plan.pack.dependencies
      ];
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
        final verifiedPlan = plan(preview.plan.pack, verified);
        final blockers = verifiedPlan.items.where(
          (item) =>
              !item.dependency.optional &&
              item.action != WesiRuntimeDependencyAction.reuse,
        );
        if (blockers.isNotEmpty) {
          throw WesiRuntimePackException(
            'WRP_POST_SCAN_FAILED',
            'Installed Runtime Pack did not pass post-install verification: '
                '${blockers.map((item) => item.dependency.id).join(', ')}',
          );
        }
        final activation =
            _activation(preview.plan.pack, verified, managedPaths);
        if (await backup.exists()) await backup.delete(recursive: true);
        return activation;
      } catch (_) {
        if (await packRoot.exists()) await packRoot.delete(recursive: true);
        if (await backup.exists()) await backup.rename(packRoot.path);
        rethrow;
      }
    } catch (_) {
      if (await staging.exists()) await staging.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> _verifyDownloadedFile(
    WesiRuntimeArtifactDescriptor descriptor,
    File file,
  ) async {
    if (!await signatureVerifier.verifyDescriptor(descriptor)) {
      throw const WesiRuntimePackException(
        'WRP_SIGNATURE_INVALID',
        'Runtime artifact signature verification failed',
      );
    }
    final stat = await file.stat();
    if (stat.size != descriptor.downloadBytes) {
      throw const WesiRuntimePackException(
        'WRP_DOWNLOAD_SIZE_MISMATCH',
        'Runtime artifact size changed before installation',
      );
    }
    final digest = await sha256.bind(file.openRead()).first;
    if (digest.toString().toLowerCase() != descriptor.sha256Hex.toLowerCase()) {
      throw const WesiRuntimePackException(
        'WRP_CHECKSUM_MISMATCH',
        'Runtime artifact SHA-256 mismatch',
      );
    }
  }

  Future<void> _installArtifact(
    WesiRuntimeArtifactDescriptor descriptor,
    File package,
    Directory staging,
  ) async {
    final destination =
        _safeInstallPath(staging.path, descriptor.installRelativePath);
    if (descriptor.installKind == WesiRuntimeInstallKind.portableFile) {
      await File(destination).parent.create(recursive: true);
      await package.copy(destination);
      return;
    }
    if (descriptor.downloadBytes > 256 * 1024 * 1024) {
      throw const WesiRuntimePackException(
        'WRP_ARCHIVE_TOO_LARGE',
        'Managed ZIP exceeds safe in-process extraction limit',
      );
    }
    final archive = ZipDecoder().decodeBytes(
      await package.readAsBytes(),
      verify: true,
    );
    if (archive.length > 10000) {
      throw const WesiRuntimePackException(
        'WRP_ARCHIVE_TOO_MANY_FILES',
        'Runtime archive contains too many entries',
      );
    }
    var expanded = 0;
    final destinationRoot = Directory(destination);
    await destinationRoot.create(recursive: true);
    for (final entry in archive) {
      final name = entry.name.replaceAll('\\', '/');
      if (!entry.isFile && !name.endsWith('/')) {
        throw const WesiRuntimePackException(
          'WRP_ARCHIVE_ENTRY_INVALID',
          'Runtime archive contains a special/symlink-like entry',
        );
      }
      final pathName = !entry.isFile && name.endsWith('/')
          ? name.substring(0, name.length - 1)
          : name;
      final output = _safeInstallPath(destinationRoot.path, pathName);
      if (entry.isFile) {
        expanded += entry.size;
        if (expanded > descriptor.installedBytes) {
          throw const WesiRuntimePackException(
            'WRP_ARCHIVE_EXPANSION_LIMIT',
            'Runtime archive exceeds signed installed-size bound',
          );
        }
        final content = entry.content;
        if (content is! List<int>) {
          throw const WesiRuntimePackException(
            'WRP_ARCHIVE_ENTRY_INVALID',
            'Runtime archive contains an unsupported entry',
          );
        }
        await File(output).parent.create(recursive: true);
        await File(output).writeAsBytes(content, flush: true);
      } else {
        await Directory(output).create(recursive: true);
      }
    }
  }

  static String _safeInstallPath(String root, String relative) {
    final clean = relative.replaceAll('\\', '/').trim();
    if (clean.isEmpty ||
        clean.contains('\u0000') ||
        clean.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(clean) ||
        clean.split('/').any((part) => part.isEmpty || part == '..')) {
      throw const WesiRuntimePackException(
        'WRP_INSTALL_PATH_ESCAPE',
        'Runtime artifact path escapes managed root',
      );
    }
    final base = p.normalize(p.absolute(root));
    final candidate = p.normalize(p.absolute(p.join(base, clean)));
    if (candidate == base || !p.isWithin(base, candidate)) {
      throw const WesiRuntimePackException(
        'WRP_INSTALL_PATH_ESCAPE',
        'Runtime artifact path escapes managed root',
      );
    }
    return candidate;
  }

  Future<Map<String, String>> _managedPathsForPack(
    WesiRuntimePackSpec pack,
    Directory packRoot,
  ) async {
    final paths = <String, String>{};
    for (final dependency in pack.dependencies) {
      final artifactId = dependency.managedArtifactId;
      if (artifactId == null) continue;
      final descriptor =
          await artifactCatalog.resolve(artifactId, scanner.platform);
      if (descriptor == null) continue;
      final installRoot = _safeInstallPath(
        packRoot.path,
        descriptor.installRelativePath,
      );
      final executable =
          descriptor.installKind == WesiRuntimeInstallKind.portableFile
              ? installRoot
              : descriptor.executableRelativePath == null
                  ? ''
                  : _safeInstallPath(
                      installRoot,
                      descriptor.executableRelativePath!,
                    );
      if (executable.isEmpty) continue;
      if (File(executable).existsSync()) paths[dependency.id] = executable;
    }
    return paths;
  }

  WesiRuntimePackActivation _activation(
    WesiRuntimePackSpec pack,
    WesiRuntimeScanSnapshot snapshot,
    Map<String, String> managedPaths,
  ) {
    final sandbox = snapshot.get('wesi-sandbox');
    String? sandboxPath = sandbox.detected && sandbox.compatible
        ? sandbox.executablePath
        : managedPaths['wesi-sandbox'];
    final executables = <String, WesiLocalExecutableBinding>{};
    final terminal = <String>{};

    for (final dependency in pack.dependencies) {
      final bindingId = dependency.bindingId;
      if (bindingId == null) continue;
      final detected = snapshot.get(dependency.id);
      if (!detected.detected ||
          !detected.compatible ||
          detected.executablePath == null) {
        continue;
      }
      if (dependency.bindingSandboxProfile ==
          WesiLocalSandboxProfile.workspaceV1) {
        if (sandboxPath == null || sandboxPath.isEmpty) {
          throw const WesiRuntimePackException(
            'WRP_SANDBOX_MISSING',
            'workspaceV1 activation requires the verified Core sandbox provider',
          );
        }
        executables[bindingId] = WesiLocalExecutableBinding(
          id: bindingId,
          executablePath: sandboxPath,
          sandboxTargetPath: detected.executablePath,
          sandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          allowArbitraryCode: dependency.bindingAllowsArbitraryCode,
        );
        terminal.add(bindingId);
      } else {
        executables[bindingId] = WesiLocalExecutableBinding(
          id: bindingId,
          executablePath: detected.executablePath!,
          sandboxProfile: WesiLocalSandboxProfile.none,
          allowArbitraryCode: false,
        );
      }
    }

    return WesiRuntimePackActivation(
      packId: pack.id,
      verifiedSnapshot: snapshot,
      bindings: WesiLocalRuntimeBindings(
        executables:
            Map<String, WesiLocalExecutableBinding>.unmodifiable(executables),
        terminalAllowlist: Set<String>.unmodifiable(terminal),
      ),
      capabilities: Set<WesiLocalCapability>.unmodifiable(pack.capabilities),
    );
  }

  static Future<void> _copyDirectory(Directory source, Directory target) async {
    await for (final entity
        in source.list(recursive: false, followLinks: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.link) continue;
      final destination = p.join(target.path, p.basename(entity.path));
      if (type == FileSystemEntityType.directory) {
        final directory = Directory(destination);
        await directory.create(recursive: true);
        await _copyDirectory(Directory(entity.path), directory);
      } else if (type == FileSystemEntityType.file) {
        await File(entity.path).copy(destination);
      }
    }
  }

  static Future<Directory> _switchDirectoryForVerification(
    Directory staging,
    Directory target,
  ) async {
    final backup = Directory('${target.path}.previous');
    if (await backup.exists()) await backup.delete(recursive: true);
    if (await target.exists()) await target.rename(backup.path);
    try {
      await staging.rename(target.path);
      return backup;
    } catch (_) {
      if (await target.exists()) await target.delete(recursive: true);
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    }
  }
}
