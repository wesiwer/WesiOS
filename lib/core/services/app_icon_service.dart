import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../theme/app_theme.dart';

/// Режим иконки приложения на рабочем столе.
///
/// - [auto]  — следует за темой (dark↔тёмная иконка, light↔светлая)
/// - [dark]  — всегда тёмная
/// - [light] — всегда светлая
enum AppIconMode { auto, dark, light }

/// Переключение launcher-иконки через activity-alias (Android).
///
/// На Windows / desktop смена иконки в меню «Пуск» и на панели задач
/// из рантайма практически недоступна — [isSupported] вернёт false,
/// выбор в настройках всё равно сохраняется на будущее.
class AppIconService {
  static const _channel = MethodChannel('wesios/icon');
  static const _box = 'wesios_settings';
  static const _key = 'app_icon_mode';

  static final ValueNotifier<AppIconMode> mode =
      ValueNotifier<AppIconMode>(AppIconMode.auto);

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isAndroid;
  }

  static void load() {
    try {
      final raw = Hive.box(_box).get(_key) as String?;
      mode.value = switch (raw) {
        'dark' => AppIconMode.dark,
        'light' => AppIconMode.light,
        _ => AppIconMode.auto,
      };
    } catch (_) {
      mode.value = AppIconMode.auto;
    }
    // Применяем после загрузки темы (main вызывает ThemeNotifier.load раньше).
    apply();
  }

  static Future<void> setMode(AppIconMode next) async {
    if (mode.value == next) {
      await apply();
      return;
    }
    mode.value = next;
    try {
      await Hive.box(_box).put(
        _key,
        switch (next) {
          AppIconMode.auto => 'auto',
          AppIconMode.dark => 'dark',
          AppIconMode.light => 'light',
        },
      );
    } catch (_) {}
    await apply();
  }

  /// Какую физическую иконку сейчас нужно показать.
  static bool get wantLight {
    return switch (mode.value) {
      AppIconMode.light => true,
      AppIconMode.dark => false,
      AppIconMode.auto => ThemeNotifier.instance.isLight,
    };
  }

  /// Вызвать после смены темы (для auto) или смены режима.
  static Future<void> apply() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('setIcon', {
        'variant': wantLight ? 'light' : 'dark',
      });
    } catch (e) {
      debugPrint('AppIconService.apply failed: $e');
    }
  }
}
