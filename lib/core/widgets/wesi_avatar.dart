import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

/// Аватарка WesiOS. Слушает Hive → меняется без рестарта приложения.
///
/// Приоритет: загруженная пользователем картинка (`avatar_custom`),
/// иначе — пресет по индексу (`avatar_index`).
class WesiAvatar extends StatelessWidget {
  final double size;
  final bool showBorder;
  final VoidCallback? onTap;

  /// Чей аватар показывать.
  ///
  /// null — того, кто сидит за приложением: так виджет и работал всегда.
  /// Число — конкретного человека, например в списке контактов, где своя
  /// аватарка на каждой строке была бы бессмыслицей. Загруженная картинка
  /// при этом не подставляется: она принадлежит владельцу устройства, а не
  /// тому, кого рисуем.
  final int? index;

  const WesiAvatar({
    super.key,
    this.size = 36,
    this.showBorder = true,
    this.onTap,
    this.index,
  });

  static const _box = 'wesios_settings';
  static const _key = 'avatar_index';
  static const _customKey = 'avatar_custom';

  static int get currentIndex {
    try {
      final box = Hive.box(_box);
      return box.get(_key, defaultValue: 0) as int;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> setIndex(int index) async {
    final box = Hive.box(_box);
    await box.put(_key, index.clamp(0, avatarPresets.length - 1));
    // Выбор пресета отменяет загруженную картинку.
    await box.delete(_customKey);
  }

  /// Байты загруженной пользователем аватарки, если есть.
  static Uint8List? get customBytes {
    try {
      final raw = Hive.box(_box).get(_customKey);
      if (raw is Uint8List) return raw;
      if (raw is List<int>) return Uint8List.fromList(raw);
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool get hasCustom => customBytes != null;

  static Future<void> setCustom(Uint8List bytes) async {
    await Hive.box(_box).put(_customKey, bytes);
  }

  static Future<void> clearCustom() async {
    await Hive.box(_box).delete(_customKey);
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder → live update по всему приложению
    return ValueListenableBuilder(
      valueListenable: Hive.box(_box).listenable(keys: [_key, _customKey]),
      builder: (context, Box box, _) {
        final border = showBorder
            ? Border.all(
                color: AppTheme.accent.withOpacity(0.55),
                width: size > 40 ? 2.2 : 1.5,
              )
            : null;
        final shadow = [
          BoxShadow(
            color: AppTheme.accent.withOpacity(0.12),
            blurRadius: size * 0.25,
            spreadRadius: 1,
          ),
        ];

        // Для чужой аватарки своя картинка не годится.
        final custom = index == null ? customBytes : null;
        final Widget avatar;

        if (custom != null) {
          avatar = Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: border,
              boxShadow: shadow,
              image: DecorationImage(
                image: MemoryImage(custom),
                fit: BoxFit.cover,
              ),
            ),
          );
        } else {
          final resolved = (index ?? (box.get(_key, defaultValue: 0) as int))
              .clamp(0, avatarPresets.length - 1);
          final preset = avatarPresets[resolved];

          avatar = Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: preset.gradient,
              border: border,
              boxShadow: shadow,
            ),
            child: Center(
              child: IconTheme(
                data: IconThemeData(size: size * 0.45),
                child: preset.icon,
              ),
            ),
          );
        }

        if (onTap != null) {
          return GestureDetector(onTap: onTap, child: avatar);
        }
        return avatar;
      },
    );
  }

  /// Набор пресетов. Обновлён: более насыщенные многоточечные градиенты
  /// и новый набор глифов вместо прежних восьми.
  static final List<WesiAvatarPreset> avatarPresets = [
    _preset(
      const [Color(0xFF2B1200), Color(0xFF7C3A00), Color(0xFF120A02)],
      Icons.local_fire_department,
      const [Color(0xFFFF8A3D), Color(0xFFFFD166)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    _preset(
      const [Color(0xFF04121F), Color(0xFF0B3C5D), Color(0xFF02070D)],
      Icons.waves,
      const [Color(0xFF38BDF8), Color(0xFFA5F3FC)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    _preset(
      const [Color(0xFF1B0733), Color(0xFF4C1D95), Color(0xFF0B0416)],
      Icons.auto_awesome,
      const [Color(0xFFC084FC), Color(0xFFF0ABFC)],
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
    ),
    _preset(
      const [Color(0xFF04170D), Color(0xFF14532D), Color(0xFF020B06)],
      Icons.eco,
      const [Color(0xFF4ADE80), Color(0xFFD9F99D)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
    _preset(
      const [Color(0xFF250505), Color(0xFF7F1D1D), Color(0xFF120202)],
      Icons.bolt,
      const [Color(0xFFFB7185), Color(0xFFFECACA)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    _preset(
      const [Color(0xFF0B1020), Color(0xFF1E293B), Color(0xFF05070E)],
      Icons.hexagon,
      const [Color(0xFF94A3B8), Color(0xFFE2E8F0)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
    _preset(
      const [Color(0xFF231803), Color(0xFF78350F), Color(0xFF110C02)],
      Icons.workspace_premium,
      const [Color(0xFFFBBF24), Color(0xFFFDE68A)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    ),
    _preset(
      const [Color(0xFF04211E), Color(0xFF115E59), Color(0xFF021110)],
      Icons.hub,
      const [Color(0xFF2DD4BF), Color(0xFF99F6E4)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ),
    _preset(
      const [Color(0xFF190A2B), Color(0xFF3730A3), Color(0xFF0A0518)],
      Icons.travel_explore,
      const [Color(0xFF818CF8), Color(0xFFC7D2FE)],
      begin: Alignment.topRight,
      end: Alignment.bottomLeft,
    ),
    WesiAvatarPreset(
      gradient: const RadialGradient(
        center: Alignment.topLeft,
        radius: 1.1,
        colors: [Color(0xFF3F3F46), Color(0xFF18181B), Color(0xFF000000)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFF9CA3AF)],
        ).createShader(b),
        child: const Icon(Icons.blur_on, color: Colors.white),
      ),
    ),
  ];

  static WesiAvatarPreset _preset(
    List<Color> background,
    IconData icon,
    List<Color> glyph, {
    required Alignment begin,
    required Alignment end,
  }) {
    return WesiAvatarPreset(
      gradient: LinearGradient(begin: begin, end: end, colors: background),
      icon: ShaderMask(
        shaderCallback: (b) => LinearGradient(colors: glyph).createShader(b),
        child: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class WesiAvatarPreset {
  final Gradient gradient;
  final Widget icon;
  const WesiAvatarPreset({required this.gradient, required this.icon});
}
