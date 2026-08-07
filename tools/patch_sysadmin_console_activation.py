from pathlib import Path
import re


def read(path):
    return Path(path).read_text(encoding='utf-8')


def write(path, text):
    Path(path).write_text(text, encoding='utf-8')


def replace_once(text, old, new, label):
    if old not in text:
        raise SystemExit(f'anchor not found: {label}')
    return text.replace(old, new, 1)


def sub_once(text, pattern, repl, label):
    new, count = re.subn(pattern, repl, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f'pattern {label}: expected 1, got {count}')
    return new

# ---------------------------------------------------------------- contacts
path = 'lib/features/team/contacts_screen.dart'
text = read(path)
if "import 'dart:async';" not in text:
    text = "import 'dart:async';\n\n" + text
text = replace_once(
    text,
    "  final Set<String> _activationBusy = <String>{};\n",
    "  final Set<String> _activationBusy = <String>{};\n  Timer? _activationTicker;\n",
    'contacts timer field',
)
text = replace_once(
    text,
    "    TeamService.ensureOwner();\n  }\n\n  @override\n  void dispose() {\n    TeamService.revision.removeListener(_refresh);\n",
    "    TeamService.ensureOwner();\n    _activationTicker = Timer.periodic(const Duration(seconds: 15), (_) {\n      if (mounted) setState(() {});\n    });\n  }\n\n  @override\n  void dispose() {\n    _activationTicker?.cancel();\n    TeamService.revision.removeListener(_refresh);\n",
    'contacts timer lifecycle',
)
activation = r'''  Widget _activationTag(EmployeeModel employee) {
    final active = EmployeeAdminService.isActivated(employee.id);
    final error = EmployeeAdminService.activationError(employee.id);
    final attempted = EmployeeAdminService.lastActivationAttempt(employee.id);
    final busy = _activationBusy.contains(employee.id);
    final age = attempted == null ? null : DateTime.now().difference(attempted);
    final stalled = !active &&
        attempted != null &&
        age != null &&
        age >= const Duration(seconds: 45);

    final color = active
        ? AppTheme.accentGreen
        : error.isNotEmpty || stalled
            ? AppTheme.accentRed
            : AppTheme.accent;
    final label = busy
        ? (_ru ? 'Проверяю активацию…' : 'Checking activation…')
        : active
            ? (_ru ? 'Активирован' : 'Activated')
            : error.isNotEmpty
                ? (_ru ? 'Ошибка активации' : 'Activation failed')
                : stalled
                    ? (_ru ? 'Активация задержалась' : 'Activation is taking too long')
                    : attempted != null
                        ? (_ru ? 'Активация…' : 'Activating…')
                        : (_ru ? 'Не активирован' : 'Not activated');

    final tag = Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy || (!active && attempted != null && !stalled && error.isEmpty)) ...[
            SizedBox(
              width: 10,
              height: 10,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: color,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );

    final canRetry = !active && !busy && (error.isNotEmpty || stalled);
    final canActivate = !active && !busy && attempted == null;
    final attemptText = attempted == null
        ? ''
        : '${_ru ? 'Последняя попытка' : 'Last attempt'}: '
            '${attempted.toLocal().toString().split('.').first}';

    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Tooltip(
            message: error.isNotEmpty
                ? error
                : attemptText.isNotEmpty
                    ? '$label\n$attemptText'
                    : label,
            child: tag,
          ),
          if (canRetry || canActivate) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: canRetry ? AppTheme.accentRed : AppTheme.accent,
              ),
              onPressed: () => _retryActivation(employee),
              icon: Icon(
                canRetry ? Icons.refresh_rounded : Icons.person_add_alt_1,
                size: 14,
              ),
              label: Text(
                canRetry
                    ? (_ru ? 'Повторить активацию' : 'Retry activation')
                    : (_ru ? 'Активировать вручную' : 'Activate manually'),
                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ],
      ),
    );
  }
'''
text = sub_once(
    text,
    r"  Widget _activationTag\(EmployeeModel employee\) \{.*?\n  Widget _tag\(String text\)",
    activation + "\n  Widget _tag(String text)",
    'activation widget',
)
write(path, text)

# -------------------------------------------------------------- sysadmin root
path = 'lib/features/sysadmin/sysadmin_screen.dart'
text = read(path)
text = text.replace("import 'console/console_screen.dart';\n", '')
state = '''class _SysadminScreenState extends State<SysadminScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => const _MonitorOverview(),
    );
  }
}

class _MonitorOverview'''
text = sub_once(
    text,
    r"class _SysadminScreenState extends State<SysadminScreen> \{.*?\n\}\n\nclass _MonitorOverview",
    state,
    'sysadmin tabs',
)
text = text.replace(
    '/// Единое рабочее место системного администратора: мониторинг и консоль.',
    '/// Системный администратор: сначала выбираем узел, затем работаем с ним.',
)
write(path, text)

# -------------------------------------------------------------- target detail
path = 'lib/features/sysadmin/target_detail_screen.dart'
text = read(path)
text = replace_once(
    text,
    "import 'models/probe_result.dart';\n",
    "import 'models/probe_result.dart';\nimport '../team/services/team_service.dart';\nimport 'console/console_screen.dart';\n",
    'target imports',
)
text = replace_once(
    text,
    "  Future<void> _edit(MonitorTarget t) async {\n",
    "  Future<void> _openConsole(MonitorTarget t) async {\n    await WesiConsoleScreen.open(context, t.id);\n  }\n\n  Future<void> _edit(MonitorTarget t) async {\n",
    'target open console method',
)
text = replace_once(
    text,
    "            IconButton(\n              tooltip: _ru ? 'Изменить' : 'Edit',\n",
    "            if (TeamService.isOwnerSession && t.kind == TargetKind.server)\n              IconButton(\n                tooltip: _ru ? 'Открыть консоль этого сервера' : 'Open this server console',\n                icon: Icon(Icons.terminal, size: 20, color: AppTheme.accent),\n                onPressed: () => _openConsole(t),\n              ),\n            IconButton(\n              tooltip: _ru ? 'Изменить' : 'Edit',\n",
    'target console button',
)
write(path, text)

# ------------------------------------------------------------------- more tab
path = 'lib/features/home/more_tab.dart'
text = read(path)
text = text.replace(
    "                ? 'Серверы, домены, TLS, нагрузка и Wesi Console'\n                : 'Servers, domains, TLS, load, and Wesi Console',",
    "                ? 'Выберите сервер: мониторинг, TLS, нагрузка и консоль'\n                : 'Choose a server: monitoring, TLS, load, and console',",
)
text = sub_once(
    text,
    r"          if \(TeamService\.isOwnerSession\)\n            _ModuleItem\(\n              route: '/sysadmin/console',.*?\n            \),\n",
    '',
    'remove standalone console tile',
)
write(path, text)

# -------------------------------------------------------------------- router
path = 'lib/core/routes/app_router.dart'
text = read(path)
text = text.replace("import '../../features/sysadmin/console/console_screen.dart';\n", '')
text = text.replace(
    "      case '/sysadmin/console':\n        return _slideUpRoute(const WesiConsoleScreen());\n",
    "      case '/sysadmin/console':\n        // Старые ссылки ведём в выбор сервера: консоль теперь контекстная.\n        return _slideUpRoute(const SysadminScreen());\n",
)
write(path, text)

# --------------------------------------------------------------- templates
path = 'lib/features/sysadmin/console/console_templates.dart'
text = read(path)
if not text.startswith("import '../models/monitor_target.dart';"):
    text = "import '../models/monitor_target.dart';\n\n" + text
repls = {
    "titleRu: 'PocketBase API',": "titleRu: 'HTTP выбранного узла',",
    "titleEn: 'PocketBase API',": "titleEn: 'Selected target HTTP',",
    "descriptionRu: 'Проверить основной health endpoint WesiOS.',": "descriptionRu: 'Проверить HTTP-ответ ранее выбранного узла.',",
    "descriptionEn: 'Check the primary WesiOS health endpoint.',": "descriptionEn: 'Check the HTTP response of the selected target.',",
    "command: 'http https://api.wesi-inc.ru/api/health',": "command: 'http',",
    "titleRu: 'Портал сотрудников',": "titleRu: 'URL выбранного узла',",
    "titleEn: 'Employee portal',": "titleEn: 'Selected target URL',",
    "descriptionRu: 'Проверить полный HTTP-ответ портала сотрудников.',": "descriptionRu: 'Проверить URL выбранного сервера или сайта.',",
    "descriptionEn: 'Check the complete employee portal HTTP response.',": "descriptionEn: 'Check the URL of the selected server or site.',",
    "command: 'http https://api.wesi-inc.ru/portal/',": "command: 'http',",
    "command: 'load wesi-russia-server',": "command: 'load',",
    "titleRu: 'DNS WesiOS',": "titleRu: 'DNS выбранного узла',",
    "titleEn: 'WesiOS DNS',": "titleEn: 'Selected target DNS',",
    "descriptionRu: 'Разрешить api.wesi-inc.ru в IP-адреса и измерить время.',": "descriptionRu: 'Разрешить имя выбранного узла в IP и измерить время.',",
    "descriptionEn: 'Resolve api.wesi-inc.ru to IP addresses and measure time.',": "descriptionEn: 'Resolve the selected target to IP addresses and measure time.',",
    "command: 'dns api.wesi-inc.ru',": "command: 'dns',",
    "titleRu: 'Отклик HTTPS',": "titleRu: 'Отклик выбранного узла',",
    "descriptionRu: 'Измерить TCP-отклик основного сервера на порту 443.',": "descriptionRu: 'Измерить TCP-отклик ранее выбранного узла.',",
    "descriptionEn: 'Measure TCP latency to the primary server on port 443.',": "descriptionEn: 'Measure TCP latency to the selected target.',",
    "command: 'ping api.wesi-inc.ru 443',": "command: 'ping',",
    "titleRu: 'Сертификат WesiOS',": "titleRu: 'TLS выбранного узла',",
    "titleEn: 'WesiOS certificate',": "titleEn: 'Selected target TLS',",
    "descriptionRu: 'Показать субъект, издателя и оставшийся срок TLS.',": "descriptionRu: 'Показать TLS-сертификат ранее выбранного узла.',",
    "command: 'tls api.wesi-inc.ru 443',": "command: 'tls',",
    "titleRu: 'SSH-порт WesiOS',": "titleRu: 'SSH выбранного сервера',",
    "titleEn: 'WesiOS SSH port',": "titleEn: 'Selected server SSH',",
    "descriptionRu: 'Без авторизации проверить, доступен ли SSH-порт сервера.',": "descriptionRu: 'Проверить SSH-порт ранее выбранного сервера без авторизации.',",
    "descriptionEn: 'Check whether the server SSH port is reachable without authenticating.',": "descriptionEn: 'Check the selected server SSH port without authenticating.',",
    "command: 'ssh-check api.wesi-inc.ru 22',": "command: 'ssh-check',",
}
for old, new in repls.items():
    if old not in text:
        raise SystemExit(f'template anchor not found: {old}')
    text = text.replace(old, new, 1)
insert = '''  static String resolveCommand(
    ConsoleTemplate template,
    MonitorTarget target,
  ) {
    final explicitUrl = target.url?.trim();
    final schemeUrl = explicitUrl != null && explicitUrl.isNotEmpty
        ? explicitUrl
        : 'https://${target.host}${target.port == 443 ? '' : ':${target.port}'}';
    return template.command
        .replaceAll('<target-id>', target.id)
        .replaceAll('<target-host>', target.host)
        .replaceAll('<target-port>', '${target.port}')
        .replaceAll('<target-url>', schemeUrl);
  }

  static bool canRunImmediatelyFor(
    ConsoleTemplate template,
    MonitorTarget target,
  ) {
    final command = resolveCommand(template, target);
    final unresolved = command.contains('<') && command.contains('>');
    return template.runImmediately && !template.sensitive && !unresolved;
  }

'''
text = replace_once(
    text,
    "  static String categoryTitle(ConsoleTemplateCategory category, bool russian) {\n",
    insert + "  static String categoryTitle(ConsoleTemplateCategory category, bool russian) {\n",
    'template helpers',
)
write(path, text)

# ----------------------------------------------------------- command service
path = 'lib/features/sysadmin/console/console_command_service.dart'
text = read(path)
text = replace_once(
    text,
    "  static List<String> completions(String prefix) {\n",
    "  static List<String> completions(String prefix, {String? targetId}) {\n",
    'completion signature',
)
text = replace_once(
    text,
    "  static Future<ConsoleExecution> execute(\n    String input, {\n    bool russian = true,\n  }) async {",
    "  static Future<ConsoleExecution> execute(\n    String input, {\n    bool russian = true,\n    String? targetId,\n  }) async {",
    'execute signature',
)
text = replace_once(
    text,
    "    final command = parts.first.toLowerCase();\n    final args = parts.skip(1).toList();\n\n    try {\n",
    "    final command = parts.first.toLowerCase();\n    final args = parts.skip(1).toList();\n    final selected = targetId == null ? null : MonitorService.byId(targetId);\n    final scopedArgs = _scopedArgs(command, args, selected);\n\n    try {\n",
    'selected target setup',
)
switch_repls = {
    "'status' => await _status(russian),": "'status' => await _status(russian, selected),",
    "'templates' => _templates(russian),": "'templates' => _templates(russian, selected),",
    "'probe' => await _probe(args, russian),": "'probe' => await _probe(scopedArgs, russian),",
    "'ping' => await _ping(args, russian),": "'ping' => await _ping(scopedArgs, russian),",
    "'dns' => await _dns(args, russian),": "'dns' => await _dns(scopedArgs, russian),",
    "'http' || 'curl' => await _http(args, russian),": "'http' || 'curl' => await _http(scopedArgs, russian),",
    "'tls' || 'cert' => await _tls(args, russian),": "'tls' || 'cert' => await _tls(scopedArgs, russian),",
    "'ssh-check' || 'sshcheck' => await _sshCheck(args, russian),": "'ssh-check' || 'sshcheck' => await _sshCheck(scopedArgs, russian),",
    "'load' => _load(args, russian),": "'load' => _load(scopedArgs, russian),",
    "'open' => _open(args, russian),": "'open' => _open(scopedArgs, russian),",
}
for old, new in switch_repls.items():
    text = replace_once(text, old, new, old)
scoped = '''  static List<String> _scopedArgs(
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

'''
text = replace_once(
    text,
    "  static List<String> _split(String input) {\n",
    scoped + "  static List<String> _split(String input) {\n",
    'scoped args helper',
)
text = replace_once(
    text,
    "  static ConsoleExecution _templates(bool ru) {\n",
    "  static ConsoleExecution _templates(bool ru, MonitorTarget? selected) {\n",
    'templates signature',
)
text = replace_once(
    text,
    "            '${template.title(ru)} · ${template.command}',\n",
    "            '${template.title(ru)} · ${selected == null ? template.command : ConsoleTemplateLibrary.resolveCommand(template, selected)}',\n",
    'template output resolution',
)
text = replace_once(
    text,
    "  static Future<ConsoleExecution> _status(bool ru) async {\n    final targets = MonitorService.targets;\n",
    "  static Future<ConsoleExecution> _status(\n    bool ru, [\n    MonitorTarget? selected,\n  ]) async {\n    if (selected != null) {\n      final sample = await MonitorService.probe(selected);\n      await MonitorService.refreshSlow(selected);\n      final load = MonitorService.loadOf(selected.id);\n      final tls = MonitorService.tlsOf(selected.id);\n      return ConsoleExecution(lines: [\n        ConsoleLine(\n          '${selected.name} · ${selected.host}:${selected.port}',\n          ConsoleLineKind.system,\n        ),\n        _sampleLine(selected.name, sample, ru),\n        if (tls != null)\n          ConsoleLine(\n            '${ru ? 'TLS до' : 'TLS until'} ${tls.validUntil.toLocal()}',\n            ConsoleLineKind.success,\n          ),\n        if (load != null)\n          ConsoleLine(\n            'CPU ${(load.cpuFraction * 100).round()}% · RAM ${(load.memFraction * 100).round()}% · DISK ${(load.diskFraction * 100).round()}%',\n            ConsoleLineKind.output,\n          ),\n      ]);\n    }\n\n    final targets = MonitorService.targets;\n",
    'target status',
)
write(path, text)

# --------------------------------------------------------------- console UI
path = 'lib/features/sysadmin/console/console_screen.dart'
text = read(path)
text = replace_once(
    text,
    "import '../target_detail_screen.dart';\n",
    "import '../models/monitor_target.dart';\nimport '../services/monitor_service.dart';\nimport '../target_detail_screen.dart';\n",
    'console imports',
)
text = replace_once(
    text,
    "class WesiConsoleScreen extends StatefulWidget {\n  const WesiConsoleScreen({super.key});\n",
    "class WesiConsoleScreen extends StatefulWidget {\n  final String targetId;\n\n  const WesiConsoleScreen({super.key, required this.targetId});\n\n  static Future<void> open(BuildContext context, String targetId) =>\n      Navigator.push(\n        context,\n        MaterialPageRoute(\n          builder: (_) => WesiConsoleScreen(targetId: targetId),\n        ),\n      );\n",
    'console constructor',
)
text = replace_once(
    text,
    "  List<String> _suggestions = const [];\n\n  bool get _ru",
    "  List<String> _suggestions = const [];\n\n  MonitorTarget? get _target => MonitorService.byId(widget.targetId);\n\n  bool get _ru",
    'console target getter',
)
text = replace_once(
    text,
    "    _input.addListener(_updateSuggestions);\n",
    "    final target = _target;\n    if (target != null) {\n      _lines.add(ConsoleLine(\n        '${_ru ? 'Выбранный сервер' : 'Selected server'}: ${target.name} · ${target.host}:${target.port}',\n        ConsoleLineKind.system,\n      ));\n    }\n    _input.addListener(_updateSuggestions);\n",
    'console init target',
)
text = replace_once(
    text,
    "    final next = ConsoleCommandService.completions(_input.text).take(5).toList();\n",
    "    final next = ConsoleCommandService.completions(\n      _input.text,\n      targetId: widget.targetId,\n    ).take(5).toList();\n",
    'console suggestions target',
)
text = replace_once(
    text,
    "        'wesi@sysadmin › ${ConsoleCommandService.displayCommand(value)}',\n",
    "        'wesi@${_target?.host ?? 'sysadmin'} › ${ConsoleCommandService.displayCommand(value)}',\n",
    'console prompt output',
)
text = replace_once(
    text,
    "    final result = await ConsoleCommandService.execute(value, russian: _ru);\n",
    "    ConsoleExecution result;\n    try {\n      result = await ConsoleCommandService.execute(\n        value,\n        russian: _ru,\n        targetId: widget.targetId,\n      );\n    } catch (error) {\n      result = ConsoleExecution(lines: [\n        ConsoleLine(\n          _ru ? 'Ошибка выполнения: $error' : 'Execution error: $error',\n          ConsoleLineKind.error,\n        ),\n      ]);\n    }\n",
    'console execute target',
)
text = replace_once(
    text,
    "      if (result.clear) {\n        _lines.clear();\n      } else {\n        _lines.addAll(result.lines);\n      }\n",
    "      if (result.clear) {\n        _lines.clear();\n      } else if (result.lines.isEmpty && result.openTargetId == null) {\n        _lines.add(ConsoleLine(\n          _ru ? 'Команда выполнена.' : 'Command completed.',\n          ConsoleLineKind.success,\n        ));\n      } else {\n        _lines.addAll(result.lines);\n      }\n",
    'console empty result',
)
text = sub_once(
    text,
    r"  void _applyTemplate\(ConsoleTemplate template, \{bool run = false\}\) \{.*?\n  \}\n\n  Future<void> _showTemplates",
    "  void _applyTemplate(ConsoleTemplate template, {bool run = false}) {\n    final target = _target;\n    if (target == null) return;\n    final command = ConsoleTemplateLibrary.resolveCommand(template, target);\n    _setTemplateInput(command);\n    if (run && ConsoleTemplateLibrary.canRunImmediatelyFor(template, target)) {\n      unawaited(_run(command));\n    }\n  }\n\n  Future<void> _showTemplates",
    'apply template',
)
text = replace_once(
    text,
    "  Future<void> _showTemplates() async {\n    await showModalBottomSheet<void>(\n",
    "  Future<void> _showTemplates() async {\n    final target = _target;\n    if (target == null) return;\n    await showModalBottomSheet<void>(\n",
    'show templates target guard',
)
text = replace_once(
    text,
    "      builder: (sheetContext) => _TemplateSheet(\n        russian: _ru,\n",
    "      builder: (sheetContext) => _TemplateSheet(\n        russian: _ru,\n        target: target,\n",
    'template sheet target',
)
text = replace_once(
    text,
    "    final matches = ConsoleCommandService.completions(_input.text);\n",
    "    final matches = ConsoleCommandService.completions(\n      _input.text,\n      targetId: widget.targetId,\n    );\n",
    'console complete target',
)
text = replace_once(
    text,
    "  Widget build(BuildContext context) {\n    if (!TeamService.isOwnerSession) return _locked();\n",
    "  Widget build(BuildContext context) {\n    if (!TeamService.isOwnerSession) return _locked();\n    if (_target == null) return _missingTarget();\n",
    'console missing target guard',
)
text = replace_once(
    text,
    "              const Expanded(child: WesiTitle('Wesi Console', size: 17)),\n",
    "              Expanded(\n                child: WesiTitle('Wesi Console · ${_target!.name}', size: 17),\n              ),\n",
    'console title',
)
text = replace_once(
    text,
    "            _statusChip('OWNER', Icons.verified_user_outlined),\n            const SizedBox(width: 7),\n",
    "            _statusChip(_target!.host.toUpperCase(), Icons.dns_outlined),\n            const SizedBox(width: 7),\n",
    'console status selected host',
)
text = replace_once(
    text,
    "              onPressed: () => _applyTemplate(\n                template,\n                run: template.canRunImmediately,\n              ),\n",
    "              onPressed: () => _applyTemplate(\n                template,\n                run: ConsoleTemplateLibrary.canRunImmediatelyFor(\n                  template,\n                  _target!,\n                ),\n              ),\n",
    'quick template run',
)
text = replace_once(
    text,
    "                'wesi@sysadmin',\n",
    "                'wesi@${_target!.host}',\n",
    'command line prompt',
)
missing_widget = '''  Widget _missingTarget() => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const WesiTitle('Wesi Console', size: 18)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              _ru
                  ? 'Сервер больше не найден. Вернитесь в «Системный администратор» и выберите узел заново.'
                  : 'The server no longer exists. Return to System administrator and select it again.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
        ),
      );

'''
text = replace_once(
    text,
    "  Widget _locked() => Scaffold(\n",
    missing_widget + "  Widget _locked() => Scaffold(\n",
    'missing target widget',
)
text = replace_once(
    text,
    "class _TemplateSheet extends StatelessWidget {\n  final bool russian;\n",
    "class _TemplateSheet extends StatelessWidget {\n  final bool russian;\n  final MonitorTarget target;\n",
    'template target field',
)
text = replace_once(
    text,
    "  const _TemplateSheet({\n    required this.russian,\n",
    "  const _TemplateSheet({\n    required this.russian,\n    required this.target,\n",
    'template constructor target',
)
text = replace_once(
    text,
    "                          template.command,\n",
    "                          ConsoleTemplateLibrary.resolveCommand(template, target),\n",
    'template display resolved',
)
text = replace_once(
    text,
    "                  if (template.canRunImmediately)\n",
    "                  if (ConsoleTemplateLibrary.canRunImmediatelyFor(\n                    template,\n                    target,\n                  ))\n",
    'template run button resolved',
)
write(path, text)

# --------------------------------------------------------------------- tests
path = 'test/sysadmin_console_test.dart'
text = read(path)
if "monitor_service.dart" not in text:
    text = replace_once(
        text,
        "import 'package:wesios/features/sysadmin/console/console_templates.dart';\n",
        "import 'package:wesios/features/sysadmin/console/console_templates.dart';\nimport 'package:wesios/features/sysadmin/services/monitor_service.dart';\n",
        'test monitor import',
    )
text = text.replace(
    "    expect(text, contains('tls api.wesi-inc.ru 443'));\n",
    "    expect(text, contains('tls'));\n",
)
extra = '''
  test('шаблоны и команды привязываются к выбранному серверу', () async {
    final target = MonitorService.byId('wesi-russia-server');
    expect(target, isNotNull);

    final result = await ConsoleCommandService.execute(
      'templates',
      targetId: target!.id,
    );
    final text = result.lines.map((line) => line.text).join('\n');

    expect(text, contains('Отклик выбранного узла'));
    expect(text, contains('ping'));
    expect(text, contains('ssh-check'));

    final httpTemplate = ConsoleTemplateLibrary.all
        .firstWhere((value) => value.id == 'wesi-api-health');
    expect(
      ConsoleTemplateLibrary.canRunImmediatelyFor(httpTemplate, target),
      isTrue,
    );
  });
'''
text = replace_once(
    text,
    "  test('clear возвращает управляющий флаг без вывода', () async {\n",
    extra + "\n  test('clear возвращает управляющий флаг без вывода', () async {\n",
    'target console test',
)
write(path, text)

print('sysadmin console + activation patch applied')
