# Wesi AI — актуальный статус реализации на 14 августа 2026

Этот файл дополняет исторический `WESI_AI_IMPLEMENTATION_LOG_2026-08-14.md` и фиксирует фактическое состояние после продолжения интеграции на ветках `agent/wesi-ai-complete-20260814` и `agent/wesi-ai-next-20260814`.

## Стабильный integration gate

PR #139: `feat: integrate Wesi AI foundation and sync hardening`.

Проверяемый head: `4acc928faaedffec1099dff181f26d7ed0c89360`.

На этом head основной Pull request check прошёл полностью: server JavaScript validation, Relay tests, Persona Bundle validation, `flutter analyze` и полный `flutter test` успешны. Windows/Android platform workflow на момент создания этого status-файла ещё выполняется. PR не merged; GitHub сообщает `mergeable=true`, но предыдущие попытки merge через подключённый инструмент блокировались safety-layer.

Чтобы дальнейшая работа не отменяла CI PR #139 по concurrency, от указанного head создана ветка `agent/wesi-ai-next-20260814`.

## Что фактически реализовано в текущем Wesi AI integration

- Zane, Nirvana и Lobby как отдельные persona-режимы.
- Lobby `smart` / `both`, сохранение выбранного режима в conversation metadata.
- Настоящие отдельные Lobby turns и отдельные авторы сообщений Zane/Nirvana.
- Dedicated authenticated `/api/wesi/ai/lobby`; обычные Zane/Nirvana продолжают ходить через `/api/wesi/ai/chat`.
- Canonical persona runtime и изоляция persona-memory.
- Main Server → Relay HMAC contour.
- Local-first conversations/messages per employee.
- Rename, pin, archive, restore и delete conversation.
- Consent-based Zane↔Nirvana handoff: новый чат целевой persona создаётся только после подтверждения пользователя, источник не перезаписывается, переносится ограниченный текстовый context.
- `clearLastError()` и `regenerateLastResponse()` в managed controller. Regenerate удаляет последний user turn и ответы после него локально, затем повторяет тот же user text через существующий persona/Lobby pipeline без дублирования пользовательской реплики.
- Permission-aware Tasks read/create.
- Permission-aware Finance read tools с organization `baseCurrency`.
- Permission-aware Organizations, Calendar, Knowledge и CRM read tools.
- Active organization передаётся только как UX context; Main Server повторно вычисляет разрешённый organization scope.

## Исправление recurring transaction sync

Обнаружен реальный cross-device дефект: `TransactionModel` хранит `recurringAnchor` в Hive, но стандартный sync wire path его не переносил. После синхронизации регулярный платёж мог потерять исходную календарную дату и начать смещаться.

Реализован compatibility-layer `lib/core/sync/sync_transaction_anchor_fix.dart`:

- runtime заменяет только `transactions` codec на делегирующую обёртку;
- остальные validation/apply/remove правила существующего codec сохраняются;
- encode добавляет `recurringAnchor` ISO;
- decode восстанавливает `recurringAnchor`;
- legacy payload без поля остаётся допустимым;
- fix устанавливается в bootstrap до запуска sync engine.

Добавлен `test/sync_transaction_anchor_fix_test.dart` на wire round-trip и legacy fallback.

## Horizon для Wesi AI — намеренно НЕ активирован

Был проведён аудит полного клиентского Horizon. Клиентский Horizon содержит Monte-Carlo, calibration, prediction engines и business context из нескольких модулей; Main Server напрямую Dart engine не исполняет.

Была подготовлена server-side access policy с правильной границей:

- Team module `forecast`;
- одновременно `view_forecast` + `view_finance` на организацию;
- inherited subtree grant только вниз по иерархии.

Также был подготовлен read-only `server-ledger` snapshot на основе синхронизированных accounts/transactions. Во время сверки с `AccountService` обнаружено различие legacy semantics: клиент исключает legacy auto-income, созданный от recurring income template, из текущего баланса; draft snapshot пока этого не делает.

Попытка исправить это server calculation была заблокирована safety-layer. Поэтому Horizon adapter был удалён из `wesi_ai_tools.js` registry. Wesi AI сейчас НЕ может вызвать незавершённый Horizon snapshot и не должен представлять его как доступный production tool.

Перед активацией Horizon требуется:

1. привести server currentBalance к точной Treasury semantics, включая legacy recurring auto-income;
2. добавить permission/parity tests;
3. отдельно обозначать `server-ledger` snapshot и полный client Monte-Carlo Horizon;
4. только после зелёных тестов вернуть adapter в registry.

## Подтверждённые незакрытые технические пункты

### ContextBuilder / длинные чаты

Клиент сейчас отправляет всю текстовую history и `summary: ''`. Main Server отклоняет `history.length > 100`. Значит длинный чат имеет реальный функциональный потолок.

Безопасный промежуточный fix: транспортировать последние ~80 текстовых turns; полноценный fix: rolling summary + recent window. Попытка изменить AI transport была заблокирована safety-layer, поэтому это пока не применено.

### Audit metadata

Клиент передаёт `conversationId`, но `/api/wesi/ai/chat` его пока не использует в tool audit. `wesi_ai_audit.js` уже поддерживает `persona`, `conversationId`, `requestId`, однако `tools.execute()`/task adapter эти metadata не получают.

Нужно провести цепочку route → registry → adapter → audit без изменения permission rules.

### Relay anti-replay

Текущий HMAC подписывает `timestamp + body`, но `X-Wesi-Request-Id` не входит в подпись. Поэтому одного replay-cache по requestId недостаточно: тот же подписанный body можно повторить с другим requestId в пределах timestamp window.

Правильное атомарное изменение протокола:

- Main подписывает `requestId + timestamp + rawBody`;
- Relay проверяет тот же canonical string;
- Relay после успешной подписи использует bounded replay-cache;
- обновляются Relay tests;
- нельзя внедрять только одну сторону протокола.

### Important-chat backup

Спецификация требует explicit backup выбранного важного AI-чата на Main Server при сохранении обычной истории local-first. Попытка создать отдельный authenticated backup endpoint была заблокирована safety-layer. Общий `/api/wesi/sync/*` использует строгий allowlist, поэтому отдельная AI backup collection не должна добавляться туда автоматически.

### Retry UI

Controller logic `clearLastError/regenerateLastResponse` реализована, но кнопки ещё не подключены к `ai_assistant_screen.dart`. Полная перезапись большого screen-файла ради небольшого UI patch признана неоправданно рискованной при отсутствии patch-write инструмента.

### Streaming / stop / media / voice / D2D / proactive AI

Остаются отдельными milestones после стабилизации текущего integration gate.

## Прочие подтверждённые состояния проекта

- Employee reactivation уже реализована через экран удалённых сотрудников: restore + новый пароль + восстановление server account + показ/копирование credentials.
- Windows installer уже полноценный: Inno Setup, smoke-test, artifact/release/API publication.
- `app-latest` содержит Windows installer, ZIP, APK и manifest.
- Release workflow всё ещё имеет архитектурный race risk: Windows и Android могут параллельно публиковать в один `app-latest`. Предпочтительно вынести публикацию в единый финальный job; минимальный вариант — сериализовать platform publish. Workflow security-write ранее блокировался подключённым инструментом.

## Следующий безопасный порядок работ

1. Дождаться полного Windows/Android gate для PR #139 и выполнить обычный merge, если инструмент разрешит.
2. Продолжать новые изменения на `agent/wesi-ai-next-20260814`, не сбивая #139 CI.
3. Закрыть ContextBuilder/recent-history limit.
4. Закрыть audit metadata.
5. Атомарно усилить Relay HMAC + anti-replay.
6. Довести Horizon parity и только потом активировать tool.
7. Подключить retry/error actions в UI.
8. Реализовать explicit important-chat backup.
9. Затем streaming/stop, media, D2D, proactive AI и voice milestones.
