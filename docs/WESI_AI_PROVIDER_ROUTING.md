# Wesi AI — provider routing

Wesi AI использует строгую монотонную иерархию текстовых tiers:

- **Fast** → `gemini-3.5-flash-lite` и только Fast-кандидаты;
- **Pro** → `gemini-3.5-flash` как Gemini finalizer и только Pro-кандидаты;
- **Maximum** (в Relay: `ultra`) → `gemini-3.6-flash` как Gemini finalizer и только Maximum-кандидаты.

Runtime assertion fail-closed запрещает Fast использовать Pro/Maximum candidate и Pro использовать Maximum candidate. Credential slot не определяет качество модели: переключение API credentials не может повысить tier.

## Gemini quota scope

Gemini rate limits учитываются на уровне Google project. Для корректной группировки credentials Relay поддерживает необязательные labels:

- `GEMINI_API_PROJECT`;
- `GEMINI_API_PROJECT_2` … `GEMINI_API_PROJECT_5`.

Если несколько Gemini keys явно помечены одним project label, их health/cooldown объединяется по `provider + model + project quota scope`. Поэтому после quota/rate-limit ответа Router не делает бессмысленный повтор другим ключом того же project для той же модели. Отдельный настроенный Google project или другой provider остаётся отдельным capacity candidate.

Без project labels Relay не пытается угадывать происхождение API key и считает slots независимыми.

## Failover

- кратковременный `429` → exponential cooldown с учётом provider `Retry-After`/retry hint;
- распознанная daily quota → отдельный более длинный cooldown;
- `5xx`, timeout, unavailable → transient cooldown;
- auth failure → длинный cooldown;
- invalid `400` не fan-out'ится по providers;
- после первого выданного streaming byte смена provider запрещена, чтобы не склеивать ответы разных моделей;
- user cancellation останавливает весь pool.

Несколько credentials/projects предназначены для легитимной независимой capacity и отказоустойчивости, а не для обхода ограничений конкретного provider.

## Validation

Регрессионный набор проверяет, что Fast не может получить Pro/Maximum candidate, Pro не может получить Maximum candidate, default Maximum сильнее default Pro, одинаковый Google project разделяет cooldown между своими credentials, а другой явно настроенный project остаётся доступным для failover. Targeted provider suite: 12/12 PASS.
