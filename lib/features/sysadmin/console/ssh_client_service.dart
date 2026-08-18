import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';

import '../models/monitor_target.dart';
import 'ssh_profile_store.dart';

class SshCommandResult {
  final bool ok;
  final int exitCode;
  final String stdout;
  final String stderr;
  final int durationMs;

  const SshCommandResult({
    required this.ok,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.durationMs,
  });

  String get combined {
    if (stderr.isEmpty) return stdout;
    if (stdout.isEmpty) return stderr;
    return '$stdout\n$stderr';
  }
}

class SshConnectionCheck {
  final bool ok;
  final String fingerprint;
  final String serverVersion;
  final String message;

  const SshConnectionCheck({
    required this.ok,
    this.fingerprint = '',
    this.serverVersion = '',
    this.message = '',
  });
}

class SshClientService {
  SshClientService._();

  /// dartssh2 <=2.17 supplied the legacy raw MD5 digest, while newer
  /// releases supply an OpenSSH-style SHA256 fingerprint encoded as UTF-8.
  /// Accept both forms so already saved legacy host keys remain readable and
  /// newly discovered keys use the stronger SHA256 representation.
  static String _fingerprint(dynamic raw) {
    if (raw is String) return raw;
    if (raw is Iterable<int>) {
      final bytes = raw.toList(growable: false);
      try {
        final text = utf8.decode(bytes, allowMalformed: false);
        if (text.startsWith('SHA256:') || text.startsWith('MD5:')) {
          return text;
        }
      } catch (_) {
        // Legacy digest bytes are intentionally not valid UTF-8 text.
      }
      final hex = bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join(':');
      return 'MD5:$hex';
    }
    return '$raw';
  }

  static Future<String> discoverFingerprint(
    String host,
    int port,
  ) async {
    SSHClient? client;
    String? fingerprint;
    try {
      final socket = await SSHSocket.connect(
        host,
        port,
        timeout: const Duration(seconds: 10),
      );
      client = SSHClient(
        socket,
        username: 'host-key-probe',
        onVerifyHostKey: (_, raw) {
          fingerprint = _fingerprint(raw);
          // Reject deliberately: the credential is never sent until the user
          // has seen and accepted the host key fingerprint.
          return false;
        },
      );
      try {
        await client.authenticated.timeout(const Duration(seconds: 10));
      } catch (_) {
        // Expected: verification above intentionally rejects the first pass.
      }
    } finally {
      client?.close();
    }
    final value = fingerprint;
    if (value == null || value.isEmpty) {
      throw StateError('Сервер не отдал SSH host key.');
    }
    return value;
  }

  static Future<SshConnectionCheck> test(
    MonitorTarget target,
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    SSHClient? client;
    try {
      client = await _connect(
        target,
        profile,
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
      );
      await client.authenticated.timeout(const Duration(seconds: 15));
      final output = utf8.decode(
        await client
            .run('printf WESIOS_SSH_OK')
            .timeout(const Duration(seconds: 15)),
        allowMalformed: true,
      );
      return SshConnectionCheck(
        ok: output.contains('WESIOS_SSH_OK'),
        fingerprint: profile.hostKeyFingerprint ?? '',
        serverVersion: client.remoteVersion ?? '',
        message: output.contains('WESIOS_SSH_OK')
            ? 'SSH-подключение работает.'
            : 'SSH подключён, но тестовая команда вернула неожиданный ответ.',
      );
    } on TimeoutException {
      return const SshConnectionCheck(
        ok: false,
        message: 'SSH-сервер не ответил вовремя.',
      );
    } catch (error) {
      return SshConnectionCheck(ok: false, message: '$error');
    } finally {
      client?.close();
    }
  }

  static Future<SshCommandResult> run(
    MonitorTarget target,
    SshProfile profile,
    String command, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final started = DateTime.now();
    SSHClient? client;
    SSHSession? session;
    try {
      client = await _connect(target, profile);
      await client.authenticated.timeout(const Duration(seconds: 15));

      // execute() keeps stdout/stderr/exitCode explicit and remains compatible
      // across the dartssh2 releases supported by WesiOS.
      session = await client.execute(command).timeout(const Duration(seconds: 15));
      final stdoutFuture = session.stdout.expand((chunk) => chunk).toList();
      final stderrFuture = session.stderr.expand((chunk) => chunk).toList();
      await session.done.timeout(timeout);
      final stdoutBytes = await stdoutFuture;
      final stderrBytes = await stderrFuture;
      final exitCode = session.exitCode ?? -1;

      return SshCommandResult(
        ok: exitCode == 0,
        exitCode: exitCode,
        stdout: utf8.decode(stdoutBytes, allowMalformed: true).trimRight(),
        stderr: utf8.decode(stderrBytes, allowMalformed: true).trimRight(),
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
    } on TimeoutException {
      session?.close();
      rethrow;
    } finally {
      client?.close();
    }
  }

  static Future<SSHClient> _connect(
    MonitorTarget target,
    SshProfile profile, {
    String? password,
    String? privateKey,
    String? passphrase,
  }) async {
    final pinned = profile.hostKeyFingerprint?.trim();
    if (pinned == null || pinned.isEmpty) {
      throw StateError(
        'Host key ещё не подтверждён. Сначала нажмите «Проверить SSH».',
      );
    }

    final socket = await SSHSocket.connect(
      target.host,
      profile.port,
      timeout: const Duration(seconds: 10),
    );

    try {
      if (profile.authType == SshAuthType.password) {
        final secret = password ?? await SshProfileStore.readPassword(target.id);
        if (secret == null || secret.isEmpty) {
          throw StateError('Пароль SSH не сохранён.');
        }
        return SSHClient(
          socket,
          username: profile.username,
          onPasswordRequest: () => secret,
          onVerifyHostKey: (_, raw) => _fingerprint(raw) == pinned,
        );
      }

      final pem = privateKey ?? await SshProfileStore.readPrivateKey(target.id);
      if (pem == null || pem.trim().isEmpty) {
        throw StateError('SSH private key не сохранён.');
      }
      final phrase = passphrase ?? await SshProfileStore.readPassphrase(target.id);
      final identities = SSHKeyPair.fromPem(
        pem,
        (phrase == null || phrase.isEmpty) ? null : phrase,
      );
      if (identities.isEmpty) throw StateError('SSH private key не распознан.');
      return SSHClient(
        socket,
        username: profile.username,
        identities: identities,
        onVerifyHostKey: (_, raw) => _fingerprint(raw) == pinned,
      );
    } catch (_) {
      socket.close();
      rethrow;
    }
  }
}
