import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'wesi_connector_api.dart';

class WesiConnectorManagerSheet extends StatefulWidget {
  const WesiConnectorManagerSheet({super.key});
  @override
  State<WesiConnectorManagerSheet> createState() =>
      _WesiConnectorManagerSheetState();
}

class _WesiConnectorManagerSheetState extends State<WesiConnectorManagerSheet> {
  final WesiConnectorApi _api = const WesiConnectorApi();
  List<WesiConnectorProvider> _providers = const [];
  WesiGithubDeviceFlow? _flow;
  Timer? _pollTimer;
  bool _loading = true, _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_reload());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final rows = await _api.listProviders();
      if (!mounted) return;
      setState(() {
        _providers = rows;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _startGithub() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final flow = await _api.startGithub();
      if (!mounted) return;
      setState(() {
        _flow = flow;
        _busy = false;
      });
      _schedulePoll(flow.intervalSeconds);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  void _schedulePoll(int seconds) {
    _pollTimer?.cancel();
    _pollTimer = Timer(Duration(seconds: seconds.clamp(5, 60).toInt()),
        () => unawaited(_pollGithub()));
  }

  Future<void> _pollGithub() async {
    final flow = _flow;
    if (flow == null || _busy || DateTime.now().toUtc().isAfter(flow.expiresAt))
      return;
    setState(() => _busy = true);
    try {
      final result = await _api.pollGithub(flow.flowId);
      if (!mounted) return;
      if (result.connected) {
        _pollTimer?.cancel();
        setState(() {
          _flow = null;
          _busy = false;
        });
        await _reload();
        return;
      }
      setState(() => _busy = false);
      _schedulePoll(result.retryAfterSeconds);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
      _schedulePoll(flow.intervalSeconds);
    }
  }

  Future<void> _disconnect(WesiConnectorCredential credential) async {
    final yes = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
                    title: const Text('Отключить GitHub?'),
                    content: Text(
                        'Wesi AI перестанет использовать аккаунт ${credential.accountLogin}. Токен будет удалён из WesiOS.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Отмена')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Отключить'))
                    ])) ??
        false;
    if (!yes) return;
    setState(() => _busy = true);
    try {
      await _api.disconnect(credential);
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
        child: Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        const Icon(Icons.hub_outlined),
                        const SizedBox(width: 10),
                        Text('Коннекторы Wesi AI',
                            style: Theme.of(context).textTheme.titleLarge),
                        const Spacer(),
                        IconButton(
                            onPressed: _busy ? null : _reload,
                            tooltip: 'Обновить',
                            icon: const Icon(Icons.refresh))
                      ]),
                      const SizedBox(height: 8),
                      Text(
                          'Секреты OAuth хранятся только в зашифрованном серверном vault. Wesi AI получает logical credential ID и разрешённые capabilities, но не токены.',
                          style: Theme.of(context).textTheme.bodySmall),
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error))
                      ],
                      const SizedBox(height: 12),
                      if (_loading)
                        const Center(
                            child: Padding(
                                padding: EdgeInsets.all(24),
                                child: CircularProgressIndicator()))
                      else
                        ..._providerCards(),
                      if (_flow != null) ...[
                        const Divider(height: 28),
                        _deviceFlowCard(_flow!)
                      ],
                    ]))));
  }

  List<Widget> _providerCards() {
    final github = _providers
        .where((p) => p.id == 'github')
        .cast<WesiConnectorProvider?>()
        .firstOrNull;
    return [
      Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.code),
                      const SizedBox(width: 10),
                      const Expanded(
                          child: Text('GitHub',
                              style: TextStyle(fontWeight: FontWeight.w700))),
                      if (github?.connected == true)
                        const Chip(label: Text('Подключён'))
                    ]),
                    const SizedBox(height: 8),
                    if (github == null || !github.available)
                      const Text(
                          'GitHub OAuth пока не настроен на сервере. Коннектор fail-closed и не принимает токены в открытом виде.')
                    else if (github.accounts.isEmpty)
                      Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton.icon(
                              onPressed: _busy ? _nullCallback : _startGithub,
                              icon: const Icon(Icons.add_link),
                              label: const Text('Подключить GitHub')))
                    else
                      ...github.accounts.map((c) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const CircleAvatar(
                              child: Icon(Icons.person_outline)),
                          title: Text(c.accountLogin),
                          subtitle: Text('Scopes: ${c.scopes.join(', ')}'),
                          trailing: IconButton(
                              onPressed: _busy
                                  ? null
                                  : () => unawaited(_disconnect(c)),
                              tooltip: 'Отключить',
                              icon: const Icon(Icons.link_off))))
                  ])))
    ];
  }

  VoidCallback? get _nullCallback => null;
  Widget _deviceFlowCard(WesiGithubDeviceFlow flow) => Card(
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const Text('Авторизация GitHub',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Откройте GitHub и введите код:'),
            const SizedBox(height: 10),
            Center(
                child: SelectableText(flow.userCode,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800, letterSpacing: 2))),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                  onPressed: () => launchUrl(flow.verificationUri,
                      mode: LaunchMode.externalApplication),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Открыть GitHub')),
              OutlinedButton.icon(
                  onPressed: _busy ? null : () => unawaited(_pollGithub()),
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.sync),
                  label: const Text('Проверить'))
            ]),
            const SizedBox(height: 8),
            Text(
                'Код действует до ${flow.expiresAt.toLocal()}. Токен не передаётся в приложение.',
                style: Theme.of(context).textTheme.bodySmall)
          ])));
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) return item;
    return null;
  }
}
