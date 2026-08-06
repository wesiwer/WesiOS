import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Точный тактильный отклик там, где устройство это умеет.
///
/// **Зачем поверх `HapticFeedback`.** Штатный отклик Flutter на Android —
/// это четыре константы `HapticFeedbackConstants`: `VIRTUAL_KEY`,
/// `KEYBOARD_TAP`, `CONTEXT_CLICK`, `CLOCK_TICK`. У них нет ни силы, ни
/// длительности, и составить из них рисунок нельзя. Поэтому «получилось» и
/// «ошибка» ощущаются одинаковым тупым толчком, тогда как на iPhone это
/// два разных, отчётливых сигнала: там `UIImpactFeedbackGenerator` с
/// интенсивностью.
///
/// С Android 12 у системы есть прямой аналог — композиция примитивов
/// (щелчок, тик, быстрый подъём) с интенсивностью 0…1 и задержками. Нативная
/// часть собирает из них рисунок под каждое событие; здесь только маршрут и
/// откат.
///
/// **Потолок — железо.** На телефоне с эксцентриковым мотором ни один
/// программный приём не даст ощущения линейного актуатора. Поэтому
/// [precise] не выдумывается, а спрашивается у системы, и настройки говорят
/// об этом прямо, вместо того чтобы обещать несбыточное.
class WesiHaptics {
  const WesiHaptics._();

  static const MethodChannel _channel = MethodChannel('wesios/haptics');

  static bool _asked = false;
  static bool _precise = false;
  static bool _hasVibrator = false;

  /// Умеет ли устройство отклик с интенсивностью и рисунком.
  static bool get precise => _precise;

  /// Есть ли вибромотор вообще.
  static bool get hasVibrator => _hasVibrator;

  /// Спросить возможности один раз. Вызывается на старте: спрашивать при
  /// каждом нажатии значит платить переходом через границу платформы за
  /// ответ, который не меняется.
  static Future<void> warmUp() async {
    if (_asked) return;
    _asked = true;
    try {
      final caps = await _channel.invokeMapMethod<String, dynamic>(
        'capabilities',
      );
      _precise = caps?['precise'] == true;
      _hasVibrator = caps?['hasVibrator'] == true;
    } catch (_) {
      // Нет канала — значит не Android: iOS обслуживает HapticFeedback, и
      // делает это хорошо, а на компьютере вибрации нет вовсе.
      _precise = false;
      _hasVibrator = false;
    }
  }

  /// Проиграть отклик. Возвращает false, если нативная сторона не взялась —
  /// тогда зовущий отдаёт штатный [HapticFeedback].
  ///
  /// Ошибку канала считаем отказом, а не поломкой: отклик не то, ради чего
  /// стоит ронять действие человека.
  static Future<bool> play(String effect) async {
    try {
      final ok = await _channel.invokeMethod<bool>('play', {'effect': effect});
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  /// Только для тестов.
  @visibleForTesting
  static void reset() {
    _asked = false;
    _precise = false;
    _hasVibrator = false;
  }

  @visibleForTesting
  static MethodChannel get channel => _channel;
}
