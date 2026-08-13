import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

import '../../team/services/team_service.dart';
import '../models/monitor_target.dart';
import '../models/probe_result.dart';
import '../services/monitor_service.dart';
import '../services/network_probe.dart';
import 'console_templates.dart';
import 'remote_shell_service.dart';

enum ConsoleLineKind { prompt, output, success, warning, error, system }

class ConsoleLine {
  final String text;
  final ConsoleLineKind kind;
  final DateTime at;

  ConsoleLine(this.text, this.kind, {DateTime? at}) : at = at ?? DateTime.now();
}

class ConsoleExecution {
  final List<ConsoleLine> lines;
  final bool clear;
  final String? openTargetId;

  const ConsoleExecution({
    this.lines = const [],
    this.clear = false,
    this.openTargetId,
  });
}

/// Операционная консоль WesiOS.
///
/// Работает в двух режимах, и разница между ними видна человеку всегда.
///
/// Местный режим — сетевые проверки с самого устройства: ping, dns, http,
/// tls, доступность SSH-порта. Это диагностика «отсюда»: она отвечает на
/// вопрос, видно ли сервер с этого телефона.
///
/// Удалённый режим — команды выполняет сам сервер и присылает вывод.
/// Приватных SSH-ключей в приложении по-прежнему нет: запрос уходит на
/// авторизованный обработчик, который пускает только владельца, обрывает
/// команду по сроку и пишет каждую в журнал.
///
/// Токены разбираются только локально и никогда не сохраняются в истории.
class ConsoleCommandService {
  static const String _settingsBox = 'wesios_settings';
  static const String _historyKey = 'sysadmin_console_history_v1';
  static const String _remoteKey = 'sysadmin_console_remote_v1';
  static const String _remoteCwdKey = 'sysadmin_console_cwd_v1';
  static const int maxHistory = 80;

  /// Команды, которые остаются местными даже в удалённом режиме.
  ///
  /// Это управление самой консолью. Отправлять `clear` на сервер бессмысленно,
  /// а `remote off` — ещё и опасно: выключить режим стало бы нечем.
  static const Set<String> _alwaysLocal = {
    'help',
    '?',
    'clear',
    'cls',
    'remote',
    'history',
    'targets',
    'ls',
    'templates',
    'open',
    'load',
    'token',
    'whoami',
  };

  static bool get remoteMode {
    try {
      return Hive.box<dynamic>(_settingsBox).get(_remoteKey) == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setRemoteMode(bool value) async {
    try {
      await Hive.box<dynamic>(_settingsBox).put(_remoteKey, value);
    } catch (_) {
      // Настройка не сохранилась — режим всё равно отработает в этом сеансе.
    }
  }

  static String get remoteCwd {
    try {
      final raw = Hive.box<dynamic>(_settingsBox).get(_remoteCwdKey);
      return raw is String && raw.trim().isNotEmpty
          ? raw.trim()
          : '/opt/pocketbase';
    } catch (_) {
      return '/opt/pocketbase';
    }
  }

  static Future<void> setRemoteCwd(String value) async {
    try {
      await Hive.box<dynamic>(_settingsBox).put(_remoteCwdKey, value.trim());
    } catch (_) {
      // См. выше: не сохранилось — не беда.
    }
  }

  static List<String> loadHistory() {
    try {
      final raw = Hive.box<dynamic>(_settingsBox).get(_historyKey);
      if (raw is! String || raw.isEmpty) return <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded
          .map((value) => '$value')
          .where((value) => value.isNotEmpty)
          .toList();
    } catch (_) {
      return <String>[];
    }
  }

  static bool isSensitiveCommand(String command) {
    final raw = command.trim();
    if (raw.isEmpty) return false;
    final parts = _split(raw);
    if (parts.isEmpty) return false;
    final name = parts.first.toLowerCase();
    if (name == 'token') return true;
    final lower = raw.toLowerCase();
    return lower.contains('authorization:') ||
        lower.contains('bearer ') ||
        lower.contains('api_key=') ||
        lower.contains('apikey=') ||
        lower.contains('access_token=');
  }

  /// Строка для журнала и экрана. Секреты маскируются до того, как попадут в
  /// дерево виджетов или историю вывода.
  static String displayCommand(String command) {
    final raw = command.trim();
    final parts = _split(raw);
    if (parts.isEmpty) return raw;
    if (parts.first.toLowerCase() == 'token') {
      final action = parts.length > 1 ? parts[1] : '';
      return [
        'token',
        if (action.isNotEmpty) action,
        if (parts.length > 2) '••••••••'
      ].join(' ');
    }
    return raw
        .replaceAll(
          RegExp(r'(bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
          r'$1••••••••',
        )
        .replaceAll(
          RegExp(
            r'((?:api[_-]?key|access[_-]?token)=)[^\s&]+',
            caseSensitive: false,
          ),
          r'$1••••••••',
        );
  }

  static Future<void> remember(String command) async {
    final value = command.trim();
    if (value.isEmpty || isSensitiveCommand(value)) return;
    final history = loadHistory();
    history.remove(value);
    history.add(value);
    if (history.length > maxHistory) {
      history.removeRange(0, history.length - maxHistory);
    }
    try {
      await Hive.box<dynamic>(_settingsBox)
          .put(_historyKey, jsonEncode(history));
    } catch (_) {}
  }

  static List<String> completions(String prefix, {String? targetId}) {
    final value = prefix.trimLeft().toLowerCase();
    const commands = [
      'help',
      'clear',
      'status',
      'targets',
      'templates',
      'probe all',
      'probe ',
      'ping ',
      'dns ',
      'http ',
      'tls ',
      'ssh-check ',
      'ssh-help',
      'sh ',
      'remote',
      'remote on',
      'remote off',
      'remote cd ',
      'token inspect ',
      'token hash ',
      'token redact ',
      'load ',
      'open ',
      'history',
      'date',
      'whoami',
      'echo ',
    ];
    if (value.isEmpty) return commands;
    final targetCommands = [
      for (final target in MonitorService.targets) ...[
        'probe ${target.id}',
        'open ${target.id}',
        'load ${target.id}',
      ],
    ];
    return [...commands, ...targetCommands]
        .where((command) => command.toLowerCase().startsWith(value))
        .toList();
  }

  static Future<ConsoleExecution> execute(
    String input, {
    bool russian = true,
    String? targetId,
  }) async {
    final raw = input.trim();
    if (raw.isEmpty) return const ConsoleExecution();
    await remember(raw);

    final parts = _split(raw);
    final command = parts.first.toLowerCase();
    final args = parts.skip(1).toList();
    final selected = targetId == null ? null : MonitorService.byId(targetId);
    final scopedArgs = _scopedArgs(command, args, selected);

    // `sh` отправляет одну команду на сервер, не меняя режима.
    if (command == 'sh' || command == 'ssh') {
      final remainder = raw.substring(parts.first.length).trim();
      if (remainder.isEmpty) return _usage('sh <команда>', russian);
      return _runRemote(remainder, russian);
    }

    // В удалённом режиме на сервер уходит всё, кроме управления консолью.
    // Проверка идёт по исходной строке: `df -h` — это команда сервера, а не
    // неизвестная команда консоли, и сообщать о ней «не знаю такой» было бы
    // неправильно.
    if (remoteMode && !_alwaysLocal.contains(command)) {
      return _runRemote(raw, russian);
    }

    try {
      return switch (command) {
        'remote' => await _remote(args, russian),
        'help' || '?' => ConsoleExecution(lines: _help(russian)),
        'clear' || 'cls' => const ConsoleExecution(clear: true),
        'status' => await _status(russian, selected),
        'targets' || 'ls' => _targets(russian),
        'templates' => _templates(russian, selected),
        'probe' => await _probe(scopedArgs, russian),
        'ping' => await _ping(scopedArgs, russian),
        'dns' => await _dns(scopedArgs, russian),
        'http' || 'curl' => await _http(scopedArgs, russian),
        'tls' || 'cert' => await _tls(scopedArgs, russian),
        'ssh-check' || 'sshcheck' => await _sshCheck(scopedArgs, russian),
        'ssh-help' => _sshHelp(russian),
        'token' => _token(args, russian),
        'load' => _load(scopedArgs, russian),
        'open' => _open(scopedArgs, russian),
        'history' => _history(russian),
        'date' || 'time' => ConsoleExecution(lines: [
            ConsoleLine(
              DateTime.now().toLocal().toString(),
              ConsoleLineKind.output,
            ),
          ]),
        'whoami' => _whoami(russian),
        'echo' => ConsoleExecution(lines: [
            ConsoleLine(args.join(' '), ConsoleLineKind.output),
          ]),
        _ => ConsoleExecution(lines: [
            ConsoleLine(
              russian
                  ? 'Команда «$command» не найдена. Введите help.'
                  : 'Command "$command" not found. Type help.',
              ConsoleLineKind.error,
            ),
          ]),
      };
    } catch (error) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          russian ? 'Ошибка: $error' : 'Error: $error',
          ConsoleLineKind.error,
        ),
      ]);
    }
  }

  static List<String> _scopedArgs(
    String command,
    List<String> args,
    MonitorTarget? target,
  ) {
    if (args.isNotEmpty || target == null) return args;
    switch (command) {
      case 'probe':
        return [target.id];
      case 'ping':
        return [target.host, '${target.port}'];
      case 'dns':
        return [target.host];
      case 'http':
      case 'curl':
        final url = target.url?.trim();
        return [
          if (url != null && url.isNotEmpty)
            url
          else
            'https://${target.host}${target.port == 443 ? '' : ':${target.port}'}',
        ];
      case 'tls':
      case 'cert':
        return [target.host, '${target.checkTls ? target.port : 443}'];
      case 'ssh-check':
      case 'sshcheck':
        return [target.host, '22'];
      case 'load':
      case 'open':
        return [target.id];
      default:
        return args;
    }
  }

  static List<String> _split(String input) {
    final result = <String>[];
    final current = StringBuffer();
    String? quote;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quote != null) {
        if (char == quote) {
          quote = null;
        } else {
          current.write(char);
        }
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
      } else if (char.trim().isEmpty) {
        if (current.isNotEmpty) {
          result.add(current.toString());
          current.clear();
        }
      } else {
        current.write(char);
      }
    }
    if (current.isNotEmpty) result.add(current.toString());
    return result.isEmpty ? [input] : result;
  }

  static List<ConsoleLine> _help(bool ru) => [
        ConsoleLine(
          ru
              ? 'WESI CONSOLE · ДОСТУПНЫЕ КОМАНДЫ'
              : 'WESI CONSOLE · AVAILABLE COMMANDS',
          ConsoleLineKind.system,
        ),
        ConsoleLine(
          'status                 ${ru ? 'сводка всей инфраструктуры' : 'infrastructure summary'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'targets                ${ru ? 'список узлов и их ID' : 'list targets and IDs'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'templates              ${ru ? 'каталог готовых команд' : 'command template catalog'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'probe all|<id>         ${ru ? 'проверить узлы' : 'probe targets'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'ping <host> [port]     ${ru ? 'TCP-отклик' : 'TCP latency'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'dns <host>             ${ru ? 'разрешить домен' : 'resolve a domain'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'http <url>             ${ru ? 'проверить HTTP' : 'check HTTP'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'tls <host> [port]      ${ru ? 'прочитать сертификат' : 'read certificate'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'ssh-check <host> [22]  ${ru ? 'проверить доступность SSH-порта' : 'check SSH port reachability'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine('', ConsoleLineKind.output),
        ConsoleLine(
          ru ? 'НА СЕРВЕРЕ' : 'ON THE SERVER',
          ConsoleLineKind.system,
        ),
        ConsoleLine(
          'sh <команда>           ${ru ? 'выполнить одну команду на сервере' : 'run one command on the server'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'remote on / off        ${ru ? 'слать на сервер всё подряд' : 'send everything to the server'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'remote                 ${ru ? 'состояние и рабочий каталог' : 'status and working directory'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'remote cd <каталог>    ${ru ? 'сменить рабочий каталог' : 'change working directory'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'token inspect <TOKEN>  ${ru ? 'локально прочитать JWT' : 'inspect JWT locally'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'token hash <TOKEN>     ${ru ? 'SHA-256 отпечаток' : 'SHA-256 fingerprint'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'token redact <TOKEN>   ${ru ? 'маскированный вид' : 'masked representation'}',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          'load [id] · open <id> · history · date · whoami · echo · clear',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          ru
              ? 'Tab дополняет команды, ↑/↓ листают историю, Ctrl+A/C/X/V редактируют строку.'
              : 'Tab completes commands, ↑/↓ browse history, Ctrl+A/C/X/V edit the line.',
          ConsoleLineKind.warning,
        ),
        ConsoleLine(
          ru
              ? 'Токены не отправляются в сеть, не выводятся полностью и не сохраняются в истории.'
              : 'Tokens are never sent over the network, printed in full, or stored in history.',
          ConsoleLineKind.success,
        ),
      ];

  static ConsoleExecution _templates(bool ru, MonitorTarget? selected) {
    return ConsoleExecution(lines: [
      ConsoleLine(
        ru ? 'WESI CONSOLE · ШАБЛОНЫ' : 'WESI CONSOLE · TEMPLATES',
        ConsoleLineKind.system,
      ),
      for (final category in ConsoleTemplateCategory.values) ...[
        ConsoleLine(
          ConsoleTemplateLibrary.categoryTitle(category, ru).toUpperCase(),
          ConsoleLineKind.warning,
        ),
        for (final template in ConsoleTemplateLibrary.inCategory(category))
          ConsoleLine(
            '${template.title(ru)} · ${selected == null ? template.command : ConsoleTemplateLibrary.resolveCommand(template, selected)}',
            ConsoleLineKind.output,
          ),
      ],
    ]);
  }

  /// Выполнить команду на сервере и показать вывод как есть.
  ///
  /// Вывод сервера не раскрашивается по догадке: строки идут обычным
  /// выводом, а цветом отмечается только итог. Иначе безобидная строка со
  /// словом «error» внутри чужого лога выглядела бы как сбой команды.
  static Future<ConsoleExecution> _runRemote(String command, bool ru) async {
    final capability = await RemoteShellService.capability();
    if (!capability.available) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Сервер не выполняет команды: ${capability.reason}'
              : 'Remote execution unavailable: ${capability.reason}',
          ConsoleLineKind.error,
        ),
        ConsoleLine(
          ru
              ? 'Местные проверки (ping, dns, http, tls) работают по-прежнему.'
              : 'Local checks (ping, dns, http, tls) still work.',
          ConsoleLineKind.system,
        ),
      ]);
    }

    final result = await RemoteShellService.run(
      command,
      cwd: remoteCwd,
      timeoutSeconds: capability.defaultTimeoutSeconds,
    );

    if (!result.executed) {
      return ConsoleExecution(lines: [
        ConsoleLine(result.error, ConsoleLineKind.error),
      ]);
    }

    final lines = <ConsoleLine>[];
    final text = result.output;
    if (text.trim().isEmpty) {
      lines.add(ConsoleLine(
        ru ? '(вывод пуст)' : '(no output)',
        ConsoleLineKind.system,
      ));
    } else {
      for (final line in text.split('\n')) {
        lines.add(ConsoleLine(line, ConsoleLineKind.output));
      }
    }

    if (result.truncated) {
      lines.add(ConsoleLine(
        ru
            ? 'Вывод обрезан: показано начало. Уточните команду — например, '
                'через head, tail или grep.'
            : 'Output truncated. Narrow the command with head, tail or grep.',
        ConsoleLineKind.warning,
      ));
    }
    if (result.timedOut) {
      lines.add(ConsoleLine(
        ru
            ? 'Команда оборвана по сроку (${capability.defaultTimeoutSeconds} с). '
                'Долгие задачи запускайте в фоне, иначе консоль их не дождётся.'
            : 'Command timed out after ${capability.defaultTimeoutSeconds}s.',
        ConsoleLineKind.warning,
      ));
    }

    final seconds = (result.durationMs / 1000).toStringAsFixed(
      result.durationMs >= 1000 ? 1 : 2,
    );
    lines.add(ConsoleLine(
      ru
          ? 'Код возврата: ${result.exitCode} · ${seconds} с · сервер'
          : 'Exit code: ${result.exitCode} · ${seconds}s · server',
      result.ok ? ConsoleLineKind.success : ConsoleLineKind.error,
    ));
    return ConsoleExecution(lines: lines);
  }

  /// Управление удалённым режимом: включить, выключить, показать состояние,
  /// сменить рабочий каталог.
  static Future<ConsoleExecution> _remote(List<String> args, bool ru) async {
    final action = args.isEmpty ? 'status' : args.first.toLowerCase();

    if (action == 'on' || action == 'вкл') {
      final capability = await RemoteShellService.capability(refresh: true);
      if (!capability.available) {
        return ConsoleExecution(lines: [
          ConsoleLine(
            ru
                ? 'Не включаю: ${capability.reason}'
                : 'Not enabling: ${capability.reason}',
            ConsoleLineKind.error,
          ),
        ]);
      }
      await setRemoteMode(true);
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Удалённый режим включён. Команды идут на сервер, '
                  'каталог: $remoteCwd'
              : 'Remote mode on. Commands run on the server in $remoteCwd',
          ConsoleLineKind.success,
        ),
        ConsoleLine(
          ru
              ? 'Выключить: remote off. Разово выполнить на сервере: sh <команда>.'
              : 'Turn off with: remote off. One-off: sh <command>.',
          ConsoleLineKind.system,
        ),
      ]);
    }

    if (action == 'off' || action == 'выкл') {
      await setRemoteMode(false);
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Удалённый режим выключен. Команды снова выполняются здесь.'
              : 'Remote mode off. Commands run locally again.',
          ConsoleLineKind.success,
        ),
      ]);
    }

    if (action == 'cd') {
      if (args.length < 2) return _usage('remote cd <каталог>', ru);
      await setRemoteCwd(args[1]);
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru ? 'Рабочий каталог: $remoteCwd' : 'Working directory: $remoteCwd',
          ConsoleLineKind.success,
        ),
      ]);
    }

    final capability = await RemoteShellService.capability(refresh: true);
    return ConsoleExecution(lines: [
      ConsoleLine(
        ru ? 'УДАЛЁННОЕ ВЫПОЛНЕНИЕ' : 'REMOTE EXECUTION',
        ConsoleLineKind.system,
      ),
      ConsoleLine(
        ru
            ? 'Режим: ${remoteMode ? 'включён' : 'выключен'}'
            : 'Mode: ${remoteMode ? 'on' : 'off'}',
        remoteMode ? ConsoleLineKind.success : ConsoleLineKind.output,
      ),
      ConsoleLine(
        ru
            ? 'Сервер: ${capability.available ? 'выполняет команды' : capability.reason}'
            : 'Server: ${capability.available ? 'ready' : capability.reason}',
        capability.available
            ? ConsoleLineKind.success
            : ConsoleLineKind.error,
      ),
      ConsoleLine(
        ru ? 'Каталог: $remoteCwd' : 'Directory: $remoteCwd',
        ConsoleLineKind.output,
      ),
      ConsoleLine(
        ru
            ? 'Срок на команду: ${capability.defaultTimeoutSeconds} с'
            : 'Timeout: ${capability.defaultTimeoutSeconds}s',
        ConsoleLineKind.output,
      ),
      ConsoleLine(
        ru
            ? 'Команды выполняет сервер и пишет каждую в журнал. Доступ '
                'только у владельца.'
            : 'The server executes and logs every command. Owner only.',
        ConsoleLineKind.system,
      ),
    ]);
  }

  static Future<ConsoleExecution> _status(
    bool ru, [
    MonitorTarget? selected,
  ]) async {
    if (selected != null) {
      final sample = await MonitorService.probe(selected);
      await MonitorService.refreshSlow(selected);
      final load = MonitorService.loadOf(selected.id);
      final tls = MonitorService.tlsOf(selected.id);
      return ConsoleExecution(lines: [
        ConsoleLine(
          '${selected.name} · ${selected.host}:${selected.port}',
          ConsoleLineKind.system,
        ),
        _sampleLine(selected.name, sample, ru),
        if (tls != null)
          ConsoleLine(
            '${ru ? 'TLS до' : 'TLS until'} ${tls.validUntil.toLocal()}',
            ConsoleLineKind.success,
          ),
        if (load != null)
          ConsoleLine(
            'CPU ${(load.cpuFraction * 100).round()}% · RAM ${(load.memFraction * 100).round()}% · DISK ${(load.diskFraction * 100).round()}%',
            ConsoleLineKind.output,
          ),
      ]);
    }

    final targets = MonitorService.targets;
    if (targets.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru ? 'Узлы не добавлены.' : 'No targets configured.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    final lines = <ConsoleLine>[
      ConsoleLine(
        ru
            ? 'Проверяю ${targets.length} узлов…'
            : 'Probing ${targets.length} targets…',
        ConsoleLineKind.system,
      ),
    ];
    var up = 0;
    for (final target in targets) {
      final sample = await MonitorService.probe(target);
      if (sample.ok) up++;
      final ms = sample.ms == null ? '' : ' · ${sample.ms!.round()} ms';
      lines.add(ConsoleLine(
        '${sample.ok ? '●' : '×'} ${target.name}: ${sample.describe(russian: ru)}$ms${sample.detail == null ? '' : ' · ${sample.detail}'}',
        sample.ok ? ConsoleLineKind.success : ConsoleLineKind.error,
      ));
    }
    lines.add(ConsoleLine(
      ru
          ? 'Итог: $up/${targets.length} отвечают.'
          : 'Summary: $up/${targets.length} responding.',
      up == targets.length ? ConsoleLineKind.success : ConsoleLineKind.warning,
    ));
    return ConsoleExecution(lines: lines);
  }

  static ConsoleExecution _targets(bool ru) {
    final targets = MonitorService.targets;
    if (targets.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru ? 'Узлы не добавлены.' : 'No targets configured.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(
        ru ? 'ID · ТИП · АДРЕС' : 'ID · TYPE · ADDRESS',
        ConsoleLineKind.system,
      ),
      for (final target in targets)
        ConsoleLine(
          '${target.id} · ${ru ? target.labelRu() : target.labelEn()} · ${target.host}:${target.port}${target.url == null ? '' : ' · ${target.url}'}',
          ConsoleLineKind.output,
        ),
    ]);
  }

  static Future<ConsoleExecution> _probe(List<String> args, bool ru) async {
    if (args.isEmpty) return _usage('probe all|<id>', ru);
    if (args.first.toLowerCase() == 'all') return _status(ru);
    final target = MonitorService.byId(args.first);
    if (target == null) return _missingTarget(args.first, ru);
    final sample = await MonitorService.probe(target);
    return ConsoleExecution(lines: [_sampleLine(target.name, sample, ru)]);
  }

  static Future<ConsoleExecution> _ping(List<String> args, bool ru) async {
    if (args.isEmpty) return _usage('ping <host> [port]', ru);
    final host = args.first;
    final port = args.length > 1 ? int.tryParse(args[1]) ?? 443 : 443;
    final sample = await NetworkProbe.tcp(host, port);
    return ConsoleExecution(lines: [_sampleLine('$host:$port', sample, ru)]);
  }

  static Future<ConsoleExecution> _dns(List<String> args, bool ru) async {
    if (args.isEmpty) return _usage('dns <host>', ru);
    final result = await NetworkProbe.dns(args.first);
    return ConsoleExecution(lines: [
      ConsoleLine(
        result.ok
            ? '${args.first} → ${result.addresses.join(', ')} · ${result.took.inMilliseconds} ms'
            : (ru
                ? '${args.first}: DNS не ответил'
                : '${args.first}: DNS lookup failed'),
        result.ok ? ConsoleLineKind.success : ConsoleLineKind.error,
      ),
    ]);
  }

  static Future<ConsoleExecution> _http(List<String> args, bool ru) async {
    if (args.isEmpty) return _usage('http <url>', ru);
    var url = args.first;
    if (!url.contains('://')) url = 'https://$url';
    final sample = await NetworkProbe.http(url);
    return ConsoleExecution(lines: [_sampleLine(url, sample, ru)]);
  }

  static Future<ConsoleExecution> _tls(List<String> args, bool ru) async {
    if (args.isEmpty) return _usage('tls <host> [port]', ru);
    final host = args.first;
    final port = args.length > 1 ? int.tryParse(args[1]) ?? 443 : 443;
    final info = await NetworkProbe.tls(host, port: port);
    if (info == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Не удалось прочитать сертификат $host:$port'
              : 'Could not read certificate for $host:$port',
          ConsoleLineKind.error,
        ),
      ]);
    }
    final days = info.daysLeft(DateTime.now());
    return ConsoleExecution(lines: [
      ConsoleLine('$host:$port', ConsoleLineKind.system),
      ConsoleLine(
        '${ru ? 'Субъект' : 'Subject'}: ${info.subject}',
        ConsoleLineKind.output,
      ),
      ConsoleLine(
        '${ru ? 'Издатель' : 'Issuer'}: ${info.issuer}',
        ConsoleLineKind.output,
      ),
      ConsoleLine(
        '${ru ? 'Действителен до' : 'Valid until'}: ${info.validUntil.toLocal()} · $days ${ru ? 'дн.' : 'days'}',
        days <= 14 ? ConsoleLineKind.warning : ConsoleLineKind.success,
      ),
    ]);
  }

  static Future<ConsoleExecution> _sshCheck(
    List<String> args,
    bool ru,
  ) async {
    if (args.isEmpty) return _usage('ssh-check <host> [port]', ru);
    final host = args.first;
    final port = args.length > 1 ? int.tryParse(args[1]) ?? 22 : 22;
    final sample = await NetworkProbe.tcp(host, port);
    if (!sample.ok) {
      return ConsoleExecution(lines: [_sampleLine('$host:$port', sample, ru)]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(
        '$host:$port · ${sample.ms?.toStringAsFixed(1) ?? '—'} ms',
        ConsoleLineKind.success,
      ),
      ConsoleLine(
        ru
            ? 'SSH-порт доступен. Авторизация не выполнялась; ключи и пароль не запрашивались.'
            : 'SSH port is reachable. No authentication was attempted; no key or password was requested.',
        ConsoleLineKind.warning,
      ),
    ]);
  }

  static ConsoleExecution _sshHelp(bool ru) => ConsoleExecution(lines: [
        ConsoleLine(
          ru ? 'WESIOS · БЕЗОПАСНАЯ РАБОТА С SSH' : 'WESIOS · SAFE SSH',
          ConsoleLineKind.system,
        ),
        ConsoleLine(
          ru
              ? '• Приватный ключ не должен храниться в APK, Hive, исходниках или истории консоли.'
              : '• Never store a private key in the APK, Hive, source code, or console history.',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          ru
              ? '• ssh-check проверяет только доступность TCP-порта и ничего не отправляет для входа.'
              : '• ssh-check probes only TCP reachability and sends no login credentials.',
          ConsoleLineKind.output,
        ),
        ConsoleLine(
          ru
              ? '• Для реальных команд нужен серверный шлюз с короткоживущей сессией, белым списком и аудитом.'
              : '• Real commands require a server gateway with short-lived sessions, an allow-list, and audit logs.',
          ConsoleLineKind.warning,
        ),
      ]);

  static ConsoleExecution _token(List<String> args, bool ru) {
    if (args.length < 2) {
      return _usage(
        'token inspect|hash|redact <TOKEN>',
        ru,
      );
    }
    final action = args.first.toLowerCase();
    final token = args.skip(1).join(' ').trim();
    if (token.isEmpty || token == '<TOKEN>') {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Вставьте токен вместо <TOKEN>. Значение останется только в памяти до выполнения команды.'
              : 'Paste the token in place of <TOKEN>. It remains only in memory until the command completes.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    return switch (action) {
      'inspect' => _inspectToken(token, ru),
      'hash' => _hashToken(token, ru),
      'redact' => ConsoleExecution(lines: [
          ConsoleLine(_redactToken(token), ConsoleLineKind.output),
        ]),
      _ => _usage('token inspect|hash|redact <TOKEN>', ru),
    };
  }

  static ConsoleExecution _inspectToken(String token, bool ru) {
    final segments = token.split('.');
    if (segments.length != 3) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Это не JWT: ожидаются три Base64URL-сегмента. Длина секрета: ${token.length} символов.'
              : 'This is not a JWT: three Base64URL segments are expected. Secret length: ${token.length} characters.',
          ConsoleLineKind.warning,
        ),
        ConsoleLine(
          '${ru ? 'Маска' : 'Masked'}: ${_redactToken(token)}',
          ConsoleLineKind.output,
        ),
      ]);
    }

    try {
      final header = _decodeJwtSegment(segments[0]);
      final payload = _decodeJwtSegment(segments[1]);
      final lines = <ConsoleLine>[
        ConsoleLine(
          ru ? 'JWT разобран локально' : 'JWT decoded locally',
          ConsoleLineKind.success,
        ),
        ConsoleLine(
          'alg: ${header['alg'] ?? '—'} · typ: ${header['typ'] ?? '—'}',
          ConsoleLineKind.output,
        ),
      ];

      void field(String key, String labelRu, String labelEn) {
        final value = payload[key];
        if (value == null) return;
        lines.add(ConsoleLine(
          '${ru ? labelRu : labelEn}: $value',
          ConsoleLineKind.output,
        ));
      }

      field('iss', 'Издатель', 'Issuer');
      field('sub', 'Субъект', 'Subject');
      field('aud', 'Аудитория', 'Audience');
      field('scope', 'Права', 'Scope');

      final issued = _epoch(payload['iat']);
      final expires = _epoch(payload['exp']);
      if (issued != null) {
        lines.add(ConsoleLine(
          '${ru ? 'Выдан' : 'Issued'}: ${issued.toLocal()}',
          ConsoleLineKind.output,
        ));
      }
      if (expires != null) {
        final expired = !expires.isAfter(DateTime.now());
        lines.add(ConsoleLine(
          '${ru ? 'Истекает' : 'Expires'}: ${expires.toLocal()} · ${expired ? (ru ? 'ПРОСРОЧЕН' : 'EXPIRED') : (ru ? 'действует' : 'valid')}',
          expired ? ConsoleLineKind.error : ConsoleLineKind.success,
        ));
      } else {
        lines.add(ConsoleLine(
          ru ? 'Поле exp отсутствует.' : 'No exp claim is present.',
          ConsoleLineKind.warning,
        ));
      }
      lines.add(ConsoleLine(
        '${ru ? 'Маска' : 'Masked'}: ${_redactToken(token)}',
        ConsoleLineKind.output,
      ));
      lines.add(ConsoleLine(
        ru
            ? 'Подпись не проверялась: для проверки нужен доверенный публичный ключ издателя.'
            : 'Signature was not verified: a trusted issuer public key is required.',
        ConsoleLineKind.warning,
      ));
      return ConsoleExecution(lines: lines);
    } catch (_) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'JWT повреждён или содержит некорректный JSON/Base64URL.'
              : 'The JWT is malformed or contains invalid JSON/Base64URL.',
          ConsoleLineKind.error,
        ),
      ]);
    }
  }

  static ConsoleExecution _hashToken(String token, bool ru) {
    final digest = sha256.convert(utf8.encode(token)).toString();
    return ConsoleExecution(lines: [
      ConsoleLine('SHA-256: $digest', ConsoleLineKind.success),
      ConsoleLine(
        ru
            ? 'Отпечаток можно сравнивать, не раскрывая сам токен.'
            : 'The fingerprint can be compared without exposing the token itself.',
        ConsoleLineKind.output,
      ),
    ]);
  }

  static Map<String, dynamic> _decodeJwtSegment(String segment) {
    final normalized = base64Url.normalize(segment);
    final decoded = utf8.decode(base64Url.decode(normalized));
    final value = jsonDecode(decoded);
    if (value is! Map) throw const FormatException('JWT segment is not a map');
    return Map<String, dynamic>.from(value);
  }

  static DateTime? _epoch(Object? value) {
    final seconds = value is num ? value.toInt() : int.tryParse('$value');
    if (seconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
  }

  static String _redactToken(String token) {
    if (token.length <= 10) return '•' * token.length;
    return '${token.substring(0, 6)}${'•' * 10}${token.substring(token.length - 4)}';
  }

  static ConsoleExecution _load(List<String> args, bool ru) {
    MonitorTarget? target;
    if (args.isNotEmpty) {
      target = MonitorService.byId(args.first);
      if (target == null) return _missingTarget(args.first, ru);
    } else {
      for (final value in MonitorService.targets) {
        if (MonitorService.loadOf(value.id) != null) {
          target = value;
          break;
        }
      }
    }
    if (target == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Агент ещё не прислал данные нагрузки.'
              : 'The agent has not reported load yet.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    final load = MonitorService.loadOf(target.id);
    if (load == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Для ${target.name} данных нагрузки нет. Выполните status или обновите мониторинг.'
              : 'No load data for ${target.name}. Run status or refresh monitoring.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(target.name, ConsoleLineKind.system),
      ConsoleLine(
        'CPU ${(load.cpuFraction * 100).round()}% · RAM ${(load.memFraction * 100).round()}% · DISK ${(load.diskFraction * 100).round()}%',
        ConsoleLineKind.output,
      ),
      ConsoleLine(
        '${ru ? 'Аптайм' : 'Uptime'}: ${load.uptime.inHours} h · ${ru ? 'замер' : 'measured'} ${load.measuredAt.toLocal()}',
        ConsoleLineKind.output,
      ),
    ]);
  }

  static ConsoleExecution _open(List<String> args, bool ru) {
    if (args.isEmpty) return _usage('open <id>', ru);
    final target = MonitorService.byId(args.first);
    if (target == null) return _missingTarget(args.first, ru);
    return ConsoleExecution(
      lines: [
        ConsoleLine(
          ru ? 'Открываю ${target.name}…' : 'Opening ${target.name}…',
          ConsoleLineKind.system,
        ),
      ],
      openTargetId: target.id,
    );
  }

  static ConsoleExecution _history(bool ru) {
    final history = loadHistory();
    if (history.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru ? 'История пуста.' : 'History is empty.',
          ConsoleLineKind.warning,
        ),
      ]);
    }
    return ConsoleExecution(lines: [
      for (var i = 0; i < history.length; i++)
        ConsoleLine(
          '${(i + 1).toString().padLeft(2)}  ${history[i]}',
          ConsoleLineKind.output,
        ),
    ]);
  }

  static ConsoleExecution _whoami(bool ru) {
    final employee = TeamService.current;
    if (employee == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Владелец WesiOS · локальная сессия'
              : 'WesiOS owner · local session',
          ConsoleLineKind.success,
        ),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(
        '${employee.displayName} · ${employee.position}',
        ConsoleLineKind.success,
      ),
      ConsoleLine(
        '${ru ? 'Логин' : 'Login'}: ${employee.login} · ${ru ? 'владелец' : 'owner'}: ${employee.isOwner}',
        ConsoleLineKind.output,
      ),
    ]);
  }

  static ConsoleExecution _usage(String syntax, bool ru) => ConsoleExecution(
        lines: [
          ConsoleLine(
            '${ru ? 'Использование' : 'Usage'}: $syntax',
            ConsoleLineKind.warning,
          ),
        ],
      );

  static ConsoleExecution _missingTarget(String id, bool ru) =>
      ConsoleExecution(lines: [
        ConsoleLine(
          ru
              ? 'Узел «$id» не найден. Выполните targets.'
              : 'Target "$id" not found. Run targets.',
          ConsoleLineKind.error,
        ),
      ]);

  static ConsoleLine _sampleLine(String name, ProbeSample sample, bool ru) {
    final ms =
        sample.ms == null ? '' : ' · ${sample.ms!.toStringAsFixed(1)} ms';
    final detail = sample.detail == null ? '' : ' · ${sample.detail}';
    return ConsoleLine(
      '$name: ${sample.describe(russian: ru)}$ms$detail',
      sample.ok ? ConsoleLineKind.success : ConsoleLineKind.error,
    );
  }
}
