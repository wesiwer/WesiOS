import crypto from 'node:crypto';

const MAX_SKEW_SECONDS = 300;

/// Сколько идентификаторов помнить, чтобы отличать повтор от нового запроса.
///
/// Помнить нужно только те, что ещё могли бы пройти проверку времени, то
/// есть окно перекоса. Предел стоит на случай потока: при 20 000 записей на
/// пятиминутное окно это больше 60 запросов в секунду непрерывно.
const MAX_SEEN = 20000;

const seen = new Map();

function remember(requestId, nowMs) {
  // Просроченные удаляются на каждой вставке, а не по таймеру: без живого
  // трафика чистить нечего, а под нагрузкой чистка идёт сама собой.
  if (seen.size >= MAX_SEEN) {
    for (const [key, expiresAt] of seen) {
      if (expiresAt <= nowMs) seen.delete(key);
    }
  }
  if (seen.size >= MAX_SEEN) return false;
  seen.set(requestId, nowMs + (MAX_SKEW_SECONDS + 60) * 1000);
  return true;
}

export function resetReplayCache() {
  seen.clear();
}

/// Проверка запроса от главного сервера.
///
/// Подписывается `requestId.timestamp.body`, а не `timestamp.body`.
/// Разница существенная: пока идентификатор оставался вне подписи, он ни
/// на что не влиял — перехваченный запрос можно было отправить повторно с
/// любым другим идентификатором, и подпись оставалась верной. Проверка
/// времени такой повтор не ловит: она пропускает всё, что моложе окна
/// перекоса.
///
/// Второй половиной защиты служит память об уже виденных идентификаторах:
/// подпись теперь привязывает запрос к конкретному идентификатору, а память
/// не даёт использовать его дважды. Одного без другого недостаточно.
export function verifyMainRequest(headers, rawBody, sharedSecret, options = {}) {
  if (String(sharedSecret || '').length < 32) {
    return {ok: false, code: 'WAI_RELAY_NOT_CONFIGURED'};
  }
  const timestamp = String(headers['x-wesi-timestamp'] || '');
  const signature = String(headers['x-wesi-signature'] || '');
  const requestId = String(headers['x-wesi-request-id'] || '');
  if (!/^wai_[A-Za-z0-9_-]{8,120}$/.test(requestId)) {
    return {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
  }
  const nowMs = typeof options.nowMs === 'number' ? options.nowMs : Date.now();
  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(Math.floor(nowMs / 1000) - ts) > MAX_SKEW_SECONDS) {
    return {ok: false, code: 'WAI_RELAY_REQUEST_EXPIRED'};
  }
  if (!/^[a-f0-9]{64}$/i.test(signature)) {
    return {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};
  }
  const expected = crypto.createHmac('sha256', sharedSecret)
    .update(`${requestId}.${timestamp}.${rawBody}`)
    .digest('hex');
  const valid = crypto.timingSafeEqual(Buffer.from(signature, 'hex'), Buffer.from(expected, 'hex'));
  if (!valid) return {ok: false, code: 'WAI_RELAY_AUTH_FAILED'};

  // Память проверяется последней и только для подлинных запросов: иначе
  // подделкой можно было бы занять чужой идентификатор заранее и не дать
  // пройти настоящему.
  if (seen.has(requestId)) {
    return {ok: false, code: 'WAI_RELAY_REPLAY_DETECTED'};
  }
  if (!remember(requestId, nowMs)) {
    // Переполнение памяти — отказ, а не пропуск. Ошибиться здесь можно в
    // две стороны, и отклонённый настоящий запрос несравнимо дешевле
    // принятого повтора.
    return {ok: false, code: 'WAI_RELAY_BUSY'};
  }
  return {ok: true, requestId};
}
