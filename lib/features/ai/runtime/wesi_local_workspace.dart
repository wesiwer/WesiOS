import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'wesi_local_runtime_executor.dart';
import 'wesi_local_runtime_models.dart';
import 'wesi_local_runtime_policy.dart';

class WesiLocalWorkspace {
  final String id;
  final String rootPath;

  const WesiLocalWorkspace({required this.id, required this.rootPath});

  WesiLocalRuntimeContext context({
    WesiLocalRuntimeBindings bindings = const WesiLocalRuntimeBindings(),
    WesiLocalRuntimeLimits limits = const WesiLocalRuntimeLimits(),
    bool destructiveConfirmed = false,
    bool allowInsecureHttp = false,
  }) =>
      WesiLocalRuntimeContext(
        workspaceRoot: rootPath,
        bindings: bindings,
        limits: limits,
        destructiveConfirmed: destructiveConfirmed,
        allowInsecureHttp: allowInsecureHttp,
      );
}

/// Owns the physical workspace boundary for local AI execution.
///
/// Employee/workspace identifiers are hashed before becoming path segments so
/// caller-controlled names never become filesystem traversal primitives.
class WesiLocalWorkspaceService {
  final Future<Directory> Function() supportDirectoryProvider;

  const WesiLocalWorkspaceService({
    this.supportDirectoryProvider = getApplicationSupportDirectory,
  });

  Future<WesiLocalWorkspace> open({
    required String employeeId,
    required String workspaceId,
  }) async {
    WesiLocalRuntimePolicy.requireDesktop();
    final owner = _segment(employeeId, label: 'employee');
    final workspace = _segment(workspaceId, label: 'workspace');
    final support = await supportDirectoryProvider();
    final root = Directory(
      p.join(
        support.path,
        'WesiOS',
        'AIRuntime',
        'workspaces',
        owner,
        workspace,
      ),
    );
    if (!await root.exists()) await root.create(recursive: true);
    final canonical = p.normalize(p.absolute(root.path));
    return WesiLocalWorkspace(id: workspaceId, rootPath: canonical);
  }

  String _segment(String raw, {required String label}) {
    final value = raw.trim();
    if (value.isEmpty || value.length > 512 || value.contains('\u0000')) {
      throw WesiLocalRuntimePolicyException(
        'WLR_BAD_WORKSPACE_ID',
        'Некорректный $label id для local runtime',
      );
    }
    return sha256.convert(utf8.encode(value)).toString();
  }
}

class WesiLocalRuntimeAuditEntry {
  final String callId;
  final String tool;
  final String risk;
  final bool ok;
  final String code;
  final int durationMs;
  final DateTime at;

  const WesiLocalRuntimeAuditEntry({
    required this.callId,
    required this.tool,
    required this.risk,
    required this.ok,
    required this.code,
    required this.durationMs,
    required this.at,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'callId': callId,
        'tool': tool,
        'risk': risk,
        'ok': ok,
        'code': code,
        'durationMs': durationMs,
        'at': at.toUtc().toIso8601String(),
      };
}

/// Append-only local audit. Tool arguments/stdout/stderr are intentionally not
/// persisted because they may contain source code, documents or secrets.
class WesiLocalRuntimeSession {
  final WesiLocalWorkspace workspace;
  final WesiLocalRuntimeExecutor executor;

  const WesiLocalRuntimeSession({
    required this.workspace,
    this.executor = const WesiLocalRuntimeExecutor(),
  });

  Future<WesiLocalToolResult> execute(
    WesiLocalToolCall call,
    WesiLocalRuntimeContext context,
  ) async {
    if (!p.equals(
      p.normalize(p.absolute(context.workspaceRoot)),
      p.normalize(p.absolute(workspace.rootPath)),
    )) {
      return WesiLocalToolResult.failure(
        'WLR_WORKSPACE_MISMATCH',
        'Runtime context не принадлежит открытой workspace',
      );
    }
    final meta = WesiLocalCapabilityRegistry.get(call.tool);
    final result = await executor.execute(call, context);
    await _audit(
      WesiLocalRuntimeAuditEntry(
        callId: call.id.length <= 180 ? call.id : call.id.substring(0, 180),
        tool: call.tool,
        risk: meta?.risk.name ?? 'unknown',
        ok: result.ok,
        code: result.code,
        durationMs: result.duration.inMilliseconds,
        at: DateTime.now(),
      ),
    );
    return result;
  }

  Future<void> _audit(WesiLocalRuntimeAuditEntry entry) async {
    try {
      final state = Directory(p.join(workspace.rootPath, '.wesi'));
      if (!await state.exists()) await state.create(recursive: true);
      final file = File(p.join(state.path, 'runtime_audit.jsonl'));
      await file.writeAsString(
        '${jsonEncode(entry.toJson())}\n',
        mode: FileMode.append,
        flush: true,
      );
      final length = await file.length();
      if (length > 4 * 1024 * 1024) {
        final lines = await file.readAsLines();
        final kept = lines.length <= 2000
            ? lines
            : lines.sublist(lines.length - 2000);
        await file.writeAsString('${kept.join('\n')}\n', flush: true);
      }
    } catch (_) {
      // Audit must never expose a second write channel or crash WesiOS. A
      // higher-level health check can surface storage failures later.
    }
  }
}
