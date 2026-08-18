import 'package:flutter/material.dart';

import '../../../core/localization/wesi_locale.dart';
import '../../../core/theme/app_theme.dart';
import '../console/ssh_client_service.dart';
import '../console/ssh_profile_store.dart';
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
  late final String _targetId = widget.initial?.id ??
      DateTime.now().microsecondsSinceEpoch.toString();
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

  final TextEditingController _sshUser = TextEditingController(text: 'root');
  final TextEditingController _sshPort = TextEditingController(text: '22');
  final TextEditingController _sshSecret = TextEditingController();
  final TextEditingController _sshPassphrase = TextEditingController();

  late TargetKind _kind = widget.initial?.kind ?? TargetKind.server;
  late bool _tls = widget.initial?.checkTls ?? false;
  bool _sshEnabled = false;
  bool _sshChecking = false;
  bool _sshVerified = false;
  bool _hideSecret = true;
  SshAuthType _sshAuth = SshAuthType.password;
  String? _hostFingerprint;
  SshProfile? _existingProfile;
  String? _error;
  String? _sshStatus;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    final existing = SshProfileStore.profileFor(_targetId);
    if (existing != null) {
      _existingProfile = existing;
      _sshEnabled = true;
      _sshAuth = existing.authType;
      _hostFingerprint = existing.hostKeyFingerprint;
      _sshUser.text = existing.username;
      _sshPort.text = '${existing.port}';
      _sshVerified = (existing.hostKeyFingerprint ?? '').isNotEmpty;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _host.dispose();
    _port.dispose();
    _url.dispose();
    _loadUrl.dispose();
    _sshUser.dispose();
    _sshPort.dispose();
    _sshSecret.dispose();
    _sshPassphrase.dispose();
    super.dispose();
  }

  void _kindChanged(TargetKind kind) {
    setState(() {
      _kind = kind;
      final wasDefault = _port.text == '443' || _port.text == '22';
      if (wasDefault) {
        _port.text = kind == TargetKind.server ? '22' : '443';
      }
      if (kind != TargetKind.server) {
        _tls = true;
        _sshEnabled = false;
      }
    });
  }

  Future<void> _checkSsh() async {
    final host = _host.text.trim();
    final username = _sshUser.text.trim();
    final port = int.tryParse(_sshPort.text.trim());
    if (host.isEmpty || username.isEmpty || port == null || port < 1 || port > 65535) {
      setState(() => _sshStatus = _ru
          ? 'Укажите адрес, SSH-пользователя и корректный порт.'
          : 'Enter host, SSH user and a valid port.');
      return;
    }

    final typedSecret = _sshSecret.text;
    final hasSaved = _existingProfile != null &&
        _existingProfile!.authType == _sshAuth &&
        await SshProfileStore.hasSecret(_existingProfile!);
    if (typedSecret.isEmpty && !hasSaved) {
      setState(() => _sshStatus = _ru
          ? (_sshAuth == SshAuthType.password
              ? 'Введите пароль SSH.'
              : 'Вставьте private key.')
          : (_sshAuth == SshAuthType.password
              ? 'Enter SSH password.'
              : 'Paste private key.'));
      return;
    }

    setState(() {
      _sshChecking = true;
      _sshStatus = _ru ? 'Получаю host key…' : 'Reading host key…';
    });

    try {
      final fingerprint = await SshClientService.discoverFingerprint(host, port);
      final pinned = _hostFingerprint;
      if (pinned != null && pinned.isNotEmpty && pinned != fingerprint) {
        setState(() {
          _sshVerified = false;
          _sshStatus = _ru
              ? 'Host key изменился. Подключение заблокировано. Был: $pinned, сейчас: $fingerprint'
              : 'Host key changed. Connection blocked. Was: $pinned, now: $fingerprint';
        });
        return;
      }

      if (pinned == null || pinned.isEmpty) {
        if (!mounted) return;
        final trusted = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                backgroundColor: AppTheme.surface,
                title: Text(
                  _ru ? 'Доверять этому серверу?' : 'Trust this server?',
                  style: TextStyle(color: AppTheme.textPrimary),
                ),
                content: SelectableText(
                  '${_ru ? 'SSH host key:' : 'SSH host key:'}\n\n$fingerprint\n\n${_ru ? 'Сверьте отпечаток с сервером. После сохранения WesiOS заблокирует подключение, если ключ изменится.' : 'Verify this fingerprint with the server. WesiOS will block the connection if it changes later.'}',
                  style: TextStyle(color: AppTheme.textSecondary),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(_ru ? 'Отмена' : 'Cancel'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: Text(_ru ? 'Доверять' : 'Trust'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!trusted) {
          setState(() => _sshStatus = _ru
              ? 'Подключение отменено: host key не подтверждён.'
              : 'Connection cancelled: host key not trusted.');
          return;
        }
        _hostFingerprint = fingerprint;
      }

      final profile = SshProfile(
        targetId: _targetId,
        username: username,
        port: port,
        authType: _sshAuth,
        hostKeyFingerprint: _hostFingerprint,
      );
      final target = MonitorTarget(
        id: _targetId,
        name: _name.text.trim().isEmpty ? host : _name.text.trim(),
        host: host,
        port: int.tryParse(_port.text.trim()) ?? 22,
        kind: TargetKind.server,
      );
      final result = await SshClientService.test(
        target,
        profile,
        password: _sshAuth == SshAuthType.password && typedSecret.isNotEmpty
            ? typedSecret
            : null,
        privateKey: _sshAuth == SshAuthType.privateKey && typedSecret.isNotEmpty
            ? typedSecret
            : null,
        passphrase: _sshPassphrase.text.isEmpty ? null : _sshPassphrase.text,
      );
      if (!mounted) return;
      setState(() {
        _sshVerified = result.ok;
        _sshStatus = result.ok
            ? (_ru
                ? 'SSH работает · ${result.serverVersion.isEmpty ? 'сервер подтверждён' : result.serverVersion}'
                : 'SSH works · ${result.serverVersion.isEmpty ? 'server verified' : result.serverVersion}')
            : result.message;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _sshVerified = false;
          _sshStatus = '${_ru ? 'Ошибка SSH' : 'SSH error'}: $error';
        });
      }
    } finally {
      if (mounted) setState(() => _sshChecking = false);
    }
  }

  Future<void> _save() async {
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

    if (_kind == TargetKind.server && _sshEnabled) {
      final sshPort = int.tryParse(_sshPort.text.trim());
      if (_sshUser.text.trim().isEmpty || sshPort == null || sshPort < 1 || sshPort > 65535) {
        setState(() => _error = _ru
            ? 'Проверьте SSH-пользователя и порт.'
            : 'Check SSH user and port.');
        return;
      }
      if (!_sshVerified || (_hostFingerprint ?? '').isEmpty) {
        setState(() => _error = _ru
            ? 'Сначала нажмите «Проверить SSH» и подтвердите host key.'
            : 'Run “Test SSH” and trust the host key first.');
        return;
      }
    }

    final target = (widget.initial ??
            MonitorTarget(
              id: _targetId,
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

    if (widget.initial == null) {
      MonitorService.add(target);
    } else {
      MonitorService.update(target);
    }

    if (_kind == TargetKind.server && _sshEnabled) {
      final profile = SshProfile(
        targetId: target.id,
        username: _sshUser.text.trim(),
        port: int.parse(_sshPort.text.trim()),
        authType: _sshAuth,
        hostKeyFingerprint: _hostFingerprint,
      );
      await SshProfileStore.saveProfile(profile);
      if (_sshSecret.text.isNotEmpty) {
        if (_sshAuth == SshAuthType.password) {
          await SshProfileStore.savePassword(target.id, _sshSecret.text);
        } else {
          await SshProfileStore.savePrivateKey(
            target.id,
            _sshSecret.text,
            passphrase: _sshPassphrase.text,
          );
        }
      }
    } else if (_existingProfile != null) {
      await SshProfileStore.remove(target.id);
    }

    if (mounted) Navigator.pop(context, target);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * .92),
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
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
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
              _field(_name, _ru ? 'Название' : 'Name', _ru ? 'Wesi AI Relay' : 'Wesi AI Relay'),
              const SizedBox(height: 10),
              _field(_host, _ru ? 'Адрес или имя' : 'Host', _ru ? '176.124.199.179 или ai.wesi-wf.su' : 'host or IP'),
              const SizedBox(height: 10),
              _field(_port, _ru ? 'Порт для замера' : 'Probe port', '22', keyboard: TextInputType.number),
              if (_kind != TargetKind.server) ...[
                const SizedBox(height: 10),
                _field(_url, _ru ? 'Адрес страницы' : 'Page URL', 'https://…'),
              ],
              const SizedBox(height: 10),
              _field(_loadUrl, _ru ? 'Адрес агента (необязательно)' : 'Agent URL (optional)', 'https://…/wesios-status.json'),
              const SizedBox(height: 6),
              Text(
                _ru
                    ? 'Загрузку процессора и памяти присылает агент с самого сервера. Поле можно оставить пустым.'
                    : 'CPU and memory are reported by the server agent. This can be left empty.',
                style: TextStyle(fontSize: 10.5, height: 1.4, color: AppTheme.textMuted),
              ),
              if (_kind == TargetKind.server) ...[
                const SizedBox(height: 16),
                _sshSection(),
              ],
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () => setState(() => _tls = !_tls),
                child: Row(
                  children: [
                    Icon(_tls ? Icons.check_box : Icons.check_box_outline_blank,
                        size: 19, color: _tls ? AppTheme.accent : AppTheme.textMuted),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(_ru ? 'Следить за сроком сертификата' : 'Watch certificate expiry',
                          style: TextStyle(fontSize: 12.5, color: AppTheme.textSecondary)),
                    ),
                  ],
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(fontSize: 12, color: AppTheme.accentRed)),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  if (widget.initial != null) ...[
                    _button(
                      _ru ? 'Удалить' : 'Delete',
                      () async {
                        MonitorService.remove(widget.initial!.id);
                        await SshProfileStore.remove(widget.initial!.id);
                        if (mounted) Navigator.pop(context);
                      },
                      color: AppTheme.accentRed,
                    ),
                    const SizedBox(width: 10),
                  ],
                  Expanded(child: _button(_ru ? 'Сохранить' : 'Save', () => _save(), filled: true)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sshSection() {
    final statusColor = _sshVerified ? AppTheme.accentGreen : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.45),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _sshEnabled ? AppTheme.accent.withOpacity(.35) : AppTheme.glassBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => setState(() {
              _sshEnabled = !_sshEnabled;
              _sshVerified = _sshEnabled && (_hostFingerprint ?? '').isNotEmpty && _existingProfile != null;
            }),
            child: Row(
              children: [
                Icon(_sshEnabled ? Icons.check_box : Icons.check_box_outline_blank,
                    color: _sshEnabled ? AppTheme.accent : AppTheme.textMuted, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ru ? 'Подключить SSH-консоль' : 'Enable SSH console',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                if (_sshVerified) Icon(Icons.verified_user_outlined, size: 18, color: AppTheme.accentGreen),
              ],
            ),
          ),
          if (_sshEnabled) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(child: _field(_sshUser, _ru ? 'SSH-пользователь' : 'SSH user', 'root')),
                const SizedBox(width: 8),
                SizedBox(width: 92, child: _field(_sshPort, _ru ? 'Порт' : 'Port', '22', keyboard: TextInputType.number)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: _authChip(SshAuthType.password, _ru ? 'Пароль' : 'Password')),
                const SizedBox(width: 8),
                Expanded(child: _authChip(SshAuthType.privateKey, 'Private key')),
              ],
            ),
            const SizedBox(height: 10),
            _secretField(),
            if (_sshAuth == SshAuthType.privateKey) ...[
              const SizedBox(height: 8),
              _field(_sshPassphrase, _ru ? 'Passphrase ключа (если есть)' : 'Key passphrase (optional)', '••••••••', obscure: true),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: _button(
                _sshChecking
                    ? (_ru ? 'Проверяю…' : 'Testing…')
                    : (_ru ? 'Проверить SSH' : 'Test SSH'),
                _sshChecking ? () {} : () => _checkSsh(),
                filled: true,
              ),
            ),
            if (_sshStatus != null) ...[
              const SizedBox(height: 8),
              Text(_sshStatus!, style: TextStyle(fontSize: 10.5, height: 1.4, color: statusColor)),
            ],
            if ((_hostFingerprint ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              SelectableText('Host key: $_hostFingerprint', style: TextStyle(fontSize: 9.5, color: AppTheme.textMuted)),
            ],
            const SizedBox(height: 6),
            Text(
              _ru
                  ? 'Пароль/private key хранится только в защищённом хранилище устройства. Host key закрепляется после подтверждения и защищает от подмены сервера.'
                  : 'Password/private key stays in secure device storage. The pinned host key protects against server impersonation.',
              style: TextStyle(fontSize: 9.8, height: 1.4, color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }

  Widget _authChip(SshAuthType type, String label) {
    final on = _sshAuth == type;
    return GestureDetector(
      onTap: () => setState(() {
        if (_sshAuth != type) {
          _sshAuth = type;
          _sshSecret.clear();
          _sshVerified = false;
          _sshStatus = null;
        }
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? AppTheme.accent.withOpacity(.15) : AppTheme.surfaceLight.withOpacity(.35),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: on ? AppTheme.accent.withOpacity(.45) : AppTheme.glassBorder),
        ),
        child: Text(label, style: TextStyle(fontSize: 11.5, color: on ? AppTheme.accent : AppTheme.textSecondary)),
      ),
    );
  }

  Widget _secretField() {
    final keyMode = _sshAuth == SshAuthType.privateKey;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          keyMode ? 'Private key' : (_ru ? 'SSH-пароль' : 'SSH password'),
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _sshSecret,
          obscureText: !keyMode && _hideSecret,
          minLines: keyMode ? 4 : 1,
          maxLines: keyMode ? 8 : 1,
          style: TextStyle(fontSize: 12.5, color: AppTheme.textPrimary, fontFamily: keyMode ? 'monospace' : null),
          decoration: InputDecoration(
            hintText: _existingProfile != null
                ? (_ru ? 'Оставьте пустым, чтобы не менять сохранённый секрет' : 'Leave empty to keep saved secret')
                : (keyMode ? '-----BEGIN OPENSSH PRIVATE KEY-----' : '••••••••'),
            hintStyle: TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
            suffixIcon: keyMode
                ? null
                : IconButton(
                    onPressed: () => setState(() => _hideSecret = !_hideSecret),
                    icon: Icon(_hideSecret ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                  ),
            filled: true,
            fillColor: AppTheme.surfaceLight.withOpacity(.4),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.glassBorder)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.glassBorder)),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.accent)),
          ),
        ),
      ],
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
          color: on ? AppTheme.accent.withOpacity(.16) : AppTheme.surface.withOpacity(.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: on ? AppTheme.accent.withOpacity(.5) : AppTheme.glassBorder),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, fontWeight: on ? FontWeight.w700 : FontWeight.w400, color: on ? AppTheme.accent : AppTheme.textSecondary)),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String hint, {
    TextInputType? keyboard,
    bool obscure = false,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: AppTheme.textMuted)),
          const SizedBox(height: 4),
          TextField(
            controller: c,
            keyboardType: keyboard,
            obscureText: obscure,
            style: TextStyle(fontSize: 13.5, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
              filled: true,
              fillColor: AppTheme.surfaceLight.withOpacity(.4),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.glassBorder)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.glassBorder)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(9), borderSide: BorderSide(color: AppTheme.accent)),
            ),
          ),
        ],
      );

  Widget _button(String label, VoidCallback onTap, {bool filled = false, Color? color}) {
    final accent = color ?? AppTheme.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? accent.withOpacity(.18) : AppTheme.surface.withOpacity(.4),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: accent.withOpacity(.5)),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: accent)),
      ),
    );
  }
}
