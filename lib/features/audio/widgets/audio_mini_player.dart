import 'dart:io';

import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../services/audio_player_service.dart';

class AudioMiniPlayer extends StatefulWidget {
  const AudioMiniPlayer({super.key});

  @override
  State<AudioMiniPlayer> createState() => _AudioMiniPlayerState();
}

class _AudioMiniPlayerState extends State<AudioMiniPlayer> {
  Offset _offset = const Offset(16, 90);

  String _time(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AudioPlayerState>(
      valueListenable: AudioPlayerService.state,
      builder: (context, state, _) {
        final beat = state.beat;
        if (beat == null) return const SizedBox.shrink();
        return Positioned(
          right: _offset.dx,
          bottom: _offset.dy,
          child: GestureDetector(
            onPanUpdate: (details) {
              final size = MediaQuery.sizeOf(context);
              setState(() {
                _offset = Offset(
                  (_offset.dx - details.delta.dx).clamp(8, size.width - 320),
                  (_offset.dy - details.delta.dy).clamp(8, size.height - 130),
                );
              });
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: MediaQuery.sizeOf(context).width < 500 ? 300 : 340,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppTheme.surface.withOpacity(.96),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.glassBorder),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(.32),
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).pushNamed('/audio'),
                          borderRadius: BorderRadius.circular(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: beat.coverPath != null && File(beat.coverPath!).existsSync()
                                ? Image.file(File(beat.coverPath!), width: 46, height: 46, fit: BoxFit.cover)
                                : Container(
                                    width: 46,
                                    height: 46,
                                    color: AppTheme.background,
                                    child: Icon(Icons.graphic_eq, color: AppTheme.accent),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: InkWell(
                            onTap: () => Navigator.of(context).pushNamed('/audio'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  beat.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: AppTheme.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.5,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${_time(state.position)} / ${_time(state.duration)}',
                                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                                ),
                              ],
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: AudioPlayerService.previous,
                          icon: Icon(Icons.skip_previous_rounded, color: AppTheme.textPrimary),
                        ),
                        IconButton(
                          onPressed: AudioPlayerService.toggle,
                          icon: Icon(
                            state.playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                            color: AppTheme.accent,
                            size: 34,
                          ),
                        ),
                        IconButton(
                          onPressed: AudioPlayerService.next,
                          icon: Icon(Icons.skip_next_rounded, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5)),
                      child: Slider(
                        value: state.duration.inMilliseconds <= 0
                            ? 0
                            : (state.position.inMilliseconds / state.duration.inMilliseconds).clamp(0.0, 1.0),
                        onChanged: state.duration.inMilliseconds <= 0
                            ? null
                            : (v) => AudioPlayerService.seek(Duration(milliseconds: (state.duration.inMilliseconds * v).round())),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.volume_down_rounded, size: 16, color: AppTheme.textMuted),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4)),
                            child: Slider(value: state.volume, onChanged: AudioPlayerService.setVolume),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть плеер',
                          onPressed: AudioPlayerService.stop,
                          icon: Icon(Icons.close, size: 16, color: AppTheme.textMuted),
                          visualDensity: VisualDensity.compact,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
