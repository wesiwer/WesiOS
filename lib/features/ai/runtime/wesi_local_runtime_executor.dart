import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'wesi_local_runtime_models.dart';
import 'wesi_local_runtime_policy.dart';

class WesiLocalProcessOutcome {
  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final Duration duration;

  const WesiLocalProcessOutcome({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.timedOut,
    required this.stdoutTruncated,
    required this.stderrTruncated,
    required this.duration,
  });
}

abstract class WesiLocalProcessRunner {
  Future<WesiLocalProcessOutcome> run({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    required Map<String, String> environment,
    required Duration timeout,
    required int maxStdoutBytes,
    required int maxStderrBytes,
  });
}

class WesiDartLocalProcessRunner implements WesiLocalProcessRunner {
  const WesiDartLocalProcessRunner();

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
    final watch = Stopwatch()..start();
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    final stdoutFuture = _collect(process.stdout, maxStdoutBytes);
    final stderrFuture = _collect(process.stderr, maxStderrBytes);

    var timedOut = false;
    final exitCode = await process.exitCode.timeout(
      timeout,
      onTimeout: () {
        timedOut = true;
        process.kill();
        return -1;
      },
    );
    final stdout = await stdoutFuture.timeout(
      const Duration(seconds: 3),
      onTimeout: () => const _BoundedText('', true),
    );
    final stderr = await stderrFuture.timeout(
      const Duration(seconds: 3),
      onTimeout: () => const _BoundedText('', true),
    );
    watch.stop();
    return WesiLocalProcessOutcome(
      exitCode: exitCode,
      stdout: stdout.text,
      stderr: stderr.text,
      timedOut: timedOut,
      stdoutTruncated: stdout.truncated,
      stderrTruncated: stderr.truncated,
      duration: watch.elapsed,
    );
  }

  Future<_BoundedText> _collect(Stream<List<int>> stream, int limit) async {
    final bytes = BytesBuilder(copy: false);
    var kept = 0;
    var truncated = false;
    await for (final chunk in stream) {
      if (kept >= limit) {
        truncated = true;
        continue;
      }
      final remaining = limit - kept;
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        kept += chunk.length;
      } else {
        bytes.add(chunk.sublist(0, remaining));
        kept += remaining;
        truncated = true;
      }
    }
    return _BoundedText(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
      truncated,
    );
  }
}

class _BoundedText {
  final String text;
  final bool truncated;

  const _BoundedText(this.text, this.truncated);
}

class WesiLocalRuntimeExecutor {
  final WesiLocalProcessRunner processRunner;
  final HttpClient Function() httpClientFactory;

  const WesiLocalRuntimeExecutor({
    this.processRunner = const WesiDartLocalProcessRunner(),
    this.httpClientFactory = _defaultHttpClient,
  });

  static HttpClient _defaultHttpClient() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..idleTimeout = const Duration(seconds: 20);

  Future<WesiLocalToolResult> execute(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final watch = Stopwatch()..start();
    try {
      WesiLocalRuntimePolicy.requireDesktop();
      final meta = WesiLocalRuntimePolicy.requireTool(call.tool);
      WesiLocalRuntimePolicy.requireRiskAllowed(meta, context);
      if (call.encodedArgumentBytes > 64 * 1024) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_ARGUMENTS_TOO_LARGE',
          'Аргументы локального инструмента слишком велики',
        );
      }
      await _ensureWorkspace(context);
      final result = await _dispatch(call, meta, context);
      watch.stop();
      return WesiLocalToolResult(
        ok: result.ok,
        code: result.code,
        message: result.message,
        exitCode: result.exitCode,
        stdout: result.stdout,
        stderr: result.stderr,
        data: result.data,
        duration:
            result.duration == Duration.zero ? watch.elapsed : result.duration,
      );
    } on WesiLocalRuntimePolicyException catch (error) {
      watch.stop();
      return WesiLocalToolResult.failure(
        error.code,
        error.message,
        duration: watch.elapsed,
      );
    } on FileSystemException catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_FILESYSTEM_FAILED',
        'Локальная файловая операция не выполнена',
        duration: watch.elapsed,
      );
    } on ProcessException catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_PROCESS_START_FAILED',
        'Не удалось запустить локальный инструмент',
        duration: watch.elapsed,
      );
    } on SocketException catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_NETWORK_FAILED',
        'Сетевая операция локального runtime не выполнена',
        duration: watch.elapsed,
      );
    } on TimeoutException catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_TIMEOUT',
        'Локальная операция превысила лимит времени',
        duration: watch.elapsed,
      );
    } on FormatException catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_BAD_ARGUMENT',
        'Локальный инструмент получил некорректные аргументы',
        duration: watch.elapsed,
      );
    } catch (_) {
      watch.stop();
      return WesiLocalToolResult.failure(
        'WLR_INTERNAL_ERROR',
        'Локальный runtime безопасно остановил операцию после ошибки',
        duration: watch.elapsed,
      );
    }
  }

  Future<void> _ensureWorkspace(WesiLocalRuntimeContext context) async {
    final root = Directory(p.normalize(p.absolute(context.workspaceRoot)));
    if (!await root.exists()) await root.create(recursive: true);
    final state = Directory(p.join(root.path, '.wesi'));
    final home = Directory(p.join(state.path, 'home'));
    final temp = Directory(p.join(state.path, 'tmp'));
    final noHooks = Directory(p.join(state.path, 'no-hooks'));
    for (final directory in <Directory>[state, home, temp, noHooks]) {
      if (!await directory.exists()) await directory.create(recursive: true);
    }
    await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      '.',
      allowRoot: true,
    );
  }

  Future<WesiLocalToolResult> _dispatch(
    WesiLocalToolCall call,
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context,
  ) async {
    switch (call.tool) {
      case WesiLocalToolNames.fsList:
        return _fsList(call, context);
      case WesiLocalToolNames.fsReadText:
        return _fsReadText(call, context);
      case WesiLocalToolNames.fsWriteText:
        return _fsWriteText(call, context);
      case WesiLocalToolNames.fsDelete:
        return _fsDelete(call, context);
      case WesiLocalToolNames.terminalRun:
        return _terminal(call, meta, context);
      case WesiLocalToolNames.gitStatus:
        return _git(call, context, mode: 'status');
      case WesiLocalToolNames.gitDiff:
        return _git(call, context, mode: 'diff');
      case WesiLocalToolNames.gitAdd:
        return _git(call, context, mode: 'add');
      case WesiLocalToolNames.gitCommit:
        return _git(call, context, mode: 'commit');
      case WesiLocalToolNames.httpGet:
        return _http(call, context, method: 'GET');
      case WesiLocalToolNames.httpPost:
        return _http(call, context, method: 'POST');
      case WesiLocalToolNames.pythonRun:
        return _script(call, meta, context,
            bindingId: 'python', extensions: const {'.py'});
      case WesiLocalToolNames.nodeRun:
        return _script(
          call,
          meta,
          context,
          bindingId: 'node',
          extensions: const {'.js', '.mjs', '.cjs'},
        );
      case WesiLocalToolNames.flutterAnalyze:
        return _flutter(call, meta, context, action: 'analyze');
      case WesiLocalToolNames.flutterTest:
        return _flutter(call, meta, context, action: 'test');
      case WesiLocalToolNames.flutterBuild:
        return _flutter(call, meta, context, action: 'build');
      case WesiLocalToolNames.documentRun:
        return _boundTool(call, meta, context, bindingId: 'document-toolchain');
      case WesiLocalToolNames.mediaRun:
        return _boundTool(call, meta, context, bindingId: 'ffmpeg');
      default:
        throw const WesiLocalRuntimePolicyException(
          'WLR_TOOL_FORBIDDEN',
          'Локальный инструмент не зарегистрирован',
        );
    }
  }

  Future<WesiLocalToolResult> _fsList(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final path = await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      call.arguments['path'] ?? '.',
      allowRoot: true,
    );
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type != FileSystemEntityType.directory) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_NOT_DIRECTORY',
        'Для списка нужен каталог workspace',
      );
    }
    final root = p.normalize(p.absolute(context.workspaceRoot));
    final entries = <Map<String, dynamic>>[];
    await for (final entity in Directory(path).list(followLinks: false)) {
      // `.wesi` stores runtime HOME/tmp/hooks/audit and is deliberately not
      // part of the model-visible workspace namespace.
      if (p.equals(path, root) &&
          p.basename(entity.path).toLowerCase() == '.wesi') {
        continue;
      }
      if (entries.length >= context.limits.maxDirectoryEntries) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_DIRECTORY_TOO_LARGE',
          'Каталог содержит слишком много записей',
        );
      }
      final entityType =
          await FileSystemEntity.type(entity.path, followLinks: false);
      int? bytes;
      if (entityType == FileSystemEntityType.file) {
        try {
          bytes = await File(entity.path).length();
        } catch (_) {}
      }
      entries.add(<String, dynamic>{
        'path': p.relative(entity.path, from: root).replaceAll('\\', '/'),
        'type': switch (entityType) {
          FileSystemEntityType.file => 'file',
          FileSystemEntityType.directory => 'directory',
          FileSystemEntityType.link => 'link-blocked',
          _ => 'other',
        },
        if (bytes != null) 'bytes': bytes,
      });
    }
    entries.sort((a, b) => '${a['path']}'.compareTo('${b['path']}'));
    return WesiLocalToolResult.success(
        data: <String, dynamic>{'entries': entries});
  }

  Future<WesiLocalToolResult> _fsReadText(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final path = await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      call.arguments['path'],
    );
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_NOT_FILE',
        'Для чтения нужен файл workspace',
      );
    }
    final file = File(path);
    final length = await file.length();
    if (length > context.limits.maxReadBytes) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_FILE_TOO_LARGE',
        'Файл превышает лимит локального чтения',
      );
    }
    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes, allowMalformed: false);
    return WesiLocalToolResult.success(
      data: <String, dynamic>{
        'path':
            p.relative(path, from: context.workspaceRoot).replaceAll('\\', '/'),
        'text': text,
        'bytes': bytes.length,
      },
    );
  }

  Future<WesiLocalToolResult> _fsWriteText(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final path = await WesiLocalRuntimePolicy.resolveWritePath(
      context,
      call.arguments['path'],
    );
    final text = '${call.arguments['text'] ?? ''}';
    final bytes = utf8.encode(text);
    if (bytes.length > context.limits.maxWriteBytes) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_FILE_TOO_LARGE',
        'Запись превышает лимит локального файла',
      );
    }
    final parent = Directory(p.dirname(path));
    if (!await parent.exists()) await parent.create(recursive: true);
    await WesiLocalRuntimePolicy.resolveWritePath(
        context, p.relative(path, from: context.workspaceRoot));
    final temp =
        File('$path.wesi-tmp-${DateTime.now().microsecondsSinceEpoch}');
    await temp.writeAsBytes(bytes, flush: true);
    final target = File(path);
    if (await target.exists()) await target.delete();
    await temp.rename(path);
    return WesiLocalToolResult.success(
      data: <String, dynamic>{
        'path':
            p.relative(path, from: context.workspaceRoot).replaceAll('\\', '/'),
        'bytes': bytes.length,
      },
    );
  }

  Future<WesiLocalToolResult> _fsDelete(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final path = await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      call.arguments['path'],
    );
    final root = p.normalize(p.absolute(context.workspaceRoot));
    if (p.equals(path, root)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_WORKSPACE_DELETE_FORBIDDEN',
        'Удалять корень workspace нельзя',
      );
    }
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.directory) {
      final recursive = call.arguments['recursive'] == true;
      if (!recursive &&
          !(await Directory(path).list(followLinks: false).isEmpty)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_DIRECTORY_NOT_EMPTY',
          'Непустой каталог требует recursive=true и явного подтверждения',
        );
      }
      await Directory(path).delete(recursive: recursive);
    } else if (type == FileSystemEntityType.file) {
      await File(path).delete();
    } else {
      throw const WesiLocalRuntimePolicyException(
        'WLR_DELETE_FORBIDDEN',
        'Этот тип объекта нельзя удалить через local runtime',
      );
    }
    return WesiLocalToolResult.success(message: 'Удалено');
  }

  Future<WesiLocalToolResult> _terminal(
    WesiLocalToolCall call,
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context,
  ) async {
    final bindingId = '${call.arguments['binding'] ?? ''}'.trim();
    if (!context.bindings.terminalAllowlist.contains(bindingId)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_TERMINAL_BINDING_FORBIDDEN',
        'Команда не входит в локальный terminal allowlist',
      );
    }
    final binding = WesiLocalRuntimePolicy.requireBinding(
      context,
      bindingId,
      requireSandbox: meta.requiresSandboxedBinding,
      arbitraryCode: true,
    );
    final workingDirectory = await _workingDirectory(call, context);
    final args = WesiLocalRuntimePolicy.validateArguments(
      (call.arguments['args'] as List? ?? const <Object>[]),
      context,
    );
    return _runProcess(binding, args, workingDirectory, context);
  }

  Future<WesiLocalToolResult> _git(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context, {
    required String mode,
  }) async {
    final write = mode == 'add' || mode == 'commit';
    final binding = WesiLocalRuntimePolicy.requireBinding(
      context,
      'git',
      requireSandbox: write,
      arbitraryCode: write,
    );
    final workingDirectory = await _workingDirectory(call, context);
    final hooks = p.join(context.workspaceRoot, '.wesi', 'no-hooks');
    final common = <String>[
      '-c',
      'core.hooksPath=$hooks',
      '-c',
      'core.fsmonitor=false',
      '-c',
      'commit.gpgSign=false',
    ];
    late final List<String> args;
    switch (mode) {
      case 'status':
        args = <String>[...common, 'status', '--porcelain=v2', '--branch'];
        break;
      case 'diff':
        args = <String>[...common, 'diff', '--no-ext-diff', '--no-textconv'];
        break;
      case 'add':
        final paths = (call.arguments['paths'] as List? ?? const <Object>[])
            .map((value) => '$value')
            .toList(growable: false);
        if (paths.isEmpty) {
          throw const WesiLocalRuntimePolicyException(
            'WLR_GIT_PATH_REQUIRED',
            'git add требует явный список путей',
          );
        }
        for (final path in paths) {
          WesiLocalRuntimePolicy.lexicalWorkspacePath(
              context,
              p.join(p.relative(workingDirectory, from: context.workspaceRoot),
                  path));
        }
        args = <String>[...common, 'add', '--', ...paths];
        break;
      case 'commit':
        final message = '${call.arguments['message'] ?? ''}'.trim();
        if (message.isEmpty ||
            message.length > 500 ||
            message.contains('\u0000')) {
          throw const WesiLocalRuntimePolicyException(
            'WLR_GIT_MESSAGE_INVALID',
            'Некорректное сообщение commit',
          );
        }
        args = <String>[...common, 'commit', '--no-verify', '-m', message];
        break;
      default:
        throw const WesiLocalRuntimePolicyException(
          'WLR_GIT_OPERATION_FORBIDDEN',
          'Git operation не разрешена',
        );
    }
    return _runProcess(binding, args, workingDirectory, context);
  }

  Future<WesiLocalToolResult> _script(
    WesiLocalToolCall call,
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context, {
    required String bindingId,
    required Set<String> extensions,
  }) async {
    final binding = WesiLocalRuntimePolicy.requireBinding(
      context,
      bindingId,
      requireSandbox: meta.requiresSandboxedBinding,
      arbitraryCode: true,
    );
    final script = await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      call.arguments['script'],
    );
    if (!extensions.contains(p.extension(script).toLowerCase())) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SCRIPT_TYPE_FORBIDDEN',
        'Тип скрипта не соответствует выбранному runtime',
      );
    }
    final args = WesiLocalRuntimePolicy.validateArguments(
      (call.arguments['args'] as List? ?? const <Object>[]),
      context,
    );
    final workingDirectory = await _workingDirectory(call, context);
    return _runProcess(
        binding, <String>[script, ...args], workingDirectory, context);
  }

  Future<WesiLocalToolResult> _flutter(
    WesiLocalToolCall call,
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context, {
    required String action,
  }) async {
    final binding = WesiLocalRuntimePolicy.requireBinding(
      context,
      'flutter',
      requireSandbox: meta.requiresSandboxedBinding,
      arbitraryCode: true,
    );
    final workingDirectory = await _workingDirectory(call, context);
    final extra = WesiLocalRuntimePolicy.validateArguments(
      (call.arguments['args'] as List? ?? const <Object>[]),
      context,
    );
    late final List<String> args;
    if (action == 'analyze') {
      args = <String>['analyze', ...extra];
    } else if (action == 'test') {
      args = <String>['test', ...extra];
    } else if (action == 'build') {
      final target = '${call.arguments['target'] ?? ''}'.trim().toLowerCase();
      const targets = <String>{
        'apk',
        'appbundle',
        'windows',
        'linux',
        'macos',
        'web'
      };
      if (!targets.contains(target)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_BUILD_TARGET_FORBIDDEN',
          'Неизвестная или запрещённая build target',
        );
      }
      if ((target == 'windows' && !Platform.isWindows) ||
          (target == 'linux' && !Platform.isLinux) ||
          (target == 'macos' && !Platform.isMacOS)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_BUILD_PLATFORM_MISMATCH',
          'Desktop build target не соответствует платформе worker',
        );
      }
      args = <String>['build', target, ...extra];
    } else {
      throw const WesiLocalRuntimePolicyException(
        'WLR_FLUTTER_OPERATION_FORBIDDEN',
        'Flutter operation не разрешена',
      );
    }
    return _runProcess(binding, args, workingDirectory, context);
  }

  Future<WesiLocalToolResult> _boundTool(
    WesiLocalToolCall call,
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context, {
    required String bindingId,
  }) async {
    final binding = WesiLocalRuntimePolicy.requireBinding(
      context,
      bindingId,
      requireSandbox: meta.requiresSandboxedBinding,
      arbitraryCode: true,
    );
    final workingDirectory = await _workingDirectory(call, context);
    final args = WesiLocalRuntimePolicy.validateArguments(
      (call.arguments['args'] as List? ?? const <Object>[]),
      context,
    );
    return _runProcess(binding, args, workingDirectory, context);
  }

  Future<String> _workingDirectory(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    final path = await WesiLocalRuntimePolicy.resolveExistingPath(
      context,
      call.arguments['cwd'] ?? '.',
      allowRoot: true,
    );
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_NOT_DIRECTORY',
        'cwd должен быть каталогом workspace',
      );
    }
    return path;
  }

  Future<WesiLocalToolResult> _runProcess(
    WesiLocalExecutableBinding binding,
    List<String> arguments,
    String workingDirectory,
    WesiLocalRuntimeContext context,
  ) async {
    final sandboxed =
        binding.sandboxProfile == WesiLocalSandboxProfile.workspaceV1;
    final processArguments = sandboxed
        ? <String>[
            '--contract',
            'workspace-v1',
            '--workspace',
            p.normalize(p.absolute(context.workspaceRoot)),
            '--cwd',
            workingDirectory,
            '--memory-bytes',
            '${context.limits.maxMemoryBytes}',
            '--workspace-bytes',
            '${context.limits.maxWorkspaceBytes}',
            '--cpu-percent',
            '${context.limits.maxCpuPercent}',
            '--timeout-ms',
            '${context.limits.processTimeout.inMilliseconds}',
            '--network',
            'deny',
            '--target',
            binding.sandboxTargetPath!,
            '--',
            ...arguments,
          ]
        : arguments;
    final outcome = await processRunner.run(
      executable: binding.executablePath,
      arguments: processArguments,
      workingDirectory: sandboxed
          ? p.normalize(p.absolute(context.workspaceRoot))
          : workingDirectory,
      environment: WesiLocalRuntimePolicy.sanitizedEnvironment(context),
      timeout: context.limits.processTimeout,
      maxStdoutBytes: context.limits.maxStdoutBytes,
      maxStderrBytes: context.limits.maxStderrBytes,
    );
    final data = <String, dynamic>{
      if (outcome.stdoutTruncated) 'stdoutTruncated': true,
      if (outcome.stderrTruncated) 'stderrTruncated': true,
    };
    if (outcome.timedOut) {
      return WesiLocalToolResult.failure(
        'WLR_PROCESS_TIMEOUT',
        'Локальный процесс остановлен по таймауту',
        exitCode: outcome.exitCode,
        stdout: outcome.stdout,
        stderr: outcome.stderr,
        data: data,
        duration: outcome.duration,
      );
    }
    if (outcome.exitCode != 0) {
      return WesiLocalToolResult.failure(
        'WLR_PROCESS_FAILED',
        'Локальный процесс завершился с ошибкой',
        exitCode: outcome.exitCode,
        stdout: outcome.stdout,
        stderr: outcome.stderr,
        data: data,
        duration: outcome.duration,
      );
    }
    return WesiLocalToolResult.success(
      exitCode: outcome.exitCode,
      stdout: outcome.stdout,
      stderr: outcome.stderr,
      data: data,
      duration: outcome.duration,
    );
  }

  Future<WesiLocalToolResult> _http(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context, {
    required String method,
  }) async {
    var uri =
        WesiLocalRuntimePolicy.validateHttpUri(call.arguments['url'], context);
    var headers =
        WesiLocalRuntimePolicy.sanitizeHttpHeaders(call.arguments['headers']);
    final rawBody = method == 'POST' ? '${call.arguments['body'] ?? ''}' : '';
    final bodyBytes = utf8.encode(rawBody);
    if (bodyBytes.length > context.limits.maxHttpRequestBytes) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_HTTP_REQUEST_TOO_LARGE',
        'HTTP request body превышает лимит',
      );
    }

    for (var redirect = 0; redirect <= 5; redirect++) {
      final requestUri = uri;
      final addresses = await InternetAddress.lookup(requestUri.host);
      if (addresses.isEmpty ||
          addresses.any(WesiLocalRuntimePolicy.isPrivateOrSpecialAddress)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_SSRF_BLOCKED',
          'HTTP-назначение попадает в private/internal/special network',
        );
      }
      final pinnedAddress = addresses.first;
      final expectedScheme = requestUri.scheme.toLowerCase();
      final expectedHost = requestUri.host.toLowerCase();
      final expectedPort = requestUri.hasPort
          ? requestUri.port
          : (expectedScheme == 'https' ? 443 : 80);
      final client = httpClientFactory();
      client.findProxy = (_) => 'DIRECT';
      client.connectionFactory = (url, proxyHost, proxyPort) {
        final targetScheme = url.scheme.toLowerCase();
        final targetPort =
            url.hasPort ? url.port : (targetScheme == 'https' ? 443 : 80);
        if (proxyHost != null ||
            proxyPort != null ||
            targetScheme != expectedScheme ||
            url.host.toLowerCase() != expectedHost ||
            targetPort != expectedPort) {
          throw const WesiLocalRuntimePolicyException(
            'WLR_SSRF_BLOCKED',
            'HTTP connection не соответствует проверенному назначению',
          );
        }
        // Socket uses the already validated address; the request URI keeps
        // the original HTTPS hostname for normal HttpClient TLS validation.
        return Socket.startConnect(pinnedAddress, targetPort);
      };
      try {
        final request = method == 'GET'
            ? await client.getUrl(requestUri)
            : await client.postUrl(requestUri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (bodyBytes.isNotEmpty) request.add(bodyBytes);
        final response =
            await request.close().timeout(const Duration(seconds: 30));

        if (response.isRedirect) {
          if (method != 'GET') {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_WRITE_REDIRECT_BLOCKED',
              'Redirect после write HTTP-запроса не выполняется автоматически',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 5) {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_REDIRECT_FAILED',
              'Слишком много или повреждённый HTTP redirect',
            );
          }
          uri = WesiLocalRuntimePolicy.validateHttpUri(
            requestUri.resolve(location),
            context,
          );
          headers = const <String, String>{};
          await response.drain<void>();
          continue;
        }

        final collected = await _collectHttpBody(
          response,
          context.limits.maxHttpResponseBytes,
        );
        final contentType = response.headers.contentType?.mimeType ?? '';
        return WesiLocalToolResult(
          ok: response.statusCode >= 200 && response.statusCode < 400,
          code: response.statusCode >= 200 && response.statusCode < 400
              ? 'OK'
              : 'WLR_HTTP_STATUS',
          message: 'HTTP ${response.statusCode}',
          data: <String, dynamic>{
            'status': response.statusCode,
            'url': requestUri.toString(),
            'contentType': contentType,
            'body': collected.text,
            if (collected.truncated) 'truncated': true,
          },
        );
      } finally {
        client.close(force: true);
      }
    }
    throw const WesiLocalRuntimePolicyException(
      'WLR_HTTP_REDIRECT_FAILED',
      'Слишком много HTTP redirect',
    );
  }

  Future<_BoundedText> _collectHttpBody(
    HttpClientResponse response,
    int limit,
  ) async {
    final bytes = BytesBuilder(copy: false);
    var kept = 0;
    var truncated = false;
    await for (final chunk in response) {
      if (kept >= limit) {
        truncated = true;
        continue;
      }
      final remaining = limit - kept;
      if (chunk.length <= remaining) {
        bytes.add(chunk);
        kept += chunk.length;
      } else {
        bytes.add(chunk.sublist(0, remaining));
        kept += remaining;
        truncated = true;
      }
    }
    return _BoundedText(
      utf8.decode(bytes.takeBytes(), allowMalformed: true),
      truncated,
    );
  }
}
