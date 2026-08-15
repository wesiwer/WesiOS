from pathlib import Path

path = Path('lib/features/ai/runtime/wesi_local_runtime_executor.dart')
text = path.read_text(encoding='utf-8')
old = '''    final client = httpClientFactory();
    try {
      for (var redirect = 0; redirect <= 5; redirect++) {
        await WesiLocalRuntimePolicy.requirePublicHttpDestination(uri);
        final request = method == 'GET'
            ? await client.getUrl(uri)
            : await client.postUrl(uri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (bodyBytes.isNotEmpty) request.add(bodyBytes);
        final response = await request.close().timeout(const Duration(seconds: 30));

        if (response.isRedirect) {
          if (method != 'GET') {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_WRITE_REDIRECT_BLOCKED',
              'Redirect после write HTTP-запроса не выполняется автоматически',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 5) {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_REDIRECT_FAILED',
              'Слишком много или повреждённый HTTP redirect',
            );
          }
          uri = WesiLocalRuntimePolicy.validateHttpUri(uri.resolve(location), context);
          headers = const <String, String>{};
          await response.drain<void>();
          continue;
        }

        final collected = await _collectHttpBody(
          response,
          context.limits.maxHttpResponseBytes,
        );
        final contentType = response.headers.contentType?.mimeType ?? '';
        return WesiLocalToolResult(
          ok: response.statusCode >= 200 && response.statusCode < 400,
          code: response.statusCode >= 200 && response.statusCode < 400
              ? 'OK'
              : 'WLR_HTTP_STATUS',
          message: 'HTTP ${response.statusCode}',
          data: <String, dynamic>{
            'status': response.statusCode,
            'url': uri.toString(),
            'contentType': contentType,
            'body': collected.text,
            if (collected.truncated) 'truncated': true,
          },
        );
      }
      throw const WesiLocalRuntimePolicyException(
        'WLR_HTTP_REDIRECT_FAILED',
        'Слишком много HTTP redirect',
      );
    } finally {
      client.close(force: true);
    }
'''
new = '''    for (var redirect = 0; redirect <= 5; redirect++) {
      final requestUri = uri;
      final addresses = await InternetAddress.lookup(requestUri.host);
      if (addresses.isEmpty ||
          addresses.any(WesiLocalRuntimePolicy.isPrivateOrSpecialAddress)) {
        throw const WesiLocalRuntimePolicyException(
          'WLR_SSRF_BLOCKED',
          'HTTP-назначение попадает в private/internal/special network',
        );
      }
      final pinnedAddress = addresses.first;
      final expectedHost = requestUri.host.toLowerCase();
      final client = httpClientFactory()
        ..findProxy = (_) => 'DIRECT'
        ..connectionFactory = (url, proxyHost, proxyPort) {
          if (proxyHost != null || proxyPort != null ||
              url.host.toLowerCase() != expectedHost) {
            throw const WesiLocalRuntimePolicyException(
              'WLR_SSRF_BLOCKED',
              'HTTP connection не соответствует проверенному назначению',
            );
          }
          final port = url.hasPort
              ? url.port
              : (url.scheme.toLowerCase() == 'https' ? 443 : 80);
          return Socket.startConnect(pinnedAddress, port);
        };
      try {
        final request = method == 'GET'
            ? await client.getUrl(requestUri)
            : await client.postUrl(requestUri);
        request.followRedirects = false;
        headers.forEach(request.headers.set);
        if (bodyBytes.isNotEmpty) request.add(bodyBytes);
        final response = await request.close().timeout(const Duration(seconds: 30));

        if (response.isRedirect) {
          if (method != 'GET') {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_WRITE_REDIRECT_BLOCKED',
              'Redirect после write HTTP-запроса не выполняется автоматически',
            );
          }
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || redirect == 5) {
            throw const WesiLocalRuntimePolicyException(
              'WLR_HTTP_REDIRECT_FAILED',
              'Слишком много или повреждённый HTTP redirect',
            );
          }
          uri = WesiLocalRuntimePolicy.validateHttpUri(
            requestUri.resolve(location),
            context,
          );
          headers = const <String, String>{};
          await response.drain<void>();
          continue;
        }

        final collected = await _collectHttpBody(
          response,
          context.limits.maxHttpResponseBytes,
        );
        final contentType = response.headers.contentType?.mimeType ?? '';
        return WesiLocalToolResult(
          ok: response.statusCode >= 200 && response.statusCode < 400,
          code: response.statusCode >= 200 && response.statusCode < 400
              ? 'OK'
              : 'WLR_HTTP_STATUS',
          message: 'HTTP ${response.statusCode}',
          data: <String, dynamic>{
            'status': response.statusCode,
            'url': requestUri.toString(),
            'contentType': contentType,
            'body': collected.text,
            if (collected.truncated) 'truncated': true,
          },
        );
      } finally {
        client.close(force: true);
      }
    }
    throw const WesiLocalRuntimePolicyException(
      'WLR_HTTP_REDIRECT_FAILED',
      'Слишком много HTTP redirect',
    );
'''
if old not in text:
    raise SystemExit('HTTP patch anchor missing')
path.write_text(text.replace(old, new, 1), encoding='utf-8')
print('Pinned Wesi Local HTTP to validated DNS address')
