import 'dart:convert';
import 'dart:io';

import 'github_auth_service.dart';

/// Чем закончилась попытка открыть файл релиза.
enum ReleaseFetch {
  ok,

  /// Репозиторий закрыт, а входа в GitHub нет. Это не «файла не существует»
  /// и не «нет сети» — это единственный случай, который человек может
  /// исправить сам, и говорить о нём надо отдельно.
  needsSignIn,

  /// Файла нет ни анонимно, ни по токену.
  notFound,

  network,
}

class ReleaseAsset {
  final ReleaseFetch status;
  final HttpClientResponse? response;

  const ReleaseAsset(this.status, [this.response]);

  bool get ok => status == ReleaseFetch.ok && response != null;
}

/// Скачивание файлов, приложенных к GitHub Release.
///
/// **Зачем отдельно.** У открытого репозитория ассеты доступны по прямой
/// ссылке кому угодно; у закрытого та же ссылка отдаёт 404 — включая само
/// приложение. Разница видна только в момент, когда репозиторий закрывают, и
/// проявляется как «скачивание перестало работать» без единого объяснения.
///
/// Здесь оба случая обрабатываются одним кодом: сначала прямая ссылка (она
/// быстрее — отдаёт CDN), при отказе — обращение к API с токеном. Ничего
/// настраивать при смене видимости репозитория не нужно.
class GitHubReleaseDownload {
  static const String owner = 'wesiwer';
  static const String repo = 'WesiOS';

  /// Узнали, что прямая ссылка не работает. Повторять её на каждый файл
  /// незачем — это лишний запрос с гарантированным отказом.
  static bool _anonymousFails = false;

  /// Идентификаторы ассетов по тегу релиза: `тег → {имя файла → id}`.
  static final Map<String, Map<String, int>> _assetIds = {};

  /// Забыть накопленное. Нужно при входе и выходе из GitHub: после входа
  /// стоит снова попробовать всё с начала.
  static void forget() {
    _anonymousFails = false;
    _assetIds.clear();
  }

  static Future<ReleaseAsset> open(
    HttpClient client, {
    required String tag,
    required String asset,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (!_anonymousFails) {
      final direct = await _anonymous(client, tag, asset, timeout);
      if (direct != null) return ReleaseAsset(ReleaseFetch.ok, direct);
      _anonymousFails = true;
    }

    final headers = await GitHubAuthService.authHeaders();
    if (headers.isEmpty) return const ReleaseAsset(ReleaseFetch.needsSignIn);

    final ids = _assetIds[tag] ?? await _fetchAssetIds(client, tag, headers);
    if (ids == null) return const ReleaseAsset(ReleaseFetch.network);
    _assetIds[tag] = ids;

    final id = ids[asset];
    if (id == null) return const ReleaseAsset(ReleaseFetch.notFound);

    final res = await _byId(client, id, headers, timeout);
    return res == null
        ? const ReleaseAsset(ReleaseFetch.network)
        : ReleaseAsset(ReleaseFetch.ok, res);
  }

  static Future<HttpClientResponse?> _anonymous(
    HttpClient client,
    String tag,
    String asset,
    Duration timeout,
  ) async {
    try {
      final req = await client.getUrl(Uri.parse(
          'https://github.com/$owner/$repo/releases/download/$tag/$asset'));
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close().timeout(timeout);
      if (res.statusCode == 200) return res;
      // Тело отказа надо вычитать, иначе соединение останется висеть.
      await res.drain<void>();
      return null;
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, int>?> _fetchAssetIds(
    HttpClient client,
    String tag,
    Map<String, String> headers,
  ) async {
    try {
      final req = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/$owner/$repo/releases/tags/$tag'));
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close();
      if (res.statusCode != 200) {
        await res.drain<void>();
        return null;
      }
      final json = jsonDecode(await res.transform(utf8.decoder).join());
      if (json is! Map || json['assets'] is! List) return null;
      return {
        for (final a in json['assets'] as List)
          if (a is Map && a['name'] is String && a['id'] is int)
            a['name'] as String: a['id'] as int,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<HttpClientResponse?> _byId(
    HttpClient client,
    int assetId,
    Map<String, String> headers,
    Duration timeout,
  ) async {
    try {
      final req = await client.getUrl(Uri.parse(
          'https://api.github.com/repos/$owner/$repo/releases/assets/$assetId'));
      // Перенаправления обрабатываем сами и НЕ переносим на них заголовок
      // Authorization: GitHub уводит на подписанную ссылку в хранилище, и
      // чужой токен в запросе к ней — повод для отказа. Плюс он утёк бы
      // третьей стороне.
      req.followRedirects = false;
      headers.forEach(req.headers.set);
      req.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      req.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
      final res = await req.close().timeout(timeout);

      if (res.statusCode == 200) return res;
      if (res.statusCode == 302 || res.statusCode == 307) {
        final location = res.headers.value(HttpHeaders.locationHeader);
        await res.drain<void>();
        if (location == null) return null;
        final redirect = await client.getUrl(Uri.parse(location));
        redirect.headers.set(HttpHeaders.userAgentHeader, 'WesiOS');
        final out = await redirect.close().timeout(timeout);
        if (out.statusCode == 200) return out;
        await out.drain<void>();
        return null;
      }
      await res.drain<void>();
      return null;
    } catch (_) {
      return null;
    }
  }
}
