import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../team/services/team_service.dart';
import '../runtime/wesi_environment_scanner.dart';
import '../runtime/wesi_local_runtime_models.dart';
import '../runtime/wesi_local_workspace.dart';

/// Protected console for complete code blocks rendered by Wesi AI.
///
/// Arbitrary code is never started with Process.run directly. Python/Node are
/// always routed through the existing workspaceV1 sandbox contract, with the
/// same network/filesystem/resource policy as the rest of Wesi local runtime.
class WesiAiCodeConsole {
  WesiAiCodeConsole._();

  static const Set<String> _python = <String>{
    'python',
    'python3',
    'py',
  };
  static const Set<String> _node = <String>{
    'javascript',
    'js',
    'node',
    'nodejs',
    'mjs',
    'cjs',
  };

  static bool supports(String language) {
    final normalized = language.trim().toLowerCase();
    return _python.contains(normalized) || _node.contains(normalized);
  }

  static Future<void> open(
    BuildContext context, {
    required String code,
    required String language,
  }) async {
    if (!supports(language) || code.trim().isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => FractionallySizedBox(
        heightFactor: 0.82,
        child: _WesiAiCodeConsoleSheet(
          code: code,
          language: language,
        ),
      ),
    );
  }
}

class _WesiAiCodeConsoleSheet extends StatefulWidget {
  final String code;
  final String language;

  const _WesiAiCodeConsoleSheet({
    required this.code,
    required this.language,
  });

  @override
  State<_WesiAiCodeConsoleSheet> createState() =>
      _WesiAiCodeConsoleSheetState();
}

class _WesiAiCodeConsoleSheetState extends State<_WesiAiCodeConsoleSheet> {
  bool _running = false;
  WesiLocalToolResult? _result;
  String? _error;

  bool get _python => const <String>{'python', 'python3', 'py'}
      .contains(widget.language.trim().toLowerCase());

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (_running) return;
    setState(() {
      _running = true;
      _error = null;
      _result = null;
    });

    try {
      if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
        throw const _ConsoleException(
          'Защищённый локальный запуск кода сейчас доступен в desktop-версии '
          'WesiOS. На телефоне нужен подключённый paired runtime; запуск без '
          'sandbox намеренно запрещён.',
        );
      }

      final employee = TeamService.current;
      if (employee == null) {
        throw const _ConsoleException(
          'Войдите в профиль сотрудника, чтобы открыть runtime workspace.',
        );
      }

      final scanner = WesiEnvironmentScanner();
      final sandbox = await _resolveSandbox(scanner);
      if (sandbox == null) {
        throw const _ConsoleException(
          'Wesi workspaceV1 sandbox не найден. Установите Core Runtime в WesiOS.',
        );
      }

      final runtime = await _resolveRuntime(scanner, python: _python);
      if (runtime == null) {
        throw _ConsoleException(
          _python
              ? 'Python 3.11+ не найден. Установите Developer Pack.'
              : 'Node.js 20+ не найден. Установите Developer Pack.',
        );
      }

      final workspace = await const WesiLocalWorkspaceService().open(
        employeeId: employee.id,
        workspaceId: 'chat-code-console',
      );
      final bindingId = _python ? 'python' : 'node';
      final bindings = WesiLocalRuntimeBindings(
        executables: <String, WesiLocalExecutableBinding>{
          bindingId: WesiLocalExecutableBinding(
            id: bindingId,
            executablePath: sandbox,
            sandboxTargetPath: runtime,
            sandboxProfile: WesiLocalSandboxProfile.workspaceV1,
            allowArbitraryCode: true,
          ),
        },
      );
      final runtimeContext = workspace.context(
        bindings: bindings,
        limits: const WesiLocalRuntimeLimits(
          processTimeout: Duration(seconds: 20),
          maxStdoutBytes: 128 * 1024,
          maxStderrBytes: 128 * 1024,
          maxReadBytes: 512 * 1024,
          maxWriteBytes: 512 * 1024,
          maxHttpRequestBytes: 0,
          maxHttpResponseBytes: 0,
          maxDirectoryEntries: 200,
          maxArguments: 32,
          maxArgumentLength: 2048,
          maxMemoryBytes: 256 * 1024 * 1024,
          maxWorkspaceBytes: 128 * 1024 * 1024,
          maxCpuPercent: 50,
        ),
      );
      final session = WesiLocalRuntimeSession(workspace: workspace);
      final stamp = DateTime.now().microsecondsSinceEpoch;
      final extension = _python ? 'py' : 'js';
      final script = 'console/run_$stamp.$extension';

      final write = await session.execute(
        WesiLocalToolCall(
          id: 'chat-code-write-$stamp',
          tool: WesiLocalToolNames.fsWriteText,
          arguments: <String, dynamic>{
            'path': script,
            'text': widget.code,
          },
        ),
        runtimeContext,
      );
      if (!write.ok) {
        throw _ConsoleException('${write.code}: ${write.message}');
      }

      final result = await session.execute(
        WesiLocalToolCall(
          id: 'chat-code-run-$stamp',
          tool: _python
              ? WesiLocalToolNames.pythonRun
              : WesiLocalToolNames.nodeRun,
          arguments: <String, dynamic>{
            'script': script,
            'cwd': 'console',
            'args': const <String>[],
          },
        ),
        runtimeContext,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on _ConsoleException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Runtime безопасно остановил запуск после внутренней ошибки.';
      });
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<String?> _resolveSandbox(WesiEnvironmentScanner scanner) async {
    final direct = scanner.resolveExecutable('wesi-sandbox');
    final candidate = direct ??
        await _findManagedExecutable(
          const <String>{'wesi-sandbox', 'wesi-sandbox.exe'},
        );
    if (candidate == null) return null;
    final probe = await const WesiIoRuntimeProbeRunner().run(
      executable: candidate,
      arguments: const <String>['--contract-version'],
      timeout: const Duration(seconds: 3),
    );
    if (probe.timedOut || probe.exitCode != 0) return null;
    final match = RegExp(r'workspace-v1\s+([0-9]+(?:\.[0-9]+)+)')
        .firstMatch('${probe.stdout}\n${probe.stderr}');
    final version = match?.group(1);
    if (version == null ||
        WesiEnvironmentScanner.compareVersions(version, '1.0.0') < 0) {
      return null;
    }
    return candidate;
  }

  Future<String?> _resolveRuntime(
    WesiEnvironmentScanner scanner, {
    required bool python,
  }) async {
    final names = python
        ? const <String>['python3', 'python']
        : const <String>['node'];
    String? candidate;
    for (final name in names) {
      candidate ??= scanner.resolveExecutable(name);
    }
    candidate ??= await _findManagedExecutable(
      python
          ? const <String>{'python', 'python.exe', 'python3', 'python3.exe'}
          : const <String>{'node', 'node.exe'},
    );
    if (candidate == null) return null;

    final probe = await const WesiIoRuntimeProbeRunner().run(
      executable: candidate,
      arguments: const <String>['--version'],
      timeout: const Duration(seconds: 3),
    );
    if (probe.timedOut || probe.exitCode != 0) return null;
    final output = '${probe.stdout}\n${probe.stderr}';
    final match = (python
            ? RegExp(r'Python\s+([0-9]+(?:\.[0-9]+)+)')
            : RegExp(r'v?([0-9]+(?:\.[0-9]+)+)'))
        .firstMatch(output);
    final version = match?.group(1);
    final minimum = python ? '3.11.0' : '20.0.0';
    if (version == null ||
        WesiEnvironmentScanner.compareVersions(version, minimum) < 0) {
      return null;
    }
    return candidate;
  }

  Future<String?> _findManagedExecutable(Set<String> names) async {
    try {
      final support = await getApplicationSupportDirectory();
      final runtimeRoot = Directory(p.join(support.path, 'WesiOS', 'AIRuntime'));
      if (!await runtimeRoot.exists()) return null;
      return _findInDirectory(runtimeRoot, names, depth: 0);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _findInDirectory(
    Directory directory,
    Set<String> names, {
    required int depth,
  }) async {
    if (depth > 7) return null;
    var seen = 0;
    try {
      await for (final entity in directory.list(followLinks: false)) {
        if (++seen > 800) break;
        final basename = p.basename(entity.path).toLowerCase();
        final type = await FileSystemEntity.type(entity.path, followLinks: false);
        if (type == FileSystemEntityType.file && names.contains(basename)) {
          return File(entity.path).absolute.path;
        }
        if (type != FileSystemEntityType.directory) continue;
        if (basename == 'workspaces' || basename == '.wesi') continue;
        final nested = await _findInDirectory(
          Directory(entity.path),
          names,
          depth: depth + 1,
        );
        if (nested != null) return nested;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _copyOutput() async {
    final value = _consoleText;
    if (value.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Вывод консоли скопирован')),
    );
  }

  String get _consoleText {
    if (_error != null) return _error!;
    final result = _result;
    if (result == null) return '';
    final chunks = <String>[
      if ((result.stdout ?? '').isNotEmpty) result.stdout!,
      if ((result.stderr ?? '').isNotEmpty) result.stderr!,
      if ((result.stdout ?? '').isEmpty && (result.stderr ?? '').isEmpty)
        result.message,
    ];
    return chunks.join('\n').trimRight();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = _result;
    final success = result?.ok == true && (result?.exitCode ?? 0) == 0;
    final status = _running
        ? 'Выполняется…'
        : _error != null
            ? 'Недоступно'
            : result == null
                ? 'Готово к запуску'
                : success
                    ? 'Завершено'
                    : 'Ошибка';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.terminal_rounded),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Консоль · ${widget.language}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      status,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Копировать вывод',
                onPressed: _consoleText.isEmpty ? null : _copyOutput,
                icon: const Icon(Icons.copy_all_outlined),
              ),
              IconButton.filledTonal(
                tooltip: 'Запустить ещё раз',
                onPressed: _running ? null : _run,
                icon: _running
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow_rounded),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(minHeight: 130),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.dividerColor),
            ),
            child: _running && _consoleText.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                    child: SelectableText(
                      _consoleText.isEmpty
                          ? 'Вывод программы появится здесь.'
                          : _consoleText,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.4,
                      ),
                    ),
                  ),
          ),
          if (result != null) ...[
            const SizedBox(height: 8),
            Text(
              'exit ${result.exitCode ?? '-'} · ${result.duration.inMilliseconds} мс · сеть запрещена',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsoleException implements Exception {
  final String message;

  const _ConsoleException(this.message);
}
