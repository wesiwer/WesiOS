const MAX_VIDEO_BYTES = 128 * 1024 * 1024;
const MAX_REDIRECTS = 4;

function allowedProviderUrl(raw, base) {
  try {
    const url = base ? new URL(String(raw || ''), base) : new URL(String(raw || ''));
    if (url.protocol !== 'https:') return null;
    if (url.username || url.password) return null;
    const host = url.hostname.toLowerCase();
    if (host === 'googleapis.com' || host.endsWith('.googleapis.com')) return url;
    return null;
  } catch {
    return null;
  }
}

async function fetchValidated(url, apiKey, fetchImpl) {
  let current = url;
  for (let redirects = 0; redirects <= MAX_REDIRECTS; redirects++) {
    let response;
    try {
      response = await fetchImpl(current, {
        method: 'GET',
        headers: {'x-goog-api-key': apiKey},
        // Never let the HTTP stack forward provider credentials to a Location
        // we did not validate. Each hop is resolved and allowlisted below.
        redirect: 'manual',
        signal: AbortSignal.timeout(180000),
      });
    } catch (error) {
      const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
      return {ok: false, status: 502, code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE'};
    }

    if (![301, 302, 303, 307, 308].includes(response.status)) {
      return {ok: true, response};
    }
    if (redirects === MAX_REDIRECTS) {
      return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_RESPONSE'};
    }
    const next = allowedProviderUrl(response.headers.get('location'), current);
    if (!next) {
      return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_RESPONSE'};
    }
    current = next;
  }
  return {ok: false, status: 502, code: 'WAI_PROVIDER_BAD_RESPONSE'};
}

export async function downloadGoogleVideo(providerUri, apiKey, options = {}) {
  if (!apiKey) return {ok: false, status: 503, code: 'WAI_PROVIDER_NOT_CONFIGURED'};
  const url = allowedProviderUrl(providerUri);
  if (!url) return {ok: false, status: 400, code: 'WAI_PROVIDER_BAD_RESPONSE'};
  const fetchImpl = options.fetchImpl || fetch;

  const fetched = await fetchValidated(url, apiKey, fetchImpl);
  if (!fetched.ok) return fetched;
  const response = fetched.response;
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

export const artifactLimits = Object.freeze({
  maxVideoBytes: MAX_VIDEO_BYTES,
  maxRedirects: MAX_REDIRECTS,
});
