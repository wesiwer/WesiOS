import 'dart:convert';

import 'package:flutter/material.dart';

import '../design/admin_theme.dart';
import '../models/admin_models.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class ServersScreen extends StatelessWidget {
  const ServersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    final servers = controller.snapshot?.servers ?? const <AdminServer>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionHeading(
                title: 'Серверы',
                subtitle: 'Любое сохранение повышает ревизию каталога клиентов.',
                trailing: FilledButton.icon(
                  onPressed: controller.busy ? null : () => _edit(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Добавить'),
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              if (servers.isEmpty)
                const GlassCard(child: Text('Серверов пока нет.'))
              else
                ...servers.map(
                  (server) => Padding(
                    padding:
                        const EdgeInsets.only(bottom: GatewayTokens.space12),
                    child: _ServerCard(
                      server: server,
                      onEdit: () => _edit(context, server),
                      onDelete: () => _delete(context, server),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, [AdminServer? server]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ServerEditor(server: server),
    );
  }

  Future<void> _delete(BuildContext context, AdminServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить сервер?'),
        content: Text(
          '${server.displayName} исчезнет у клиентов после синхронизации.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await AdminScope.read(context).deleteServer(server.id);
    } catch (_) {
      if (context.mounted) _showError(context);
    }
  }
}

class _ServerCard extends StatelessWidget {
  const _ServerCard({
    required this.server,
    required this.onEdit,
    required this.onDelete,
  });

  final AdminServer server;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: (server.online ? palette.connected : palette.textMuted)
                  .withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
            ),
            child: Icon(
              server.online ? Icons.dns_rounded : Icons.dns_outlined,
              color: server.online ? palette.connected : palette.textMuted,
            ),
          ),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: GatewayTokens.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      server.displayName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (server.recommended)
                      const Chip(label: Text('Рекомендуемый')),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${server.endpoint} · ${(server.load * 100).round()}% · '
                  '${server.protocols.join(' / ')}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Изменить',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: 'Удалить',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _ServerEditor extends StatefulWidget {
  const _ServerEditor({this.server});

  final AdminServer? server;

  @override
  State<_ServerEditor> createState() => _ServerEditorState();
}

class _ServerEditorState extends State<_ServerEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _id;
  late final TextEditingController _name;
  late final TextEditingController _city;
  late final TextEditingController _country;
  late final TextEditingController _code;
  late final TextEditingController _endpoint;
  late final TextEditingController _capacity;
  late final TextEditingController _load;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  late final TextEditingController _transport;
  late bool _online;
  late bool _recommended;
  late bool _vless;
  late bool _vmess;
  late bool _amnezia;
  bool _busy = false;
  String? _jsonError;

  @override
  void initState() {
    super.initState();
    final server = widget.server;
    _id = TextEditingController(text: server?.id ?? '');
    _name = TextEditingController(text: server?.displayName ?? '');
    _city = TextEditingController(text: server?.city ?? '');
    _country = TextEditingController(text: server?.country ?? '');
    _code = TextEditingController(text: server?.countryCode ?? '');
    _endpoint = TextEditingController(text: server?.endpoint ?? '');
    _capacity = TextEditingController(text: '${server?.capacity ?? 500}');
    _load = TextEditingController(text: '${server?.load ?? 0}');
    _tags = TextEditingController(text: server?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: server?.notes ?? '');
    _transport = TextEditingController(
      text: const JsonEncoder.withIndent('  ')
          .convert(server?.transportConfig ?? {}),
    );
    _online = server?.online ?? true;
    _recommended = server?.recommended ?? false;
    _vless = server?.protocols.contains('vless-reality') ?? true;
    _vmess = server?.protocols.contains('vmess-xray') ?? true;
    _amnezia = server?.protocols.contains('amneziawg') ?? true;
  }

  @override
  void dispose() {
    for (final controller in [
      _id,
      _name,
      _city,
      _country,
      _code,
      _endpoint,
      _capacity,
      _load,
      _tags,
      _notes,
      _transport,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.server == null ? 'Новый сервер' : 'Настроить сервер'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                _two(
                  _field(_id, 'ID', enabled: widget.server == null),
                  _field(_name, 'Название'),
                ),
                const SizedBox(height: 12),
                _two(_field(_city, 'Город'), _field(_country, 'Страна')),
                const SizedBox(height: 12),
                _two(
                  _field(_code, 'Код страны'),
                  _field(_endpoint, 'Endpoint host:port'),
                ),
                const SizedBox(height: 12),
                _two(
                  _field(_capacity, 'Ёмкость', number: true),
                  _field(_load, 'Нагрузка 0–1', number: true),
                ),
                const SizedBox(height: 12),
                _field(_tags, 'Теги через запятую'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    SizedBox(
                      width: 210,
                      child: CheckboxListTile(
                        value: _vless,
                        onChanged: (value) =>
                            setState(() => _vless = value ?? false),
                        title: const Text('VLESS · REALITY'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: CheckboxListTile(
                        value: _vmess,
                        onChanged: (value) =>
                            setState(() => _vmess = value ?? false),
                        title: const Text('VMess · Xray'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    SizedBox(
                      width: 180,
                      child: CheckboxListTile(
                        value: _amnezia,
                        onChanged: (value) =>
                            setState(() => _amnezia = value ?? false),
                        title: const Text('AmneziaWG'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: SwitchListTile(
                        value: _online,
                        onChanged: (value) => setState(() => _online = value),
                        title: const Text('Онлайн'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    Expanded(
                      child: SwitchListTile(
                        value: _recommended,
                        onChanged: (value) =>
                            setState(() => _recommended = value),
                        title: const Text('Рекомендуемый'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ],
                ),
                _field(_notes, 'Заметки', lines: 2, mandatory: false),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _transport,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(
                    labelText: 'Внутренняя transport-конфигурация (JSON)',
                    errorText: _jsonError,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Сохраняем…' : 'Сохранить'),
        ),
      ],
    );
  }

  Widget _two(Widget left, Widget right) => Row(
        children: [
          Expanded(child: left),
          const SizedBox(width: 12),
          Expanded(child: right),
        ],
      );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool enabled = true,
    bool number = false,
    bool mandatory = true,
    int lines = 1,
  }) =>
      TextFormField(
        controller: controller,
        enabled: enabled,
        keyboardType: number ? TextInputType.number : null,
        minLines: lines,
        maxLines: lines,
        decoration: InputDecoration(labelText: label),
        validator: mandatory
            ? (value) => value == null || value.trim().isEmpty
                ? 'Обязательное поле'
                : null
            : null,
      );

  Future<void> _save() async {
    if (_formKey.currentState?.validate() != true ||
        (!_vless && !_vmess && !_amnezia)) {
      return;
    }
    Map<String, dynamic> transport;
    try {
      transport = jsonDecode(_transport.text) as Map<String, dynamic>;
    } catch (_) {
      setState(() => _jsonError = 'Введите корректный JSON-объект');
      return;
    }
    setState(() {
      _busy = true;
      _jsonError = null;
    });
    try {
      await AdminScope.read(context).upsertServer({
        'id': _id.text.trim(),
        'displayName': _name.text.trim(),
        'city': _city.text.trim(),
        'country': _country.text.trim(),
        'countryCode': _code.text.trim(),
        'endpoint': _endpoint.text.trim(),
        'protocols': [
          if (_vless) 'vless-reality',
          if (_vmess) 'vmess-xray',
          if (_amnezia) 'amneziawg',
        ],
        'load': double.tryParse(_load.text) ?? 0,
        'online': _online,
        'recommended': _recommended,
        'capacity': int.tryParse(_capacity.text) ?? 0,
        'tags': _tags.text
            .split(',')
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(),
        'notes': _notes.text.trim(),
        'transportConfig': transport,
      }, id: widget.server?.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() => _busy = false);
      if (mounted) _showError(context);
    }
  }
}

void _showError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        AdminScope.read(context).error ?? 'Операция не выполнена.',
      ),
    ),
  );
}
