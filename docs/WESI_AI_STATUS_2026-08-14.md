# Wesi AI — актуальный статус реализации на 14 августа 2026

Этот файл дополняет исторический `WESI_AI_IMPLEMENTATION_LOG_2026-08-14.md` и фиксирует фактическое состояние после продолжения интеграции на ветках `agent/wesi-ai-complete-20260814` и `agent/wesi-ai-next-20260814`.

## Стабильный integration gate

PR #139: `feat: integrate Wesi AI foundation and sync hardening`.

Проверенный head: `4acc928faaedffec1099dff181f26d7ed0c89360`.

На этом head оба обязательных workflow прошли полностью успешно:

- Pull request check: server JavaScript validation, Relay tests, Persona Bundle validation, `flutter analyze` и полный `flutter test`;
- Verify CRM Roadmap Console builds: Android debug APK и Windows release build.

PR не merged: повторная попытка merge с exact expected head SHA была заблокирована safety-layer подключённого GitHub-инструмента. Это не ошибка GitHub CI и не конфликт PR.

Чтобы дальнейшая работа не отменяла проверенный gate PR #139, от указанного head создана ветка `agent/wesi-ai-next-20260814`.

На ней открыт PR #140. Изначально он был stacked на `agent/wesi-ai-complete-20260814`, поэтому PR-triggered workflows для него не стартовали. Попытка ретаргетировать #140 напрямую на `main` также была заблокирована safety-layer GitHub-инструмента.

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

Основной `/api/wesi/ai/chat` transport исправлен на ветке `agent/wesi-ai-next-20260814`, commit `cde28cb8a47af0923e48f63f8c6eb30b38c7593e`:

- локальная история не обрезается;
- в transport попадают только текстовые несистемные сообщения;
- на сервер отправляются последние 80 сообщений, оставляя запас относительно серверного лимита 100.

Lobby пока остаётся со старым поведением и отправляет всю history. Попытка внести такой же cap в `wesi_ai_lobby_api.dart` была заблокирована safety-layer. Полноценный дальнейший этап всё ещё: rolling summary + recent window.

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

Controller logic `clearLastError/regenerateLastResponse` реализована, но кнопки ещё не подключены к `ai_assistant_screen.dart`. Попытка записать UI patch была заблокирована safety-layer GitHub-инструмента.

### Streaming / stop / media / voice / D2D / proactive AI

Остаются отдельными milestones после стабилизации текущего integration gate.

## Прочие подтверждённые состояния проекта

- Employee reactivation уже реализована через экран удалённых сотрудников: restore + новый пароль + восстановление server account + показ/копирование credentials.
- Windows installer уже полноценный: Inno Setup, smoke-test, artifact/release/API publication.
- `app-latest` содержит Windows installer, ZIP, APK и manifest.
- Release workflow всё ещё имеет архитектурный race risk: Windows и Android параллельно выполняют `gh release view/create/upload --clobber` в один `app-latest`. Предпочтительно вынести публикацию в единый финальный job; минимальный вариант — сериализовать platform publish. Текущий GitHub-инструмент не имеет patch-write и требует полной замены большого workflow-файла.
- Текущая release version согласована: `pubspec.yaml` = `0.22.7+82`, `AppVersion` = `0.22.7 / 82`.
- Android Gradle release запрещает сборку без постоянного release keystore и запрещает несовпадение `pubspec/local.properties` с `AppVersion`.

### Updater: точность пропуска версии

Обнаружен отдельный подтверждённый дефект в `AppUpdateService`:

- новизна релиза корректно сравнивается по `version + build`;
- однако `skip()` сохраняет только `version`;
- `updateAvailable` сравнивает `skippedVersion != r.version`.

Следствие: пропуск `0.22.7+81` может скрыть и более новую `0.22.7+82`.

Подготовлено безопасное решение: UI-маркер пропуска должен хранить точный ключ `${version}+${build}` и баннер должен определять доступность через `AppRelease.isNewerThan(currentVersion, currentBuild)` плюс exact skipped key. Попытка применить правку в `app_update_card.dart` была заблокирована safety-layer GitHub-инструмента, поэтому дефект пока НЕ исправлен в коде.

## Следующий безопасный порядок работ

1. Слить проверенный PR #139, как только GitHub write-operation перестанет блокироваться safety-layer.
2. Добиться CI для #140 или ретаргетировать его на `main`.
3. Довести Lobby history cap / полноценный ContextBuilder.
4. Исправить exact `version+build` skip в updater.
5. Закрыть audit metadata.
6. Атомарно усилить Relay HMAC + anti-replay.
7. Довести Horizon parity и только потом активировать tool.
8. Подключить retry/error actions в UI.
9. Реализовать explicit important-chat backup.
10. Затем streaming/stop, media, D2D, proactive AI и voice milestones.