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
