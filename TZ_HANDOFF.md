# WesiOS — текущий handoff

## Wesi AI Observable Rich Chat UX — 2026-08-16

**Базовый main перед проходом:** `0f817169913281d5efa4f5ac9b328f8af753e0dd`  
**Рабочая ветка:** `agent/wesi-ai-chat-ux-parity-secure`  
**Validated product commit:** `c3ba4699655093fcbd332118cc530e63283a33f1`  
**Последний полный one-shot gate:** workflow `31911490007` — success; временный workflow и патчеры после проверки удалены.

### Что является source of truth по chat UX

Подробный контракт: `docs/WESI_AI_CHAT_UX.md`.

Реализовано:

- обычный ответ больше не выводится одним сырым `Text`: fenced code имеет отдельную карточку, язык, быстрый copy и полноэкранный просмотр;
- `> quote` и fenced `text/message/email/draft/letter` отображаются как переносимые текстовые блоки с вертикальной линией и copy;
- inline `**bold**`, `*italic*`, `` `code` `` рендерятся и не показывают служебные markdown-маркеры;
- вместо выдуманного reasoning summary используется раскрываемый **наблюдаемый ход работы**: реальные `meta/activity/tool/agent` события streaming protocol; скрытая chain-of-thought не выводится;
- work log виден ещё до первого токена финального ответа, во время работы раскрыт автоматически и сохраняется в `WesiAiMessage.metadata.activity` вместе с финальным сообщением;
- tool/agent events привязаны к `textOffset`, поэтому renderer может показывать их в месте хода ответа, а не сваливать всё в отдельный хвост;
- у каждого tool/agent event есть отдельные `additions/deletions/files`; общий badge открывает diff-review;
- для `github_file_upsert` `+/-` берутся из GitHub commit detail после уже успешной записи; enrichment не повторяет WRITE и не может создать дубликат side effect;
- под завершённым ответом есть copy, bookmark в архив **только текущего чата**, branch conversation от выбранного сообщения и diff review;
- ветка чата сохраняет `branchedFromConversationId` и `branchedFromMessageId`, копирует историю только до выбранного сообщения и переживает reload;
- камера Wesi AI открывается компактным modal dialog вместо fullscreen, при этом внутренний `CameraPreview` сохраняет аппаратный aspect ratio;
- server streaming gateway теперь отдаёт lead-agent start/result и фактические activity/tool lifecycle events; неизвестные diff-числа не выдумываются и остаются нулевыми.

### Проверки

На validated product slice прошли:

- `node --check` streaming gateway и GitHub connector;
- весь `server/wesi-ai-stream/*.test.mjs`;
- observability/security guards;
- `flutter analyze --no-fatal-infos`;
- новые rich-chat widget/parser tests;
- durable Hive tests для chat-local archive и conversation branch;
- расширенный streaming regression: tool activity видна до финала, затем остаётся в финальном сообщении и persisted store;
- существующие confirmation/memory/queue regressions;
- полный `flutter test` всего WesiOS.

### Не откатывать

- Не возвращать `safeReasoningSummary` как искусственную «мысль модели».
- Не показывать скрытую chain-of-thought как будто это реальная телеметрия. Пользовательский блок — только наблюдаемые этапы/действия.
- Не считать `+/-` токенами или временем. В WesiOS это исключительно реальные добавленные/удалённые строки, когда backend может их подтвердить.
- Не возвращать отдельный конкурирующий renderer для code/quotes/activity: единый слой — `WesiAiRichMessage`.

---

# WesiOS — Horizon Top-Tier A→G final handoff

**Дата:** 2026-08-10  
**Рабочая ветка:** `agent/horizon-top-tier`  
**Подтверждённый code SHA:** `4f07cd05e3d9461870874595230cf74a0aa358d0`  
**Успешный workflow:** `31342362575` — `Horizon final verification`, run #6  
**Jobs:** analysis/tests `93318127054`; Windows `93318127077`; Android `93318127096` — все `success`.  

Старые красные run/job, PR #69 и `bef2dcb...` являются только историей и больше не являются текущей точкой продолжения.

## Финальный green gate

На точном product SHA `4f07cd05e3d9461870874595230cf74a0aa358d0` подтверждено:

- exact-SHA guard — success во всех трёх jobs;
- `flutter analyze --no-fatal-infos` — success;
- полный `flutter test` — **887/887 passed**;
- legacy Treasury regression tests — success;
- `horizon_top_tier_test.dart` — success;
- `horizon_product_integration_test.dart` — success;
- `horizon_completion_test.dart` — success;
- Android verification build (`flutter build apk --debug`) — success;
- Windows release verification (`flutter build windows --release`) — success.

## Что исправлено финальным gate

1. Windows verification переведён с плавающего `windows-latest` на `windows-2022`, где Flutter 3.24 получает совместимый Visual Studio toolchain. Ошибка генератора Visual Studio устранена.
2. Recurring reliability больше не придумывает пропущенные платежи до момента существования расписания.
3. Fallback daily volatility рассчитывается по реальным non-recurring cash observations.
4. Account balance и backtest truth исключают recurring schedule-parent и legacy auto-generated recurring-income expectation rows из фактических денег.
5. Recurring payment automation при injected Treasury service не запускает посторонний global Hive maintenance; production shared automation сохранён.
6. Recurring income не становится committed cash только из-за высокой вероятности расписания: требуется совпадающее реальное поступление. Auto-generated income rows не считаются доказательством получения денег.

## Merge / release

Ветка технически прошла обязательный кодовый gate и готова к решению владельца о merge. **Не мержить `agent/horizon-top-tier` в `main` автоматически и не запускать production release без отдельного явного разрешения владельца.**

Verification PR используются только как CI harness и не являются продуктовыми PR для merge.

## Empirical truth gate

Зелёный CI подтверждает реализацию и контрактные проверки, но не доказывает будущую фактическую точность модели или точное real-world coverage интервалов. `HorizonPredictionRegistry` должен продолжать сохранять реально выданные прогнозы. Утверждения о coverage, calibration, bias и cash-gap accuracy на горизонтах 14/30/90/180 дней допустимы только после накопления достаточного количества созревших live outcomes.

## Точка продолжения

Horizon заново не начинать и архитектурный проход A→G не повторять. Следующее продуктовое действие после exact-SHA проверки текущего documentation head — решение владельца о merge.