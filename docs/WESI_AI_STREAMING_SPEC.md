# Wesi AI — True Network Streaming Spec

Статус: normative
Дата: 2026-08-15
Этап плана: 2/16

## 1. Цель

Обычный прямой чат Wesi AI с Зейном или Нирваной должен показывать ответ по мере фактического получения текста от провайдера. Локальная анимация уже полностью полученного ответа не считается streaming.

Канонический путь:

`WesiOS -> Main Stream Gateway -> PocketBase policy/persona/tools -> Foreign Relay -> provider SSE -> Relay NDJSON -> Main Gateway NDJSON -> WesiOS`.

Main Server остаётся policy brain. Relay не получает пользовательский bearer/session и не принимает решений о правах WesiOS.

## 2. Транспорт

- публичный клиентский endpoint: `POST /api/wesi/ai/chat/stream`;
- transport: `application/x-ndjson`;
- nginx для endpoint обязан использовать `proxy_buffering off` и `X-Accel-Buffering: no`;
- Relay streaming endpoint: `POST /v1/wesi-ai-stream`;
- Relay request остаётся HMAC-подписанным Main/Relay shared secret;
- Main Stream Gateway имеет отдельный `WESI_STREAM_SECRET` для доверенных внутренних вызовов PocketBase prepare/tool routes;
- streaming capability рекламируется только при реально настроенном gateway secret.

События client stream:

- `meta` — requestId/persona/tier;
- `delta` — новая часть текста;
- `tool` — безопасный статус server-side tool execution без внутренних prompt/provider details;
- `done` — канонический полный ответ + verified toolResults;
- `error` — стабильный WAI_* code.

## 3. Tool loop и безопасность

- tool definitions и runtime context формирует только Main/PocketBase после проверки пользователя и AI permission;
- модель не выполняет tool напрямую;
- raw `wesiTool` JSON не должен попадать пользователю как частичный ответ;
- gateway удерживает потенциальный tool envelope до определения, является ли он обычным текстом или структурированным вызовом;
- разрешённый tool исполняется через защищённый Main route;
- результат возвращается модели только как `verified` result;
- повторный одинаковый вызов в одном turn блокируется;
- число tool turns ограничено;
- после лимита выполняется final-only synthesis без новых tool calls.

## 4. Stop / Steer

Streaming обязан быть связан с Smart Queue этапа 1:

- CONTROL/Stop закрывает клиентскую подписку и запрещает сохранение позднего результата;
- STEER может прервать текущий stream и запустить корректирующий turn раньше deferred queue;
- transient partial assistant message не сохраняется как финальная история;
- после отмены partial удаляется;
- после успешного `done` partial заменяется одним финальным assistant message и только он persist-ится.

## 5. Flutter UI

- один live assistant message обновляется по `delta`;
- каждый delta не создаёт отдельное сообщение и не вызывает запись Hive;
- typewriter-анимация отключается для live transport stream, иначе каждый delta визуально перезапускал бы локальную анимацию;
- после `done` используется полный канонический answer, requestId и content blocks;
- старый JSON `/api/wesi/ai/chat` сохраняется как rollout/rollback fallback, пока streaming не активирован в production.

## 6. Lobby

На этом этапе true network streaming обязателен для прямых чатов `zane` и `nirvana`.

Lobby сохраняет существующий canonical multi-author JSON flow. Это сознательное ограничение этапа 2, а не псевдо-streaming Lobby. Расширение Lobby на multi-speaker stream выполняется отдельно, когда будет определён устойчивый multi-author event contract.

## 7. Provider routing

- Google Gemini использует provider streaming endpoint;
- OpenAI-compatible free providers используют `stream: true` и SSE parsing;
- Fast/Pro сохраняют существующий routing/fallback policy;
- Ultra не должен выдавать пользователю промежуточные внутренние черновики ensemble как финальный stream; streaming Ultra обязан сохранять текущую политику синтеза.

## 8. Deployment

Production deployment streaming — только по отдельному ручному `workflow_dispatch`. Merge этапа не должен автоматически изменять production.

Permanent workflow: `.github/workflows/deploy-wesi-ai-streaming.yml`.

Он обязан до установки проверить:

- JS syntax Relay/Main gateway;
- Relay unit tests;
- Main gateway unit tests;
- shell syntax;
- наличие обязательных SSH/provider secrets.

## 9. Regression gates

Минимум перед merge:

- Relay streaming tests green;
- Main stream gateway tests green;
- Flutter `analyze` green;
- Smart Queue + streaming regression tests green;
- полный Flutter test suite green;
- Android debug build green;
- Windows release build green.

## 10. Не считается выполнением этого ТЗ

- посимвольная анимация после получения полного JSON answer;
- Client -> Foreign Relay напрямую;
- streaming без отмены при Stop;
- сохранение каждого delta в Hive;
- показ raw tool envelope пользователю;
- автоматический production deploy при merge.
