# WesiOS Telegram Webhook

Webhook-сервер для отправки уведомлений из WesiOS в Telegram.

## Установка

1. Зарегистрируйся на [Vercel](https://vercel.com)
2. Создай новый проект из этого репозитория
3. Добавь переменную окружения `TELEGRAM_BOT_TOKEN`
4. Задеплой

## API

### POST /api/send-message

Отправляет сообщение в Telegram.

**Body:**
```json
{
  "chat_id": "123456789",
  "message": "Привет из WesiOS!",
  "parse_mode": "HTML"
}
```

**Response:**
```json
{
  "success": true,
  "message_id": 123
}
```

## Использование в WesiOS

```dart
final response = await http.post(
  Uri.parse('https://your-vercel-url.vercel.app/api/send-message'),
  headers: {'Content-Type': 'application/json'},
  body: jsonEncode({
    'chat_id': userChatId,
    'message': 'Ваша задача просрочена!',
  }),
);
```
