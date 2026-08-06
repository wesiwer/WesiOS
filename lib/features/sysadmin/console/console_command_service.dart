import 'dart:convert';

import 'package:hive/hive.dart';

import '../../team/services/team_service.dart';
import '../models/monitor_target.dart';
import '../models/probe_result.dart';
import '../services/monitor_service.dart';
import '../services/network_probe.dart';

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

/// Безопасная операционная консоль WesiOS.
///
/// Она выполняет настоящие сетевые проверки из приложения, но не хранит SSH
/// ключ и не запускает произвольный shell на сервере. Приватный ключ внутри
/// APK можно извлечь, поэтому «настоящий SSH из телефона» превратил бы сам
/// серверный ключ в публичный. Для удалённых административных команд нужен
/// отдельный авторизованный серверный endpoint с аудитом и белым списком.
class ConsoleCommandService {
  static const String _settingsBox = 'wesios_settings';
  static const String _historyKey = 'sysadmin_console_history_v1';
  static const int maxHistory = 80;

  static List<String> loadHistory() {
    try {
      final raw = Hive.box<dynamic>(_settingsBox).get(_historyKey);
      if (raw is! String || raw.isEmpty) return <String>[];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return <String>[];
      return decoded.map((value) => '$value').where((value) => value.isNotEmpty).toList();
    } catch (_) {
      return <String>[];
    }
  }

  static Future<void> remember(String command) async {
    final value = command.trim();
    if (value.isEmpty) return;
    final history = loadHistory();
    history.remove(value);
    history.add(value);
    if (history.length > maxHistory) {
      history.removeRange(0, history.length - maxHistory);
    }
    try {
      await Hive.box<dynamic>(_settingsBox).put(_historyKey, jsonEncode(history));
    } catch (_) {}
  }

  static List<String> completions(String prefix) {
    final value = prefix.trimLeft().toLowerCase();
    const commands = [
      'help',
      'clear',
      'status',
      'targets',
      'probe all',
      'probe ',
      'ping ',
      'dns ',
      'http ',
      'tls ',
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
  }) async {
    final raw = input.trim();
    if (raw.isEmpty) return const ConsoleExecution();
    await remember(raw);

    final parts = _split(raw);
    final command = parts.first.toLowerCase();
    final args = parts.skip(1).toList();

    try {
      return switch (command) {
        'help' || '?' => ConsoleExecution(lines: _help(russian)),
        'clear' || 'cls' => const ConsoleExecution(clear: true),
        'status' => await _status(russian),
        'targets' || 'ls' => _targets(russian),
        'probe' => await _probe(args, russian),
        'ping' => await _ping(args, russian),
        'dns' => await _dns(args, russian),
        'http' || 'curl' => await _http(args, russian),
        'tls' || 'cert' => await _tls(args, russian),
        'load' => _load(args, russian),
        'open' => _open(args, russian),
        'history' => _history(russian),
        'date' || 'time' => ConsoleExecution(lines: [
            ConsoleLine(DateTime.now().toLocal().toString(), ConsoleLineKind.output),
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
          ru ? 'WESI CONSOLE · ДОСТУПНЫЕ КОМАНДЫ' : 'WESI CONSOLE · AVAILABLE COMMANDS',
          ConsoleLineKind.system,
        ),
        ConsoleLine('status                 ${ru ? 'сводка всей инфраструктуры' : 'infrastructure summary'}', ConsoleLineKind.output),
        ConsoleLine('targets                ${ru ? 'список узлов и их ID' : 'list targets and IDs'}', ConsoleLineKind.output),
        ConsoleLine('probe all|<id>         ${ru ? 'проверить узлы' : 'probe targets'}', ConsoleLineKind.output),
        ConsoleLine('ping <host> [port]     ${ru ? 'TCP-отклик' : 'TCP latency'}', ConsoleLineKind.output),
        ConsoleLine('dns <host>             ${ru ? 'разрешить домен' : 'resolve a domain'}', ConsoleLineKind.output),
        ConsoleLine('http <url>             ${ru ? 'проверить HTTP' : 'check HTTP'}', ConsoleLineKind.output),
        ConsoleLine('tls <host> [port]      ${ru ? 'прочитать сертификат' : 'read certificate'}', ConsoleLineKind.output),
        ConsoleLine('load [id]              ${ru ? 'нагрузка от серверного агента' : 'server-agent load'}', ConsoleLineKind.output),
        ConsoleLine('open <id>              ${ru ? 'открыть карточку узла' : 'open target details'}', ConsoleLineKind.output),
        ConsoleLine('history · date · whoami · echo · clear', ConsoleLineKind.output),
        ConsoleLine(
          ru
              ? 'Подсказка: Tab дополняет команды, ↑/↓ листают историю, Ctrl+L очищает экран.'
              : 'Tip: Tab completes commands, ↑/↓ browse history, Ctrl+L clears the screen.',
          ConsoleLineKind.warning,
        ),
      ];

  static Future<ConsoleExecution> _status(bool ru) async {
    final targets = MonitorService.targets;
    if (targets.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(ru ? 'Узлы не добавлены.' : 'No targets configured.', ConsoleLineKind.warning),
      ]);
    }
    final lines = <ConsoleLine>[
      ConsoleLine(
        ru ? 'Проверяю ${targets.length} узлов…' : 'Probing ${targets.length} targets…',
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
      ru ? 'Итог: $up/${targets.length} отвечают.' : 'Summary: $up/${targets.length} responding.',
      up == targets.length ? ConsoleLineKind.success : ConsoleLineKind.warning,
    ));
    return ConsoleExecution(lines: lines);
  }

  static ConsoleExecution _targets(bool ru) {
    final targets = MonitorService.targets;
    if (targets.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(ru ? 'Узлы не добавлены.' : 'No targets configured.', ConsoleLineKind.warning),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(ru ? 'ID · ТИП · АДРЕС' : 'ID · TYPE · ADDRESS', ConsoleLineKind.system),
      for (final target in targets)
        ConsoleLine(
          '${target.id} · ${ru ? target.labelRu() : target.labelEn()} · ${target.host}:${target.port}${target.url == null ? '' : ' · ${target.url}'}',
          ConsoleLineKind.output,
        ),
    ]);
  }

  static Future<ConsoleExecution> _probe(List<String> args, bool ru) async {
    if (args.isEmpty) {
      return _usage('probe all|<id>', ru);
    }
    if (args.first.toLowerCase() == 'all') return _status(ru);
    final target = MonitorService.byId(args.first);
    if (target == null) return _missingTarget(args.first, ru);
    final sample = await MonitorService.probe(target);
    return ConsoleExecution(lines: [
      _sampleLine(target.name, sample, ru),
    ]);
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
            : (ru ? '${args.first}: DNS не ответил' : '${args.first}: DNS lookup failed'),
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
        ConsoleLine(ru ? 'Не удалось прочитать сертификат $host:$port' : 'Could not read certificate for $host:$port', ConsoleLineKind.error),
      ]);
    }
    final days = info.daysLeft(DateTime.now());
    return ConsoleExecution(lines: [
      ConsoleLine('$host:$port', ConsoleLineKind.system),
      ConsoleLine('${ru ? 'Субъект' : 'Subject'}: ${info.subject}', ConsoleLineKind.output),
      ConsoleLine('${ru ? 'Издатель' : 'Issuer'}: ${info.issuer}', ConsoleLineKind.output),
      ConsoleLine(
        '${ru ? 'Действителен до' : 'Valid until'}: ${info.validUntil.toLocal()} · $days ${ru ? 'дн.' : 'days'}',
        days <= 14 ? ConsoleLineKind.warning : ConsoleLineKind.success,
      ),
    ]);
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
        ConsoleLine(ru ? 'Агент ещё не прислал данные нагрузки.' : 'The agent has not reported load yet.', ConsoleLineKind.warning),
      ]);
    }
    final load = MonitorService.loadOf(target.id);
    if (load == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(ru ? 'Для ${target.name} данных нагрузки нет. Выполните status или обновите мониторинг.' : 'No load data for ${target.name}. Run status or refresh monitoring.', ConsoleLineKind.warning),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine(target.name, ConsoleLineKind.system),
      ConsoleLine('CPU ${(load.cpuFraction * 100).round()}% · RAM ${(load.memFraction * 100).round()}% · DISK ${(load.diskFraction * 100).round()}%', ConsoleLineKind.output),
      ConsoleLine('${ru ? 'Аптайм' : 'Uptime'}: ${load.uptime.inHours} h · ${ru ? 'замер' : 'measured'} ${load.measuredAt.toLocal()}', ConsoleLineKind.output),
    ]);
  }

  static ConsoleExecution _open(List<String> args, bool ru) {
    if (args.isEmpty) return _usage('open <id>', ru);
    final target = MonitorService.byId(args.first);
    if (target == null) return _missingTarget(args.first, ru);
    return ConsoleExecution(
      lines: [ConsoleLine(ru ? 'Открываю ${target.name}…' : 'Opening ${target.name}…', ConsoleLineKind.system)],
      openTargetId: target.id,
    );
  }

  static ConsoleExecution _history(bool ru) {
    final history = loadHistory();
    if (history.isEmpty) {
      return ConsoleExecution(lines: [
        ConsoleLine(ru ? 'История пуста.' : 'History is empty.', ConsoleLineKind.warning),
      ]);
    }
    return ConsoleExecution(lines: [
      for (var i = 0; i < history.length; i++)
        ConsoleLine('${(i + 1).toString().padLeft(2)}  ${history[i]}', ConsoleLineKind.output),
    ]);
  }

  static ConsoleExecution _whoami(bool ru) {
    final employee = TeamService.current;
    if (employee == null) {
      return ConsoleExecution(lines: [
        ConsoleLine(ru ? 'Владелец WesiOS · локальная сессия' : 'WesiOS owner · local session', ConsoleLineKind.success),
      ]);
    }
    return ConsoleExecution(lines: [
      ConsoleLine('${employee.displayName} · ${employee.position}', ConsoleLineKind.success),
      ConsoleLine('${ru ? 'Логин' : 'Login'}: ${employee.login} · ${ru ? 'владелец' : 'owner'}: ${employee.isOwner}', ConsoleLineKind.output),
    ]);
  }

  static ConsoleExecution _usage(String syntax, bool ru) => ConsoleExecution(lines: [
        ConsoleLine('${ru ? 'Использование' : 'Usage'}: $syntax', ConsoleLineKind.warning),
      ]);

  static ConsoleExecution _missingTarget(String id, bool ru) => ConsoleExecution(lines: [
        ConsoleLine(ru ? 'Узел «$id» не найден. Выполните targets.' : 'Target "$id" not found. Run targets.', ConsoleLineKind.error),
      ]);

  static ConsoleLine _sampleLine(String name, ProbeSample sample, bool ru) {
    final ms = sample.ms == null ? '' : ' · ${sample.ms!.toStringAsFixed(1)} ms';
    final detail = sample.detail == null ? '' : ' · ${sample.detail}';
    return ConsoleLine(
      '$name: ${sample.describe(russian: ru)}$ms$detail',
      sample.ok ? ConsoleLineKind.success : ConsoleLineKind.error,
    );
  }
}