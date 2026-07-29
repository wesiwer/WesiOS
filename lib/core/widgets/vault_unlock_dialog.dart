import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';
import '../security/shield_service.dart';
import 'window_controls.dart';

/// Диалог доступа к ключам Firebase: пароль, а на телефоне — ещё и
/// отпечаток/скан лица.
///
/// Пароль тот же самый, что у Wesi Shield: два разных пароля на одно
/// приложение пользователь всё равно сведёт к одному, только запутавшись.
///
/// Один и тот же диалог используется и для первичной установки пароля
/// (когда он ещё не задан), и для последующих разблокировок.
class VaultUnlockDialog extends StatefulWidget {
  /// true — режим создания пароля (просит ввести дважды).
  final bool setupMode;

  const VaultUnlockDialog({super.key, required this.setupMode});

  /// Возвращает true, если доступ разрешён.
  static Future<bool> unlock(BuildContext context) async {
    final setup = !ShieldService.isConfigured;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VaultUnlockDialog(setupMode: setup),
    );
    return ok ?? false;
  }

  @override
  State<VaultUnlockDialog> createState() => _VaultUnlockDialogState();
}

class _VaultUnlockDialogState extends State<VaultUnlockDialog> {
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  String? _error;
  bool _bioAvailable = false;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    _initBiometrics();
  }

  Future<void> _initBiometrics() async {
    final available = await ShieldService.isBiometricAvailable;
    if (!mounted) return;
    setState(() => _bioAvailable = available);
    // Если биометрия включена пользователем — предлагаем её сразу, чтобы
    // не заставлять набирать пароль там, где достаточно приложить палец.
    if (!widget.setupMode && available && ShieldService.biometricsEnabled) {
      _tryBiometric();
    }
  }

  Future<void> _tryBiometric() async {
    final ru = WesiLocale.isRussian;
    final ok = await ShieldService.authenticateBiometric(
      ru ? 'Доступ к ключам Firebase' : 'Access Firebase keys',
    );
    if (ok && mounted) Navigator.pop(context, true);
  }

  Future<void> _submit() async {
    final ru = WesiLocale.isRussian;
    final pass = _passCtrl.text;

    if (widget.setupMode) {
      if (pass.length < 6) {
        setState(() => _error =
            ru ? 'Минимум 6 символов' : 'At least 6 characters');
        return;
      }
      if (pass != _confirmCtrl.text) {
        setState(() =>
            _error = ru ? 'Пароли не совпадают' : 'Passwords do not match');
        return;
      }
      await ShieldService.setPassword(pass);
      if (mounted) Navigator.pop(context, true);
      return;
    }

    // Пауза после неудачных попыток общая с Shield: обходить её через диалог
    // ключей было бы дырой ровно в той защите, ради которой она и стоит.
    final wait = ShieldService.lockoutRemaining;
    if (wait > Duration.zero) {
      setState(() => _error = ru
          ? 'Слишком много попыток. Подождите ${wait.inSeconds} с.'
          : 'Too many attempts. Wait ${wait.inSeconds} s.');
      return;
    }

    if (await ShieldService.verify(pass)) {
      if (mounted) Navigator.pop(context, true);
    } else if (mounted) {
      setState(() => _error = ru ? 'Неверный пароль' : 'Wrong password');
    }
  }

  @override
  void dispose() {
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return Dialog(
      backgroundColor: AppTheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.fromLTRB(40, kTitleBarHeight + 24, 40, 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.lock_outline,
                      size: 20, color: AppTheme.accentOrange),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.setupMode
                          ? (ru ? 'Создайте пароль' : 'Create a password')
                          : (ru ? 'Введите пароль' : 'Enter password'),
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.setupMode
                    ? (ru
                        ? 'Он закроет доступ к ключам Firebase. Пароль не хранится — сохраняется только его хэш, восстановить его нельзя.'
                        : 'It protects your Firebase keys. The password itself is never stored — only its hash — so it cannot be recovered.')
                    : (ru
                        ? 'Ключи Firebase защищены паролем.'
                        : 'Firebase keys are password protected.'),
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textMuted, height: 1.4),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _passCtrl,
                obscureText: _obscure,
                autofocus: true,
                style: const TextStyle(color: AppTheme.textPrimary),
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: ru ? 'Пароль' : 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                        _obscure ? Icons.visibility_off : Icons.visibility,
                        size: 18,
                        color: AppTheme.textMuted),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
              if (widget.setupMode) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmCtrl,
                  obscureText: _obscure,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  onSubmitted: (_) => _submit(),
                  decoration: InputDecoration(
                    labelText: ru ? 'Повторите пароль' : 'Repeat password',
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(_error!,
                    style: const TextStyle(
                        fontSize: 12, color: AppTheme.accentRed)),
              ],
              if (!widget.setupMode && _bioAvailable) ...[
                const SizedBox(height: 14),
                TextButton.icon(
                  onPressed: _tryBiometric,
                  icon: const Icon(Icons.fingerprint,
                      size: 18, color: AppTheme.accentOrange),
                  label: Text(
                    ru ? 'Отпечаток или Face ID' : 'Fingerprint or Face ID',
                    style: const TextStyle(color: AppTheme.accentOrange),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: Text(WesiLocale.get('cancel'),
                        style: const TextStyle(color: AppTheme.textMuted)),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: _submit,
                    child: Text(
                      widget.setupMode
                          ? (ru ? 'Установить' : 'Set')
                          : (ru ? 'Открыть' : 'Unlock'),
                      style: const TextStyle(
                          color: AppTheme.accentOrange,
                          fontWeight: FontWeight.w700),
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
