import 'package:flutter/material.dart';

import '../design/admin_theme.dart';
import '../state/admin_scope.dart';
import '../widgets/glass_card.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = AdminScope.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(GatewayTokens.space24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                title: 'Настройки Admin',
                subtitle: 'Подключение к control plane и безопасность доступа.',
              ),
              const SizedBox(height: GatewayTokens.space24),
              GlassCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.cloud_outlined),
                      title: Text(controller.isDemo ? 'Локальная демонстрация' : 'Control plane подключён'),
                      subtitle: Text(controller.remoteUrl ?? 'Изменения остаются только в этом демо-сеансе'),
                      trailing: FilledButton(
                        onPressed: controller.busy
                            ? null
                            : () => showDialog<void>(
                                  context: context,
                                  builder: (_) => const _ConnectionDialog(),
                                ),
                        child: Text(controller.isDemo ? 'Подключить' : 'Изменить'),
                      ),
                    ),
                    if (!controller.isDemo) ...[
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.science_outlined),
                        title: const Text('Вернуться в demo'),
                        subtitle: const Text('Удалить сохранённый URL и admin token с устройства'),
                        trailing: TextButton(onPressed: controller.useDemo, child: const Text('Сбросить')),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              GlassCard(
                child: Column(
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.palette_outlined),
                      title: const Text('Тема'),
                      subtitle: Text(controller.themeMode == ThemeMode.dark ? 'Тёмная WesiOS' : 'Светлая WesiOS'),
                      trailing: IconButton(
                        onPressed: controller.toggleTheme,
                        icon: Icon(
                          controller.themeMode == ThemeMode.dark
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                        ),
                      ),
                    ),
                    const Divider(height: 24),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.sync_rounded),
                      title: Text('Автообновление'),
                      subtitle: Text('Admin обновляется каждые 10 секунд, клиенты — каждые 20 секунд'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              GlassCard(
                color: context.palette.connected.withValues(alpha: 0.06),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.admin_panel_settings_outlined),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Admin token хранится в системном защищённом хранилище. '
                        'Платёжные секреты должны находиться только в окружении сервера. '
                        'Для удалённого подключения требуется HTTPS.',
                      ),
                    ),
                  ],
                ),
              ),
              if (controller.error != null) ...[
                const SizedBox(height: GatewayTokens.space16),
                Text(controller.error!, style: TextStyle(color: context.palette.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ConnectionDialog extends StatefulWidget {
  const _ConnectionDialog();

  @override
  State<_ConnectionDialog> createState() => _ConnectionDialogState();
}

class _ConnectionDialogState extends State<_ConnectionDialog> {
  late final TextEditingController _url;
  final TextEditingController _token = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(
      text: AdminScope.read(context).remoteUrl ?? 'https://gateway.example.com',
    );
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Подключить Admin API'),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Control plane URL',
                  hintText: 'https://gateway.example.com',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _token,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  labelText: 'Admin token',
                  errorText: _error,
                  suffixIcon: IconButton(
                    onPressed: () => setState(() => _obscure = !_obscure),
                    icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: _busy ? null : _connect, child: Text(_busy ? 'Проверяем…' : 'Подключить')),
        ],
      );

  Future<void> _connect() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await AdminScope.read(context).connectRemote(_url.text, _token.text);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = AdminScope.read(context).error;
        });
      }
    }
  }
}
