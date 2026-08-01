# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-08-01 (сессия 6 — научный калькулятор, Grok)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** `main` · **UI:** v0.11.7 α · **build:** 23  
**Тесты:** `flutter analyze` / `flutter test` — проверять после каждой правки.  

Читай этот файл **перед** любыми правками. Не помечай задачу ✅, пока пользователь не подтвердил на билде.

---

## Правило: перед запуском билда / релиза

**Запрос владельца (2026-07-31):** перед любым билдом (push, workflow_dispatch
`build.yml` / `release-app.yml`) агент **обязан** сначала всё проверить.
Запускать сборку только если уверен, что она пройдёт.

### Чеклист перед билдом (обязателен)

1. **Статический анализ** — `flutter analyze` → **0** замечаний.
2. **Юнит-тесты** — `flutter test` → все тесты зелёные (как делает Claude).
3. **Ревью затронутых файлов** — особенно:
   - `android/app/build.gradle` (подпись: `ks*` vars, не `keyAlias`/`keyPassword` — иначе Groovy shadowing);
   - `.github/workflows/*.yml` (секреты, env, шаги decode keystore);
   - любые правки в `lib/` — не ломают Hive typeId, open boxes, known bugs из STATUS.
4. **Если Flutter недоступен в среде агента** — минимум:
   - прочитать diff и убедиться, что нет известных ловушек (shadowing, debug signing, overwrite google-services.json);
   - дождаться зелёного `Build WesiOS` на push (если правки уже запушены);
   - **не** запускать `release-app.yml`, пока analyze/test не подтверждены.
5. **Только после зелёного чеклиста** — `workflow_dispatch` на `release-app.yml` (с осмысленными `notes`).

Не «запустить и посмотреть». Сначала проверка — потом билд.

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
6. Только после этого — запускать `release-app.yml`.

### Последствия нарушения

Если `app_version.dart` и `pubspec.yaml` расходятся — OTA-обновление ломается:
приложение видит `0.10.1` в коде, а в релизе `0.11.0`, и считает, что релиз
**старше** установленной версии → отказывается обновляться.

---

## Сессия 6 (2026-08-01) — научный калькулятор

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

**Функции:**
- Память: mc / m+ / m- / mr (индикатор «M» на дисплее)
- 2nd: переключает sin↔asin и т.п.
- Rad/Deg: режим углов (триг пересчитывается)
- Факториал (целые ≤ 20), гиперболические (через exp-rewrite), % , EE (*10^), Rand, π, e
- Обыкновенные дроби: через `/` и скобки (1/2, (3+1)/4 и т.д.)

Классический режим сохранён без изменений по логике.

**Коммит:** `feat(calculator): classic / scientific mode switch + full scientific keypad (Grok)`

### 3. Чего НЕ делать

- Не убирать переключатель режимов.
- Не ломать историю / pin / blur / scale / keyboard.
- Не менять визуальный стиль кнопок «под iOS» без запроса — придерживаться AppTheme.

---

## Сессия 5 (2026-08-01) — артефакты в релизном workflow

Сессия велась агентом **Grok** (xAI) по прямому запросу владельца.  
**Не откатывать и не «улучшать» без явной просьбы пользователя.**

### 1. Upload-artifact в `release-app.yml`

**Запрос владельца:** «при создании релизной версии всё равно делались артифакты» — чтобы APK и Windows ZIP были доступны для скачивания со страницы прогона Actions, а не только из постоянного Release `app-latest`.

**Что сделано:**

| Job | Шаг | Что |
|-----|-----|-----|
| `build-windows` | `Upload Windows artifact` | `actions/upload-artifact@v4`, name: `WesiOS-Windows`, path: `wesios-windows-x64.zip`, retention-days: 30 |
| `build-android` | `Upload Android artifact` | `actions/upload-artifact@v4`, name: `WesiOS-Android`, path: `wesios-android.apk`, retention-days: 30 |

Артефакты кладутся **после** сборки и **до/параллельно** с `gh release upload --clobber`.  
APK в артефакте — **тот же подписанный** файл, что уходит в Release (после шага Decode+verify keystore и `flutter build apk --release`). Windows ZIP — тот же portable-архив.

**Коммит:** изменения в `.github/workflows/release-app.yml` (SHA около `3de37d90…` / последующие).  
**Прогон:** `workflow_dispatch` run #24 — https://github.com/wesiwer/WesiOS/actions/runs/30718231331

**Важно для следующих AI:**

- Не убирать `upload-artifact` «чтобы workflow был короче» — владелец явно попросил.
- Артефакты живут 30 дней на странице run; Release `app-latest` — постоянный источник для OTA.
- Подпись APK в артефакте идентична релизу (один и тот же путь после keystore decode).

### 2. Чего НЕ делать

- Не возвращать только-Release без artifacts.
- Не менять retention-days без запроса.
- Не дублировать keystore-логику — артефакт берёт уже готовый подписанный APK.

---

## Сессия 3 (2026-07-31) — подпись APK, часы, шапка, changelog

Сессия велась агентом Grok по прямому запросу владельца. Ниже — всё, что
сделано, с причинами и ограничениями. **Не откатывать и не «улучшать»
без явной просьбы пользователя.**

### 1. Постоянная подпись Android APK (решено)

**Проблема:** при попытке обновиться через приложение Android показывал
«Подпись пакета и установленного приложения не совпадают». Причина —
в `android/app/build.gradle` release собирался с `signingConfigs.debug`.
Debug-ключ разный на каждом CI-раннере и на локальной машине → обновление
поверх существующей установки невозможно.

**Что сделано:**

| Файл | Изменение |
|---|---|
| `android/app/build.gradle` | `signingConfigs.release` читает `KEYSTORE_PATH` / `KEYSTORE_PASSWORD` / `KEY_ALIAS` / `KEY_PASSWORD` из env. Если переменных нет — fallback на debug (удобно для локальных сборок). Если есть — подписывает release-ключом. Имена локальных vars: `ksPath`/`ksAlias`/`ksStorePassword`/`ksKeyPassword` — **не** `keyAlias`/`keyPassword`, иначе Groovy shadowing и `No signature of method: java.lang.String.call()`. |
| `.github/workflows/release-app.yml` | Шаг «Decode release keystore»: base64 → `$RUNNER_TEMP/wesios-release.jks`, выставляет `KEYSTORE_PATH`. Без секрета `ANDROID_KEYSTORE_BASE64` job **падает явно**, а не молча собирает debug. |

**Секреты репозитория (уже добавлены владельцем):**

| Secret | Назначение |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | Содержимое `.jks` в base64 |
| `ANDROID_KEYSTORE_PASSWORD` | Пароль keystore |
| `ANDROID_KEY_ALIAS` | Alias ключа (`wesios`) |
| `ANDROID_KEY_PASSWORD` | Пароль ключа |

Keystore сгенерирован один раз (RSA 2048, validity 10000 дней, CN=WesiOS).
Пароль и base64 выданы владельцу в чате — **в репозиторий не класть**.

**Важно для следующих AI:**

- Первый переход с debug-подписи на release **требует одноразового удаления**
  старого приложения с телефона. После этого все обновления с тем же ключом
  встают поверх без удаления, **данные Hive сохраняются**.
- Не возвращать `signingConfig signingConfigs.debug` в release.
- Не коммитить `.jks` / пароли в репозиторий.
- Локальная `flutter build apk --release` без env-переменных по-прежнему
  соберётся debug-ключом — это нормально.

### 2. Два варианта часов (цифровые + циферблат)

**Запрос ТЗ:** два варианта часов — обычные цифровые и циферблат (analog).

**Файл:** `lib/core/widgets/wesi_clock.dart`

| Что | Как |
|---|---|
| Стили | `digital` (как было: HH:MM:SS + дата) и `analog` (CustomPainter: круг, деления, цветные стрелки) |
| Переключение | Long-press по часам |
| Сохранение | Hive `wesios_settings` → ключ `clock_style` (`digital` / `analog`) |
| Размер | Адаптивный от ширины экрана, чтобы не давить на лого и иконки |

**Не трогать:** long-press как жест переключения; ключ Hive `clock_style`;
не вводить третий стиль без запроса.

### 3. Adaptive header — убран overlap сверху

**Проблема (скриншот пользователя):** на мобиле крупные цифры часов
наезжали на логотип WesiOS, дату и иконки статус-бара.

**Файл:** `lib/features/home/home_screen.dart`

- Шапка переведена на адаптивную раскладку (MediaQuery, SafeArea,
  `kTitleBarInset` где нужно).
- Размеры часов и отступы считаются от ширины экрана.
- Элементы сверху больше не накладываются друг на друга на узких экранах.

**Правило:** любой новый элемент в шапке главной обязан учитывать
узкий экран и не использовать фиксированные большие кегли без clamp.

### 4. Changelog («Что нового») при обновлении

**Запрос:** при появлении обновления сразу показывать, что добавится /
улучшится.

**Файл:** `lib/core/widgets/app_update_card.dart`

- Поле `notes` из `app-manifest.json` уже парсилось в `AppRelease.notes`.
- Раньше notes показывались только в полной карточке настроек и только
  если `!compact`.
- Теперь блок **«Что нового»** показывается **всегда**, когда есть
  обновление и непустые notes — и в баннере на главной, и в настройках.
- В compact-режиме длинный текст сворачивается (3 строки + «Подробнее»).

**Как писать notes при релизе:** в Actions → Run workflow → поле `notes`.
Пример:

```
• Два варианта часов (цифровые + циферблат), long-press для переключения
• Исправлено наложение элементов шапки на мобиле
• Постоянная подпись APK — обновления без удаления приложения
• Changelog виден прямо в баннере обновления
```

Пустые notes → блок «Что нового» не рисуется (не пустая рамка).

### 5. Что пользователь должен сделать руками (один раз)

1. Секреты подписи — **уже добавлены**.
2. Запустить workflow `release-app.yml` вручную (Actions → Run workflow),
   желательно с заполненным `notes`.
3. **Один раз** удалить старый WesiOS с телефона (был debug-подпись).
4. Установить новый APK из релиза `app-latest`.
5. Дальше обновления идут через приложение без удаления, данные сохраняются.

### 6. Чего НЕ делать следующим AI

- Не откатывать signing на debug «для простоты».
- Не убирать блок «Что нового» из баннера «чтобы было компактнее».
- Не менять жест переключения часов без запроса владельца.
- Не коммитить keystore / пароли.
- Не обещать «обновление без удаления», пока пользователь не прошёл
  одноразовую переустановку на release-подпись.
- Не дублировать логику notes в другом виджете — источник один:
  `AppRelease.notes` → `AppUpdateCard`.

---

## Сессия 4 (2026-07-31 — 2026-08-01) — UI-правки, светлая тема, агент Kimi

Сессия велась агентом **Kimi** (Moonshot AI). Ниже — всё, что сделано, с причинами.
**Не откатывать и не «улучшать» без явной просьбы пользователя.**

### 1. Часы под логотипом + переключатель стиля рядом

**Запрос ТЗ:** часы с датой под логотипом WesiOS, два формата (цифровой + циферблат), переключатель — маленькая иконка рядом с часами (не long-press).

**Файл:** `lib/features/home/home_screen.dart`

| Что | Как |
|---|---|
| Расположение | `WesiClock` перенесён из правой части header в `Column` под `WesiLogo` |
| Размер лого | `WesiLogo(size: 40)` → `size: 56` |
| Размер иконок справа | `_HoverIconButton` icon size: 24 → 28; `_ProfileDropdown` avatar: 28×28 → 36×36 |
| Переключатель | Иконка `Icons.watch` / `Icons.watch_later` рядом с часами, тап переключает стиль |

**Файл:** `lib/core/widgets/wesi_clock.dart`

- Переключение теперь через тап по иконке рядом (не long-press). Long-press оставлен как fallback.
- Сохранение стиля: Hive `wesios_settings` → ключ `clock_style`.

### 2. Убран WelcomeScreen

**Запрос ТЗ:** убрать экран «Начать работу», сразу переход к приложению.

| Файл | Изменение |
|---|---|
| `lib/features/splash/splash_screen.dart` | `Navigator.pushReplacementNamed(context, '/welcome')` → `'/login'` |
| `lib/core/routes/app_router.dart` | Маршрут `/welcome` оставлен для обратной совместимости, но не используется при старте |

### 3. Лого «смерть с косой» в Истории создания

**Запрос ТЗ:** Easter-egg лого (`assets/images/wesi_logo_easter.png`) вместо оранжевого круга с W на экране Founder Story.

| Файл | Изменение |
|---|---|
| `lib/features/profile/founder_story_screen.dart` | Оранжевый круг с буквой «W» → `Image.asset('assets/images/wesi_logo_easter.png')` |

### 4. Светлая тема (Light Theme)

**Запрос ТЗ:** белый фон, серые элементы, голубые акценты. Плавная анимация переключения (~0.5–1 сек), элементы перекрашиваются по очереди.

**Файл:** `lib/core/theme/app_theme.dart`

| Что | Как |
|---|---|
| `ThemeNotifier` | `ValueNotifier<bool>` для `isDark`; `toggle()` переключает + сохраняет в Hive `wesios_settings` → ключ `theme_dark` |
| `AppTheme` | Все цвета стали **геттерами** (`get textMuted => isDark ? dark : light`), а не `static const`. Это критично: `const TextStyle(color: AppTheme.xxx)` больше невозможен. |
| Цвета светлой темы | Фон `#FFFFFF`, поверхность `#F5F5F7`, текст `#1A1A2E`, акцент `#3B82F6` (голубой), стекло — полупрозрачный чёрный |

**Файл:** `lib/app.dart`

- `AnimatedTheme` с `duration: 600ms`, `curve: Curves.easeInOutCubic` — плавный переход всех элементов.
- `ValueListenableBuilder` на `ThemeNotifier.instance`.

**Файл:** `lib/features/settings/settings_screen.dart`

- Переключатель темы: Switch с иконками `Icons.dark_mode` / `Icons.light_mode`.
- Подписи локализованы (`theme_dark`, `theme_light` в `wesi_locale.dart`).

**Последствие (критично для следующих AI):**
`AppTheme.xxx` теперь геттеры. Любой `const TextStyle(color: AppTheme.xxx)` сломает компиляцию.
Было проведено массовое исправление ~90 файлов: `const TextStyle(...)` → `TextStyle(...)`.
Если добавляешь новый виджет — **не используй `const` с `AppTheme` цветами**.

### 5. App Icon Mode (auto / dark / light)

**Запрос ТЗ:** иконка приложения на Android должна переключаться вместе с темой.

| Файл | Роль |
|---|---|
| `lib/core/services/app_icon_service.dart` | `AppIconMode` (`auto`/`dark`/`light`), `setIconMode()`, слушает `ThemeNotifier` при `auto` |
| `android/app/src/main/res/mipmap-*/` | Два набора иконок: `ic_launcher` (тёмная) + `ic_launcher_light` (светлая) |
| `lib/features/settings/settings_screen.dart` | Пикер: Auto / Dark / Light |

### 6. Массовый фикс `const` → `TextStyle`

**Причина:** `AppTheme` цвета стали геттерами → `const TextStyle(color: AppTheme.xxx)` невозможен.

**Коммиты:** `fix(theme): remove const from widgets using AppTheme getters` × 5+ файлов.

**Файлы:** `category_editor_dialog.dart`, `knowledge_base_screen.dart`, `global_search_sheet.dart`, `alerts_sheet.dart`, `engine_download_overlay.dart`, и др.

### 7. Версии в этой сессии

| Версия | Что |
|---|---|
| v0.11.0+14 α | Первый релиз сессии (часы, лого, иконки) |
| v0.11.1+15 α | Часы под логотипом, переключатель рядом |
| v0.11.2+17 α | Убран WelcomeScreen, лого смерти в Истории |
| v0.11.3+18 α | Светлая тема, переключатель в настройках |
| v0.11.4+20 α | App icon mode, mass `const` fix, light theme polish |

### 8. Чего НЕ делать следующим AI

- Не возвращать `const` с `AppTheme` геттерами — сломает компиляцию.
- Не менять расположение часов без запроса (сейчас под логотипом).
- Не возвращать WelcomeScreen как стартовый экран.
- Не менять цвета светлой темы без запроса.
- Не удалять `AppIconService` или dual-иконки Android.

---

## Сессия 2, часть 3 — подтверждённые архитектурные решения

Пользователю заданы 2 вопроса (см. предыдущую часть) — оба решены:

### Fullscreen при старте — подтверждено, реализовано

Пользователь подтвердил: нужен настоящий OS fullscreen, несмотря на то что это
ломает системный minimize (как и предупреждалось). Нашёл точную причину в
исходниках плагина `window_manager` (`windows/window_manager.cpp:344`):

```cpp
void WindowManager::Minimize() {
  if (IsFullScreen()) {  // Like chromium, we don't want to minimize fullscreen windows
    return;
  }
  ...
}
```

Это намеренное поведение плагина (как у Chromium) — `minimize()` на Win32
безусловно ничего не делает, если окно в fullscreen. Обойти нельзя, вызывая
`minimize()` напрямую. Решение — обходной путь на уровне приложения:

| Файл | Изменение |
|---|---|
| `lib/main.dart` | `windowManager.maximize()` → `windowManager.setFullScreen(true)` при старте. |
| `lib/core/widgets/window_controls.dart` | Кнопка «Свернуть» теперь зовёт `_minimize()`: сначала явно `setFullScreen(false)`, потом `minimize()` — на этот момент `IsFullScreen()` уже `false`, и нативный `Minimize()` отрабатывает как обычно. Разведены два разных булевых состояния: `_isFullScreen` (текущее нативное состояние — только для иконки кнопки) и `_wantFullScreen` (выбор пользователя — используется в `onWindowRestore()`, чтобы при восстановлении из трея вернуть fullscreen обратно). Это разделение критично: если бы `onWindowRestore` смотрел на `_isFullScreen`, оно было бы `false` сразу после сворачивания (мы же сами его погасили) — и fullscreen не возвращался бы никогда после первого же minimize. Средняя кнопка (была maximize/restore) теперь переключает fullscreen (`Icons.fullscreen`/`fullscreen_exit`), двойной клик по drag-зоне делает то же самое. |

Проверено по исходнику плагина: `SetFullScreen(false)` — лёгкая операция
(меняет `GWL_STYLE` + `SetWindowPos`, без пересоздания окна), поэтому пара
setFullScreen(false)+minimize() не должна давать заметного визуального
«моргания». **Требует подтверждения на живом билде** — сам Win32 у меня
недоступен для ручной проверки.

### Слой 2 прогноза — подтверждено: подключать Prophet/SARIMAX

Пользователь выбрал реальную библиотеку вместо нативного Dart-движка. Это
architecturно больше, чем один вопрос — есть развилка, которую ещё не решили,
и я не стал делать выбор сам (это ровно то же правило CLAUDE.md). Смотри
финальный ответ пользователю — там 3 конкретных варианта реализации
(bundled Python + statsmodels SARIMAX, bundled Python + Prophet/CmdStan,
облачный backend) с честными компромиссами по каждому, и рекомендация.
Работа над этим **не начата** — ждёт уточнения, какой именно вариант.

---

## Сессия 2, часть 4 — мульти-движковый прогноз (Wesi Horizon / Prophet / SARIMAX)

Запрос пользователя: тумблер на экране прогноза для выбора движка — родной
(с крутым английским именем, с приставкой Wesi) / Prophet / SARIMAX — плюс
режим сравнения (график и таблица, от 0 до всех 3 сразу) и режим
«Комбинированный» — среднее по тем движкам, что реально посчитались.

### Архитектура

| Файл | Роль |
|---|---|
| `lib/features/treasury/services/multi_engine_forecast.dart` | `ForecastEngineKind` (wesiHorizon/prophet/sarimax/combined), `ExternalForecastBridge` (Dart↔Python подпроцесс), `RiskEstimate` (Cash Gap Risk Score по готовым P10/P50/P90 через нормальную аппроксимацию — нужно для движков без сырых Monte-Carlo путей), `combineForecastResults` (поэлементное среднее, пропускает недоступные движки, не считает их нулём). |
| `python_engines/_io_common.py` | Общий контракт ввода/вывода для обоих внешних движков: JSON `{history: [{date, net}], days, current_balance}` → JSON `{engine, p10, p50, p90, history_days}` или `{error, detail}`. |
| `python_engines/forecast_prophet.py` | Prophet (Meta), `interval_width=0.8` → P10/P90. |
| `python_engines/forecast_sarimax.py` | statsmodels SARIMAX(1,1,1)x(1,1,1,7) с откатом на ARIMA(1,1,1) без сезонной части, если модель не сходится. |

**Родное имя движка: «Wesi Horizon»** — так называется существующий
`ForecastEngine` (bootstrap Monte-Carlo) в UI/сравнении; сам класс не
переименовывался (не имеет смысла менять публичное Dart-имя ради
отображаемой строки — она и так задаётся через `ForecastEngineKind.nameRu/nameEn`).

Ключевое упрощение (задокументировано и в коде, и здесь): Prophet/SARIMAX
прогнозируют **один** ряд — чистый дневной денежный поток (доход минус
расход), в отличие от Wesi Horizon, который считает доход и расход как два
независимых потока (даёт точность и рычаг для «Что если?»). Следствие:
множители «Что если?» к Prophet/SARIMAX не применяются — сценарий влияет
только на Wesi Horizon. Показывать это как недостаток внешних движков было
бы нечестно: это стандартный вход для готовых библиотек временных рядов,
не особенность нашей реализации.

Всё протестировано end-to-end локально (pip install numpy/pandas/statsmodels/
prophet/cmdstanpy, оба скрипта дают корректные P10≤P50≤P90 на синтетических
данных, мост Dart→Python отрабатывает за ~1-1.1 сек на вызов). Юнит-тесты:
`test/multi_engine_forecast_test.dart` (8 тестов — среднее по движкам,
пропуск недоступных вместо нуля, несовпадение длин не роняет приложение,
Cash Gap Risk Score по перцентилям).

### UI (`forecast_chart_screen.dart`)

- `_engineSelector()` — 4 независимых тумблера (Wesi Horizon/Prophet/SARIMAX/
  Combined), с индикатором загрузки на конкретном тумблере (Prophet/SARIMAX
  считаются лениво — только по первому включению, до следующей смены
  периода/сценария) и индикатором «недоступен» (не найден Python/скрипт
  упал — с тултипом-объяснением), а не тихой пустотой.
- График: **ровно один активный движок** → полная деталировка (P10-P90
  заливка/пунктир по существующим тумблерам `_controls()`, но обобщено на
  выбранный движок и его цвет — не только Wesi Horizon, как было раньше).
  **Ноль или 2+** → режим сравнения: только линия P50 на каждый активный
  движок (полосы убраны — иначе нечитаемо), легенда под графиком.
- `_comparisonTable()` — таблица под графиком, колонка на активный движок,
  равномерная выборка дней (не более 12 строк — полный список на 365-дневном
  горизонте не поместится и не нужен).
- Цвета движков: Wesi Horizon — существующий `accentOrange`; Prophet —
  `#38BDF8` (голубой); SARIMAX — `#C084FC` (фиолетовый); Combined —
  `#2DD4BF` (бирюзовый) — те же оттенки, что уже использованы в пресетах
  `wesi_avatar.dart`, ничего нового в палитру не добавлено.

### Bundling Python — итоговая модель: установка по требованию (сессия 2, часть 5)

Первая версия этого раздела (см. историю коммитов) описывала бандлинг
SARIMAX прямо в основной Windows-инсталлятор по умолчанию. Пользователь
попросил лучше: **вообще ничего не бандлить в основную сборку** — по
умолчанию должен стоять только Wesi Horizon, а Prophet/SARIMAX скачиваются
по требованию (баннер на Forecast + раздел в Settings), с прогресс-баром,
скоростью и этапами загрузки, видимыми через плавающий индикатор поверх
любого экрана. Модель полностью переделана под это — см. следующий раздел.

### Область действия — Windows-only

Prophet/SARIMAX/Combined **работают только в Windows-сборке**. На Android
ничего скачать нельзя (см. ниже) — тумблеры честно покажут «недоступен»,
доступен только Wesi Horizon. Это не баг, а следствие того, что бандлинг
Python подпроцессом — desktop-специфичный паттерн; для Android потребовался
бы принципиально другой подход (например, Chaquopy или облачный API) —
новое архитектурное решение, не часть этого захода.

---

## Правила для AI (актуально)

1. Не удалять дублирование Sandbox/Treasury.
2. Не возвращать лого в title bar.
3. Только `MainAxisSize.min`, никогда `MainAxis.min`.
4. Overlay-тултипы → всегда `IgnorePointer`.
5. Forecast period change → не full-screen loader.
6. После правок — обновить **этот** STATUS.md (статус строк таблицы).
7. Не ставить ✅ без проверки на Windows-билде пользователем.
8. Локально проверяй `flutter analyze` — он должен давать **0** замечаний. Windows-билд на Linux собрать нельзя, только через CI (`workflow_dispatch` на ветке).
9. Нативные папки `windows/` и `android/` — неполные шаблоны. Прежде чем чинить платформенный баг правкой там, сверься с п. 5 «Архитектуры».
10. **Android release подписывается постоянным ключом из Secrets.** Не откатывать на debug. Первый переход с debug → release требует одноразового удаления приложения у пользователя.
11. **Changelog обновления** — блок «Что нового» в `AppUpdateCard` обязателен при непустых `notes`. Не убирать «для компактности».
12. **Часы:** два стиля (digital/analog), переключатель рядом с часами, Hive `clock_style`. Не ломать без запроса.
13. **Тема:** `AppTheme` цвета — геттеры (не `const`). `const TextStyle(color: AppTheme.xxx)` сломает компиляцию. Используй `TextStyle(...)` без `const`.
14. **App Icon Mode:** Auto/Dark/Light в настройках. Не удалять dual-иконки Android.
15. **Перед билдом/релизом** — чеклист выше (`flutter analyze` + `flutter test` + ревью). Запускать workflow только если уверен, что пройдёт. Не «запустить и посмотреть».
16. **Артефакты в release-app.yml** — `upload-artifact` для WesiOS-Android и WesiOS-Windows обязателен (сессия 5, Grok). Не убирать.
17. **Калькулятор:** режимы Classic / Scientific, научная раскладка по скрину (сессия 6, Grok). Не убирать переключатель.

---

## Ключевые файлы (дополнение сессий 4–6)

| Что | Путь |
|-----|------|
| Подпись Android | `android/app/build.gradle` |
| CI релиза + keystore + artifacts | `.github/workflows/release-app.yml` |
| Часы (digital + analog) | `lib/core/widgets/wesi_clock.dart` |
| Шапка главной | `lib/features/home/home_screen.dart` |
| UI обновления + changelog | `lib/core/widgets/app_update_card.dart` |
| Сервис обновлений | `lib/core/services/app_update_service.dart` |
| Калькулятор (classic + scientific) | `lib/features/calculator/calculator_screen.dart` |

## Занятые Hive typeId

Менять нельзя — по ним читаются уже записанные данные.

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

Все четыре адаптера задач регистрируются в `lib/main.dart`. Забыть об этом —
падение в рантайме при открытии бокса, которое `flutter analyze` не ловит.

Боксы без адаптеров (обычный JSON/примитивы): `wesios_cache`,
`wesios_settings`, `wesios_offline_queue`, `wesios_whatif`.

Типизированные боксы: `wesios_treasury`, `wesios_sandbox`, `wesios_tasks`,
`wesios_accounts`, `wesios_knowledge`.

Доп. ключи в `wesios_settings` (строки/примитивы, без typeId):
`clock_style` (`digital`|`analog`), `update_skipped_version`, и др.
