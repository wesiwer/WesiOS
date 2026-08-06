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
import '../target_detail_screen.dart';
import 'console_command_service.dart';

class WesiConsoleScreen extends StatefulWidget {
  const WesiConsoleScreen({super.key});

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

  bool get _ru => WesiLocale.isRussian;
  bool get _android => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  void initState() {
    super.initState();
    _history = ConsoleCommandService.loadHistory();
    _historyIndex = _history.length;
    _lines.addAll([
      ConsoleLine('WesiOS SYSTEM CONSOLE', ConsoleLineKind.system),
      ConsoleLine(
        _ru
            ? 'Диагностическая оболочка готова. Введите help или нажмите Tab.'
            : 'Diagnostic shell ready. Type help or press Tab.',
        ConsoleLineKind.success,
      ),
      ConsoleLine(
        _ru
            ? 'Режим защиты: SSH-ключи в приложении не хранятся; команды выполняют реальные сетевые проверки.'
            : 'Protected mode: no SSH keys are stored in the app; commands run real network diagnostics.',
        ConsoleLineKind.warning,
      ),
    ]);
    _input.addListener(_updateSuggestions);
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
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
    final next = ConsoleCommandService.completions(_input.text).take(5).toList();
    if (listEquals(next, _suggestions)) return;
    if (mounted) setState(() => _suggestions = next);
  }

  Future<void> _run([String? command]) async {
    final value = (command ?? _input.text).trim();
    if (value.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _lines.add(ConsoleLine('wesi@sysadmin › $value', ConsoleLineKind.prompt));
      _input.clear();
      _suggestions = const [];
      _resetModifiers();
    });
    _history = ConsoleCommandService.loadHistory();
    _historyIndex = _history.length;
    _scrollBottom();

    final result = await ConsoleCommandService.execute(value, russian: _ru);
    if (!mounted) return;
    setState(() {
      if (result.clear) {
        _lines.clear();
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
      _inputFocus.requestFocus();
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
    if (ctrl && key == LogicalKeyboardKey.keyL) {
      setState(_lines.clear);
      return KeyEventResult.handled;
    }
    if (ctrl && key == LogicalKeyboardKey.keyC) {
      _cancelLine();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _historyMove(int delta) {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + delta).clamp(0, _history.length).toInt();
    if (_historyIndex == _history.length) {
      _setInput('');
    } else {
      _setInput(_history[_historyIndex]);
    }
  }

  void _setInput(String value, {int? cursor}) {
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: cursor ?? value.length),
    );
    _inputFocus.requestFocus();
  }

  void _complete() {
    final matches = ConsoleCommandService.completions(_input.text);
    if (matches.isEmpty) return;
    if (matches.length == 1) {
      _setInput(matches.first);
      return;
    }
    final prefix = _commonPrefix(matches);
    if (prefix.length > _input.text.trimLeft().length) {
      _setInput(prefix);
    }
    setState(() => _suggestions = matches.take(5).toList());
  }

  String _commonPrefix(List<String> values) {
    if (values.isEmpty) return '';
    var prefix = values.first;
    for (final value in values.skip(1)) {
      while (!value.toLowerCase().startsWith(prefix.toLowerCase()) &&
          prefix.isNotEmpty) {
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
      if (_input.text.isNotEmpty) {
        _lines.add(ConsoleLine('^C ${_input.text}', ConsoleLineKind.warning));
      } else {
        _lines.add(ConsoleLine('^C', ConsoleLineKind.warning));
      }
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
    if (key == 'CTRL') {
      setState(() => _ctrl = !_ctrl);
      return;
    }
    if (key == 'ALT') {
      setState(() => _alt = !_alt);
      return;
    }
    if (key == 'SHIFT') {
      setState(() => _shift = !_shift);
      return;
    }
    if (key == 'ESC') {
      _escape();
      return;
    }
    if (key == 'TAB') {
      _complete();
      return;
    }
    if (key == 'ENTER') {
      _run();
      return;
    }
    if (key == '↑') {
      _historyMove(-1);
      return;
    }
    if (key == '↓') {
      _historyMove(1);
      return;
    }
    if (key == '←') {
      _moveCursor(-1, byWord: _alt);
      return;
    }
    if (key == '→') {
      _moveCursor(1, byWord: _alt);
      return;
    }
    if (key == 'HOME') {
      _selection(0);
      return;
    }
    if (key == 'END') {
      _selection(_input.text.length);
      return;
    }
    if (key == 'PG↑') {
      _page(-1);
      return;
    }
    if (key == 'PG↓') {
      _page(1);
      return;
    }
    if (key == 'DEL') {
      _deleteForward();
      return;
    }
    if (key == 'BKSP') {
      _deleteBackward();
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
        _cancelLine();
        return true;
      case 'L':
        setState(_lines.clear);
        return true;
      case 'A':
        _input.selection = TextSelection(baseOffset: 0, extentOffset: _input.text.length);
        return true;
      case 'E':
        _selection(_input.text.length);
        return true;
      case 'U':
        final cursor = _cursor;
        _replace(0, cursor, '');
        return true;
      case 'K':
        final cursor = _cursor;
        _replace(cursor, _input.text.length, '');
        return true;
      case 'W':
        final cursor = _cursor;
        if (cursor == 0) return true;
        var start = cursor;
        while (start > 0 && _input.text[start - 1].trim().isEmpty) start--;
        while (start > 0 && !_input.text[start - 1].trim().isEmpty) start--;
        _replace(start, cursor, '');
        return true;
      case 'R':
        setState(() => _suggestions = ConsoleCommandService.completions(_input.text));
        return true;
    }
    return false;
  }

  int get _cursor {
    final selection = _input.selection;
    if (!selection.isValid) return _input.text.length;
    return selection.extentOffset.clamp(0, _input.text.length).toInt();
  }

  void _insert(String text) {
    final selection = _input.selection.isValid
        ? _input.selection
        : TextSelection.collapsed(offset: _input.text.length);
    _replace(selection.start, selection.end, text);
  }

  void _replace(int start, int end, String replacement) {
    final text = _input.text;
    final next = text.replaceRange(start, end, replacement);
    _setInput(next, cursor: start + replacement.length);
  }

  void _moveCursor(int direction, {bool byWord = false}) {
    var cursor = _cursor;
    if (!byWord) {
      cursor = (cursor + direction).clamp(0, _input.text.length).toInt();
    } else if (direction < 0) {
      while (cursor > 0 && _input.text[cursor - 1].trim().isEmpty) cursor--;
      while (cursor > 0 && !_input.text[cursor - 1].trim().isEmpty) cursor--;
    } else {
      while (cursor < _input.text.length && !_input.text[cursor].trim().isEmpty) {
        cursor++;
      }
      while (cursor < _input.text.length && _input.text[cursor].trim().isEmpty) {
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
    final next = (_scroll.offset + direction * _scroll.position.viewportDimension * .82)
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
                  border: Border.all(color: AppTheme.accent.withOpacity(.28)),
                ),
                child: Icon(Icons.terminal, size: 17, color: AppTheme.accent),
              ),
              const SizedBox(width: 10),
              const Expanded(child: WesiTitle('Wesi Console', size: 17)),
            ],
          ),
          actions: [
            IconButton(
              tooltip: _ru ? 'Очистить' : 'Clear',
              onPressed: () => setState(_lines.clear),
              icon: const Icon(Icons.cleaning_services_outlined, size: 20),
            ),
            IconButton(
              tooltip: _ru ? 'Справка' : 'Help',
              onPressed: () => _run('help'),
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
            _statusChip('OWNER', Icons.verified_user_outlined),
            const SizedBox(width: 7),
            _statusChip(_android ? 'ANDROID' : 'DESKTOP',
                _android ? Icons.android : Icons.desktop_windows_outlined),
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
            Text(text,
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 8.5,
                    letterSpacing: .7,
                    color: Color(0xFF7C858F))),
          ],
        ),
      );

  Widget _terminal() => Container(
        color: const Color(0xFF060708),
        child: Scrollbar(
          controller: _scroll,
          thumbVisibility: !kIsWeb && defaultTargetPlatform == TargetPlatform.windows,
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
              Text('wesi@sysadmin',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.accentGreen)),
              const Text(' › ',
                  style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                      color: Color(0xFFFF8A3D))),
              Expanded(
                child: TextField(
                  controller: _input,
                  focusNode: _inputFocus,
                  enabled: !_busy,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _run(),
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: Color(0xFFF2F4F6),
                  ),
                  cursorColor: AppTheme.accent,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: _ru ? 'команда…' : 'command…',
                    hintStyle: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                        color: Color(0xFF4F5660)),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 7),
                  ),
                ),
              ),
              IconButton(
                onPressed: _busy ? _cancelLine : () => _run(),
                icon: Icon(
                  _busy ? Icons.stop_circle_outlined : Icons.arrow_upward_rounded,
                  color: _busy ? AppTheme.accentRed : AppTheme.accent,
                ),
              ),
            ],
          ),
        ),
      );

  Widget _androidKeyboard() {
    final first = ['ESC', 'TAB', 'CTRL', 'ALT', 'SHIFT', '↑', '↓', '←', '→', 'HOME', 'END', 'PG↑', 'PG↓'];
    final second = ['C', 'L', 'A', 'E', 'U', 'K', 'W', '|', '/', '\\', '~', '-', '_', ':', '.', 'DEL', 'BKSP', 'ENTER'];
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
          width: wide ? 58 : 38,
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
              fontSize: label.length > 4 ? 8.5 : 10.5,
              fontWeight: FontWeight.w700,
              color: active ? AppTheme.accent : const Color(0xFFB7BEC6),
            ),
          ),
        ),
      ),
    );
  }
}