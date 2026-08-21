# Wesi Aero Stage 2: Admin, тарифы, ключи и оплаты

## Что реализовано

- revisioned catalog: клиенты опрашивают `/v1/catalog` каждые 20 секунд и
  применяют изменения серверов, тарифов и способов оплаты без переустановки;
- серверный расчёт цены для общего/индивидуального IP, 1–5 устройств и сроков
  7/30/90/180/365 дней;
- ключи `WA1-*`, хранение verifier через `scrypt`, шифрование восстанавливаемой
  копии ключа AES-256-GCM master key сервера;
- привязка устройств и серверные ошибки `DEVICE_LIMIT_EXCEEDED`,
  `LICENSE_EXPIRED`, `LICENSE_REVOKED`;
- заказы с idempotency key и отдельным claim token;
- mock provider для интеграционных тестов, YooKassa/SBP и Crypto Pay adapters;
- Wesi Aero Admin для Android/Windows: серверы, тарифы, ключи, оплаты и настройки;
- application-layer encrypted control channel: HKDF-SHA256 + AES-256-GCM,
  timestamp и replay guard поверх обязательного HTTPS.

## Запуск control plane

1. Скопировать `server-node/config/commerce.example.env` в защищённое хранилище
   окружения и задать независимые `ADMIN_TOKEN` и `MASTER_KEY`.
2. Поставить reverse proxy с TLS перед `127.0.0.1:8790`.
3. Для YooKassa направить уведомления на
   `https://<host>/v1/webhooks/yookassa`.
4. Для Crypto Pay направить webhook на
   `https://<host>/v1/webhooks/crypto-pay`.
5. В production выставить `WESI_AERO_ALLOW_MOCK_PAYMENTS=false`.

YooKassa notification не считается доказательством оплаты: сервер повторно
запрашивает payment status у провайдера и сверяет сумму/валюту. Crypto Pay
webhook проверяется по HMAC точного raw body, свежести `request_date`, payload и
deduplication `update_id`.

## Подключение приложений

Клиентская production-сборка получает URL на этапе сборки:

```bash
flutter build apk --release \
  --dart-define=WESI_AERO_CONTROL_URL=https://gateway.example.com
```

Без `WESI_AERO_CONTROL_URL` клиент запускает безопасную локальную симуляцию и не
делает списаний. Admin-приложение принимает URL и admin token в настройках во
время выполнения; token сохраняется в системном secure storage.

## Контракт оплаты

1. Клиент получает каталог и серверную quote.
2. `POST /v1/orders` создаёт pending order с idempotency key.
3. Провайдер возвращает checkout URL; клиент открывает его во внешнем приложении.
4. Только проверенный webhook/reconciliation переводит заказ в `paid` и создаёт
   лицензию.
5. Клиент опрашивает заказ с claim token, получает ключ и сразу вызывает redeem.
6. Повторный poll возвращает тот же зашифрованный в базе ключ, поэтому потеря
   первого ответа не теряет покупку.

## Проверки

Node test suite проверяет:

- формулу цены и допустимые варианты тарифа;
- лимит устройств, истечение срока и отзыв ключа;
- конфиденциальное хранение ключа;
- idempotent fulfillment и защищённый claim заказа;
- HMAC/timestamp/deduplication Crypto Pay;
- повторную проверку статуса и суммы YooKassa;
- Admin → revision → client catalog;
- AES-GCM round trip, tamper detection и replay detection.

## Граница готовности

Stage 2 полностью реализует control plane, биллинг-контракт, ключи и интерфейсы.
Он не превращает Stage 1 demo engine в production VPN: Android `VpnService`,
Windows Wintun/WFP, Xray/REALITY и AmneziaWG data plane всё ещё требуют M1–M3 из
`PRODUCTION_ROADMAP.md`. До их интеграции кнопка соединения визуально работает в
demo mode, но не должна рекламироваться как реальный системный туннель.
