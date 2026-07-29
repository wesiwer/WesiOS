import 'package:flutter/material.dart';
import '../../core/localization/wesi_locale.dart';
import '../../core/widgets/module_scaffold.dart';

/// Audio Vault — хранилище аудиоматериалов: биты, демо, референсы.
class AudioVaultScreen extends StatelessWidget {
  const AudioVaultScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ru = WesiLocale.isRussian;
    return ModuleScaffold(
      title: 'Audio Vault',
      subtitle: ru
          ? 'Хранилище аудио: биты, демо, референсы и права на них'
          : 'Audio storage: beats, demos, references, and their rights',
      icon: Icons.graphic_eq,
      stage: ModuleStage.planned,
      plannedFeatures: [
        ru
            ? 'Библиотека треков с прослушиванием прямо в приложении'
            : 'Track library with in-app playback',
        ru
            ? 'Теги: жанр, темп, тональность, настроение'
            : 'Tags: genre, tempo, key, mood',
        ru
            ? 'Статус трека: черновик, готов, продан, эксклюзив'
            : 'Track status: draft, ready, sold, exclusive',
        ru
            ? 'Связь продажи трека с транзакцией в Treasury'
            : 'Link a track sale to its Treasury transaction',
        ru
            ? 'Хранение лицензий и условий использования'
            : 'Store licences and usage terms',
      ],
      child: Column(
        children: [
          StubBlock(
            icon: Icons.library_music,
            height: 150,
            label: ru ? 'Библиотека треков' : 'Track library',
          ),
          const SizedBox(height: 12),
          StubBlock(
            icon: Icons.play_circle,
            height: 80,
            label: ru
                ? 'Плеер с волной и таймлайном'
                : 'Player with waveform and timeline',
          ),
        ],
      ),
    );
  }
}
