import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../design/gateway_theme.dart';
import '../models/gateway_models.dart';
import '../state/gateway_scope.dart';
import '../widgets/glass_card.dart';
import 'subscription_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final locked = controller.isConnected || controller.isBusy;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        GatewayTokens.space16,
        GatewayTokens.space24,
        GatewayTokens.space16,
        GatewayTokens.space32,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeading(
                title: 'Настройки',
                subtitle: 'Протокол, движок, защита от утечек и конфигурации.',
              ),
              const SizedBox(height: GatewayTokens.space24),
              Text('Протокол', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              if (controller.isIrelandBsSelected)
                const GlassCard(
                  child: ListTile(
                    leading: Icon(Icons.auto_awesome_rounded),
                    title: Text('Автоматический режим · Ирландия БС'),
                    subtitle: Text('Протокол, движок и REALITY-профиль выбираются автоматически. Ничего перебирать вручную не нужно.'),
                  ),
                )
              else
                _ProtocolSelector(enabled: !locked),
              const SizedBox(height: GatewayTokens.space16),
              Text('Движок', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space4),
              Text(
                'Авто предпочитает sing-box и переключается на Xray/Native, если протокол этого требует.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: GatewayTokens.space12),
              if (!controller.isIrelandBsSelected)
                _EngineSelector(enabled: !locked),
              const SizedBox(height: GatewayTokens.space24),
              Text('Соединение', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              GlassCard(
                child: Column(
                  children: [
                    _SettingsSwitch(
                      icon: Icons.shield_outlined,
                      title: 'Kill Switch',
                      subtitle: 'Блокировать сеть при неожиданном разрыве',
                      value: controller.killSwitch,
                      onChanged: locked ? null : controller.setKillSwitch,
                    ),
                    const _SettingsDivider(),
                    _SettingsSwitch(
                      icon: Icons.wifi_tethering_rounded,
                      title: 'Автопереподключение',
                      subtitle: 'Восстанавливать туннель после смены сети',
                      value: controller.autoConnect,
                      onChanged: controller.setAutoConnect,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              Text('Тариф и доступ', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              GlassCard(
                child: _SettingsAction(
                  icon: Icons.workspace_premium_outlined,
                  title: controller.license?.isActive == true
                      ? 'Тариф активен'
                      : 'Настроить тариф',
                  subtitle: controller.license?.isActive == true
                      ? '${controller.license!.deviceCount}/${controller.license!.deviceLimit} устройств · '
                          '${controller.license!.maskedKey}'
                      : 'Оплата или активация ключом',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SubscriptionScreen(embedded: true),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              Text('Конфигурация', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              GlassCard(
                child: Column(
                  children: [
                    _SettingsAction(
                      icon: Icons.qr_code_scanner_rounded,
                      title: controller.importProfileName ?? 'Импортировать профиль',
                      subtitle: controller.importProfileName == null
                          ? 'QR-код, текстовый ключ или файл'
                          : 'Профиль сохранён в защищённом хранилище',
                      onTap: locked ? null : () => _showImport(context),
                    ),
                    const _SettingsDivider(),
                    const _SettingsAction(
                      icon: Icons.system_update_alt_rounded,
                      title: 'Автоматические обновления',
                      subtitle: 'Только подписанные сборки из доверенного канала',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              Text('Интерфейс', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: GatewayTokens.space12),
              GlassCard(
                child: Column(
                  children: [
                    _SettingsAction(
                      icon: controller.themeMode == ThemeMode.dark
                          ? Icons.dark_mode_outlined
                          : Icons.light_mode_outlined,
                      title: 'Тема',
                      subtitle: controller.themeMode == ThemeMode.dark
                          ? 'Тёмная WesiOS'
                          : 'Светлая WesiOS',
                      onTap: controller.toggleTheme,
                    ),
                    const _SettingsDivider(),
                    _SettingsSwitch(
                      icon: Icons.animation_rounded,
                      title: 'Уменьшить движение',
                      subtitle: 'Остановить фон и декоративные циклы',
                      value: controller.reducedMotion,
                      onChanged: controller.setReducedMotion,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: GatewayTokens.space24),
              const _PrivacyCard(),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showImport(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => GatewayConfigImportSheet(
        onImport: GatewayScope.read(context).importConfig,
      ),
    );
  }
}

class _ProtocolSelector extends StatelessWidget {
  const _ProtocolSelector({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final available = controller.selectedNode?.protocols ??
        const {
          GatewayProtocol.vlessReality,
          GatewayProtocol.vmess,
          GatewayProtocol.trojan,
          GatewayProtocol.shadowsocks,
          GatewayProtocol.hysteria2,
          GatewayProtocol.tuic,
          GatewayProtocol.wireGuard,
          GatewayProtocol.amneziaWg,
        };
    return Wrap(
      spacing: GatewayTokens.space8,
      runSpacing: GatewayTokens.space8,
      children: GatewayProtocol.values.map((protocol) {
        final supported = protocol == GatewayProtocol.automatic ||
            available.contains(protocol);
        return ChoiceChip(
          avatar: Icon(_protocolIcon(protocol), size: 18),
          label: Text(protocol.title),
          selected: controller.protocol == protocol,
          onSelected: enabled && supported
              ? (_) => controller.setProtocol(protocol)
              : null,
        );
      }).toList(growable: false),
    );
  }

  IconData _protocolIcon(GatewayProtocol protocol) => switch (protocol) {
        GatewayProtocol.automatic => Icons.auto_awesome_rounded,
        GatewayProtocol.vlessReality => Icons.visibility_off_outlined,
        GatewayProtocol.vmess => Icons.hub_outlined,
        GatewayProtocol.trojan => Icons.security_rounded,
        GatewayProtocol.shadowsocks => Icons.blur_on_rounded,
        GatewayProtocol.hysteria2 => Icons.speed_rounded,
        GatewayProtocol.tuic => Icons.bolt_rounded,
        GatewayProtocol.wireGuard => Icons.vpn_lock_outlined,
        GatewayProtocol.amneziaWg => Icons.shield_moon_outlined,
      };
}

class _EngineSelector extends StatelessWidget {
  const _EngineSelector({required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final controller = GatewayScope.of(context);
    final protocol = controller.protocol;
    return Wrap(
      spacing: GatewayTokens.space8,
      runSpacing: GatewayTokens.space8,
      children: TunnelEngine.values.map((engine) {
        final supported = protocol == GatewayProtocol.automatic ||
            protocol.supportsEngine(engine);
        final subtitle = switch (engine) {
          TunnelEngine.automatic => 'Рекомендованный',
          TunnelEngine.singBox => 'Основной',
          TunnelEngine.xray => 'Резервный',
          TunnelEngine.native => 'WG / AWG',
        };
        return ChoiceChip(
          avatar: Icon(
            switch (engine) {
              TunnelEngine.automatic => Icons.auto_fix_high_rounded,
              TunnelEngine.singBox => Icons.dns_outlined,
              TunnelEngine.xray => Icons.hub_outlined,
              TunnelEngine.native => Icons.memory_rounded,
            },
            size: 18,
          ),
          label: Text('${engine.title} · $subtitle'),
          selected: controller.engine == engine,
          onSelected: enabled && supported
              ? (_) => controller.setEngine(engine)
              : null,
        );
      }).toList(growable: false),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  const _SettingsSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _SettingsIcon(icon: icon),
        const SizedBox(width: GatewayTokens.space12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 2),
              Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
        const SizedBox(width: GatewayTokens.space12),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _SettingsAction extends StatelessWidget {
  const _SettingsAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(GatewayTokens.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: GatewayTokens.space8),
        child: Row(
          children: [
            _SettingsIcon(icon: icon),
            const SizedBox(width: GatewayTokens.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
          ],
        ),
      ),
    );
  }
}

class _SettingsIcon extends StatelessWidget {
  const _SettingsIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: palette.surfaceRaised.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(GatewayTokens.radiusSmall),
      ),
      child: Icon(icon, size: 21, color: palette.textSecondary),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  const _SettingsDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: GatewayTokens.space12),
      child: Divider(height: 1, color: context.palette.border),
    );
  }
}

class _PrivacyCard extends StatelessWidget {
  const _PrivacyCard();

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return GlassCard(
      color: palette.connected.withValues(alpha: 0.07),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.policy_outlined, color: palette.connected),
          const SizedBox(width: GatewayTokens.space12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('No-Logs by design', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: GatewayTokens.space4),
                Text(
                  'Control plane хранит только техническое состояние сессии и объём трафика. Домены, URL, DNS-запросы и содержимое пакетов не записываются.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class GatewayConfigImportSheet extends StatefulWidget {
  const GatewayConfigImportSheet({
    required this.onImport,
    super.key,
  });

  final Future<ImportedGatewayConfig> Function(String value) onImport;

  @override
  State<GatewayConfigImportSheet> createState() =>
      _GatewayConfigImportSheetState();
}

class _GatewayConfigImportSheetState extends State<GatewayConfigImportSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _busy = false;
  bool _scanner = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      margin: const EdgeInsets.all(GatewayTokens.space8),
      padding: EdgeInsets.fromLTRB(
        GatewayTokens.space16,
        GatewayTokens.space16,
        GatewayTokens.space16,
        GatewayTokens.space16 + bottom,
      ),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(GatewayTokens.radiusHero),
        border: Border.all(color: palette.border),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Импорт конфигурации',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Закрыть',
                  onPressed: _busy ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: GatewayTokens.space8),
            Text(
              'Ключ сохраняется в системном защищённом хранилище и не попадает в журналы.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: GatewayTokens.space16),
            if (_scanner && Platform.isAndroid)
              ClipRRect(
                borderRadius: BorderRadius.circular(GatewayTokens.radiusLarge),
                child: SizedBox(
                  height: 280,
                  child: MobileScanner(
                    onDetect: (capture) {
                      String? raw;
                      for (final barcode in capture.barcodes) {
                        if (barcode.rawValue != null) {
                          raw = barcode.rawValue;
                          break;
                        }
                      }
                      if (raw == null || _busy) return;
                      _controller.text = raw;
                      setState(() => _scanner = false);
                    },
                  ),
                ),
              )
            else
              TextField(
                controller: _controller,
                minLines: 5,
                maxLines: 10,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText:
                      'vless:// · vmess:// · trojan:// · ss:// · hysteria2:// · tuic:// · [Interface]/[Peer]',
                  errorText: _error,
                  alignLabelWithHint: true,
                ),
              ),
            const SizedBox(height: GatewayTokens.space12),
            Wrap(
              spacing: GatewayTokens.space8,
              runSpacing: GatewayTokens.space8,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : _pickFile,
                  icon: const Icon(Icons.file_open_outlined),
                  label: const Text('Выбрать файл'),
                ),
                if (Platform.isAndroid)
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => setState(() {
                              _scanner = !_scanner;
                              _error = null;
                            }),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text(_scanner ? 'Ввести текстом' : 'Сканировать QR'),
                  ),
              ],
            ),
            const SizedBox(height: GatewayTokens.space16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: _busy
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_rounded),
                label: Text(_busy ? 'Проверяем…' : 'Проверить и импортировать'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['conf', 'txt', 'json'],
      withData: true,
    );
    final file = result?.files.single;
    if (file == null) return;
    if (file.bytes != null) {
      _controller.text = utf8.decode(file.bytes!);
    } else if (file.path != null) {
      _controller.text = await File(file.path!).readAsString();
    }
    if (mounted) {
      setState(() {
        _scanner = false;
        _error = null;
      });
    }
  }

  Future<void> _import() async {
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = 'Вставьте конфигурацию или выберите файл.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onImport(value);
      if (!mounted) return;
      Navigator.of(context).pop();
    } on FormatException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Не удалось сохранить конфигурацию.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}
