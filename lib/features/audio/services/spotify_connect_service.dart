import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class SpotifyPlaybackState {
  final bool configured;
  final bool connected;
  final bool loading;
  final bool available;
  final bool playing;
  final String track;
  final String artist;
  final String album;
  final String? imageUrl;
  final String? deviceName;
  final int progressMs;
  final int durationMs;
  final int volumePercent;
  final String? error;

  const SpotifyPlaybackState({
    this.configured = false,
    this.connected = false,
    this.loading = false,
    this.available = false,
    this.playing = false,
    this.track = '',
    this.artist = '',
    this.album = '',
    this.imageUrl,
    this.deviceName,
    this.progressMs = 0,
    this.durationMs = 0,
    this.volumePercent = 50,
    this.error,
  });

  SpotifyPlaybackState copyWith({
    bool? configured,
    bool? connected,
    bool? loading,
    bool? available,
    bool? playing,
    String? track,
    String? artist,
    String? album,
    String? imageUrl,
    String? deviceName,
    int? progressMs,
    int? durationMs,
    int? volumePercent,
    String? error,
    bool clearError = false,
  }) =>
      SpotifyPlaybackState(
        configured: configured ?? this.configured,
        connected: connected ?? this.connected,
        loading: loading ?? this.loading,
        available: available ?? this.available,
        playing: playing ?? this.playing,
        track: track ?? this.track,
        artist: artist ?? this.artist,
        album: album ?? this.album,
        imageUrl: imageUrl ?? this.imageUrl,
        deviceName: deviceName ?? this.deviceName,
        progressMs: progressMs ?? this.progressMs,
        durationMs: durationMs ?? this.durationMs,
        volumePercent: volumePercent ?? this.volumePercent,
        error: clearError ? null : (error ?? this.error),
      );
}

class SpotifyConnectService {
  SpotifyConnectService._();

  static const _clientIdKey = 'audio_spotify_client_id';
  static const _accessKey = 'audio_spotify_access';
  static const _refreshKey = 'audio_spotify_refresh';
  static const _expiresKey = 'audio_spotify_expires';
  static const _secure = FlutterSecureStorage();
  static Timer? _poll;
  static bool _refreshing = false;

  static final ValueNotifier<SpotifyPlaybackState> state =
      ValueNotifier(const SpotifyPlaybackState());

  static Future<String> clientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clientIdKey)?.trim() ?? '';
  }

  static Future<void> initialize() async {
    final id = await clientId();
    final refresh = await _secure.read(key: _refreshKey);
    state.value = state.value.copyWith(
      configured: id.isNotEmpty,
      connected: refresh?.isNotEmpty == true,
    );
    if (id.isNotEmpty && refresh?.isNotEmpty == true) {
      await refreshPlayback();
      _startPolling();
    }
  }

  static Future<void> saveClientId(String value) async {
    final prefs = await SharedPreferences.getInstance();
    final id = value.trim();
    if (id.isEmpty) {
      await prefs.remove(_clientIdKey);
    } else {
      await prefs.setString(_clientIdKey, id);
    }
    state.value = state.value.copyWith(configured: id.isNotEmpty);
  }

  static Future<void> connect() async {
    final id = await clientId();
    if (id.isEmpty) {
      state.value = state.value.copyWith(
        configured: false,
        error: 'Сначала укажи Spotify Client ID.',
      );
      return;
    }
    state.value = state.value.copyWith(loading: true, clearError: true);
    HttpServer? server;
    try {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final redirect = 'http://127.0.0.1:${server.port}/callback';
      final verifier = _randomToken(64);
      final challenge = base64UrlEncode(sha256.convert(utf8.encode(verifier)).bytes)
          .replaceAll('=', '');
      final oauthState = _randomToken(24);
      final auth = Uri.https('accounts.spotify.com', '/authorize', {
        'client_id': id,
        'response_type': 'code',
        'redirect_uri': redirect,
        'scope': 'user-read-playback-state user-read-currently-playing user-modify-playback-state',
        'code_challenge_method': 'S256',
        'code_challenge': challenge,
        'state': oauthState,
      });
      final opened = await launchUrl(auth, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('Не удалось открыть Spotify authorization page.');

      final req = await server.first.timeout(const Duration(minutes: 3));
      final returnedState = req.uri.queryParameters['state'];
      final code = req.uri.queryParameters['code'];
      final oauthError = req.uri.queryParameters['error'];
      req.response.headers.contentType = ContentType.html;
      req.response.write('''<!doctype html><html><body style="font-family:sans-serif;background:#0b0d12;color:white;padding:40px"><h2>WesiOS × Spotify</h2><p>${oauthError == null ? 'Аккаунт подключён. Можно вернуться в WesiOS.' : 'Spotify не выдал доступ: $oauthError'}</p></body></html>''');
      await req.response.close();
      if (oauthError != null) throw Exception('Spotify OAuth: $oauthError');
      if (returnedState != oauthState || code == null || code.isEmpty) {
        throw Exception('Spotify OAuth state/code validation failed.');
      }

      final tokenResponse = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': id,
          'grant_type': 'authorization_code',
          'code': code,
          'redirect_uri': redirect,
          'code_verifier': verifier,
        },
      );
      if (tokenResponse.statusCode < 200 || tokenResponse.statusCode >= 300) {
        throw Exception('Spotify token exchange ${tokenResponse.statusCode}: ${tokenResponse.body}');
      }
      await _storeToken(jsonDecode(tokenResponse.body) as Map<String, dynamic>);
      state.value = state.value.copyWith(
        configured: true,
        connected: true,
        loading: false,
        clearError: true,
      );
      await refreshPlayback();
      _startPolling();
    } on TimeoutException {
      state.value = state.value.copyWith(
        loading: false,
        error: 'Spotify authorization timeout.',
      );
    } catch (e) {
      state.value = state.value.copyWith(loading: false, error: '$e');
    } finally {
      await server?.close(force: true);
    }
  }

  static Future<void> disconnect() async {
    _poll?.cancel();
    _poll = null;
    await _secure.delete(key: _accessKey);
    await _secure.delete(key: _refreshKey);
    await _secure.delete(key: _expiresKey);
    state.value = SpotifyPlaybackState(configured: (await clientId()).isNotEmpty);
  }

  static void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => refreshPlayback());
  }

  static Future<void> refreshPlayback() async {
    final response = await _call('GET', Uri.parse('https://api.spotify.com/v1/me/player'));
    if (response == null) return;
    if (response.statusCode == 204) {
      state.value = state.value.copyWith(
        connected: true,
        available: false,
        loading: false,
        clearError: true,
      );
      return;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      state.value = state.value.copyWith(error: _apiError(response));
      return;
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final item = json['item'] as Map?;
    final device = json['device'] as Map?;
    final album = item?['album'] as Map?;
    final artists = item?['artists'] as List?;
    String? image;
    final images = album?['images'] as List?;
    if (images != null && images.isNotEmpty && images.first is Map) {
      image = '${(images.first as Map)['url'] ?? ''}';
      if (image.isEmpty) image = null;
    }
    state.value = SpotifyPlaybackState(
      configured: true,
      connected: true,
      loading: false,
      available: item != null,
      playing: json['is_playing'] == true,
      track: '${item?['name'] ?? ''}',
      artist: artists == null
          ? ''
          : artists
              .whereType<Map>()
              .map((e) => '${e['name'] ?? ''}')
              .where((e) => e.isNotEmpty)
              .join(', '),
      album: '${album?['name'] ?? ''}',
      imageUrl: image,
      deviceName: device == null ? null : '${device['name'] ?? ''}',
      progressMs: (json['progress_ms'] as num?)?.toInt() ?? 0,
      durationMs: (item?['duration_ms'] as num?)?.toInt() ?? 0,
      volumePercent: (device?['volume_percent'] as num?)?.toInt() ?? 50,
    );
  }

  static Future<void> toggle() async {
    final s = state.value;
    final endpoint = s.playing ? '/v1/me/player/pause' : '/v1/me/player/play';
    final response = await _call('PUT', Uri.parse('https://api.spotify.com$endpoint'));
    if (_ok(response)) {
      state.value = state.value.copyWith(playing: !s.playing, clearError: true);
      await refreshPlayback();
    }
  }

  static Future<void> next() async {
    final response = await _call('POST', Uri.parse('https://api.spotify.com/v1/me/player/next'));
    if (_ok(response)) await Future<void>.delayed(const Duration(milliseconds: 250));
    await refreshPlayback();
  }

  static Future<void> previous() async {
    final response = await _call('POST', Uri.parse('https://api.spotify.com/v1/me/player/previous'));
    if (_ok(response)) await Future<void>.delayed(const Duration(milliseconds: 250));
    await refreshPlayback();
  }

  static Future<void> seek(int milliseconds) async {
    final ms = max(0, milliseconds);
    final response = await _call(
      'PUT',
      Uri.parse('https://api.spotify.com/v1/me/player/seek?position_ms=$ms'),
    );
    if (_ok(response)) {
      state.value = state.value.copyWith(progressMs: ms, clearError: true);
    }
  }

  static Future<void> setVolume(int percent) async {
    final v = percent.clamp(0, 100);
    final response = await _call(
      'PUT',
      Uri.parse('https://api.spotify.com/v1/me/player/volume?volume_percent=$v'),
    );
    if (_ok(response)) {
      state.value = state.value.copyWith(volumePercent: v, clearError: true);
    }
  }

  static Future<http.Response?> _call(String method, Uri uri) async {
    try {
      final token = await _validAccessToken();
      if (token == null || token.isEmpty) {
        state.value = state.value.copyWith(connected: false, error: 'Spotify не подключён.');
        return null;
      }
      final headers = {'Authorization': 'Bearer $token'};
      http.Response response;
      switch (method) {
        case 'POST':
          response = await http.post(uri, headers: headers);
          break;
        case 'PUT':
          response = await http.put(uri, headers: headers);
          break;
        default:
          response = await http.get(uri, headers: headers);
      }
      if (response.statusCode == 401) {
        await _refreshAccessToken(force: true);
        final retry = await _secure.read(key: _accessKey);
        if (retry == null || retry.isEmpty) return response;
        final h = {'Authorization': 'Bearer $retry'};
        switch (method) {
          case 'POST':
            return http.post(uri, headers: h);
          case 'PUT':
            return http.put(uri, headers: h);
          default:
            return http.get(uri, headers: h);
        }
      }
      return response;
    } catch (e) {
      state.value = state.value.copyWith(error: 'Spotify: $e');
      return null;
    }
  }

  static bool _ok(http.Response? response) {
    if (response == null) return false;
    if (response.statusCode >= 200 && response.statusCode < 300) return true;
    state.value = state.value.copyWith(error: _apiError(response));
    return false;
  }

  static String _apiError(http.Response response) {
    if (response.statusCode == 403) {
      return 'Spotify отклонил playback-команду. Player API требует Premium и активное Spotify Connect устройство.';
    }
    if (response.statusCode == 429) return 'Spotify rate limit. Повтори чуть позже.';
    return 'Spotify API ${response.statusCode}: ${response.body}';
  }

  static Future<String?> _validAccessToken() async {
    final expiresRaw = await _secure.read(key: _expiresKey);
    final expires = DateTime.tryParse(expiresRaw ?? '');
    final access = await _secure.read(key: _accessKey);
    if (access != null && access.isNotEmpty && expires != null &&
        DateTime.now().isBefore(expires.subtract(const Duration(minutes: 2)))) {
      return access;
    }
    await _refreshAccessToken();
    return _secure.read(key: _accessKey);
  }

  static Future<void> _refreshAccessToken({bool force = false}) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final refresh = await _secure.read(key: _refreshKey);
      final id = await clientId();
      if (refresh == null || refresh.isEmpty || id.isEmpty) return;
      final response = await http.post(
        Uri.parse('https://accounts.spotify.com/api/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'refresh_token',
          'refresh_token': refresh,
          'client_id': id,
        },
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.body.contains('invalid_grant')) await disconnect();
        return;
      }
      await _storeToken(jsonDecode(response.body) as Map<String, dynamic>);
      state.value = state.value.copyWith(connected: true, clearError: true);
    } finally {
      _refreshing = false;
    }
  }

  static Future<void> _storeToken(Map<String, dynamic> token) async {
    final access = '${token['access_token'] ?? ''}';
    if (access.isNotEmpty) await _secure.write(key: _accessKey, value: access);
    final refresh = '${token['refresh_token'] ?? ''}';
    if (refresh.isNotEmpty) await _secure.write(key: _refreshKey, value: refresh);
    final seconds = (token['expires_in'] as num?)?.toInt() ?? 3600;
    await _secure.write(
      key: _expiresKey,
      value: DateTime.now().add(Duration(seconds: seconds)).toIso8601String(),
    );
  }

  static String _randomToken(int bytes) {
    final random = Random.secure();
    return base64UrlEncode(List<int>.generate(bytes, (_) => random.nextInt(256)))
        .replaceAll('=', '');
  }
}
