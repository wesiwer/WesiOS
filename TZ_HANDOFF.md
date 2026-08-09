# WesiOS — ТЗ / передача текущей работы

**Дата передачи:** 2026-08-10  
**Рабочая ветка:** `agent/horizon-top-tier`  
**Текущий verification PR:** #69 — `verify: clean Horizon final gate`  
**Последний подтверждённый head:** `bef2dcb40bcc267c7f2e64999779773c9d8a6ed4`  
**Последний проверяемый workflow:** `31335488274`  
**Проблемный job:** `93300530710`

Этот файл является дополнением к основному `TZ.md` и предназначен для передачи работы следующему исполнителю. Основные продуктовые требования WesiOS и полный набор требований Wesi Horizon Top-Tier A→G остаются в `TZ.md` этой ветки.

---

## 1. Что уже сделано

### Базовый WesiOS до Horizon

В основном `TZ.md` уже зафиксированы реализованные требования версии `0.19.18+66`: мобильный UX, точный баланс, Calendar ready, корректные системные отступы, единый выбор сотрудников, Android launcher icon по теме, точная дата/время Treasury, группировка операций, секундомер по абсолютному времени, масштаб Roadmap, исправление короткого Forecast и recurring What-If. Для этого прохода ранее были подтверждены analyze/tests/Android production release, как записано в основном ТЗ.

### Wesi Horizon Top-Tier A→G

В ветке `agent/horizon-top-tier` реализован большой проход Wesi Horizon Top-Tier, разбитый в основном `TZ.md` на Sprint A→G. Требования включают:

- anti-millionaire baseline, mean reversion, затухание recent pace и horizon-aware поведение;
- честное расширение P10–P90, low-data режим и block residual bootstrap;
- калибровку coverage, cash-gap probability и systematic bias;
- rolling backtest 14/30/90/180 и multi-seed проверку стохастического движка;
- разделение committed/known cash и uncertain cash;
- reliability recurring, shock pools и frequency × size модель нерегулярных потоков;
- семантические денежные группы;
- regimes `stable/growth/downturn`, обучаемые переходы и stress library;
- Decision Layer: runway, risk thresholds, recommended reserve, free safety buffer и action prompts;
- What-If delta относительно Base;
- `HorizonPredictionRegistry` для live predictions и последующего сравнения с фактами;
- конкуренцию Horizon / Prophet / SARIMAX / Combined на одинаковых origins и target dates;
- quantile-first objective и выбор чемпиона отдельно для 14/30/90/180;
- интеграцию Treasury + recurring + CRM + Tasks cash obligations + Audio Vault expectations + account liquidity;
- contract assumptions и realized outcomes Audio Vault;
- early-warning structural shifts, recurring misses и concentration risk;
- currency/liquidity/netting/FX haircut/transfer delay;
- additive attribution изменения P50;
- truth-first UI с confidence, known/unknown share и calibration evidence.

### Что сделано по проверке

- Требования A→G и validation gate записаны в основном `TZ.md` ветки.
- Введён отдельный clean final gate: проверка должна идти на точном финальном head, без self-modifying CI.
- Создан read-only verification PR #69. Его нельзя мержить как продуктовый PR.
- Последний проход проверки дошёл до commit `bef2dcb40bcc267c7f2e64999779773c9d8a6ed4`.
- Запущен workflow `31335488274`.
- Финальный gate ещё **не подтверждён зелёным**; известная точка продолжения — job `93300530710`.
- Описание PR #69 также обновлено кратким handoff, чтобы состояние не потерялось даже без чтения этого файла.

---

## 2. Что нужно сделать дальше — обязательно

1. Получить **полный лог** job `93300530710` из workflow run `31335488274`.
2. Найти первую реальную первопричину падения. Не считать вторичные ошибки корнем проблемы.
3. Не ослаблять тесты, assertions, validation gate или требования Horizon ради зелёного CI.
4. Если причина в коде, тестах или CI проекта — исправить её в `agent/horizon-top-tier`.
5. Запушить исправление и получить новый точный head SHA.
6. Повторно запустить clean final gate именно на новом head.
7. Повторять цикл «лог → первопричина → исправление → clean gate», пока весь обязательный набор не станет зелёным.

Обязательный зелёный набор перед любым обсуждением merge:

- `flutter analyze --no-fatal-infos`;
- полный `flutter test`;
- legacy Treasury tests;
- `horizon_top_tier_test.dart`;
- `horizon_product_integration_test.dart`;
- `horizon_completion_test.dart`;
- Android verification build;
- Windows release verification build.

После полного success обязательно записать в `TZ.md` и при необходимости `STATUS.md`:

- финальный commit SHA;
- ID успешного verification workflow;
- количество прошедших тестов;
- результаты Android и Windows builds;
- любые исправленные регрессии, обнаруженные финальным gate.

---

## 3. Что нельзя делать автоматически

- Не мержить `agent/horizon-top-tier` в `main` без отдельного явного решения владельца.
- Не запускать production release без отдельного явного запроса владельца.
- Не использовать PR #69 как продуктовый merge PR: это read-only verification gate.
- Не коммитить secrets, токены, пароли, keystore и приватные ключи.
- Не ломать обратную совместимость Hive/JSON без явной миграции.
- Не подменять реальный список сотрудников demo-данными.
- Не позволять What-If изменять реальные Treasury-операции.
- Не объявлять Horizon «100% точным» и не обещать точный баланс на длинном горизонте.

---

## 4. Empirical truth gate — нельзя закрыть одним CI

Кодовая реализация модели и фактическая доказанная точность — разные вещи.

Даже после полностью зелёного CI нельзя утверждать, что 80%-интервал уже реально имеет ровно 80% coverage или что заявленные вероятности cash-gap идеально откалиброваны, пока не накоплено достаточно **реально выданных и созревших** прогнозов на 14/30/90/180 дней.

`HorizonPredictionRegistry` должен сохранять live predictions, а после наступления target date сравнивать их с фактическим балансом. До накопления достаточной выборки UI обязан показывать честный confidence и доступный calibration evidence. Это не баг и не незавершённый код, а физическое ограничение отсутствия будущих фактов.

---

## 5. Точная точка продолжения для следующего ИИ

Начать не с нового аудита всего проекта, а с текущей незавершённой проверки:

**ветка:** `agent/horizon-top-tier`  
**head:** `bef2dcb40bcc267c7f2e64999779773c9d8a6ed4`  
**PR:** #69  
**workflow:** `31335488274`  
**job для разбора:** `93300530710`

Первое действие: открыть полный лог job `93300530710`, зафиксировать конкретное сообщение/step, на котором возникло первое падение, и продолжить исправления до полного green gate.

Если после передачи head уже изменился, сначала сравнить новый head с указанным SHA и не потерять изменения, внесённые после этой записи.
