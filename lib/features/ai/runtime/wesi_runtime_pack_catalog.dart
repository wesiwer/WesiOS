import 'wesi_local_runtime_models.dart';
import 'wesi_runtime_pack_models.dart';

class WesiRuntimePackCatalog {
  WesiRuntimePackCatalog._();

  static const _desktop = <WesiRuntimePlatform>[
    WesiRuntimePlatform.windows,
    WesiRuntimePlatform.linux,
    WesiRuntimePlatform.macos,
  ];

  static final List<WesiRuntimePackSpec> packs = <WesiRuntimePackSpec>[
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.core,
      title: 'Core Runtime',
      description:
          'Workspace, Git, archives and the Wesi workspaceV1 sandbox provider.',
      required: true,
      capabilities: const <WesiLocalCapability>[
        WesiLocalCapability.filesystem,
        WesiLocalCapability.git,
      ],
      dependencies: <WesiRuntimeDependencySpec>[
        WesiRuntimeDependencySpec(
          id: 'git',
          title: 'Git',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '2.40.0',
          platforms: _desktop,
          managedArtifactId: 'git-portable',
          bindingId: 'git',
          description: 'Local-only Git used by typed status/diff/add/commit tools.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['git'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'git version\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'archive-tools',
          title: 'Archive tools',
          kind: WesiRuntimeDependencyKind.executable,
          platforms: _desktop,
          managedArtifactId: 'archive-tools',
          description: '7-Zip compatible archive tooling used by managed workflows.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['7zz', '7z'],
              arguments: const <String>['i'],
              versionPattern: RegExp(r'7-Zip[^0-9]*([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'wesi-sandbox',
          title: 'Wesi workspaceV1 sandbox',
          kind: WesiRuntimeDependencyKind.sandboxProvider,
          minimumVersion: '1.0.0',
          platforms: _desktop,
          allowSystemReuse: false,
          managedArtifactId: 'wesi-sandbox',
          description:
              'Wesi-managed OS sandbox wrapper. Required before arbitrary project code may execute.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['wesi-sandbox'],
              arguments: const <String>['--contract-version'],
              versionPattern: RegExp(r'workspace-v1\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
      ],
    ),
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.developer,
      title: 'Developer Pack',
      description:
          'Python, Node.js, Flutter/Dart, JDK and native/mobile build dependencies.',
      capabilities: const <WesiLocalCapability>[
        WesiLocalCapability.terminal,
        WesiLocalCapability.python,
        WesiLocalCapability.node,
        WesiLocalCapability.flutter,
        WesiLocalCapability.build,
      ],
      dependencies: <WesiRuntimeDependencySpec>[
        WesiRuntimeDependencySpec(
          id: 'python',
          title: 'Python',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '3.11.0',
          platforms: _desktop,
          managedArtifactId: 'python-runtime',
          bindingId: 'python',
          bindingSandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          bindingAllowsArbitraryCode: true,
          description: 'Python runtime for project scripts and automation.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['python3', 'python'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'Python\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'node',
          title: 'Node.js',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '20.0.0',
          platforms: _desktop,
          managedArtifactId: 'node-runtime',
          bindingId: 'node',
          bindingSandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          bindingAllowsArbitraryCode: true,
          description: 'Node.js LTS runtime for project tools.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['node'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'v?([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'jdk',
          title: 'Java JDK',
          kind: WesiRuntimeDependencyKind.sdk,
          minimumVersion: '17.0.0',
          platforms: _desktop,
          managedArtifactId: 'jdk-runtime',
          description: 'JDK used by Gradle and Android builds.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['java'],
              arguments: const <String>['-version'],
              versionStream: WesiRuntimeProbeStream.combined,
              versionPattern: RegExp(r'version\s+"?([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'flutter',
          title: 'Flutter SDK',
          kind: WesiRuntimeDependencyKind.sdk,
          minimumVersion: '3.24.0',
          platforms: _desktop,
          managedArtifactId: 'flutter-sdk',
          bindingId: 'flutter',
          bindingSandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          bindingAllowsArbitraryCode: true,
          description: 'Flutter/Dart toolchain reused when compatible.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['flutter'],
              arguments: const <String>['--version', '--machine'],
              versionPattern: RegExp(r'"frameworkVersion"\s*:\s*"([0-9]+(?:\.[0-9]+)+)'),
            ),
            WesiRuntimeProbe(
              executableNames: const <String>['flutter'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'Flutter\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'android-sdk',
          title: 'Android SDK / platform-tools',
          kind: WesiRuntimeDependencyKind.sdk,
          platforms: _desktop,
          managedArtifactId: 'android-command-line-tools',
          description: 'Android command-line SDK and platform tools.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['adb'],
              arguments: const <String>['version'],
              versionPattern: RegExp(r'Android Debug Bridge version\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'cmake',
          title: 'CMake',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '3.22.0',
          platforms: _desktop,
          managedArtifactId: 'cmake-runtime',
          description: 'Native build generator used when the project requires it.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['cmake'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'cmake version\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
        WesiRuntimeDependencySpec(
          id: 'vs-build-tools',
          title: 'Visual Studio Build Tools C++ workload',
          kind: WesiRuntimeDependencyKind.workload,
          platforms: const <WesiRuntimePlatform>[WesiRuntimePlatform.windows],
          managedArtifactId: 'vs-build-tools-cpp',
          description:
              'Windows C++ Build Tools only. Full Visual Studio IDE is not required.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['vswhere.exe', 'vswhere'],
              arguments: const <String>[
                '-latest',
                '-products',
                '*',
                '-requires',
                'Microsoft.VisualStudio.Component.VC.Tools.x86.x64',
                '-property',
                'installationVersion',
              ],
              versionPattern: RegExp(r'([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
      ],
    ),
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.browser,
      title: 'Browser Pack',
      description: 'Managed Chromium foundation for later browser automation.',
      capabilities: const <WesiLocalCapability>[],
      dependencies: <WesiRuntimeDependencySpec>[
        WesiRuntimeDependencySpec(
          id: 'chromium-runtime',
          title: 'Managed Chromium',
          kind: WesiRuntimeDependencyKind.managedTool,
          platforms: _desktop,
          allowSystemReuse: false,
          managedArtifactId: 'chromium-runtime',
          description:
              'Pinned managed browser. System Chrome is not silently reused for automation.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['wesi-chromium'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'Chromium\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
      ],
    ),
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.documents,
      title: 'Documents Pack',
      description: 'Managed PDF/DOCX/XLSX/PPTX creation and validation toolchain.',
      capabilities: const <WesiLocalCapability>[WesiLocalCapability.documents],
      dependencies: <WesiRuntimeDependencySpec>[
        WesiRuntimeDependencySpec(
          id: 'document-toolchain',
          title: 'Wesi Document Toolchain',
          kind: WesiRuntimeDependencyKind.managedTool,
          minimumVersion: '1.0.0',
          platforms: _desktop,
          allowSystemReuse: false,
          managedArtifactId: 'document-toolchain',
          bindingId: 'document-toolchain',
          bindingSandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          bindingAllowsArbitraryCode: true,
          description: 'Wesi-managed document generator/validator entrypoint.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['wesi-documents'],
              arguments: const <String>['--version'],
              versionPattern: RegExp(r'([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
      ],
    ),
    WesiRuntimePackSpec(
      id: WesiRuntimePackId.media,
      title: 'Media Pack',
      description: 'FFmpeg and managed media processing entrypoints.',
      capabilities: const <WesiLocalCapability>[WesiLocalCapability.media],
      dependencies: <WesiRuntimeDependencySpec>[
        WesiRuntimeDependencySpec(
          id: 'ffmpeg',
          title: 'FFmpeg',
          kind: WesiRuntimeDependencyKind.executable,
          minimumVersion: '6.0.0',
          platforms: _desktop,
          managedArtifactId: 'ffmpeg-runtime',
          bindingId: 'ffmpeg',
          bindingSandboxProfile: WesiLocalSandboxProfile.workspaceV1,
          bindingAllowsArbitraryCode: true,
          description: 'FFmpeg reused when compatible or installed as a managed tool.',
          probes: <WesiRuntimeProbe>[
            WesiRuntimeProbe(
              executableNames: const <String>['ffmpeg'],
              arguments: const <String>['-version'],
              versionPattern: RegExp(r'ffmpeg version\s+([0-9]+(?:\.[0-9]+)+)'),
            ),
          ],
        ),
      ],
    ),
  ];

  static WesiRuntimePackSpec byId(WesiRuntimePackId id) =>
      packs.firstWhere((pack) => pack.id == id);

  static List<WesiRuntimeDependencySpec> get dependencies {
    final seen = <String>{};
    final out = <WesiRuntimeDependencySpec>[];
    for (final pack in packs) {
      for (final dependency in pack.dependencies) {
        if (seen.add(dependency.id)) out.add(dependency);
      }
    }
    return List<WesiRuntimeDependencySpec>.unmodifiable(out);
  }
}
