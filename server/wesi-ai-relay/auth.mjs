import crypto from 'node:crypto';

const MAX_SKEW_SECONDS = 300;

export function verifyMainRequest(headers, rawBody, sharedSecret) {
  if (String(sharedSecret || '').length < 32) {
    return {ok: false, code: 'WAI_RELAY_NOT_CONFIGURED'};
  }
  const timestamp = String(headers['x-wesi-timestamp'] || '');
  const signature = String(headers['x-wesi-signature'] || '');
  const requestId = String(headers['x-wesi-request-id'] || '');
  if (!/^wai_[A-Za-z0-9_-]{8,120}$/.test(requestId)) {
    return {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
  }
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Math.floor(Date.now() / 1000) - ts) > MAX_SKEW_SECONDS) {
    return {ok: false, code: 'WAI_RELAY_REQUEST_EXPIRED'};
  }
  if (!/^[a-f0-9]{64}$/i.test(signature)) {
    return {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
  }
  const expected = crypto.createHmac('sha256', sharedSecret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex');
  const valid = crypto.timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expected, 'hex'));
  return valid ? {ok: true, requestId} : {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
}
