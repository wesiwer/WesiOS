import 'dart:io';

import 'package:path/path.dart' as p;

import 'wesi_local_runtime_models.dart';

class WesiLocalRuntimePolicyException implements Exception {
  final String code;
  final String message;

  const WesiLocalRuntimePolicyException(this.code, this.message);

  @override
  String toString() => '$code: $message';
}

class WesiLocalRuntimePolicy {
  WesiLocalRuntimePolicy._();

  static const Set<String> _forbiddenHeaderNames = <String>{
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
    'api-key',
    'x-auth-token',
  };

  static const Set<String> _allowedEnvironmentKeys = <String>{
    'PATH',
    'Path',
    'SystemRoot',
    'WINDIR',
    'JAVA_HOME',
    'ANDROID_HOME',
    'ANDROID_SDK_ROOT',
    'FLUTTER_ROOT',
    'PUB_CACHE',
    'LANG',
    'LC_ALL',
  };

  static bool get desktopSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;

  static WesiLocalToolMeta requireTool(String name) {
    final meta = WesiLocalCapabilityRegistry.get(name);
    if (meta == null) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_TOOL_FORBIDDEN',
        'Локальный инструмент не зарегистрирован',
      );
    }
    return meta;
  }

  static void requireDesktop() {
    if (!desktopSupported) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_DESKTOP_REQUIRED',
        'Локальные тяжёлые инструменты доступны только на desktop WesiOS',
      );
    }
  }

  static void requireRiskAllowed(
    WesiLocalToolMeta meta,
    WesiLocalRuntimeContext context,
  ) {
    if (meta.risk == WesiLocalRisk.destructive &&
        !context.destructiveConfirmed) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_CONFIRMATION_REQUIRED',
        'Разрушающее локальное действие требует явного подтверждения',
      );
    }
  }

  static String lexicalWorkspacePath(
    WesiLocalRuntimeContext context,
    Object? raw, {
    bool allowRoot = false,
  }) {
    final root = p.normalize(p.absolute(context.workspaceRoot));
    final relative = '${raw ?? ''}'.trim();
    if (relative.contains('\u0000')) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_PATH',
        'Путь содержит запрещённый символ',
      );
    }
    if (relative.isEmpty || relative == '.') {
      if (allowRoot) return root;
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_PATH',
        'Нужен путь внутри workspace',
      );
    }
    if (relative.length > 2048 || p.isAbsolute(relative)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_PATH',
        'Абсолютные и слишком длинные пути запрещены',
      );
    }

    final normalizedInput = relative.replaceAll('\\', '/');
    final segments = normalizedInput.split('/');
    if (segments.any((segment) => segment == '..')) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_PATH_ESCAPE',
        'Выход за пределы workspace запрещён',
      );
    }
    final visibleSegments = segments
        .where((segment) => segment.isNotEmpty && segment != '.')
        .toList(growable: false);
    if (visibleSegments.isNotEmpty &&
        visibleSegments.first.toLowerCase() == '.wesi') {
      throw const WesiLocalRuntimePolicyException(
        'WLR_INTERNAL_PATH_FORBIDDEN',
        'Внутреннее состояние local runtime недоступно через model tool calls',
      );
    }

    final candidate = p.normalize(p.absolute(p.join(root, relative)));
    if (candidate != root && !p.isWithin(root, candidate)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_PATH_ESCAPE',
        'Выход за пределы workspace запрещён',
      );
    }
    return candidate;
  }

  static Future<String> resolveExistingPath(
    WesiLocalRuntimeContext context,
    Object? raw, {
    bool allowRoot = false,
  }) async {
    final root = p.normalize(p.absolute(context.workspaceRoot));
    final candidate = lexicalWorkspacePath(context, raw, allowRoot: allowRoot);
    await _rejectSymlinkAncestors(root, candidate);
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_NOT_FOUND',
        'Объект workspace не найден',
      );
    }
    if (type == FileSystemEntityType.link) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SYMLINK_FORBIDDEN',
        'Символические ссылки не разрешены на границе workspace',
      );
    }
    final resolved = await File(candidate).resolveSymbolicLinks();
    final normalizedResolved = p.normalize(p.absolute(resolved));
    if (normalizedResolved != root && !p.isWithin(root, normalizedResolved)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_PATH_ESCAPE',
        'Реальный путь вышел за пределы workspace',
      );
    }
    return candidate;
  }

  static Future<String> resolveWritePath(
    WesiLocalRuntimeContext context,
    Object? raw,
  ) async {
    final root = p.normalize(p.absolute(context.workspaceRoot));
    final candidate = lexicalWorkspacePath(context, raw);
    await _rejectSymlinkAncestors(root, candidate);
    final type = await FileSystemEntity.type(candidate, followLinks: false);
    if (type == FileSystemEntityType.link) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SYMLINK_FORBIDDEN',
        'Запись через символическую ссылку запрещена',
      );
    }
    return candidate;
  }

  static Future<void> _rejectSymlinkAncestors(
    String root,
    String candidate,
  ) async {
    final relative = p.relative(candidate, from: root);
    var cursor = root;
    final rootType = await FileSystemEntity.type(root, followLinks: false);
    if (rootType == FileSystemEntityType.link) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SYMLINK_FORBIDDEN',
        'Корень workspace не может быть символической ссылкой',
      );
    }
    if (relative == '.') return;
    for (final part in p.split(relative)) {
      cursor = p.join(cursor, part);
      final type = await FileSystemEntity.type(cursor, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_SYMLINK_FORBIDDEN',
          'Путь workspace проходит через символическую ссылку',
        );
      }
      if (type == FileSystemEntityType.notFound) break;
    }
  }

  static List<String> validateArguments(
    Iterable<Object?> raw,
    WesiLocalRuntimeContext context,
  ) {
    final values = raw.map((value) => '$value').toList(growable: false);
    if (values.length > context.limits.maxArguments) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_TOO_MANY_ARGUMENTS',
        'Слишком много аргументов процесса',
      );
    }
    final root = p.normalize(p.absolute(context.workspaceRoot));
    for (final value in values) {
      if (value.contains('\u0000') ||
          value.length > context.limits.maxArgumentLength) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_BAD_ARGUMENT',
          'Аргумент процесса отклонён политикой',
        );
      }
      final pathCandidate = _absolutePathCandidate(value);
      if (pathCandidate == null) continue;
      final normalized = p.normalize(p.absolute(pathCandidate));
      if (normalized != root && !p.isWithin(root, normalized)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_ARGUMENT_PATH_ESCAPE',
          'Аргумент процесса ссылается на путь вне workspace',
        );
      }
    }
    return values;
  }

  static String? _absolutePathCandidate(String argument) {
    if (p.isAbsolute(argument)) return argument;
    final equals = argument.indexOf('=');
    if (equals > 0) {
      final tail = argument.substring(equals + 1);
      if (p.isAbsolute(tail)) return tail;
    }
    return null;
  }

  static WesiLocalExecutableBinding requireBinding(
    WesiLocalRuntimeContext context,
    String id, {
    bool requireSandbox = false,
    bool arbitraryCode = false,
  }) {
    final binding = context.bindings[id];
    if (binding == null || binding.executablePath.trim().isEmpty) {
      throw WesiLocalRuntimePolicyException(
        'WLR_DEPENDENCY_MISSING',
        'Не настроен локальный runtime: $id',
      );
    }
    if (requireSandbox && !binding.sandboxed) {
      throw WesiLocalRuntimePolicyException(
        'WLR_SANDBOX_REQUIRED',
        'Runtime $id не подтверждён как изолированный',
      );
    }
    if (arbitraryCode && !binding.allowArbitraryCode) {
      throw WesiLocalRuntimePolicyException(
        'WLR_CODE_EXECUTION_FORBIDDEN',
        'Runtime $id не разрешён для выполнения кода проекта',
      );
    }
    return binding;
  }

  static Map<String, String> sanitizedEnvironment(
    WesiLocalRuntimeContext context,
  ) {
    final out = <String, String>{};
    for (final entry in context.bindings.environment.entries) {
      if (_allowedEnvironmentKeys.contains(entry.key) &&
          !entry.value.contains('\u0000') &&
          entry.value.length <= 8192) {
        out[entry.key] = entry.value;
      }
    }
    final stateDir = p.join(context.workspaceRoot, '.wesi');
    final home = p.join(stateDir, 'home');
    final temp = p.join(stateDir, 'tmp');
    out['HOME'] = home;
    out['USERPROFILE'] = home;
    out['TMPDIR'] = temp;
    out['TMP'] = temp;
    out['TEMP'] = temp;
    out['GIT_TERMINAL_PROMPT'] = '0';
    out['GIT_CONFIG_NOSYSTEM'] = '1';
    return out;
  }

  static Map<String, String> sanitizeHttpHeaders(Object? raw) {
    if (raw == null) return const <String, String>{};
    if (raw is! Map) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_HEADERS',
        'HTTP headers должны быть объектом',
      );
    }
    if (raw.length > 40) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_HEADERS',
        'Слишком много HTTP headers',
      );
    }
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final key = '${entry.key}'.trim();
      final value = '${entry.value}'.trim();
      final lower = key.toLowerCase();
      if (key.isEmpty || key.length > 100 || value.length > 8192) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_BAD_HEADERS',
          'HTTP header отклонён политикой',
        );
      }
      if (_forbiddenHeaderNames.contains(lower)) {
        throw WesiLocalRuntimePolicyException(
          'WLR_SECRET_HEADER_FORBIDDEN',
          'Header $key должен добавляться только доверенным Connector Broker',
        );
      }
      if (lower == 'host' || lower == 'content-length' || lower == 'connection') {
        continue;
      }
      out[key] = value;
    }
    return out;
  }

  static Uri validateHttpUri(
    Object? raw,
    WesiLocalRuntimeContext context,
  ) {
    final uri = Uri.tryParse('${raw ?? ''}'.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_BAD_URL',
        'Некорректный HTTP URL',
      );
    }
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'https' && !(scheme == 'http' && context.allowInsecureHttp)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_INSECURE_HTTP_FORBIDDEN',
        'Разрешён HTTPS; обычный HTTP требует отдельной доверенной политики',
      );
    }
    if (uri.hasUserInfo) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_URL_CREDENTIALS_FORBIDDEN',
        'Credentials в URL запрещены',
      );
    }
    final host = uri.host.toLowerCase();
    if (host == 'localhost' ||
        host.endsWith('.localhost') ||
        host.endsWith('.local') ||
        host == 'metadata.google.internal') {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SSRF_BLOCKED',
        'Локальные и metadata HTTP-назначения запрещены',
      );
    }
    return uri;
  }

  static Future<void> requirePublicHttpDestination(Uri uri) async {
    List<InternetAddress> addresses;
    try {
      addresses = await InternetAddress.lookup(uri.host);
    } on SocketException {
      throw const WesiLocalRuntimePolicyException(
        'WLR_DNS_FAILED',
        'Не удалось разрешить HTTP hostname',
      );
    }
    if (addresses.isEmpty || addresses.any(isPrivateOrSpecialAddress)) {
      throw const WesiLocalRuntimePolicyException(
        'WLR_SSRF_BLOCKED',
        'HTTP-назначение попадает в private/internal/special network',
      );
    }
  }

  static bool isPrivateOrSpecialAddress(InternetAddress address) {
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      final a = bytes[0];
      final b = bytes[1];
      if (a == 0 || a == 10 || a == 127) return true;
      if (a == 100 && b >= 64 && b <= 127) return true;
      if (a == 169 && b == 254) return true;
      if (a == 172 && b >= 16 && b <= 31) return true;
      final c = bytes[2];
      if (a == 192 && b == 168) return true;
      if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
      if (a == 192 && b == 88 && c == 99) return true;
      if (a == 198 && (b == 18 || b == 19)) return true;
      if (a == 198 && b == 51 && c == 100) return true;
      if (a == 203 && b == 0 && c == 113) return true;
      if (a >= 224) return true;
      return false;
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      final allZero = bytes.every((value) => value == 0);
      if (allZero) return true;
      final loopback = bytes.take(15).every((value) => value == 0) && bytes[15] == 1;
      if (loopback) return true;
      final ipv4Mapped = bytes.take(10).every((value) => value == 0) &&
          bytes[10] == 0xff &&
          bytes[11] == 0xff;
      if (ipv4Mapped) {
        final a = bytes[12];
        final b = bytes[13];
        final c = bytes[14];
        if (a == 0 || a == 10 || a == 127) return true;
        if (a == 100 && b >= 64 && b <= 127) return true;
        if (a == 169 && b == 254) return true;
        if (a == 172 && b >= 16 && b <= 31) return true;
        if (a == 192 && b == 168) return true;
        if (a == 192 && b == 0 && (c == 0 || c == 2)) return true;
        if (a == 192 && b == 88 && c == 99) return true;
        if (a == 198 && (b == 18 || b == 19)) return true;
        if (a == 198 && b == 51 && c == 100) return true;
        if (a == 203 && b == 0 && c == 113) return true;
        if (a >= 224) return true;
        return false;
      }
      if ((bytes[0] & 0xfe) == 0xfc) return true; // fc00::/7 unique-local
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return true; // fe80::/10
      if (bytes[0] == 0xff) return true; // multicast
      return false;
    }
    return true;
  }
}
