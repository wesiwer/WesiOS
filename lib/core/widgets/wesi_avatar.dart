import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../theme/app_theme.dart';

/// Аватарка WesiOS. Слушает Hive → меняется без рестарта приложения.
class WesiAvatar extends StatelessWidget {
  final double size;
  final bool showBorder;
  final VoidCallback? onTap;

  const WesiAvatar({
    super.key,
    this.size = 36,
    this.showBorder = true,
    this.onTap,
  });

  static const _box = 'wesios_settings';
  static const _key = 'avatar_index';

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
  }

  @override
  Widget build(BuildContext context) {
    // ValueListenableBuilder → live update по всему приложению
    return ValueListenableBuilder(
      valueListenable: Hive.box(_box).listenable(keys: [_key]),
      builder: (context, Box box, _) {
        final index =
            (box.get(_key, defaultValue: 0) as int).clamp(0, avatarPresets.length - 1);
        final preset = avatarPresets[index];

        final avatar = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: preset.gradient,
            border: showBorder
                ? Border.all(
                    color: AppTheme.accentOrange.withOpacity(0.55),
                    width: size > 40 ? 2.2 : 1.5,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: AppTheme.accentOrange.withOpacity(0.12),
                blurRadius: size * 0.25,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Center(
            child: IconTheme(
              data: IconThemeData(size: size * 0.45),
              child: preset.icon,
            ),
          ),
        );

        if (onTap != null) {
          return GestureDetector(onTap: onTap, child: avatar);
        }
        return avatar;
      },
    );
  }

  static final List<WesiAvatarPreset> avatarPresets = [
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A0A00), Color(0xFF3D1F00), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [AppTheme.accentOrange, Color(0xFFFFD700)],
        ).createShader(b),
        child: const Icon(Icons.bolt, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF0A1A2A), Color(0xFF001A33), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFF60A5FA), Color(0xFF93C5FD)],
        ).createShader(b),
        child: const Icon(Icons.ac_unit, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1A0A1A), Color(0xFF2D1F3D), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFFA78BFA), Color(0xFFC4B5FD)],
        ).createShader(b),
        child: const Icon(Icons.visibility_off, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Color(0xFF0A1A0A), Color(0xFF1A3D1A), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [AppTheme.accentGreen, Color(0xFFBEF264)],
        ).createShader(b),
        child: const Icon(Icons.biotech, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [Color(0xFF2A0A0A), Color(0xFF4D1F1F), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFFF87171), Color(0xFFFCA5A5)],
        ).createShader(b),
        child: const Icon(Icons.local_fire_department, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppTheme.carbonDark, AppTheme.carbonMid, AppTheme.carbonLight],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [AppTheme.textPrimary, AppTheme.textSecondary],
        ).createShader(b),
        child: const Icon(Icons.shield, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF2A240A), Color(0xFF4D3D1F), Color(0xFF0A0A0F)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFFFCD34D), Color(0xFFFDE68A)],
        ).createShader(b),
        child: const Icon(Icons.trending_up, color: Colors.white),
      ),
    ),
    WesiAvatarPreset(
      gradient: const RadialGradient(
        center: Alignment.center,
        colors: [Color(0xFF1A1A2E), Color(0xFF0A0A0F), Color(0xFF000000)],
      ),
      icon: ShaderMask(
        shaderCallback: (b) => const LinearGradient(
          colors: [Color(0xFF818CF8), Color(0xFFA5B4FC)],
        ).createShader(b),
        child: const Icon(Icons.all_inclusive, color: Colors.white),
      ),
    ),
  ];
}

class WesiAvatarPreset {
  final Gradient gradient;
  final Widget icon;
  const WesiAvatarPreset({required this.gradient, required this.icon});
}
