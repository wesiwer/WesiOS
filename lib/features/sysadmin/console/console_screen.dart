import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wesi_wordmark.dart';
import '../../../core/widgets/window_controls.dart';
import '../../team/services/team_service.dart';
import '../models/monitor_target.dart';
import '../services/monitor_service.dart';
import '../target_detail_screen.dart';
import 'console_command_service.dart';
import 'console_templates.dart';

class WesiConsoleScreen extends StatefulWidget {
  final String targetId;

  const WesiConsoleScreen({super.key, required this.targetId});

  static Future<void> open(BuildContext context, String targetId) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WesiConsoleScreen(targetId: targetId),
        ),
      );

  @override
  State<WesiConsoleScreen> createState() => _WesiConsoleScreenState();
}

class _WesiConsoleScreenState extends State<WesiConsoleScreen> {
  final TextEditingController _input = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final ScrollController _scroll = ScrollController();
  final List<ConsoleLine> _lines = [];

  late List<String> _history;
  int _historyIndex = 0;
  bool _busy = false;
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  List<String> _suggestions = const [];

  MonitorTarget? get _target => MonitorService.byId(widget.targetId);

  bool get _ru => WesiLocale.isRussian;
  bool get _android =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _history = ConsoleCommandService.loadHistory();
    _historyIndex = _history.length;
    _lines.addAll([
      ConsoleLine('WesiOS SYSTEM CONSOLE', ConsoleLineKind.system),
      ConsoleLine(
        _ru
            ? 'Диагностическая оболочка готова. Используйте шаблоны или введите help.'
            : 'Diagnostic shell ready. Use templates or type help.',
        ConsoleLineKind.success,
      ),
      ConsoleLine(
        _ru
            ? 'Защищённый режим: ключи SSH не хранятся, токены не попадают в историю.'
            : 'Protected mode: SSH keys are not stored and tokens never enter history.',
        ConsoleLineKind.warning,
      ),
    ]);
    final target = _target;
    if (target != null) {
      _lines.add(ConsoleLine(
        '${_ru ? 'Выбранный сервер' : 'Selected server'}: ${target.name} · ${target.host}:${target.port}',
        ConsoleLineKind.system,
      ));
    }
    _input.addListener(_updateSuggestions);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _input.removeListener(_updateSuggestions);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _updateSuggestions() {
    final next = ConsoleCommandService.completions(
      _input.text,
      targetId: widget.targetId,
    ).take(5).toList();
    if (listEquals(next, _suggestions) || !mounted) return;
    setState(() => _suggestions = next);
  }

  Future<void> _run([String? command]) async {
    final value = (command ?? _input.text).trim();
    if (value.isEmpty || _busy) return;

    setState(() {
      _busy = true;
      _lines.add(ConsoleLine(
        'wesi@${_target?.host ?? 'sysadmin'} › ${ConsoleCommandService.displayCommand(value)}',
        ConsoleLineKind.prompt,
      ));
      _input.clear();
      _suggestions = const [];
      _resetModifiers();
    });
    _scrollBottom();

    ConsoleExecution result;
    try {
      result = await ConsoleCommandService.execute(
        value,
        russian: _ru,
        targetId: widget.targetId,
      );
    } catch (error) {
      result = ConsoleExecution(lines: [
        ConsoleLine(
          _ru ? 'Ошибка выполнения: $error' : 'Execution error: $error',
          ConsoleLineKind.error,
        ),
      ]);
    }
    if (!mounted) return;
    setState(() {
      if (result.clear) {
        _lines.clear();
      } else if (result.lines.isEmpty && result.openTargetId == null) {
        _lines.add(ConsoleLine(
          _ru ? 'Команда выполнена.' : 'Command completed.',
          ConsoleLineKind.success,
        ));
      } else {
        _lines.addAll(result.lines);
      }
      _busy = false;
    });
    _history = ConsoleCommandService.loadHistory();
    _historyIndex = _history.length;
    _scrollBottom();
    _inputFocus.requestFocus();

    if (result.openTargetId != null && mounted) {
      await TargetDetailScreen.open(context, result.openTargetId!);
      if (mounted) _inputFocus.requestFocus();
    }
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  KeyEventResult _physicalKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    final ctrl = keyboard.isControlPressed || keyboard.isMetaPressed;
    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      _historyMove(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _historyMove(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab) {
      _complete();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _escape();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.delete) {
      _deleteForward();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyL) {
      setState(() => _lines.clear());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyA) {
      _selectAll();
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      if (_hasSelection) {
        unawaited(_copySelection());
      } else {
        _cancelLine();
      }
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyX) {
      unawaited(_cutSelection());
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyV) {
      unawaited(_pasteClipboard());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _historyMove(int delta) {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + delta).clamp(0, _history.length).toInt();
    _setInput(
      _historyIndex == _history.length ? '' : _history[_historyIndex],
    );
  }

  void _setInput(String value, {int? cursor}) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: cursor ?? value.length),
    );
    _inputFocus.requestFocus();
  }

  void _setTemplateInput(String command) {
    _setInput(command);
    final start = command.indexOf('<');
    final end = start < 0 ? -1 : command.indexOf('>', start + 1);
    if (start >= 0 && end > start) {
      _input.selection = TextSelection(
        baseOffset: start,
        extentOffset: end + 1,
      );
    }
  }

  void _applyTemplate(ConsoleTemplate template, {bool run = false}) {
    final target = _target;
    if (target == null) return;
    final command = ConsoleTemplateLibrary.resolveCommand(template, target);
    _setTemplateInput(command);
    if (run && ConsoleTemplateLibrary.canRunImmediatelyFor(template, target)) {
      unawaited(_run(command));
    }
  }

  Future<void> _showTemplates() async {
    final target = _target;
    if (target == null) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _TemplateSheet(
        russian: _ru,
        target: target,
        onInsert: (template) {
          Navigator.pop(sheetContext);
          _applyTemplate(template);
        },
        onRun: (template) {
          Navigator.pop(sheetContext);
          _applyTemplate(template, run: true);
        },
      ),
    );
    if (mounted) _inputFocus.requestFocus();
  }

  void _complete() {
    final matches = ConsoleCommandService.completions(
      _input.text,
      targetId: widget.targetId,
    );
    if (matches.isEmpty) return;
    if (matches.length == 1) {
      _setInput(matches.first);
      return;
    }
    final prefix = _commonPrefix(matches);
    if (prefix.length > _input.text.trimLeft().length) _setInput(prefix);
    setState(() => _suggestions = matches.take(5).toList());
  }

  String _commonPrefix(List<String> values) {
    if (values.isEmpty) return '';
    var prefix = values.first;
    for (final value in values.skip(1)) {
      while (prefix.isNotEmpty &&
          !value.toLowerCase().startsWith(prefix.toLowerCase())) {
        prefix = prefix.substring(0, prefix.length - 1);
      }
    }
    return prefix;
  }

  void _escape() {
    setState(() {
      _suggestions = const [];
      _resetModifiers();
    });
    _inputFocus.requestFocus();
  }

  void _cancelLine() {
    setState(() {
      _lines.add(ConsoleLine(
        _input.text.isEmpty ? '^C' : '^C ${_input.text}',
        ConsoleLineKind.warning,
      ));
      _input.clear();
      _busy = false;
      _resetModifiers();
    });
    _scrollBottom();
  }

  void _resetModifiers() {
    _ctrl = false;
    _alt = false;
    _shift = false;
  }

  void _softKey(String key) {
    switch (key) {
      case 'CTRL':
        setState(() => _ctrl = !_ctrl);
        return;
      case 'ALT':
        setState(() => _alt = !_alt);
        return;
      case 'SHIFT':
        setState(() => _shift = !_shift);
        return;
      case 'ESC':
        _escape();
        return;
      case 'TAB':
        _complete();
        return;
      case 'ENTER':
        unawaited(_run());
        return;
      case '↑':
        _historyMove(-1);
        return;
      case '↓':
        _historyMove(1);
        return;
      case '←':
        _moveCursor(-1, byWord: _alt);
        return;
      case '→':
        _moveCursor(1, byWord: _alt);
        return;
      case 'HOME':
        _selection(0);
        return;
      case 'END':
        _selection(_input.text.length);
        return;
      case 'PG↑':
        _page(-1);
        return;
      case 'PG↓':
        _page(1);
        return;
      case 'DEL':
        _deleteForward();
        return;
      case 'BKSP':
        _deleteBackward();
        return;
      case 'SELECT':
        _selectAll();
        return;
      case 'COPY':
        unawaited(_copySelection());
        return;
      case 'CUT':
        unawaited(_cutSelection());
        return;
      case 'PASTE':
        unawaited(_pasteClipboard());
        return;
    }

    if (_ctrl) {
      final handled = _control(key.toUpperCase());
      if (handled) {
        setState(() => _ctrl = false);
        return;
      }
    }

    final char = _shift ? key.toUpperCase() : key;
    _insert(char);
    if (_shift) setState(() => _shift = false);
  }

  bool _control(String key) {
    switch (key) {
      case 'C':
        if (_hasSelection) {
          unawaited(_copySelection());
        } else {
          _cancelLine();
        }
        return true;
      case 'X':
        unawaited(_cutSelection());
        return true;
      case 'V':
        unawaited(_pasteClipboard());
        return true;
      case 'L':
        setState(() => _lines.clear());
        return true;
      case 'A':
        _selectAll();
        return true;
      case 'E':
        _selection(_input.text.length);
        return true;
      case 'U':
        _replace(0, _cursor, '');
        return true;
      case 'K':
        _replace(_cursor, _input.text.length, '');
        return true;
      case 'W':
        final cursor = _cursor;
        if (cursor == 0) return true;
        var start = cursor;
        while (start > 0 && _input.text[start - 1].trim().isEmpty) {
          start--;
        }
        while (start > 0 && !_input.text[start - 1].trim().isEmpty) {
          start--;
        }
        _replace(start, cursor, '');
        return true;
      case 'R':
        setState(() {
          _suggestions = ConsoleCommandService.completions(_input.text);
        });
        return true;
    }
    return false;
  }

  bool get _hasSelection =>
      _input.selection.isValid && !_input.selection.isCollapsed;

  int get _cursor {
    final selection = _input.selection;
    if (!selection.isValid) return _input.text.length;
    return selection.extentOffset.clamp(0, _input.text.length).toInt();
  }

  void _selectAll() {
    _input.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _input.text.length,
    );
    _inputFocus.requestFocus();
  }

  Future<void> _copySelection() async {
    if (!_hasSelection) return;
    final selected = _input.selection.textInside(_input.text);
    await Clipboard.setData(ClipboardData(text: selected));
    if (mounted) _inputFocus.requestFocus();
  }

  Future<void> _cutSelection() async {
    if (!_hasSelection) return;
    final selection = _input.selection;
    await Clipboard.setData(
      ClipboardData(text: selection.textInside(_input.text)),
    );
    _replace(selection.start, selection.end, '');
  }

  Future<void> _pasteClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final value = data?.text;
    if (value == null || value.isEmpty) return;
    _insert(value);
  }

  void _insert(String text) {
    final selection = _input.selection.isValid
        ? _input.selection
        : TextSelection.collapsed(offset: _input.text.length);
    _replace(selection.start, selection.end, text);
  }

  void _replace(int start, int end, String replacement) {
    final text = _input.text;
    final safeStart = start.clamp(0, text.length).toInt();
    final safeEnd = end.clamp(safeStart, text.length).toInt();
    final next = text.replaceRange(safeStart, safeEnd, replacement);
    _setInput(next, cursor: safeStart + replacement.length);
  }

  void _moveCursor(int direction, {bool byWord = false}) {
    var cursor = _cursor;
    if (!byWord) {
      cursor = (cursor + direction).clamp(0, _input.text.length).toInt();
    } else if (direction < 0) {
      while (cursor > 0 && _input.text[cursor - 1].trim().isEmpty) {
        cursor--;
      }
      while (cursor > 0 && !_input.text[cursor - 1].trim().isEmpty) {
        cursor--;
      }
    } else {
      while (
          cursor < _input.text.length && !_input.text[cursor].trim().isEmpty) {
        cursor++;
      }
      while (
          cursor < _input.text.length && _input.text[cursor].trim().isEmpty) {
        cursor++;
      }
    }
    _selection(cursor);
  }

  void _selection(int cursor) {
    _input.selection = TextSelection.collapsed(
      offset: cursor.clamp(0, _input.text.length).toInt(),
    );
    _inputFocus.requestFocus();
  }

  void _deleteForward() {
    final selection = _input.selection;
    if (selection.isValid && !selection.isCollapsed) {
      _replace(selection.start, selection.end, '');
      return;
    }
    final cursor = _cursor;
    if (cursor < _input.text.length) _replace(cursor, cursor + 1, '');
  }

  void _deleteBackward() {
    final selection = _input.selection;
    if (selection.isValid && !selection.isCollapsed) {
      _replace(selection.start, selection.end, '');
      return;
    }
    final cursor = _cursor;
    if (cursor > 0) _replace(cursor - 1, cursor, '');
  }

  void _page(int direction) {
    if (!_scroll.hasClients) return;
    final next =
        (_scroll.offset + direction * _scroll.position.viewportDimension * .82)
            .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(
      next,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!TeamService.isOwnerSession) return _locked();
    if (_target == null) return _missingTarget();
    return ValueListenableBuilder<AppThemeMode>(
      valueListenable: ThemeNotifier.instance,
      builder: (context, _, __) => Scaffold(
        backgroundColor: const Color(0xFF060708),
        appBar: AppBar(
          backgroundColor: const Color(0xFF080A0C),
          title: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  color: AppTheme.accent.withOpacity(.13),
                  border: Border.all(
                    color: AppTheme.accent.withOpacity(.28),
                  ),
                ),
                child: Icon(Icons.terminal, size: 17, color: AppTheme.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: WesiTitle('Wesi Console · ${_target!.name}', size: 17),
              ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _ru ? 'Шаблоны команд' : 'Command templates',
              onPressed: _showTemplates,
              icon: Icon(
                Icons.dashboard_customize_outlined,
                size: 20,
                color: AppTheme.accent,
              ),
            ),
            IconButton(
              tooltip: _ru ? 'Очистить' : 'Clear',
              onPressed: () => setState(() => _lines.clear()),
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            ),
            IconButton(
              tooltip: _ru ? 'Справка' : 'Help',
              onPressed: () => unawaited(_run('help')),
              icon: const Icon(Icons.help_outline, size: 20),
            ),
            SizedBox(width: kHasCustomTitleBar ? 140 : 4),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _statusBar(),
              _quickActions(),
              Expanded(child: _terminal()),
              if (_suggestions.isNotEmpty) _completionBar(),
              _commandLine(),
              if (_android) _androidKeyboard(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _missingTarget() => Scaffold(
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

  Widget _locked() => Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const WesiTitle('Wesi Console', size: 18)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.lock_outline, size: 46, color: AppTheme.textMuted),
                const SizedBox(height: 14),
                Text(
                  _ru
                      ? 'Консоль доступна только владельцу WesiOS.'
                      : 'The console is available only to the WesiOS owner.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _statusBar() => Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: const Color(0xFF0B0E11),
          border: Border(
            bottom: BorderSide(color: AppTheme.accent.withOpacity(.15)),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: _busy ? AppTheme.accent : AppTheme.accentGreen,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: (_busy ? AppTheme.accent : AppTheme.accentGreen)
                        .withOpacity(.45),
                    blurRadius: 7,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 7),
            Text(
              _busy
                  ? (_ru ? 'ВЫПОЛНЕНИЕ' : 'RUNNING')
                  : (_ru ? 'ГОТОВО' : 'READY'),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
                color: _busy ? AppTheme.accent : AppTheme.accentGreen,
              ),
            ),
            const Spacer(),
            _statusChip(_target!.host.toUpperCase(), Icons.dns_outlined),
            const SizedBox(width: 7),
            _statusChip(
              _android ? 'ANDROID' : 'DESKTOP',
              _android ? Icons.android : Icons.desktop_windows_outlined,
            ),
          ],
        ),
      );

  Widget _statusChip(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.white.withOpacity(.035),
          border: Border.all(color: Colors.white.withOpacity(.07)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: const Color(0xFF7C858F)),
            const SizedBox(width: 4),
            Text(
              text,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 8.5,
                letterSpacing: .7,
                color: Color(0xFF7C858F),
              ),
            ),
          ],
        ),
      );

  Widget _quickActions() => Container(
        height: 52,
        color: const Color(0xFF090B0D),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          itemCount: ConsoleTemplateLibrary.pinned.length + 1,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, index) {
            if (index == ConsoleTemplateLibrary.pinned.length) {
              return ActionChip(
                avatar: Icon(Icons.grid_view_rounded,
                    size: 15, color: AppTheme.accent),
                label: Text(_ru ? 'Все шаблоны' : 'All templates'),
                onPressed: _showTemplates,
                backgroundColor: AppTheme.accent.withOpacity(.08),
                side: BorderSide(color: AppTheme.accent.withOpacity(.22)),
                labelStyle: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
              );
            }
            final template = ConsoleTemplateLibrary.pinned[index];
            return ActionChip(
              avatar: Icon(
                _categoryIcon(template.category),
                size: 15,
                color: const Color(0xFFB9C0C8),
              ),
              label: Text(template.title(_ru)),
              onPressed: () => _applyTemplate(
                template,
                run: ConsoleTemplateLibrary.canRunImmediatelyFor(
                  template,
                  _target!,
                ),
              ),
              backgroundColor: const Color(0xFF14181C),
              side: const BorderSide(color: Color(0xFF292F35)),
              labelStyle: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9.5,
                color: Color(0xFFD5D9DE),
              ),
            );
          },
        ),
      );

  Widget _terminal() => Container(
        color: const Color(0xFF060708),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility:
              !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(13, 14, 13, 20),
            itemCount: _lines.length + (_busy ? 1 : 0),
            itemBuilder: (_, index) {
              if (index == _lines.length) return _workingLine();
              return _line(_lines[index]);
            },
          ),
        ),
      );

  Widget _line(ConsoleLine line) {
    final color = switch (line.kind) {
      ConsoleLineKind.prompt => const Color(0xFFFF8A3D),
      ConsoleLineKind.success => const Color(0xFF8BD450),
      ConsoleLineKind.warning => const Color(0xFFFFB454),
      ConsoleLineKind.error => const Color(0xFFFF5C5C),
      ConsoleLineKind.system => const Color(0xFF56B6C2),
      ConsoleLineKind.output => const Color(0xFFD5D9DE),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 54,
            child: Text(
              DateFormat('HH:mm:ss').format(line.at),
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 9,
                color: Color(0xFF4B525A),
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.38,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _workingLine() => Padding(
        padding: const EdgeInsets.only(left: 54, top: 2),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.6,
                color: AppTheme.accent,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              _ru ? 'выполняется…' : 'running…',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: AppTheme.accent,
              ),
            ),
          ],
        ),
      );

  Widget _completionBar() => Container(
        height: 40,
        color: const Color(0xFF0A0C0E),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, index) {
            final value = _suggestions[index];
            return ActionChip(
              visualDensity: VisualDensity.compact,
              backgroundColor: AppTheme.accent.withOpacity(.08),
              side: BorderSide(color: AppTheme.accent.withOpacity(.2)),
              label: Text(
                value,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 9.5,
                  color: AppTheme.accent,
                ),
              ),
              onPressed: () => _setInput(value),
            );
          },
        ),
      );

  Widget _commandLine() => Focus(
        onKeyEvent: _physicalKey,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 7, 8, 7),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1013),
            border: Border(
              top: BorderSide(color: AppTheme.accent.withOpacity(.2)),
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.accent.withOpacity(.05),
                blurRadius: 16,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Row(
            children: [
              Text(
                'wesi@${_target!.host}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accentGreen,
                ),
              ),
              const Text(
                ' › ',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 13,
                  color: Color(0xFFFF8A3D),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: true,
                  smartDashesType: SmartDashesType.disabled,
                  smartQuotesType: SmartQuotesType.disabled,
                  keyboardType: TextInputType.visiblePassword,
                  keyboardAppearance: Brightness.dark,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => unawaited(_run()),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFF2F4F6),
                  ),
                  cursorColor: AppTheme.accent,
                  selectionControls: materialTextSelectionControls,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _ru ? 'команда…' : 'command…',
                    hintStyle: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Color(0xFF4F5660),
                    ),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? _cancelLine : () => unawaited(_run()),
                icon: Icon(
                  _busy
                      ? Icons.stop_circle_outlined
                      : Icons.arrow_upward_rounded,
                  color: _busy ? AppTheme.accentRed : AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _androidKeyboard() {
    const first = [
      'ESC',
      'TAB',
      'CTRL',
      'ALT',
      'SHIFT',
      '↑',
      '↓',
      '←',
      '→',
      'HOME',
      'END',
      'PG↑',
      'PG↓',
    ];
    const second = [
      'SELECT',
      'COPY',
      'CUT',
      'PASTE',
      'C',
      'L',
      'A',
      'E',
      'U',
      'K',
      'W',
      '|',
      '/',
      '\\',
      '~',
      '-',
      '_',
      ':',
      '.',
      'DEL',
      'BKSP',
      'ENTER',
    ];
    return Container(
      color: const Color(0xFF090B0D),
      padding: const EdgeInsets.fromLTRB(7, 5, 7, 7),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _keyRow(first),
          const SizedBox(height: 5),
          _keyRow(second),
        ],
      ),
    );
  }

  Widget _keyRow(List<String> keys) => SizedBox(
        height: 36,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: keys.length,
          separatorBuilder: (_, __) => const SizedBox(width: 5),
          itemBuilder: (_, index) => _key(keys[index]),
        ),
      );

  Widget _key(String label) {
    final active = (label == 'CTRL' && _ctrl) ||
        (label == 'ALT' && _alt) ||
        (label == 'SHIFT' && _shift);
    final wide = label.length > 3 || label == 'ENTER' || label == 'BKSP';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _softKey(label),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: wide ? 62 : 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: active
                ? AppTheme.accent.withOpacity(.2)
                : const Color(0xFF15191D),
            border: Border.all(
              color: active
                  ? AppTheme.accent.withOpacity(.65)
                  : const Color(0xFF292F35),
            ),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: AppTheme.accent.withOpacity(.14),
                      blurRadius: 8,
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: label.length > 5 ? 8 : 10.5,
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.accent : const Color(0xFFB7BEC6),
            ),
          ),
        ),
      ),
    );
  }
}

class _TemplateSheet extends StatelessWidget {
  final bool russian;
  final MonitorTarget target;
  final ValueChanged<ConsoleTemplate> onInsert;
  final ValueChanged<ConsoleTemplate> onRun;

  const _TemplateSheet({
    required this.russian,
    required this.target,
    required this.onInsert,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: .78,
      minChildSize: .48,
      maxChildSize: .94,
      builder: (context, controller) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0B0D10),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFF353B42),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 15, 10, 10),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: AppTheme.accent.withOpacity(.13),
                      border: Border.all(
                        color: AppTheme.accent.withOpacity(.3),
                      ),
                    ),
                    child: Icon(
                      Icons.dashboard_customize_outlined,
                      color: AppTheme.accent,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          russian ? 'Шаблоны команд' : 'Command templates',
                          style: const TextStyle(
                            color: Color(0xFFF2F4F6),
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          russian
                              ? 'Нажатие вставляет команду. Кнопка ▶ выполняет безопасный шаблон сразу.'
                              : 'Tap inserts a command. ▶ immediately runs a safe template.',
                          style: const TextStyle(
                            color: Color(0xFF858D96),
                            fontSize: 10.5,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Color(0xFF858D96)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 30),
                children: [
                  for (final category in ConsoleTemplateCategory.values) ...[
                    _categoryHeader(category),
                    for (final template
                        in ConsoleTemplateLibrary.inCategory(category))
                      _templateCard(template),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _categoryHeader(ConsoleTemplateCategory category) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
        child: Row(
          children: [
            Icon(
              _categoryIcon(category),
              size: 16,
              color: AppTheme.accent,
            ),
            const SizedBox(width: 8),
            Text(
              ConsoleTemplateLibrary.categoryTitle(category, russian)
                  .toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF8F98A2),
                fontSize: 10,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.05,
              ),
            ),
          ],
        ),
      );

  Widget _templateCard(ConsoleTemplate template) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => onInsert(template),
            child: Container(
              padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFF12161A),
                border: Border.all(color: const Color(0xFF282E34)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: template.sensitive
                          ? const Color(0xFFFFB454).withOpacity(.08)
                          : AppTheme.accent.withOpacity(.08),
                    ),
                    child: Icon(
                      template.sensitive
                          ? Icons.shield_outlined
                          : _categoryIcon(template.category),
                      size: 18,
                      color: template.sensitive
                          ? const Color(0xFFFFB454)
                          : AppTheme.accent,
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title(russian),
                          style: const TextStyle(
                            color: Color(0xFFE8EBEE),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          template.description(russian),
                          style: const TextStyle(
                            color: Color(0xFF7F8892),
                            fontSize: 9.7,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          ConsoleTemplateLibrary.resolveCommand(
                              template, target),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            color: Color(0xFFB9C0C8),
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (ConsoleTemplateLibrary.canRunImmediatelyFor(
                    template,
                    target,
                  ))
                    IconButton(
                      tooltip: russian ? 'Выполнить' : 'Run',
                      onPressed: () => onRun(template),
                      icon: Icon(
                        Icons.play_circle_outline_rounded,
                        color: AppTheme.accent,
                      ),
                    )
                  else
                    const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 18,
                        color: Color(0xFF66707A),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
}

IconData _categoryIcon(ConsoleTemplateCategory category) {
  return switch (category) {
    ConsoleTemplateCategory.wesi => Icons.hub_outlined,
    ConsoleTemplateCategory.network => Icons.language_outlined,
    ConsoleTemplateCategory.certificates => Icons.verified_user_outlined,
    ConsoleTemplateCategory.ssh => Icons.key_outlined,
    ConsoleTemplateCategory.tokens => Icons.password_outlined,
  };
}
