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
        handshakeTimeout: const Duration(seconds: 10),
        authTimeout: const Duration(seconds: 5),
        onVerifyHostKey: (_, raw) {
          fingerprint = utf8.decode(raw, allowMalformed: false);
          // Important: reject here. This lets us show the host key to the
          // user before any password/private key is ever sent to the host.
          return false;
        },
      );
      try {
        await client.authenticated;
      } catch (_) {
        // Expected: host key verification above intentionally rejects.
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
        await client.run('printf WESIOS_SSH_OK'),
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
    try {
      client = await _connect(target, profile);
      await client.authenticated.timeout(const Duration(seconds: 15));
      final result = await client.runWithResult(command).timeout(timeout);
      return SshCommandResult(
        ok: (result.exitCode ?? 0) == 0,
        exitCode: result.exitCode ?? -1,
        stdout: utf8.decode(result.stdout, allowMalformed: true).trimRight(),
        stderr: utf8.decode(result.stderr, allowMalformed: true).trimRight(),
        durationMs: DateTime.now().difference(started).inMilliseconds,
      );
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
        'Host key ещё не подтверждён. Сначала нажмите «Проверить соединение».',
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
          onVerifyHostKey: (_, raw) =>
              utf8.decode(raw, allowMalformed: false) == pinned,
          handshakeTimeout: const Duration(seconds: 10),
          authTimeout: const Duration(seconds: 15),
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
        onVerifyHostKey: (_, raw) =>
            utf8.decode(raw, allowMalformed: false) == pinned,
        handshakeTimeout: const Duration(seconds: 10),
        authTimeout: const Duration(seconds: 15),
      );
    } catch (_) {
      await socket.close();
      rethrow;
    }
  }
}
