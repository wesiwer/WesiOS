// Отправка сообщения в Telegram от имени бота WesiOS.
//
// ЧТО ЗДЕСЬ ИЗМЕНИЛОСЬ И ПОЧЕМУ. Прежняя версия принимала chat_id и текст от
// кого угодно, без всякой проверки, да ещё с Access-Control-Allow-Origin: *.
// Любой, кто узнал адрес, рассылал бы от имени бота что угодно кому угодно —
// это открытый ретранслятор, а не служебная ручка.
//
// Теперь вызывающий обязан предъявить токен Firebase. Проверяется он по
// ОТКРЫТЫМ ключам Google, поэтому на сервере не нужен ни сервисный аккаунт,
// ни какой-либо секрет, кроме токена самого бота. В приложении секрета тоже
// не появляется: токен пользователя оно и так получает при входе.

const { createRemoteJWKSet, jwtVerify } = require('jose');

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID;
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;

// Открытые ключи, которыми Google подписывает токены пользователей.
// createRemoteJWKSet сам кэширует их и обновляет по мере надобности.
const JWKS = createRemoteJWKSet(
  new URL(
    'https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com',
  ),
);

/// Экранирование для parse_mode: HTML.
///
/// Без него одна угловая скобка в чужом имени заставит Telegram отвергнуть
/// всё сообщение — причём молча для того, кто его отправлял.
function escapeHtml(text) {
  return String(text)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

async function verifyCaller(req) {
  const header = req.headers.authorization || '';
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7);

  try {
    const { payload } = await jwtVerify(token, JWKS, {
      // Оба поля обязательны: без них токен из ЧУЖОГО проекта Firebase
      // прошёл бы проверку подписи — ключи-то у Google общие.
      issuer: `https://securetoken.google.com/${PROJECT_ID}`,
      audience: PROJECT_ID,
    });
    if (!payload.sub) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }
  if (!BOT_TOKEN || !PROJECT_ID) {
    // Разные тексты для разных пропущенных переменных: иначе при настройке
    // придётся гадать, какую именно забыли.
    return res.status(500).json({
      error: !BOT_TOKEN
        ? 'TELEGRAM_BOT_TOKEN not configured'
        : 'FIREBASE_PROJECT_ID not configured',
    });
  }

  const caller = await verifyCaller(req);
  if (!caller) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const { chat_id: chatId, message } = req.body || {};
  if (!chatId || !message) {
    return res.status(400).json({ error: 'chat_id and message are required' });
  }

  try {
    const response = await fetch(
      `https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          chat_id: chatId,
          text: escapeHtml(message),
          parse_mode: 'HTML',
        }),
      },
    );
    const data = await response.json();

    if (data.ok) {
      return res
        .status(200)
        .json({ success: true, message_id: data.result.message_id });
    }
    return res.status(400).json({ success: false, error: data.description });
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};
