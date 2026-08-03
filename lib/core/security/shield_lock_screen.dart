import 'dart:async';

import 'package:flutter/material.dart';

import '../localization/wesi_locale.dart';
import '../theme/app_theme.dart';
import '../widgets/hover_button.dart';
import '../widgets/wesi_wordmark.dart';
import 'shield_service.dart';

/// Экран блокировки Wesi Shield.
///
/// Показывается поверх всего приложения, пока не введён пароль или не пройдена
/// биометрия. Намеренно не даёт закрыть себя: это не диалог, а состояние
/// приложения.
class ShieldLockScreen extends StatefulWidget {
  const ShieldLockScreen({super.key});

  @override
  State<ShieldLockScreen> createState() => _ShieldLockScreenState();
}

class _ShieldLockScreenState extends State<ShieldLockScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  bool _busy = false;
  bool _error = false;
  Duration _lockout = Duration.zero;
  Timer? _ticker;

  bool get _ru => WesiLocale.isRussian;

  @override
  void initState() {
    super.initState();
    _lockout = ShieldService.lockoutRemaining;
    // Тикаем, пока идёт штрафная пауза: без обратного отсчёта экран выглядит
    // просто сломанным — кнопка нажимается, ничего не происходит.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = ShieldService.lockoutRemaining;
      if (left != _lockout && mounted) setState(() => _lockout = left);
    });
    _tryBiometrics();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _tryBiometrics() async {
    if (!ShieldService.biometricsEnabled) return;
    if (ShieldService.lockoutRemaining > Duration.zero) return;
    await ShieldService.authenticateBiometric(
      _ru ? 'Разблокировать WesiOS' : 'Unlock WesiOS',
    );
  }

  Future<void> _submit() async {
    if (_busy || _ctrl.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = false;
    });
    final ok = await ShieldService.verify(_ctrl.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = !ok;
      _lockout = ShieldService.lockoutRemaining;
      if (ok) _ctrl.clear();
    });
    if (!ok) {
      _ctrl.clear();
      _focus.requestFocus();
    }
  }

  String _lockoutLabel(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    if (m > 0) return '$m:${s.toString().padLeft(2, '0')}';
    return '$s ${_ru ? 'с' : 's'}';
  }

  @override
  Widget build(BuildContext context) {
    final blocked = _lockout > Duration.zero;
    final fails = ShieldService.failedAttempts;

    return Material(
      color: AppTheme.background,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  WesiWordmark(size: 30),
                  SizedBox(height: 28),
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      blocked ? Icons.lock_clock : Icons.shield_outlined,
                      color: AppTheme.accent,
                      size: 28,
                    ),
                  ),
                  SizedBox(height: 18),
                  Text(
                    _ru ? 'Wesi Shield' : 'Wesi Shield',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: AppTheme.textPrimary),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    blocked
                        ? (_ru
                            ? 'Слишком много попыток. Подождите ${_lockoutLabel(_lockout)}.'
                            : 'Too many attempts. Wait ${_lockoutLabel(_lockout)}.')
                        : (_ru
                            ? 'Введите пароль, чтобы продолжить'
                            : 'Enter your password to continue'),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color:
                          blocked ? AppTheme.accent : AppTheme.textMuted,
                    ),
                  ),
                  SizedBox(height: 22),
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    autofocus: true,
                    obscureText: true,
                    enabled: !blocked && !_busy,
                    onSubmitted: (_) => _submit(),
                    style: TextStyle(color: AppTheme.textPrimary),
                    decoration: InputDecoration(
                      labelText: _ru ? 'Пароль' : 'Password',
                      errorText: _error
                          ? (_ru ? 'Неверный пароль' : 'Wrong password')
                          : null,
                      prefixIcon: Icon(Icons.key,
                          size: 18, color: AppTheme.textMuted),
                    ),
                  ),
                  SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: HoverButton(
                      onTap: blocked ? () {} : _submit,
                      padding: EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: blocked
                          ? AppTheme.surface
                          : AppTheme.accent,
                      child: Center(
                        child: _busy
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Text(
                                _ru ? 'Разблокировать' : 'Unlock',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: blocked
                                      ? AppTheme.textMuted
                                      : Colors.white,
                                ),
                              ),
                      ),
                    ),
                  ),
                  if (ShieldService.biometricsEnabled && !blocked) ...[
                    SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _tryBiometrics,
                      icon: Icon(Icons.fingerprint,
                          size: 18, color: AppTheme.accent),
                      label: Text(
                        _ru ? 'Отпечаток или лицо' : 'Fingerprint or face',
                        style: TextStyle(color: AppTheme.accent),
                      ),
                    ),
                  ],
                  if (fails > 0) ...[
                    SizedBox(height: 14),
                    Text(
                      _ru
                          ? 'Неудачных попыток: $fails'
                          : 'Failed attempts: $fails',
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.accentRed),
                    ),
                  ],
                  if (ShieldService.wipeAfterAttempts != null) ...[
                    SizedBox(height: 6),
                    Text(
                      _ru
                          ? 'Данные будут стёрты после '
                              '${ShieldService.wipeAfterAttempts} неудачных попыток'
                          : 'Data is wiped after '
                              '${ShieldService.wipeAfterAttempts} failed attempts',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 11, color: AppTheme.accentRed),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Экран блокировки как элемент глобального Overlay.
///
/// Живёт в Overlay, а не поверх всего Stack, ради одной детали: кнопки окна
/// на Windows должны остаться выше замка. Иначе заблокированное приложение
/// нельзя было бы даже свернуть или закрыть — только убить из диспетчера.
class ShieldOverlay extends StatelessWidget {
  const ShieldOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ShieldService.locked,
      builder: (context, locked, _) =>
          locked ? const ShieldLockScreen() : const SizedBox.shrink(),
    );
  }
}

/// Обёртка приложения: следит за бездействием и блокирует при запуске.
///
/// Слушатели жестов стоят здесь, а не в каждом экране: активность — свойство
/// приложения целиком, и дублировать её по экранам значит однажды забыть.
class ShieldGate extends StatefulWidget {
  final Widget child;

  const ShieldGate({super.key, required this.child});

  @override
  State<ShieldGate> createState() => _ShieldGateState();
}

class _ShieldGateState extends State<ShieldGate> with WidgetsBindingObserver {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (ShieldService.shouldLockOnStart) {
      ShieldService.lock();
    } else {
      ShieldService.touch();
    }
    // Раз в минуту проверяем бездействие: чаще незачем, минимальный таймаут
    // всё равно измеряется минутами.
    _timer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => ShieldService.checkAutoLock(),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Уход в фон — самый частый способ «оставить открытым»: проверяем таймаут
    // и при возврате тоже.
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      ShieldService.checkAutoLock();
    }
    if (state == AppLifecycleState.resumed) {
      ShieldService.checkAutoLock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => ShieldService.touch(),
      onPointerMove: (_) => ShieldService.touch(),
      child: widget.child,
    );
  }
}
