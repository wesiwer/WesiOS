const { createClient } = require('@vercel/postgres');

module.exports = async (req, res) => {
  // Enable CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');

  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }

  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'Method not allowed' });
  }

  const { chat_id, message, parse_mode = 'HTML' } = req.body;

  if (!chat_id || !message) {
    return res.status(400).json({ error: 'chat_id and message are required' });
  }

  const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN;

  if (!BOT_TOKEN) {
    return res.status(500).json({ error: 'Bot token not configured' });
  }

  try {
    const response = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/sendMessage`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        chat_id,
        text: message,
        parse_mode,
      }),
    });

    const data = await response.json();

    if (data.ok) {
      return res.status(200).json({ success: true, message_id: data.result.message_id });
    } else {
      return res.status(400).json({ success: false, error: data.description });
    }
  } catch (error) {
    return res.status(500).json({ success: false, error: error.message });
  }
};
