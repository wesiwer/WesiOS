const MAX_VIDEO_BYTES = 128 * 1024 * 1024;

function allowedProviderUrl(raw) {
  try {
    const url = new URL(String(raw || ''));
    if (url.protocol !== 'https:') return null;
    const host = url.hostname.toLowerCase();
    if (host === 'googleapis.com' || host.endsWith('.googleapis.com')) return url;
    return null;
  } catch {
    return null;
  }
}

export async function downloadGoogleVideo(providerUri, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const url = allowedProviderUrl(providerUri);
  if (!url) return {ok: false, status: 400, code: 'WAI_PROVIDER_BAD_RESPONSE'};
  const fetchImpl = options.fetchImpl || fetch;

  let response;
  try {
    response = await fetchImpl(url, {
      method: 'GET',
      headers: {'x-goog-api-key': apiKey},
      redirect: 'follow',
      signal: AbortSignal.timeout(180000),
    });
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
  }
  if (!response.ok) {
    return {
      ok: false,
      status: response.status === 429 ? 429 : 502,
      code: response.status === 429 ? 'WAI_PROVIDER_RATE_LIMIT' : 'WAI_PROVIDER_REJECTED',
    };
  }

  const mimeType = String(response.headers.get('content-type') || '').split(';')[0].trim().toLowerCase();
  if (!mimeType.startsWith('video/')) {
    return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  const declared = Number(response.headers.get('content-length') || 0);
  if (declared > MAX_VIDEO_BYTES) {
    return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
  }
  if (!response.body) return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};

  const chunks = [];
  let total = 0;
  const reader = response.body.getReader();
  try {
    while (true) {
      const {done, value} = await reader.read();
      if (done) break;
      if (!value?.byteLength) continue;
      total += value.byteLength;
      if (total > MAX_VIDEO_BYTES) {
        try { await reader.cancel(); } catch {}
        return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_MEDIA'};
      }
      chunks.push(Buffer.from(value));
    }
  } finally {
    try { reader.releaseLock(); } catch {}
  }
  if (!total) return {ok: false, status: 502, code: 'WAI_PROVIDER_EMPTY_RESPONSE'};
  return {
    ok: true,
    bytes: Buffer.concat(chunks, total),
    mimeType,
    byteSize: total,
  };
}

export const artifactLimits = Object.freeze({maxVideoBytes: MAX_VIDEO_BYTES});
