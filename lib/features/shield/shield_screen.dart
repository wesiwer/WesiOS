import 'package:flutter/material.dart';

import '../../core/localization/wesi_locale.dart';
import '../../core/security/shield_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/hover_button.dart';
import '../../core/widgets/wesi_wordmark.dart';
import '../../core/widgets/window_controls.dart';

/// Панель Wesi Shield: статус защиты, настройки и журнал.
///
/// Оценка внизу — не «насколько вы в безопасности вообще», а насколько
/// использованы те меры, которые приложение реально умеет. Обещать больше
/// было бы враньём.
class ShieldScreen extends StatefulWidget {
  const ShieldScreen({super.key});

  @override
  State<ShieldScreen> createState() => _ShieldScreenState();
}

class _ShieldScreenState extends State<ShieldScreen> {
  bool _bioAvailable = false;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    ShieldService.revision.addListener(_refresh);
    _checkBio();
  }

  @override
  void dispose() {
    ShieldService.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _checkBio() async {
    final ok = await ShieldService.isBiometricAvailable;
    if (mounted) setState(() => _bioAvailable = ok);
  }

  @override
  Widget build(BuildContext context) {
    final configured = ShieldService.isConfigured;
    final a = ShieldService.assess();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, kTitleBarInset + 8, 16, 32),
          children: [
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back,
                      color: AppTheme.textPrimary),
                  onPressed: () => Navigator.pop(context),
                ),
                Expanded(child: WesiTitle('Wesi Shield', size: 22)),
                SizedBox(width: kHasCustomTitleBar ? 140 : 0),
              ],
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                _ru
                    ? 'Защита доступа к WesiOS: пароль, биометрия, '
                        'автоблокировка и журнал входов'
                    : 'Access protection for WesiOS: password, biometrics, '
                        'auto-lock and a sign-in log',
                style: TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(height: 18),
            _scoreCard(a),
            const SizedBox(height: 16),
            if (!configured) _setupCard() else ...[
              _settingsCard(),
              const SizedBox(height: 16),
              _logCard(),
              const SizedBox(height: 16),
              _dangerCard(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _scoreCard(ShieldAssessment a) {
    final color = a.score >= 80
        ? AppTheme.accentGreen
        : (a.score >= 45 ? AppTheme.accentOrange : AppTheme.accentRed);

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.shield, color: color, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _ru ? 'Уровень защиты' : 'Protection level',
                  style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary),
                ),
              ),
              Text('${a.score}%',
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: color)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: a.score / 100,
              minHeight: 7,
              backgroundColor: AppTheme.background,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          if (a.good.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...a.good.map((t) => _bullet(t, Icons.check_circle_outline,
                AppTheme.accentGreen)),
          ],
          if (a.advice.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...a.advice.map((t) =>
                _bullet(t, Icons.lightbulb_outline, AppTheme.accentOrange)),
          ],
        ],
      ),
    );
  }

  Widget _bullet(String text, IconData icon, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text,
                  style: TextStyle(
                      fontSize: 12,
                      height: 1.4,
                      color: AppTheme.textSecondary)),
            ),
          ],
        ),
      );

  Widget _setupCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _ru ? 'Защита не включена' : 'Protection is off',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              _ru
                  ? 'Пока пароль не задан, любой, кто взял устройство, видит '
                      'ваши финансы, задачи и ключи целиком.'
                  : 'Without a password anyone holding the device sees your '
                      'finances, tasks and keys in full.',
              style:
                  TextStyle(fontSize: 12, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            HoverButton(
              onTap: _setPassword,
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              backgroundColor: AppTheme.accentOrange,
              child: Text(
                _ru ? 'Задать пароль' : 'Set a password',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _settingsCard() {
    final scope = ShieldService.scope;
    final timeout = ShieldService.timeoutMinutes;
    final wipe = ShieldService.wipeAfterAttempts;

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_ru ? 'Настройки' : 'Settings',
              style: TextStyle(
                  fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
          const SizedBox(height: 14),
          _switchRow(
            icon: Icons.lock_outline,
            title: _ru ? 'Закрывать всё приложение' : 'Lock the whole app',
            subtitle: _ru
                ? 'Иначе закрыты только ключи Firebase'
                : 'Otherwise only the Firebase keys are locked',
            value: scope == ShieldScope.wholeApp,
            onChanged: (v) => ShieldService.setScope(
                v ? ShieldScope.wholeApp : ShieldScope.keysOnly),
          ),
          _switchRow(
            icon: Icons.fingerprint,
            title: _ru ? 'Вход по биометрии' : 'Biometric unlock',
            subtitle: _bioAvailable
                ? (_ru ? 'Отпечаток или лицо' : 'Fingerprint or face')
                : (_ru
                    ? 'Недоступна на этом устройстве'
                    : 'Not available on this device'),
            value: ShieldService.biometricsEnabled,
            onChanged: _bioAvailable
                ? (v) => ShieldService.setBiometricsEnabled(v)
                : null,
          ),
          const SizedBox(height: 8),
          Text(
            _ru ? 'Автоблокировка' : 'Auto-lock',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: const [0, 1, 5, 15, 30].map((m) {
              final sel = m == timeout;
              return GestureDetector(
                onTap: () => ShieldService.setTimeoutMinutes(m),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.accentOrange.withOpacity(0.18)
                        : AppTheme.background,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: sel
                            ? AppTheme.accentOrange.withOpacity(0.6)
                            : AppTheme.glassBorder),
                  ),
                  child: Text(
                    m == 0
                        ? (_ru ? 'Никогда' : 'Never')
                        : (_ru ? '$m мин.' : '$m min'),
                    style: TextStyle(
                      fontSize: 12,
                      color: sel
                          ? AppTheme.accentOrange
                          : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Text(
            _ru ? 'Стереть данные после неудачных попыток' : 'Wipe after failures',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
          const SizedBox(height: 4),
          Text(
            _ru
                ? 'Необратимо. Включайте только если понимаете, что забытый '
                    'пароль означает потерю данных.'
                : 'Irreversible. Enable only if you accept that a forgotten '
                    'password means losing the data.',
            style: TextStyle(fontSize: 11, color: AppTheme.accentRed),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [null, 10, 20].map((n) {
              final sel = n == wipe;
              return GestureDetector(
                onTap: () => ShieldService.setWipeAfterAttempts(n),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppTheme.accentRed.withOpacity(0.18)
                        : AppTheme.background,
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                        color: sel
                            ? AppTheme.accentRed.withOpacity(0.6)
                            : AppTheme.glassBorder),
                  ),
                  child: Text(
                    n == null
                        ? (_ru ? 'Никогда' : 'Never')
                        : (_ru ? 'После $n' : 'After $n'),
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          sel ? AppTheme.accentRed : AppTheme.textSecondary,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _switchRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    ValueChanged<bool>? onChanged,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          children: [
            Icon(icon,
                size: 18,
                color: onChanged == null
                    ? AppTheme.textMuted
                    : AppTheme.accentOrange),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontSize: 13,
                          color: onChanged == null
                              ? AppTheme.textMuted
                              : AppTheme.textPrimary)),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.textMuted)),
                ],
              ),
            ),
            Switch(
              value: value,
              activeColor: AppTheme.accentOrange,
              onChanged: onChanged,
            ),
          ],
        ),
      );

  Widget _logCard() {
    final log = ShieldService.log;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(_ru ? 'Журнал' : 'Log',
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
              ),
              if (log.isNotEmpty)
                TextButton(
                  onPressed: ShieldService.clearLog,
                  child: Text(_ru ? 'Очистить' : 'Clear',
                      style: TextStyle(
                          fontSize: 12, color: AppTheme.textMuted)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          if (log.isEmpty)
            Text(
              _ru ? 'Событий пока нет' : 'No events yet',
              style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
            )
          else
            ...log.take(12).map(_logRow),
        ],
      ),
    );
  }

  String _kindLabel(String kind) {
    if (!_ru) return kind;
    return switch (kind) {
      'unlock_password' => 'Вход по паролю',
      'unlock_biometric' => 'Вход по биометрии',
      'password_set' => 'Пароль изменён',
      'auto_lock' => 'Автоблокировка',
      'biometrics' => 'Биометрия',
      'scope' => 'Область защиты',
      'timeout' => 'Таймаут',
      'wipe_policy' => 'Политика стирания',
      'wipe' => 'Данные стёрты',
      'disable' => 'Защита снята',
      _ => kind,
    };
  }

  Widget _logRow(ShieldEvent e) {
    final d = e.at;
    final stamp = '${d.day.toString().padLeft(2, '0')}.'
        '${d.month.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Icon(
            e.success ? Icons.check_circle_outline : Icons.error_outline,
            size: 14,
            color: e.success ? AppTheme.accentGreen : AppTheme.accentRed,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              e.detail == null
                  ? _kindLabel(e.kind)
                  : '${_kindLabel(e.kind)} · ${e.detail}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary),
            ),
          ),
          Text(stamp,
              style:
                  TextStyle(fontSize: 11, color: AppTheme.textMuted)),
        ],
      ),
    );
  }

  Widget _dangerCard() => _card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: HoverButton(
                    onTap: _setPassword,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: AppTheme.surface,
                    child: Center(
                      child: Text(
                        _ru ? 'Сменить пароль' : 'Change password',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.textPrimary),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: HoverButton(
                    onTap: _disable,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    backgroundColor: AppTheme.accentRed.withOpacity(0.14),
                    child: Center(
                      child: Text(
                        _ru ? 'Снять защиту' : 'Turn off',
                        style: TextStyle(
                            fontSize: 13, color: AppTheme.accentRed),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Future<void> _setPassword() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(),
    );
    if (result == null) return;
    await ShieldService.setPassword(result);
    if (mounted) setState(() {});
  }

  Future<void> _disable() async {
    final password = await showDialog<String>(
      context: context,
      builder: (_) => const _PasswordDialog(confirmOnly: true),
    );
    if (password == null) return;
    final ok = await ShieldService.disable(password);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_ru ? 'Неверный пароль' : 'Wrong password'),
          backgroundColor: AppTheme.accentRed,
        ),
      );
    }
    setState(() {});
  }

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppTheme.surface.withOpacity(0.35),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.glassBorder),
        ),
        child: child,
      );
}

/// Диалог задания/подтверждения пароля.
class _PasswordDialog extends StatefulWidget {
  /// true — просто спросить текущий пароль, без повтора и оценки.
  final bool confirmOnly;

  const _PasswordDialog({this.confirmOnly = false});

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _first = TextEditingController();
  final _second = TextEditingController();
  String? _error;

  bool get _ru => WesiLocale.isRussian;

  @override
  void dispose() {
    _first.dispose();
    _second.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _first.text;
    if (widget.confirmOnly) {
      if (value.isEmpty) return;
      Navigator.pop(context, value);
      return;
    }
    if (value.length < 6) {
      setState(() => _error =
          _ru ? 'Минимум 6 символов' : 'At least 6 characters');
      return;
    }
    if (value != _second.text) {
      setState(() => _error = _ru ? 'Пароли не совпадают' : 'Passwords differ');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final strength = ShieldService.passwordStrength(_first.text);
    final labels = _ru
        ? ['очень слабый', 'слабый', 'средний', 'хороший', 'сильный']
        : ['very weak', 'weak', 'fair', 'good', 'strong'];
    final colors = [
      AppTheme.accentRed,
      AppTheme.accentRed,
      AppTheme.accentOrange,
      AppTheme.accentGreen,
      AppTheme.accentGreen,
    ];

    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.fromLTRB(32, kTitleBarHeight + 24, 32, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.confirmOnly
                    ? (_ru ? 'Подтвердите пароль' : 'Confirm password')
                    : (_ru ? 'Пароль Wesi Shield' : 'Wesi Shield password'),
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary),
              ),
              if (!widget.confirmOnly) ...[
                const SizedBox(height: 6),
                Text(
                  _ru
                      ? 'Пароль не хранится — только производный ключ. '
                          'Восстановить его нечем, запишите надёжно.'
                      : 'The password is not stored — only a derived key. '
                          'There is no recovery, keep it safe.',
                  style: TextStyle(
                      fontSize: 11, color: AppTheme.textMuted),
                ),
              ],
              const SizedBox(height: 18),
              TextField(
                controller: _first,
                autofocus: true,
                obscureText: true,
                onChanged: (_) => setState(() => _error = null),
                onSubmitted: (_) => widget.confirmOnly ? _submit() : null,
                style: TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  labelText: _ru ? 'Пароль' : 'Password',
                  errorText: _error,
                ),
              ),
              if (!widget.confirmOnly) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: _first.text.isEmpty ? 0 : (strength + 1) / 5,
                          minHeight: 4,
                          backgroundColor: AppTheme.background,
                          valueColor:
                              AlwaysStoppedAnimation(colors[strength]),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _first.text.isEmpty ? '' : labels[strength],
                      style: TextStyle(
                          fontSize: 11, color: colors[strength]),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _second,
                  obscureText: true,
                  onSubmitted: (_) => _submit(),
                  style: TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    labelText: _ru ? 'Повторите пароль' : 'Repeat password',
                  ),
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(WesiLocale.get('cancel'),
                        style: TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  HoverButton(
                    onTap: _submit,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 22, vertical: 11),
                    backgroundColor: AppTheme.accentOrange,
                    child: Text(
                      widget.confirmOnly
                          ? (_ru ? 'Подтвердить' : 'Confirm')
                          : WesiLocale.get('save'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600),
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
}
