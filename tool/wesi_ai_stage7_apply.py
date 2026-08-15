from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def replace_once(path: Path, old: str, new: str, label: str) -> None:
    text = path.read_text(encoding='utf-8')
    if new in text:
        return
    if old not in text:
        raise SystemExit(f'missing anchor {label} in {path}')
    path.write_text(text.replace(old, new, 1), encoding='utf-8')


models = ROOT / 'lib/features/ai/runtime/wesi_local_runtime_models.dart'
replace_once(
    models,
    """  /// Versioned isolation contract attested by trusted runtime provisioning.\n  final WesiLocalSandboxProfile sandboxProfile;\n\n  /// Arbitrary scripts/project code may run only through such a binding.\n""",
    """  /// For workspaceV1, executablePath is the trusted Wesi sandbox wrapper.\n  /// The real detected runtime binary is stored separately and never supplied\n  /// by model arguments.\n  final String? sandboxTargetPath;\n\n  /// Versioned isolation contract attested by trusted runtime provisioning.\n  final WesiLocalSandboxProfile sandboxProfile;\n\n  /// Arbitrary scripts/project code may run only through such a binding.\n""",
    'sandbox target field',
)
replace_once(
    models,
    """    required this.id,\n    required this.executablePath,\n    this.sandboxProfile = WesiLocalSandboxProfile.none,\n""",
    """    required this.id,\n    required this.executablePath,\n    this.sandboxTargetPath,\n    this.sandboxProfile = WesiLocalSandboxProfile.none,\n""",
    'sandbox target constructor',
)

policy = ROOT / 'lib/features/ai/runtime/wesi_local_runtime_policy.dart'
replace_once(
    policy,
    """    if (binding == null || binding.executablePath.trim().isEmpty) {\n      throw WesiLocalRuntimePolicyException(\n        'WLR_DEPENDENCY_MISSING',\n        'Не настроен локальный runtime: $id',\n      );\n    }\n    if (requireSandbox &&\n""",
    """    if (binding == null || binding.executablePath.trim().isEmpty) {\n      throw WesiLocalRuntimePolicyException(\n        'WLR_DEPENDENCY_MISSING',\n        'Не настроен локальный runtime: $id',\n      );\n    }\n    if (!p.isAbsolute(binding.executablePath)) {\n      throw WesiLocalRuntimePolicyException(\n        'WLR_BINDING_PATH_INVALID',\n        'Runtime $id должен использовать доверенный абсолютный executable path',\n      );\n    }\n    if (binding.sandboxProfile == WesiLocalSandboxProfile.workspaceV1) {\n      final target = binding.sandboxTargetPath?.trim() ?? '';\n      if (target.isEmpty || !p.isAbsolute(target)) {\n        throw WesiLocalRuntimePolicyException(\n          'WLR_SANDBOX_TARGET_MISSING',\n          'Runtime $id не содержит доверенный target для workspaceV1 wrapper',\n        );\n      }\n    }\n    if (requireSandbox &&\n""",
    'binding validation',
)

executor = ROOT / 'lib/features/ai/runtime/wesi_local_runtime_executor.dart'
replace_once(
    executor,
    """    final outcome = await processRunner.run(\n      executable: binding.executablePath,\n      arguments: arguments,\n      workingDirectory: workingDirectory,\n      environment: WesiLocalRuntimePolicy.sanitizedEnvironment(context),\n      timeout: context.limits.processTimeout,\n      maxStdoutBytes: context.limits.maxStdoutBytes,\n      maxStderrBytes: context.limits.maxStderrBytes,\n    );\n""",
    """    final sandboxed =\n        binding.sandboxProfile == WesiLocalSandboxProfile.workspaceV1;\n    final processArguments = sandboxed\n        ? <String>[\n            '--contract',\n            'workspace-v1',\n            '--workspace',\n            p.normalize(p.absolute(context.workspaceRoot)),\n            '--cwd',\n            workingDirectory,\n            '--memory-bytes',\n            '${context.limits.maxMemoryBytes}',\n            '--workspace-bytes',\n            '${context.limits.maxWorkspaceBytes}',\n            '--cpu-percent',\n            '${context.limits.maxCpuPercent}',\n            '--timeout-ms',\n            '${context.limits.processTimeout.inMilliseconds}',\n            '--network',\n            'deny',\n            '--target',\n            binding.sandboxTargetPath!,\n            '--',\n            ...arguments,\n          ]\n        : arguments;\n    final outcome = await processRunner.run(\n      executable: binding.executablePath,\n      arguments: processArguments,\n      workingDirectory:\n          sandboxed ? p.normalize(p.absolute(context.workspaceRoot)) : workingDirectory,\n      environment: WesiLocalRuntimePolicy.sanitizedEnvironment(context),\n      timeout: context.limits.processTimeout,\n      maxStdoutBytes: context.limits.maxStdoutBytes,\n      maxStderrBytes: context.limits.maxStderrBytes,\n    );\n""",
    'wrapper invocation',
)

stage6_test = ROOT / 'test/wesi_local_runtime_test.dart'
replace_once(
    stage6_test,
    """            executablePath: '/trusted/python',\n            sandboxProfile: WesiLocalSandboxProfile.workspaceV1,\n""",
    """            executablePath: '/trusted/wesi-sandbox',\n            sandboxTargetPath: '/trusted/python',\n            sandboxProfile: WesiLocalSandboxProfile.workspaceV1,\n""",
    'stage6 sandbox binding',
)
replace_once(
    stage6_test,
    """    expect(fake.executable, '/trusted/python');\n""",
    """    expect(fake.executable, '/trusted/wesi-sandbox');\n    expect(fake.arguments, containsAllInOrder(<String>[\n      '--contract',\n      'workspace-v1',\n      '--target',\n      '/trusted/python',\n      '--',\n      '--version',\n    ]));\n""",
    'stage6 wrapper expectation',
)

pack_models = ROOT / 'lib/features/ai/runtime/wesi_runtime_pack_models.dart'
replace_once(
    pack_models,
    "downloadUri.hasUserInfo",
    "downloadUri.userInfo.isNotEmpty",
    'Uri user info',
)
replace_once(
    pack_models,
    """  bool get supported =>\n      items.every((item) => item.action != WesiRuntimeDependencyAction.unsupported);\n""",
    """  bool get supported => items.every(\n        (item) =>\n            item.dependency.optional ||\n            item.action != WesiRuntimeDependencyAction.unsupported,\n      );\n""",
    'optional supported plan',
)

stage7_test = ROOT / 'test/wesi_runtime_pack_test.dart'
replace_once(
    stage7_test,
    "hashOverride: '0' * 64",
    "hashOverride: '${'0' * 64}'",
    'Dart repeated string',
)

manager = ROOT / 'lib/features/ai/runtime/wesi_runtime_pack_manager.dart'
text = manager.read_text(encoding='utf-8')
if "import 'wesi_runtime_pack_catalog.dart';" not in text:
    text = text.replace(
        "import 'wesi_runtime_pack_models.dart';\n",
        "import 'wesi_runtime_pack_models.dart';\nimport 'wesi_runtime_pack_catalog.dart';\n",
        1,
    )
manager.write_text(text, encoding='utf-8')
replace_once(
    manager,
    """        descriptor.id,\n        descriptor.platform.name,\n        descriptor.version,\n""",
    """        descriptor.id,\n        descriptor.platform.name,\n        descriptor.downloadUri.toString(),\n        descriptor.version,\n""",
    'signed URL payload',
)
replace_once(
    manager,
    """      final managedPaths = await _managedPathsForPack(preview.plan.pack, packRoot);\n      final verified = await scanner.scan(\n        preview.plan.pack.dependencies,\n        managedExecutablePaths: managedPaths,\n      );\n      final verifiedPlan = plan(preview.plan.pack, verified);\n""",
    """      final managedPaths =\n          await _managedPathsForPack(preview.plan.pack, packRoot);\n      final verificationDependencies =\n          <WesiRuntimeDependencySpec>[...preview.plan.pack.dependencies];\n      final needsSandbox = preview.plan.pack.dependencies.any(\n        (dependency) =>\n            dependency.bindingSandboxProfile ==\n            WesiLocalSandboxProfile.workspaceV1,\n      );\n      if (needsSandbox && preview.plan.pack.id != WesiRuntimePackId.core) {\n        final corePack = WesiRuntimePackCatalog.byId(WesiRuntimePackId.core);\n        final sandboxDependency = corePack.dependencies.firstWhere(\n          (dependency) => dependency.id == 'wesi-sandbox',\n        );\n        verificationDependencies.add(sandboxDependency);\n        final coreRoot = Directory(p.join(rootCanonical, WesiRuntimePackId.core.name));\n        managedPaths.addAll(await _managedPathsForPack(corePack, coreRoot));\n      }\n      final backup = await _switchDirectoryForVerification(staging, packRoot);\n      try {\n        final verified = await scanner.scan(\n          verificationDependencies,\n          managedExecutablePaths: managedPaths,\n        );\n        final verifiedPlan = plan(preview.plan.pack, verified);\n""",
    'post scan sandbox and rollback start',
)
replace_once(
    manager,
    """      if (blockers.isNotEmpty) {\n        throw WesiRuntimePackException(\n          'WRP_POST_SCAN_FAILED',\n          'Installed Runtime Pack did not pass post-install verification: '\n              '${blockers.map((item) => item.dependency.id).join(', ')}',\n        );\n      }\n      return _activation(preview.plan.pack, verified, managedPaths);\n    } catch (_) {\n      if (await staging.exists()) await staging.delete(recursive: true);\n      rethrow;\n    }\n""",
    """        if (blockers.isNotEmpty) {\n          throw WesiRuntimePackException(\n            'WRP_POST_SCAN_FAILED',\n            'Installed Runtime Pack did not pass post-install verification: '\n                '${blockers.map((item) => item.dependency.id).join(', ')}',\n          );\n        }\n        final activation =\n            _activation(preview.plan.pack, verified, managedPaths);\n        if (await backup.exists()) await backup.delete(recursive: true);\n        return activation;\n      } catch (_) {\n        if (await packRoot.exists()) await packRoot.delete(recursive: true);\n        if (await backup.exists()) await backup.rename(packRoot.path);\n        rethrow;\n      }\n    } catch (_) {\n      if (await staging.exists()) await staging.delete(recursive: true);\n      rethrow;\n    }\n""",
    'post scan rollback finish',
)
# The old swap call must disappear because verification now owns the swap.
replace_once(
    manager,
    """      await _replaceDirectoryAtomically(staging, packRoot);\n\n      final managedPaths =\n""",
    """      final managedPaths =\n""",
    'remove premature swap',
)
replace_once(
    manager,
    """      final descriptor = await artifactCatalog.resolve(artifactId, scanner.platform);\n      if (descriptor == null || descriptor.executableRelativePath == null) continue;\n      final installRoot = _safeInstallPath(\n        packRoot.path,\n        descriptor.installRelativePath,\n      );\n      final executable = descriptor.installKind == WesiRuntimeInstallKind.portableFile\n          ? installRoot\n          : _safeInstallPath(installRoot, descriptor.executableRelativePath!);\n""",
    """      final descriptor = await artifactCatalog.resolve(artifactId, scanner.platform);\n      if (descriptor == null) continue;\n      final installRoot = _safeInstallPath(\n        packRoot.path,\n        descriptor.installRelativePath,\n      );\n      final executable =\n          descriptor.installKind == WesiRuntimeInstallKind.portableFile\n              ? installRoot\n              : descriptor.executableRelativePath == null\n                  ? ''\n                  : _safeInstallPath(\n                      installRoot,\n                      descriptor.executableRelativePath!,\n                    );\n      if (executable.isEmpty) continue;\n""",
    'portable managed executable',
)
replace_once(
    manager,
    """    for (final entry in archive) {\n      final name = entry.name.replaceAll('\\\\', '/');\n      final output = _safeInstallPath(destinationRoot.path, name);\n      if (entry.isFile) {\n""",
    """    for (final entry in archive) {\n      final name = entry.name.replaceAll('\\\\', '/');\n      if (!entry.isFile && !name.endsWith('/')) {\n        throw const WesiRuntimePackException(\n          'WRP_ARCHIVE_ENTRY_INVALID',\n          'Runtime archive contains a special/symlink-like entry',\n        );\n      }\n      final pathName =\n          !entry.isFile && name.endsWith('/') ? name.substring(0, name.length - 1) : name;\n      final output = _safeInstallPath(destinationRoot.path, pathName);\n      if (entry.isFile) {\n""",
    'safe ZIP directories',
)
replace_once(
    manager,
    """      } else {\n        if (!name.endsWith('/')) {\n          throw const WesiRuntimePackException(\n            'WRP_ARCHIVE_ENTRY_INVALID',\n            'Runtime archive contains a special/symlink-like entry',\n          );\n        }\n        await Directory(output).create(recursive: true);\n      }\n""",
    """      } else {\n        await Directory(output).create(recursive: true);\n      }\n""",
    'remove duplicate ZIP special check',
)
replace_once(
    manager,
    """  static Future<void> _replaceDirectoryAtomically(\n    Directory staging,\n    Directory target,\n  ) async {\n    final backup = Directory('${target.path}.previous');\n    if (await backup.exists()) await backup.delete(recursive: true);\n    if (await target.exists()) await target.rename(backup.path);\n    try {\n      await staging.rename(target.path);\n      if (await backup.exists()) await backup.delete(recursive: true);\n    } catch (_) {\n      if (await target.exists()) await target.delete(recursive: true);\n      if (await backup.exists()) await backup.rename(target.path);\n      rethrow;\n    }\n  }\n""",
    """  static Future<Directory> _switchDirectoryForVerification(\n    Directory staging,\n    Directory target,\n  ) async {\n    final backup = Directory('${target.path}.previous');\n    if (await backup.exists()) await backup.delete(recursive: true);\n    if (await target.exists()) await target.rename(backup.path);\n    try {\n      await staging.rename(target.path);\n      return backup;\n    } catch (_) {\n      if (await target.exists()) await target.delete(recursive: true);\n      if (await backup.exists()) await backup.rename(target.path);\n      rethrow;\n    }\n  }\n""",
    'verified atomic switch',
)

print('Stage 7 integration patch applied')
