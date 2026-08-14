import http from 'node:http';
import {verifyMainRequest} from './auth.mjs';
import {callTextRoute} from './google.mjs';
import {
  callGoogleTts,
  callGoogleImage,
  callGoogleMusic,
  startGoogleVideo,
  getGoogleVideoStatus,
} from './google-media.mjs';
import {downloadGoogleVideo} from './google-artifact.mjs';
import {putMedia, putBytes, takeMedia} from './media-cache.mjs';

const host = process.env.WESI_RELAY_HOST || '127.0.0.1';
const port = Number(process.env.WESI_RELAY_PORT || 8787);
const secret = String(process.env.WESI_MAIN_SHARED_SECRET || '');
const googleKey = String(process.env.GEMINI_API_KEY || '');
// Image/video/music provider endpoints can incur provider charges. Wesi AI is
// free-by-default, so those routes remain unavailable unless an operator
// explicitly opts in on the Relay host. Natural TTS is kept separate.
const paidMediaEnabled = /^(1|true|yes)$/i.test(String(process.env.WESI_ENABLE_PAID_MEDIA || 'false'));

function send(res, status, body) {
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
  });
  res.end(JSON.stringify(body));
}

function sendArtifact(res, item) {
  res.writeHead(200, {
    'content-type': item.mimeType || 'application/octet-stream',
    'content-length': String(item.bytes.length),
    'cache-control': 'no-store',
    'x-content-type-options': 'nosniff',
    'x-wesi-media-kind': item.kind || 'media',
  });
  res.end(item.bytes);
}

async function readBody(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > 2097152) throw new Error('too_large');
    chunks.push(chunk);
  }
  return Buffer.concat(chunks).toString('utf8');
}

function authenticate(req, raw) {
  const auth = verifyMainRequest(req.headers, raw, secret);
  if (!auth.ok) return {ok: false, auth};
  let request;
  try {
    request = JSON.parse(raw);
  } catch {
    return {ok: false, badJson: true};
  }
  if (String(request.requestId || '') !== auth.requestId) {
    return {ok: false, auth: {ok: false, code: 'WAI_RELAY_AUTH_FAILED'}};
  }
  return {ok: true, request};
}

async function execute(request) {
  const operation = String(request.operation || '');
  if (operation === 'chat' || operation === 'lobby') {
    return callTextRoute(request.route, request.input || {}, googleKey);
  }
  if (operation === 'tts') return callGoogleTts(request.input || {}, googleKey);
  if (operation === 'image' || operation === 'music' || operation === 'video.start' || operation === 'video.status') {
    if (!paidMediaEnabled) {
      return {ok: false, status: 409, code: 'WAI_LOCAL_MEDIA_ENGINE_REQUIRED'};
    }
  }
  if (operation === 'image') return callGoogleImage(request.input || {}, googleKey);
  if (operation === 'music') return callGoogleMusic(request.input || {}, googleKey);
  if (operation === 'video.start') return startGoogleVideo(request.input || {}, googleKey);
  if (operation === 'video.status') {
    const status = await getGoogleVideoStatus(request.input?.operationName, googleKey);
    if (!status?.ok || !status.done || status.failed || !status.providerUri) return status;
    const downloaded = await downloadGoogleVideo(status.providerUri, googleKey);
    if (!downloaded?.ok) return downloaded;
    const cached = putBytes(downloaded.bytes, {
      kind: 'video',
      mimeType: downloaded.mimeType,
    });
    if (!cached.ok) return {ok: false, status: 503, code: cached.code};
    return {
      ok: true,
      done: true,
      failed: false,
      media: {
        kind: 'video',
        mimeType: downloaded.mimeType,
        byteSize: cached.byteSize,
        relayArtifactId: cached.artifactId,
        expiresAt: cached.expiresAt,
      },
    };
  }
  return {ok: false, status: 400, code: 'WAI_OPERATION_UNAVAILABLE'};
}

http.createServer(async (req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    return send(res, 200, {
      ok: true,
      service: 'wesi-ai-relay',
      ready: secret.length >= 32 && googleKey.length > 0,
      routing: ['fast', 'pro', 'ultra'],
      media: {
        tts: googleKey.length > 0,
        paidCloudEnabled: paidMediaEnabled,
        image: paidMediaEnabled,
        music: paidMediaEnabled,
        video: paidMediaEnabled,
        localEngines: true,
      },
    });
  }

  const isMain = req.method === 'POST' && req.url === '/v1/wesi-ai';
  const isArtifact = req.method === 'POST' && req.url === '/v1/wesi-ai-artifact';
  if (!isMain && !isArtifact) return send(res, 404, {ok: false, code: 'NOT_FOUND'});

  let raw;
  try {
    raw = await readBody(req);
  } catch {
    return send(res, 413, {ok: false, code: 'WAI_RELAY_BODY_TOO_LARGE'});
  }

  const parsed = authenticate(req, raw);
  if (!parsed.ok) {
    if (parsed.badJson) return send(res, 400, {ok: false, code: 'WAI_RELAY_BAD_JSON'});
    const auth = parsed.auth || {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
    return send(res, auth.code === 'WAI_RELAY_NOT_CONFIGURED' ? 503 : 401, auth);
  }
  const request = parsed.request;

  if (isArtifact) {
    const artifactId = String(request.artifactId || '');
    const item = takeMedia(artifactId);
    if (!item) return send(res, 404, {ok: false, code: 'WAI_RELAY_ARTIFACT_NOT_FOUND'});
    return sendArtifact(res, item);
  }

  try {
    const result = await execute(request);
    if (!result?.ok) {
      return send(res, result?.status || 502, {ok: false, code: result?.code || 'WAI_PROVIDER_UNAVAILABLE'});
    }
    if (result.answer) {
      return send(res, 200, {
        ok: true,
        answer: result.answer,
        provider: result.provider || null,
        model: result.model || null,
      });
    }

    if (result.media) {
      if (String(result.media.kind || '') === 'tts') {
        return send(res, 200, {ok: true, media: result.media});
      }
      if (result.media.relayArtifactId) {
        return send(res, 200, {ok: true, media: result.media});
      }
      const cached = putMedia(result.media);
      if (!cached.ok) return send(res, 503, {ok: false, code: cached.code});
      const safeMedia = {...result.media};
      delete safeMedia.data;
      safeMedia.relayArtifactId = cached.artifactId;
      safeMedia.mimeType = cached.mimeType;
      safeMedia.byteSize = cached.byteSize;
      safeMedia.expiresAt = cached.expiresAt;
      return send(res, 200, {ok: true, media: safeMedia});
    }

    if (result.operationName) {
      return send(res, 200, {
        ok: true,
        job: {
          operationName: result.operationName,
          model: result.model,
          aspectRatio: result.aspectRatio,
          resolution: result.resolution,
          durationSeconds: result.durationSeconds,
        },
      });
    }

    if (typeof result.done === 'boolean') {
      return send(res, 200, {
        ok: true,
        job: {
          done: result.done,
          failed: result.failed === true,
          code: result.code || null,
          media: result.media || null,
        },
      });
    }
    return send(res, 502, {ok: false, code: 'WAI_RELAY_BAD_RESPONSE'});
  } catch (error) {
    const timeout = error?.name === 'TimeoutError' || error?.name === 'AbortError';
    return send(res, 502, {
      ok: false,
      code: timeout ? 'WAI_PROVIDER_TIMEOUT' : 'WAI_PROVIDER_UNAVAILABLE',
    });
  }
}).listen(port, host, () => console.log(`Wesi AI Relay listening on ${host}:${port}`));
