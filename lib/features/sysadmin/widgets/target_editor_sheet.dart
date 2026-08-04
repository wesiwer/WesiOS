import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../models/monitor_target.dart';
import '../services/monitor_service.dart';

/// Добавление и правка наблюдаемого узла.
class TargetEditorSheet extends StatefulWidget {
  final MonitorTarget? initial;

  const TargetEditorSheet({super.key, this.initial});

  static Future<MonitorTarget?> show(
    BuildContext context, {
    MonitorTarget? initial,
  }) {
    return showModalBottomSheet<MonitorTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TargetEditorSheet(initial: initial),
    );
  }

  @override
  State<TargetEditorSheet> createState() => _TargetEditorSheetState();
}

class _TargetEditorSheetState extends State<TargetEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initial?.name ?? '');
  late final TextEditingController _host =
      TextEditingController(text: widget.initial?.host ?? '');
  late final TextEditingController _port =
      TextEditingController(text: '${widget.initial?.port ?? 443}');
  late final TextEditingController _url =
      TextEditingController(text: widget.initial?.url ?? '');
  late final TextEditingController _loadUrl =
      TextEditingController(text: widget.initial?.loadUrl ?? '');

  late TargetKind _kind = widget.initial?.kind ?? TargetKind.server;
  late bool _tls = widget.initial?.checkTls ?? false;
  String? _error;

  bool get _ru => WesiLocale.isRussian;

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _url.dispose();
    _loadUrl.dispose();
    super.dispose();
  }

  /// Разумные умолчания при смене типа.
  ///
  /// Порт 443 для домена и сайта, 22 для сервера: у свежей машины из портов
  /// открыт обычно только SSH, и проверка по 443 показывала бы «не отвечает»
  /// на совершенно живом сервере.
  void _kindChanged(TargetKind kind) {
    setState(() {
      _kind = kind;
      final wasDefault = _port.text == '443' || _port.text == '22';
      if (wasDefault) {
        _port.text = kind == TargetKind.server ? '22' : '443';
      }
      if (kind != TargetKind.server) _tls = true;
    });
  }

  void _save() {
    final host = _host.text.trim();
    if (host.isEmpty) {
      setState(() => _error = _ru ? 'Нужен адрес или имя' : 'Host required');
      return;
    }
    final port = int.tryParse(_port.text.trim());
    if (port == null || port < 1 || port > 65535) {
      setState(() => _error = _ru ? 'Порт от 1 до 65535' : 'Port 1..65535');
      return;
    }

    final target = (widget.initial ??
            MonitorTarget(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: host,
              host: host,
            ))
        .copyWith(
      name: _name.text.trim().isEmpty ? host : _name.text.trim(),
      host: host,
      port: port,
      url: _url.text.trim().isEmpty ? null : _url.text.trim(),
      loadUrl: _loadUrl.text.trim().isEmpty ? null : _loadUrl.text.trim(),
      kind: _kind,
      checkTls: _tls,
    );

    unawaitedSave(target);
    Navigator.pop(context, target);
  }

  void unawaitedSave(MonitorTarget target) {
    if (widget.initial == null) {
      MonitorService.add(target);
    } else {
      MonitorService.update(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.glassBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.initial == null
                    ? (_ru ? 'Новый узел' : 'New target')
                    : (_ru ? 'Правка узла' : 'Edit target'),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  for (final k in TargetKind.values) ...[
                    Expanded(child: _kindChip(k)),
                    if (k != TargetKind.values.last) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              _field(_name, _ru ? 'Название' : 'Name',
                  _ru ? 'Сервер СПб' : 'Main server'),
              const SizedBox(height: 10),
              _field(_host, _ru ? 'Адрес или имя' : 'Host',
                  _ru ? '203.0.113.10 или sync.домен.ru' : 'host or IP'),
              const SizedBox(height: 10),
              _field(_port, _ru ? 'Порт для замера' : 'Port', '443',
                  keyboard: TextInputType.number),
              if (_kind != TargetKind.server) ...[
                const SizedBox(height: 10),
                _field(_url, _ru ? 'Адрес страницы' : 'Page URL',
                    'https://…'),
              ],
              const SizedBox(height: 10),
              _field(
                _loadUrl,
                _ru ? 'Адрес агента (необязательно)' : 'Agent URL (optional)',
                'https://…/wesios-status.json',
              ),
              const SizedBox(height: 6),
              Text(
                _ru
                    ? 'Загрузку процессора и памяти из сети узнать нельзя — '
                        'её присылает агент с самого сервера. Установка: '
                        'server/wesios-agent.sh'
                    : 'CPU and memory cannot be read over the network — an '
                        'agent on the server reports them. See '
                        'server/wesios-agent.sh',
                style: TextStyle(
                    fontSize: 10.5, height: 1.4, color: AppTheme.textMuted),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _tls = !_tls),
                child: Row(
                  children: [
                    Icon(
                      _tls ? Icons.check_box : Icons.check_box_outline_blank,
                      size: 19,
                      color: _tls ? AppTheme.accent : AppTheme.textMuted,
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        _ru
                            ? 'Следить за сроком сертификата'
                            : 'Watch certificate expiry',
                        style: TextStyle(
                            fontSize: 12.5, color: AppTheme.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style: TextStyle(
                        fontSize: 12, color: AppTheme.accentRed)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.initial != null) ...[
                    _button(
                      _ru ? 'Удалить' : 'Delete',
                      () {
                        MonitorService.remove(widget.initial!.id);
                        Navigator.pop(context);
                      },
                      color: AppTheme.accentRed,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: _button(
                      _ru ? 'Сохранить' : 'Save',
                      _save,
                      filled: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kindChip(TargetKind k) {
    final on = k == _kind;
    final label = switch (k) {
      TargetKind.server => _ru ? 'Сервер' : 'Server',
      TargetKind.domain => _ru ? 'Домен' : 'Domain',
      TargetKind.site => _ru ? 'Сайт' : 'Site',
    };
    return GestureDetector(
      onTap: () => _kindChanged(k),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on
              ? AppTheme.accent.withOpacity(0.16)
              : AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: on ? AppTheme.accent.withOpacity(0.5)
                  : AppTheme.glassBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: on ? FontWeight.w700 : FontWeight.w400,
            color: on ? AppTheme.accent : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    TextInputType? keyboard,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            keyboardType: keyboard,
            style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle:
                  TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              filled: true,
              fillColor: AppTheme.surfaceLight.withOpacity(0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: AppTheme.glassBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: AppTheme.accent),
              ),
            ),
          ),
        ],
      );

  Widget _button(String label, VoidCallback onTap,
      {bool filled = false, Color? color}) {
    final accent = color ?? AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled
              ? accent.withOpacity(0.18)
              : AppTheme.surface.withOpacity(0.4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: accent.withOpacity(0.5)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w600, color: accent),
        ),
      ),
    );
  }
}
