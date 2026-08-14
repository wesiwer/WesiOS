import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/wesi_wordmark.dart';
import '../models/monitor_target.dart';
import '../services/monitor_service.dart';
import 'ssh_client_service.dart';
import 'ssh_profile_store.dart';

class DirectSshConsoleScreen extends StatefulWidget {
  final String targetId;

  const DirectSshConsoleScreen({super.key, required this.targetId});

  static Future<void> open(BuildContext context, String targetId) =>
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DirectSshConsoleScreen(targetId: targetId),
        ),
      );

  @override
  State<DirectSshConsoleScreen> createState() => _DirectSshConsoleScreenState();
}

class _DirectSshConsoleScreenState extends State<DirectSshConsoleScreen> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  final List<_SshLine> _lines = [];
  final List<String> _history = [];

  int _historyIndex = 0;
  bool _busy = false;
  String _cwd = '~';

  bool get _ru => WesiLocale.isRussian;
  MonitorTarget? get _target => MonitorService.byId(widget.targetId);
  SshProfile? get _profile => SshProfileStore.profileFor(widget.targetId);

  @override
  void initState() {
    super.initState();
    final target = _target;
    final profile = _profile;
    _lines.add(_SshLine('WesiOS DIRECT SSH', _SshLineKind.system));
    if (target == null || profile == null) {
      _lines.add(_SshLine(
        _ru ? 'SSH-профиль не найден.' : 'SSH profile not found.',
        _SshLineKind.error,
      ));
    } else {
      _lines.add(_SshLine(
        '${profile.username}@${target.host}:${profile.port}',
        _SshLineKind.success,
      ));
      _lines.add(_SshLine(
        _ru
            ? 'Host key закреплён. Пароль/private key читается только из Secure Storage.'
            : 'Host key pinned. Password/private key is read only from Secure Storage.',
        _SshLineKind.system,
      ));
      unawaited(_initialPwd());
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _initialPwd() async {
    final target = _target;
    final profile = _profile;
    if (target == null || profile == null) return;
    try {
      final result = await SshClientService.run(target, profile, 'pwd');
      if (mounted && result.ok && result.stdout.trim().isNotEmpty) {
        setState(() => _cwd = result.stdout.trim().split('\n').last);
      }
    } catch (_) {}
  }

  Future<void> _run([String? command]) async {
    final raw = (command ?? _input.text).trim();
    if (raw.isEmpty || _busy) return;
    final target = _target;
    final profile = _profile;
    if (target == null || profile == null) return;

    if (raw == 'clear' || raw == 'cls') {
      setState(() {
        _lines.clear();
        _input.clear();
      });
      return;
    }

    if (raw == 'exit') {
      if (mounted) Navigator.pop(context);
      return;
    }

    setState(() {
      _busy = true;
      _lines.add(_SshLine(
        '${profile.username}@${target.host}:$_cwd\$ $raw',
        _SshLineKind.prompt,
      ));
      _input.clear();
      if (_history.isEmpty || _history.last != raw) _history.add(raw);
      if (_history.length > 80) _history.removeAt(0);
      _historyIndex = _history.length;
    });
    _scrollBottom();

    try {
      if (raw == 'cd' || raw.startsWith('cd ')) {
        final requested = raw == 'cd' ? '~' : raw.substring(3).trim();
        final commandText = 'cd -- ${_shellQuote(requested)} && pwd';
        final result = await SshClientService.run(target, profile, commandText);
        if (!mounted) return;
        setState(() {
          if (result.ok && result.stdout.trim().isNotEmpty) {
            _cwd = result.stdout.trim().split('\n').last;
            _lines.add(_SshLine(_cwd, _SshLineKind.output));
          } else {
            _appendResult(result);
          }
        });
      } else {
        final wrapped = _cwd == '~'
            ? raw
            : 'cd -- ${_shellQuote(_cwd)} && $raw';
        final result = await SshClientService.run(target, profile, wrapped);
        if (!mounted) return;
        setState(() => _appendResult(result));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _lines.add(_SshLine('$error', _SshLineKind.error)));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _scrollBottom();
        _focus.requestFocus();
      }
    }
  }

  void _appendResult(SshCommandResult result) {
    final text = result.combined.trimRight();
    if (text.isNotEmpty) {
      for (final line in text.split('\n')) {
        _lines.add(_SshLine(
          line,
          result.ok ? _SshLineKind.output : _SshLineKind.error,
        ));
      }
    }
    _lines.add(_SshLine(
      '${_ru ? 'Код' : 'Exit'} ${result.exitCode} · ${(result.durationMs / 1000).toStringAsFixed(2)}s',
      result.ok ? _SshLineKind.success : _SshLineKind.error,
    ));
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\\''")}'";

  void _historyMove(int delta) {
    if (_history.isEmpty) return;
    _historyIndex = (_historyIndex + delta).clamp(0, _history.length);
    final value = _historyIndex == _history.length ? '' : _history[_historyIndex];
    _input.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final target = _target;
    final profile = _profile;
    if (target == null || profile == null) {
      return Scaffold(
        backgroundColor: AppTheme.background,
        appBar: AppBar(title: const WesiTitle('SSH Console', size: 18)),
        body: Center(
          child: Text(
            _ru ? 'Настройте SSH в карточке сервера.' : 'Configure SSH in the server card.',
            style: TextStyle(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF060708),
      appBar: AppBar(
        backgroundColor: const Color(0xFF080A0C),
        title: WesiTitle('SSH · ${target.name}', size: 17),
        actions: [
          IconButton(
            tooltip: _ru ? 'Очистить' : 'Clear',
            onPressed: () => setState(() => _lines.clear()),
            icon: const Icon(Icons.cleaning_services_outlined),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: const Color(0xFF0B0E11),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: AppTheme.accentGreen),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      '${profile.username}@${target.host}:${profile.port} · ${profile.hostKeyFingerprint ?? 'host key ?'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 9.5,
                        color: Color(0xFF8F98A2),
                      ),
                    ),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 1.5),
                    ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(12),
                itemCount: _lines.length,
                itemBuilder: (_, index) => _line(_lines[index]),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 6, 6, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF0D1013),
                border: Border(top: BorderSide(color: Color(0xFF282E34))),
              ),
              child: Row(
                children: [
                  Text(
                    '${profile.username}@${target.host}:$_cwd\$ ',
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10.5,
                      color: AppTheme.accentGreen,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      focusNode: _focus,
                      enabled: !_busy,
                      autocorrect: false,
                      enableSuggestions: false,
                      keyboardType: TextInputType.visiblePassword,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => unawaited(_run()),
                      onEditingComplete: () {},
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: Color(0xFFF2F4F6),
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        isDense: true,
                        hintText: 'command…',
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _busy ? null : () => unawaited(_run()),
                    icon: Icon(Icons.arrow_upward_rounded, color: AppTheme.accent),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 42,
              child: Row(
                children: [
                  Expanded(child: _softButton('↑', () => _historyMove(-1))),
                  Expanded(child: _softButton('↓', () => _historyMove(1))),
                  Expanded(child: _softButton('clear', () => _run('clear'))),
                  Expanded(child: _softButton('pwd', () => _run('pwd'))),
                  Expanded(child: _softButton('whoami', () => _run('whoami'))),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _softButton(String label, VoidCallback onTap) => InkWell(
        onTap: _busy ? null : onTap,
        child: Container(
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFF111419),
            border: Border(top: BorderSide(color: Color(0xFF282E34))),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 10.5,
              color: Color(0xFFB7BEC6),
            ),
          ),
        ),
      );

  Widget _line(_SshLine line) {
    final color = switch (line.kind) {
      _SshLineKind.prompt => const Color(0xFFFF8A3D),
      _SshLineKind.output => const Color(0xFFD5D9DE),
      _SshLineKind.success => const Color(0xFF8BD450),
      _SshLineKind.error => const Color(0xFFFF5C5C),
      _SshLineKind.system => const Color(0xFF56B6C2),
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: SelectableText(
        line.text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11.5,
          height: 1.38,
          color: color,
        ),
      ),
    );
  }
}

enum _SshLineKind { prompt, output, success, error, system }

class _SshLine {
  final String text;
  final _SshLineKind kind;
  const _SshLine(this.text, this.kind);
}
