// Приём обновлений от Telegram — сюда бот присылает то, что ему написали.
//
// Нужен ровно для одного: узнать chat_id человека. Отправить сообщение в
// личный чат можно только зная его номер, а номер Telegram сообщает лишь
// тогда, когда человек сам напишет боту. Отсюда схема привязки:
//
//   приложение показывает код  →  человек шлёт боту «/start <код>»  →
//   сюда приходит обновление с chat_id  →  приложение забирает пару
//   «код → chat_id» и записывает её себе в профиль.
//
// Адрес этой ручки знает только Telegram, но полагаться на это нельзя:
// адрес может утечь, и тогда кто угодно подделает привязку чужого чата.
// Поэтому Telegram при установке вебхука получает secret_token и присылает
// его в заголовке — проверяем.

const SECRET = process.env.TELEGRAM_WEBHOOK_SECRET;
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;

// Привязки живут в памяти функции и недолго. Это сознательно: хранить их
// дольше незачем — приложение забирает пару сразу, а вечный список
// «код → чат» был бы лишним местом, откуда утекают номера чатов.
//
// Vercel может поднять несколько экземпляров, и тогда код, пришедший в один,
// не найдётся в другом. Поэтому подтверждение отправляется в сам чат: даже
// если приложение промахнётся мимо экземпляра, человек увидит свой chat_id
// сообщением и введёт его руками.
const pending = new Map();
const TTL_MS = 15 * 60 * 1000;

function prune() {
  const now = Date.now();
  for (const [code, entry] of pending) {
    if (now - entry.at > TTL_MS) pending.delete(code);
  }
}

async function reply(chatId, text) {
  if (!BOT_TOKEN) return;
  try {
    await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ chat_id: chatId, text }),
    });
  } catch (_) {
    // Не доставили подтверждение — привязка всё равно состоялась.
  }
}

module.exports = async (req, res) => {
  if (req.method === 'GET') {
    // Приложение спрашивает: код уже подтвердили?
    const code = String(req.query?.code || '').trim();
    prune();
    const entry = code && pending.get(code);
    if (!entry) return res.status(404).json({ linked: false });
    pending.delete(code); // одноразово: второй раз тот же код не сработает
    return res.status(200).json({ linked: true, chat_id: entry.chatId });
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  // Telegram присылает секрет в этом заголовке — см. setWebhook.
  if (
    !SECRET ||
    req.headers['x-telegram-bot-api-secret-token'] !== SECRET
  ) {
    return res.status(401).json({ error: 'Unauthorized' });
  }

  const message = req.body?.message;
  const text = message?.text || '';
  const chatId = message?.chat?.id;
  if (!chatId) return res.status(200).json({ ok: true });

  const match = text.match(/^\/start\s+(\S+)/);
  if (match) {
    prune();
    pending.set(match[1], { chatId, at: Date.now() });
    await reply(
      chatId,
      'WesiOS: чат привязан. Если приложение не подхватило привязку само, '
        + `введите этот номер вручную: ${chatId}`,
    );
  } else if (text.startsWith('/start')) {
    await reply(
      chatId,
      'WesiOS: откройте привязку в приложении — там будет код, отправьте '
        + 'его сюда вместе с командой /start.',
    );
  }

  // Telegram считает доставку неудачной на любом ответе, кроме 200, и будет
  // повторять её. Отвечаем 200 всегда, даже когда сообщение нам не нужно.
  return res.status(200).json({ ok: true });
};
