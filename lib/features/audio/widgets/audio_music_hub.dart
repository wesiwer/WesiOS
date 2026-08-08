import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../models/audio_vault_extended_models.dart';
import '../services/audio_player_service.dart';
import '../services/audio_vault_extras_service.dart';
import '../services/spotify_connect_service.dart';

class AudioMusicHub extends StatefulWidget {
  final VoidCallback? onLocalPlaybackStarted;
  const AudioMusicHub({super.key, this.onLocalPlaybackStarted});

  @override
  State<AudioMusicHub> createState() => _AudioMusicHubState();
}

class _AudioMusicHubState extends State<AudioMusicHub> {
  List<MusicLibraryTrack> _tracks = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    AudioVaultExtrasService.revision.addListener(_load);
    SpotifyConnectService.initialize();
    _load();
  }

  @override
  void dispose() {
    AudioVaultExtrasService.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final list = await AudioVaultExtrasService.musicLibrary();
    if (!mounted) return;
    setState(() {
      _tracks = list;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 140),
      children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Music Hub',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 20, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text(
                'Отдельная музыкальная библиотека. Локальные треки и Spotify управляются из WesiOS, а мини-плеер остаётся поверх других модулей.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 11.5, height: 1.4),
              ),
            ]),
          ),
          FilledButton.icon(
            onPressed: _import,
            icon: const Icon(Icons.library_add),
            label: const Text('Добавить музыку'),
          ),
        ]),
        const SizedBox(height: 16),
        _spotify(),
        const SizedBox(height: 16),
        _localLibrary(),
      ],
    );
  }

  Widget _localLibrary() {
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: AppTheme.surface.withOpacity(.45),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.glassBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.folder_copy_outlined, color: AppTheme.accent),
          const SizedBox(width: 9),
          Text('Локальная библиотека',
              style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900)),
          const Spacer(),
          Text('${_tracks.length} треков', style: TextStyle(color: AppTheme.textMuted, fontSize: 10)),
        ]),
        const SizedBox(height: 10),
        if (_loading)
          const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
        else if (_tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Center(
              child: Text('Добавь MP3 / WAV / OGG / FLAC — WesiOS скопирует их в Music Hub.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
            ),
          )
        else
          for (final track in _tracks)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withOpacity(.1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(Icons.music_note, color: AppTheme.accent),
              ),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(track.path, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  tooltip: 'Играть',
                  onPressed: () => _play(track),
                  icon: Icon(Icons.play_circle_fill_rounded, color: AppTheme.accent, size: 30),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'delete') _remove(track);
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'delete', child: Text('Удалить из Music Hub')),
                  ],
                ),
              ]),
            ),
      ]),
    );
  }

  Widget _spotify() {
    return ValueListenableBuilder<SpotifyPlaybackState>(
      valueListenable: SpotifyConnectService.state,
      builder: (context, s, _) {
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppTheme.surface.withOpacity(.45),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.glassBorder),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFF1DB954).withOpacity(.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.sensors, color: Color(0xFF1DB954)),
              ),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Spotify Connect',
                    style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900, fontSize: 15)),
                Text(
                  s.connected
                      ? (s.deviceName?.isNotEmpty == true ? 'Подключено · ${s.deviceName}' : 'Аккаунт подключён')
                      : 'Управление активным Spotify устройством через Web API',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5),
                ),
              ])),
              IconButton(
                tooltip: 'Spotify Client ID / OAuth',
                onPressed: _spotifySettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              if (s.connected)
                TextButton(onPressed: SpotifyConnectService.disconnect, child: const Text('Отключить'))
              else
                FilledButton(
                  onPressed: s.loading ? null : SpotifyConnectService.connect,
                  child: s.loading
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(s.configured ? 'Подключить' : 'Настроить'),
                ),
            ]),
            if (!s.configured) ...[
              const SizedBox(height: 10),
              Text(
                'Нужен Spotify Client ID. В Spotify Developer Dashboard добавь redirect URI: http://127.0.0.1/callback — WesiOS подставит динамический loopback-порт при авторизации.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 10.3, height: 1.4),
              ),
            ],
            if (s.error != null) ...[
              const SizedBox(height: 8),
              Text(s.error!, style: TextStyle(color: AppTheme.accentRed, fontSize: 10.5)),
            ],
            if (s.connected) ...[
              const SizedBox(height: 12),
              if (!s.available)
                Row(children: [
                  Expanded(child: Text('Нет активного playback. Запусти любой трек в Spotify, затем WesiOS подхватит устройство.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5))),
                  OutlinedButton.icon(onPressed: _openSpotify, icon: const Icon(Icons.open_in_new), label: const Text('Открыть Spotify')),
                ])
              else ...[
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: s.imageUrl != null
                        ? Image.network(s.imageUrl!, width: 58, height: 58, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _spotifyPlaceholder())
                        : _spotifyPlaceholder(),
                  ),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.track, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textPrimary, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5)),
                    if (s.album.isNotEmpty)
                      Text(s.album, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: AppTheme.textMuted, fontSize: 9)),
                  ])),
                ]),
                Slider(
                  value: s.durationMs <= 0 ? 0 : (s.progressMs / s.durationMs).clamp(0.0, 1.0),
                  onChanged: s.durationMs <= 0 ? null : (v) => SpotifyConnectService.seek((s.durationMs * v).round()),
                ),
                Row(children: [
                  IconButton(onPressed: SpotifyConnectService.previous, icon: const Icon(Icons.skip_previous_rounded)),
                  IconButton(
                    onPressed: SpotifyConnectService.toggle,
                    icon: Icon(s.playing ? Icons.pause_circle_filled : Icons.play_circle_fill,
                        size: 38, color: const Color(0xFF1DB954)),
                  ),
                  IconButton(onPressed: SpotifyConnectService.next, icon: const Icon(Icons.skip_next_rounded)),
                  const SizedBox(width: 8),
                  Icon(Icons.volume_down, size: 17, color: AppTheme.textMuted),
                  Expanded(
                    child: Slider(
                      value: s.volumePercent.toDouble().clamp(0, 100),
                      min: 0,
                      max: 100,
                      onChanged: (v) => SpotifyConnectService.setVolume(v.round()),
                    ),
                  ),
                ]),
              ],
            ],
          ]),
        );
      },
    );
  }

  Widget _spotifyPlaceholder() => Container(
        width: 58,
        height: 58,
        color: const Color(0xFF1DB954).withOpacity(.13),
        child: const Icon(Icons.album, color: Color(0xFF1DB954)),
      );

  Future<void> _spotifySettings() async {
    final current = await SpotifyConnectService.clientId();
    if (!mounted) return;
    final controller = TextEditingController(text: current);
    final saved = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Spotify OAuth'),
        content: SizedBox(
          width: 500,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Spotify Client ID'),
            const SizedBox(height: 7),
            TextField(controller: controller, decoration: const InputDecoration(hintText: 'Client ID из Spotify Developer Dashboard')),
            const SizedBox(height: 12),
            Text(
              'В настройках Spotify App добавь Redirect URI:\nhttp://127.0.0.1/callback\n\nClient Secret в WesiOS не нужен: используется PKCE.',
              style: TextStyle(color: AppTheme.textMuted, fontSize: 10.5, height: 1.45),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Сохранить')),
        ],
      ),
    );
    controller.dispose();
    if (saved == null) return;
    await SpotifyConnectService.saveClientId(saved);
  }

  Future<void> _openSpotify() async {
    final app = Uri.parse('spotify:');
    if (!await launchUrl(app, mode: LaunchMode.externalApplication)) {
      await launchUrl(Uri.parse('https://open.spotify.com'), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _import() async {
    setState(() => _loading = true);
    await AudioVaultExtrasService.importMusic();
    await _load();
  }

  Future<void> _play(MusicLibraryTrack track) async {
    final queue = _tracks.map(AudioVaultExtrasService.asPlayable).toList();
    final beat = AudioVaultExtrasService.asPlayable(track);
    await AudioPlayerService.playBeat(beat, queue: queue);
    widget.onLocalPlaybackStarted?.call();
  }

  Future<void> _remove(MusicLibraryTrack track) async {
    await AudioVaultExtrasService.removeMusic(track);
    await _load();
  }
}
