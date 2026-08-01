# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-08-01 (сессия 7 — home white-on-white + calculator, Grok)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** `main` · **UI:** v0.11.7 α · **build:** 23  
**Тесты:** `flutter analyze` / `flutter test` — проверять после каждой правки.  

Читай этот файл **перед** любыми правками. Не помечай задачу ✅, пока пользователь не подтвердил на билде.

---

## Правило: журнал (STATUS.md) вести всегда

**Запрос владельца (2026-08-01):** после **каждого** изменения агент **обязан** обновить этот STATUS.md, чтобы в нём всегда была актуальная информация:

- что сделано в текущей сессии;
- какие файлы затронуты;
- известные ограничения / TODO;
- новые правила от владельца.

Не откладывать «на потом». Журнал — единый источник правды для следующих агентов и для владельца.

---

## Правило: релизы и билды — только по запросу пользователя

**Запрос владельца (2026-08-01):** с этого момента:

1. **Не запускать** workflow `release-app.yml` / `build.yml` / любые CI-сборки **самостоятельно**.
2. Билды (особенно релизные, пригодные для OTA-обновления) — **только по явному запросу** пользователя.
3. Все мелкие фиксы, UI-правки, багфиксы **сначала накапливаем** в `main` коммитами.
4. Когда пользователь попросит релиз — тогда:
   - прогнать чеклист (analyze + test + ревью);
   - при необходимости бампнуть версию (см. правило версий);
   - запустить `release-app.yml` с осмысленными `notes`.

**Причина:** экономия лимита GitHub Actions (минуты компиляции).

---

## Правило: перед запуском билда / релиза

**Запрос владельца (2026-07-31):** перед любым билдом (push-триггер не в счёт; `workflow_dispatch` `build.yml` / `release-app.yml`) агент **обязан** сначала всё проверить.
Запускать сборку только если уверен, что она пройдёт. **И только если пользователь явно попросил билд.**

### Чеклист перед билдом (обязателен)

1. **Статический анализ** — `flutter analyze` → **0** замечаний.
2. **Юнит-тесты** — `flutter test` → все тесты зелёные.
3. **Ревью затронутых файлов** — особенно:
   - `android/app/build.gradle` (подпись: `ks*` vars, не `keyAlias`/`keyPassword` — иначе Groovy shadowing);
   - `.github/workflows/*.yml` (секреты, env, шаги decode keystore);
   - любые правки в `lib/` — не ломают Hive typeId, open boxes, known bugs из STATUS.
4. **Если Flutter недоступен в среде агента** — минимум:
   - прочитать diff и убедиться, что нет известных ловушек (shadowing, debug signing, overwrite google-services.json);
   - **не** запускать `release-app.yml`, пока analyze/test не подтверждены и пользователь не попросил.
5. **Только после зелёного чеклиста и явного запроса пользователя** — `workflow_dispatch` на `release-app.yml` (с осмысленными `notes`).

Не «запустить и посмотреть». Сначала проверка — потом билд. Билд — только по запросу.

---

## Правило: версия приложения — единый источник правды

**Запрос владельца (2026-07-31):** при любом бампе версии (major / minor / patch /
hotfix / alpha → beta и т.д.) агент **обязан** обновить **все** следующие файлы
**одновременно**, в одном коммите или в явной цепочке коммитов без пропусков.

### Список файлов, где обязана быть актуальная версия

| # | Файл | Пример строки |
|---|------|---------------|
| 1 | `lib/core/constants/app_version.dart` | `static const String number = '0.11.7';` |
| 2 | `lib/core/constants/app_version.dart` | `static const int build = 23;` |
| 3 | `pubspec.yaml` | `version: 0.11.7+23` |
| 4 | `README.md` | строка с версией (если есть) |
| 5 | `STATUS.md` | строка `**UI:** v0.11.7 α` в шапке |

### Алгоритм бампа версии

1. Прочитать текущую версию из `lib/core/constants/app_version.dart`.
2. Определить новую версию (согласно логике: patch — багфикс, minor — фича,
   major — ломающие изменения; α → β → RC → stable).
3. Увеличить `build` на +1 (даже если `number` не меняется — новая сборка).
4. Записать новые значения **во все 5 файлов**.
5. Коммит с сообщением: `chore(release): bump version to X.Y.Z+B`.
6. Только после этого (и по запросу пользователя) — запускать `release-app.yml`.

### Последствия нарушения

Если `app_version.dart` и `pubspec.yaml` расходятся — OTA-обновление ломается:
приложение видит `0.10.1` в коде, а в релизе `0.11.0`, и считает, что релиз
**старше** установленной версии → отказывается обновляться.

---

## Сессия 7 (2026-08-01) — Windows UI + акценты светлой темы + калькулятор + home

Сессия велась агентом **Grok** (xAI) по прямому запросу владельца.  
**Не откатывать и не «улучшать» без явной просьбы пользователя.**

### 1. Оранжевые акценты на светлой теме → `AppTheme.accent`

**Проблема:** на светлой теме оставались оранжевые места (чипы периодов Analytics, badge/ссылки Treasury, операторы калькулятора, линия Wesi Horizon в прогнозе).

**Решение:** везде, где UI-хром/выделение (не warning/anomaly), использовать `AppTheme.accent` (dark → orange, light → blue `lightAccentBlue`).

| Область | Файлы |
|---|---|
| Analytics period chips / header | `lib/features/analytics/analytics_screen.dart` |
| Treasury currency badge, links | `lib/features/treasury/treasury_screen.dart`, `widgets/accounts_bar.dart` |
| Forecast Wesi Horizon chart color | `lib/features/treasury/forecast_chart_screen.dart` — `_engineColorOf()` вместо static map с `accentOrange` |
| Calculator chrome / ops / pin / history / M | `lib/features/calculator/calculator_screen.dart` — **готово** (`AppTheme.accent`, `accentOps`) |

### 2. Заголовок Analytics → «Wesi Analytics»

В шапке модуля: **Wesi Analytics**. В нижней панели навигации остаётся «Аналитика».

### 3. Кнопка «Назад» в Analytics / Settings / Tasks

**Проблема:** при push-навигации не было способа выйти назад.

**Решение:** виджет `ModuleHeader` (`lib/core/widgets/module_header.dart`) — AppBar-like с `BackButton` при `Navigator.canPop`, title, actions, запас под WindowControls.

Подключено в:
- `analytics_screen.dart`
- `settings_screen.dart`
- `tasks_screen.dart`

### 4. Кнопки окна Windows (свернуть / развернуть / закрыть)

**Файл:** `lib/core/widgets/window_controls.dart`

- Hover-цвета адаптированы под light/dark.
- Minimize: корректный выход из fullscreen перед minimize.
- Maximize / restore + sync state.
- Hit-testing через GestureDetector (надёжнее, чем голый Listener).

### 5. Иконка приложения при смене темы

На Windows смена launcher-иконки ограничена ОС (не как на Android adaptive). Документировано как OS-limitation; `AppIconService` остаётся для платформ, где поддерживается.

### 6. Калькулятор — accent + minimize-to-bar ✅

**Файл:** `lib/features/calculator/calculator_screen.dart` (коммит `7d751b3e`)

| Что | Как |
|---|---|
| Акценты | Все `accentOrange` в хроме/операторах/пине/истории/M → `AppTheme.accent` (следует теме) |
| Параметр рядов | `orangeOps` → `accentOps` |
| Свернуть | кнопка `Icons.minimize` в header → `_minimized = true` |
| Плавающая полоска | `_minimizedBar()`: иконка + title + результат + expand + close; без блюра, не блокирует клики по приложению |
| Развернуть | `Icons.open_in_full` на полоске → `_minimized = false` |

### 7. Главная: «Календарь» / «Задачи» белые на белом ✅

**Проблема:** на светлой теме заголовки карточек Календарь/Задачи нечитаемы (белый на белом).

**Причина:** `HomeAgenda` / `HomePulse` не слушали `ThemeNotifier` — после смены темы оставались цвета предыдущей (тёмной) темы.

**Исправление:**

| Файл | Изменение |
|---|---|
| `lib/features/home/widgets/home_agenda.dart` | `ValueListenableBuilder` на `ThemeNotifier`; заголовки секций → `AppTheme.textSecondary` (серый) |
| `lib/features/home/widgets/home_pulse.dart` | `ValueListenableBuilder` на `ThemeNotifier`; runway color → `AppTheme.accent` вместо hardcoded orange |

### 8. Чего НЕ делать

- Не запускать release/build CI без явного запроса пользователя.
- Не возвращать hardcoded `accentOrange` в UI-хром светлой темы (warnings/anomalies — ок).
- Не убирать `ModuleHeader` / back button с push-экранов.
- Не ломать pin / history / blur / scale / minimize калькулятора.
- Виджеты с `AppTheme.*` на главной **должны** слушать `ThemeNotifier` (IndexedStack + const child иначе не перекрашиваются).

---

## Сессия 6 (2026-08-01) — научный калькулятор + фикс анимации темы

Сессия велась агентом **Grok** (xAI) по прямому запросу владельца.  
**Не откатывать и не «улучшать» без явной просьбы пользователя.**

### 1. Переключатель Classic ↔ Scientific

**Запрос:** улучшить калькулятор — выбор классического (текущий) и научного (как на присланном скрине), чтобы можно было писать обыкновенные дроби и т.д.

**Файл:** `lib/features/calculator/calculator_screen.dart`

| Что | Как |
|---|---|
| Режим | `_scientific` bool, переключатель в header (иконка `Icons.science_outlined` / `Icons.calculate_outlined`) |
| Заголовок | «Wesi Calculator» / «Wesi Scientific» |
| Размер панели | classic maxW 360 / scientific maxW 420, maxH выше |

### 2. Научная раскладка (по скриншоту)

Кнопки (сверху вниз):

1. `( ) mc m+ m- mr`
2. `2nd x² x³ xʸ eˣ 10ˣ`
3. `1/x √ ∛ ʸ√x ln log`
4. `x! sin/cos/tg e EE` (2nd → asin/acos/atan)
5. `Rand sh ch th π Rad/Deg`
6. `⌫ AC % ÷`
7–10. цифры + `× − + = ± .`

**Функции:** память, 2nd, Rad/Deg, факториал, гиперболические, %, EE, Rand, π, e; дроби через `/` и скобки.

### 3. Фикс смены темы (авто + плавная анимация)

**Проблема:** тема менялась только после тапа по иконке/смене вкладки; экран не перекрашивался плавно.

**Причины:**
1. `AnimatedTheme` стоял **снаружи** `MaterialApp` — MaterialApp вставлял свой `Theme` и мгновенно перекрывал интерполяцию.
2. `HomeScreen` не слушал `ThemeNotifier` — Scaffold/вкладки оставались со старыми `AppTheme.*` до `setState`.

**Что сделано:**

| Файл | Изменение |
|---|---|
| `lib/app.dart` | `AnimatedTheme` перенесён **внутрь** `MaterialApp.builder` (600ms, easeInOutCubic) |
| `lib/features/home/home_screen.dart` | `ValueListenableBuilder` на `ThemeNotifier`; `Scaffold.backgroundColor` из `Theme.of(context).scaffoldBackgroundColor`; bottom bar через `AnimatedContainer` |
| `lib/features/home/more_tab.dart` | `backgroundColor: Theme.of(context).scaffoldBackgroundColor` |

**Правило:** не выносить `AnimatedTheme` наружу `MaterialApp` снова. Экраны с `AppTheme.*` должны либо слушать `ThemeNotifier`, либо брать фон из `Theme.of(context)`.

### 4. Чего НЕ делать

- Не убирать переключатель режимов калькулятора.
- Не возвращать `AnimatedTheme` снаружи `MaterialApp`.
- Не ломать историю / pin / blur / scale / keyboard калькулятора.

---

## Сессия 5 (2026-08-01) — артефакты в релизном workflow

Сессия велась агентом **Grok** (xAI). См. историю: upload-artifact для APK/ZIP в release-app.yml.

---

## Сессия 3 (2026-07-31) — подпись APK, часы, шапка, changelog

Сессия велась агентом Grok. Подпись release keystore, часы, adaptive header, changelog в AppUpdateCard.

---

## Сессия 4 (2026-07-31 — 2026-08-01) — UI-правки, светлая тема, агент Kimi

Сессия велась агентом **Kimi**. Светлая тема, AppTheme getters, App Icon Mode, WelcomeScreen убран, часы под логотипом.

**Критично:** `AppTheme.xxx` — геттеры. `const TextStyle(color: AppTheme.xxx)` ломает компиляцию.

---

## Правила для AI (актуально)

1. Не удалять дублирование Sandbox/Treasury.
2. Не возвращать лого в title bar.
3. Только `MainAxisSize.min`, никогда `MainAxis.min`.
4. Overlay-тултипы → всегда `IgnorePointer`.
5. Forecast period change → не full-screen loader.
6. После **каждой** правки — обновить **этот** STATUS.md (журнал всегда актуален).
7. Не ставить ✅ без проверки на билде пользователем.
8. `flutter analyze` → 0 замечаний.
9. Нативные папки `windows/` и `android/` — неполные шаблоны.
10. **Android release** — постоянный ключ из Secrets. Не откатывать на debug.
11. **Changelog** в `AppUpdateCard` обязателен при непустых notes.
12. **Часы:** digital/analog, Hive `clock_style`.
13. **Тема:** `AppTheme` — геттеры (не const). `AnimatedTheme` только **внутри** `MaterialApp.builder`. Экраны с `AppTheme.*` слушают `ThemeNotifier` или берут фон из `Theme.of(context)`.
14. **App Icon Mode:** Auto/Dark/Light.
15. **Перед билдом/релизом** — чеклист analyze + test + ревью.
16. **Артефакты** в release-app.yml обязательны (сессия 5).
17. **Калькулятор:** Classic / Scientific + minimize-to-bar + theme accent (сессии 6–7).
18. **Релизы/билды** — только по явному запросу пользователя; мелкие фиксы накапливаем (сессия 7).
19. **Акценты UI** на светлой теме — `AppTheme.accent` (голубой), не hardcoded orange (кроме warnings).
20. **ModuleHeader** — стандарт шапки для push-экранов с back.
21. **Home карточки** (`HomeAgenda`, `HomePulse`) — всегда `ValueListenableBuilder` на `ThemeNotifier` (IndexedStack иначе не перекрашивает).

---

## Ключевые файлы

| Что | Путь |
|-----|------|
| Тема + AnimatedTheme | `lib/app.dart`, `lib/core/theme/app_theme.dart` |
| Home + theme rebuild | `lib/features/home/home_screen.dart` |
| Home agenda / pulse | `lib/features/home/widgets/home_agenda.dart`, `home_pulse.dart` |
| ModuleHeader (back) | `lib/core/widgets/module_header.dart` |
| Window controls (Win) | `lib/core/widgets/window_controls.dart` |
| Подпись Android | `android/app/build.gradle` |
| CI релиза + artifacts | `.github/workflows/release-app.yml` |
| Калькулятор | `lib/features/calculator/calculator_screen.dart` |
| Forecast charts | `lib/features/treasury/forecast_chart_screen.dart` |
| Часы | `lib/core/widgets/wesi_clock.dart` |
| Changelog обновления | `lib/core/widgets/app_update_card.dart` |

## Занятые Hive typeId

| typeId | Что |
|---|---|
| 1 | `TransactionModel` |
| 2 | `TransactionType` |
| 3 | `RecurringPeriod` |
| 10 | `TaskStatus` |
| 11 | `TaskPriority` |
| 12 | `SubTask` |
| 13 | `TaskModel` |
| 14 | `AccountKind` |
| 15 | `AccountModel` |
| 16 | `ArticleSection` |
| 17 | `ArticleModel` |

Доп. ключи в `wesios_settings`: `clock_style`, `app_theme`, `update_skipped_version`, и др.

---

## Открытые TODO (сессия 7)

- [x] Калькулятор: minimize → floating bar (expand / close); `accentOrange` → `AppTheme.accent` на операторах/пине/истории.
- [x] Главная: белый текст «Календарь»/«Задачи» на светлой теме → `textSecondary` + listen ThemeNotifier.
- [ ] Knowledge: полный rich-editor (Quill toolbar + insert link/table/image/video + wesios://) — body view уже есть.
- [ ] Релизный билд — **только по запросу** пользователя после накопления фиксов.
