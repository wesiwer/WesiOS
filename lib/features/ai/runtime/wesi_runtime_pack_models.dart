import 'dart:io';

import 'wesi_local_runtime_models.dart';

enum WesiRuntimePlatform { windows, linux, macos, unsupported }

enum WesiRuntimePackId { core, developer, browser, documents, media }

enum WesiRuntimeDependencyKind {
  executable,
  sdk,
  workload,
  managedTool,
  sandboxProvider,
}

enum WesiRuntimeDependencyAction { reuse, install, upgrade, unsupported }

enum WesiRuntimeInstallKind { portableFile, zipArchive }

enum WesiRuntimeProbeStream { stdout, stderr, combined }

class WesiRuntimePlatformInfo {
  WesiRuntimePlatformInfo._();

  static WesiRuntimePlatform get current {
    if (Platform.isWindows) return WesiRuntimePlatform.windows;
    if (Platform.isLinux) return WesiRuntimePlatform.linux;
    if (Platform.isMacOS) return WesiRuntimePlatform.macos;
    return WesiRuntimePlatform.unsupported;
  }
}

class WesiRuntimeProbe {
  final List<String> executableNames;
  final List<String> arguments;
  final WesiRuntimeProbeStream versionStream;
  final RegExp? versionPattern;
  final Duration timeout;

  const WesiRuntimeProbe({
    required this.executableNames,
    this.arguments = const <String>[],
    this.versionStream = WesiRuntimeProbeStream.combined,
    this.versionPattern,
    this.timeout = const Duration(seconds: 8),
  });
}

class WesiRuntimeDependencySpec {
  final String id;
  final String title;
  final WesiRuntimeDependencyKind kind;
  final String? minimumVersion;
  final List<WesiRuntimePlatform> platforms;
  final List<WesiRuntimeProbe> probes;
  final bool allowSystemReuse;
  final bool optional;
  final String? managedArtifactId;
  final String? bindingId;
  final WesiLocalSandboxProfile bindingSandboxProfile;
  final bool bindingAllowsArbitraryCode;
  final String description;

  const WesiRuntimeDependencySpec({
    required this.id,
    required this.title,
    required this.kind,
    required this.platforms,
    required this.probes,
    required this.description,
    this.minimumVersion,
    this.allowSystemReuse = true,
    this.optional = false,
    this.managedArtifactId,
    this.bindingId,
    this.bindingSandboxProfile = WesiLocalSandboxProfile.none,
    this.bindingAllowsArbitraryCode = false,
  });

  bool supports(WesiRuntimePlatform platform) => platforms.contains(platform);
}

class WesiRuntimePackSpec {
  final WesiRuntimePackId id;
  final String title;
  final String description;
  final bool required;
  final List<WesiLocalCapability> capabilities;
  final List<WesiRuntimeDependencySpec> dependencies;

  const WesiRuntimePackSpec({
    required this.id,
    required this.title,
    required this.description,
    required this.capabilities,
    required this.dependencies,
    this.required = false,
  });
}

class WesiRuntimeDetectedDependency {
  final String dependencyId;
  final bool detected;
  final String? version;
  final String? executablePath;
  final bool compatible;
  final bool systemInstallation;
  final String? probeOutput;

  const WesiRuntimeDetectedDependency({
    required this.dependencyId,
    required this.detected,
    required this.compatible,
    required this.systemInstallation,
    this.version,
    this.executablePath,
    this.probeOutput,
  });

  static WesiRuntimeDetectedDependency missing(String dependencyId) =>
      WesiRuntimeDetectedDependency(
        dependencyId: dependencyId,
        detected: false,
        compatible: false,
        systemInstallation: false,
      );
}

class WesiRuntimeDependencyPlanItem {
  final WesiRuntimeDependencySpec dependency;
  final WesiRuntimeDependencyAction action;
  final WesiRuntimeDetectedDependency detected;
  final String reason;

  const WesiRuntimeDependencyPlanItem({
    required this.dependency,
    required this.action,
    required this.detected,
    required this.reason,
  });
}

class WesiRuntimePackPlan {
  final WesiRuntimePackSpec pack;
  final WesiRuntimePlatform platform;
  final List<WesiRuntimeDependencyPlanItem> items;

  const WesiRuntimePackPlan({
    required this.pack,
    required this.platform,
    required this.items,
  });

  bool get supported => items.every(
        (item) =>
            item.dependency.optional ||
            item.action != WesiRuntimeDependencyAction.unsupported,
      );

  bool get ready => items.every(
        (item) =>
            item.dependency.optional ||
            item.action == WesiRuntimeDependencyAction.reuse,
      );

  List<WesiRuntimeDependencyPlanItem> get changes => items
      .where((item) =>
          item.action == WesiRuntimeDependencyAction.install ||
          item.action == WesiRuntimeDependencyAction.upgrade)
      .toList(growable: false);
}

class WesiRuntimeScanSnapshot {
  final WesiRuntimePlatform platform;
  final DateTime scannedAt;
  final Map<String, WesiRuntimeDetectedDependency> dependencies;

  const WesiRuntimeScanSnapshot({
    required this.platform,
    required this.scannedAt,
    required this.dependencies,
  });

  WesiRuntimeDetectedDependency get(String id) =>
      dependencies[id] ?? WesiRuntimeDetectedDependency.missing(id);
}

class WesiRuntimeArtifactDescriptor {
  final String id;
  final WesiRuntimePlatform platform;
  final Uri downloadUri;
  final String sha256Hex;
  final String signingKeyId;
  final String signatureBase64;
  final int downloadBytes;
  final int installedBytes;
  final WesiRuntimeInstallKind installKind;
  final String installRelativePath;
  final String? executableRelativePath;
  final String version;

  const WesiRuntimeArtifactDescriptor({
    required this.id,
    required this.platform,
    required this.downloadUri,
    required this.sha256Hex,
    required this.signingKeyId,
    required this.signatureBase64,
    required this.downloadBytes,
    required this.installedBytes,
    required this.installKind,
    required this.installRelativePath,
    required this.version,
    this.executableRelativePath,
  });

  void validateShape() {
    if (id.isEmpty || id.length > 160) {
      throw const FormatException('Invalid runtime artifact id');
    }
    if (downloadUri.scheme.toLowerCase() != 'https' ||
        downloadUri.host.isEmpty ||
        downloadUri.userInfo.isNotEmpty) {
      throw const FormatException(
          'Runtime artifact must use credential-free HTTPS');
    }
    if (!RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256Hex)) {
      throw const FormatException('Invalid SHA-256');
    }
    if (signingKeyId.isEmpty || signatureBase64.isEmpty) {
      throw const FormatException('Signed runtime artifact is required');
    }
    if (downloadBytes <= 0 || installedBytes <= 0) {
      throw const FormatException('Invalid artifact size');
    }
    if (!_safeRelative(installRelativePath) ||
        (executableRelativePath != null &&
            !_safeRelative(executableRelativePath!))) {
      throw const FormatException('Unsafe runtime artifact path');
    }
  }

  static bool _safeRelative(String value) {
    final normalized = value.replaceAll('\\', '/').trim();
    if (normalized.isEmpty || normalized.startsWith('/')) return false;
    if (RegExp(r'^[A-Za-z]:').hasMatch(normalized)) return false;
    return !normalized.split('/').any((part) => part == '..' || part.isEmpty);
  }
}

class WesiRuntimeInstallPreview {
  final WesiRuntimePackPlan plan;
  final List<WesiRuntimeArtifactDescriptor> artifacts;
  final int totalDownloadBytes;
  final int totalInstalledBytes;
  final bool requiresAdministrator;
  final List<String> permissions;

  const WesiRuntimeInstallPreview({
    required this.plan,
    required this.artifacts,
    required this.totalDownloadBytes,
    required this.totalInstalledBytes,
    required this.requiresAdministrator,
    required this.permissions,
  });
}

class WesiRuntimePackActivation {
  final WesiRuntimePackId packId;
  final WesiRuntimeScanSnapshot verifiedSnapshot;
  final WesiLocalRuntimeBindings bindings;
  final Set<WesiLocalCapability> capabilities;

  const WesiRuntimePackActivation({
    required this.packId,
    required this.verifiedSnapshot,
    required this.bindings,
    required this.capabilities,
  });
}
