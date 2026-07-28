# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-07-28 (сессия: починка сборки + P0/P1/P2)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** claude/document-review-wp4jch · **UI:** v0.1.2 α · **pubspec:** 0.1.2+3

Читай этот файл **перед** любыми правками. Не помечай задачу ✅, пока пользователь не подтвердил на билде.

## Что сделано в последней сессии

### Сначала — починка сборки

CI был красный **30+ прогонов подряд**, падали оба джоба на компиляции Dart.
Ни один пункт ТЗ нельзя было подтвердить билдом. Три причины:

| # | Файл | Что было |
|---|------|----------|
| 1 | `operations_screen.dart`, `sandbox_screen.dart`, `forecast_chart_screen.dart` | `../../../core/…` уходит выше `lib/`; в `operations_screen` ещё и `../services/`, `../models/`, `../widgets/` вместо путей той же директории. Эталон правильных путей — `treasury_screen.dart` |
| 2 | `home_screen.dart` | `_DashboardTab` — `StatelessWidget`, а внутри `setState` / `mounted` |
| 3 | `calculator_screen.dart` | `const`-мапа с ключами `LogicalKeyboardKey` — у них нет primitive equality |

### Дальше — пункты ТЗ

| # | Файл | Изменение |
|---|------|-----------|
| 1 | `main.dart` | Убран `setFullScreen(true)` — только `maximize()` (см. пункты 1, 5) |
| 2 | `windows/runner/main.cpp` | `SetQuitOnClose` возвращён в `true` (см. «Архитектура», п. 5) |
| 3 | `home_screen.dart` | Ленивые вкладки + cross-fade 170 мс; баланс дашборда реальный, а не `0` |
| 4 | `operations_screen.dart`, `add_transaction_dialog.dart` | Настоящее редактирование: предзаполнение и запись по тому же `id` |
| 5 | `exchange_rate_service.dart`, `treasury_screen.dart` | Курсы с cbr.ru + строка «Курс ЦБ на дд.мм.гггг» |
| 6 | `forecast_chart_screen.dart` | Календарь диапазона; режимы графика прогноз / структура / тренд |
| 7 | `wesi_avatar.dart`, `profile_screen.dart` | Новый набор пресетов + загрузка своей аватарки |
| 8 | `calculator_screen.dart`, `app.dart` | Калькулятор — глобальный оверлей; resize за угол |
| 9 | `hover_button.dart`, `home_screen.dart` | `FocusableActionDetector` — навигация стрелками + Enter/Space |
| 10 | `wesi_locale.dart`, `app.dart` | `localeNotifier` — смена языка перерисовывает все вкладки |
| 11 | `analysis_options.yaml` | `flutter analyze` — 0 замечаний |

---

## Архитектура (не баги)

1. `SandboxService` ≠ `TreasuryService` — **намеренное** дублирование.
2. Суммы внутри в RUB-эквиваленте; UI через `CurrencyService.fromRub` / `toRub`.
3. Кастомный title bar (`TitleBarStyle.hidden` + `WindowControls`).
4. Курсы: `ExchangeRateService` → cbr.ru (`scripts/XML_daily.asp`); fallback — exchangerate.host, затем зашитые курсы. ЦБ **не отдаёт UAH** — у неё остаётся зашитый курс.
5. **CI пересоздаёт `windows/`.** Шаг «Wipe broken Windows platform stub» удаляет всю папку и заново генерирует её через `flutter create`, потому что в репозитории лежит неполный огрызок (нет `flutter_window.cpp`, `win32_window.cpp`, `utils.cpp`, `Runner.rc`). Любая правка в `windows/runner/` **в сборку не попадает** — переживает только то, что workflow восстанавливает отдельным шагом (сейчас это иконка). Не чини нативные баги правками в `windows/` — они не доедут.
6. `SetQuitOnClose` должен быть `true`. При `false` `WM_DESTROY` не вызывает `PostQuitMessage`, и после закрытия окна процесс остаётся жить.
7. `lib/core/services/finance_firestore_service.dart` — мёртвый код, исключён из анализа: `cloud_firestore` / `firebase_auth` убраны из pubspec (ломают Windows desktop build), файл ниоткуда не импортируется.
8. Калькулятор — глобальный оверлей в `app.dart` (`CalculatorOverlay`), не route. Закреплённый переживает смену вкладок и не перехватывает клики.
9. `android/app/src/main/res/` отсутствовал в репозитории целиком, хотя `AndroidManifest.xml` всегда ссылался на `@mipmap/ic_launcher`, `@style/LaunchTheme`, `@style/NormalTheme`. Сборка падала на `:app:processReleaseResources` — этого не было видно, потому что раньше билд умирал ещё на компиляции Dart. Ресурсы добавлены; иконки отрисованы из `assets/images/app_icon.png`, launch-тема тёмная под `#09090B`.

---

## Полный разбор баг-листа пользователя

Легенда: ✅ в коде и ожидаемо работает · ⚠️ в коде, **не подтверждено** / частично · ❌ не сделано

### Окно Windows

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 1 | Кнопка **свернуть** не работает | ⚠️ | Найдена вероятная причина: `main.dart` звал `setFullScreen(true)`, а borderless-fullscreen окно Win32 не сворачивается по `windowManager.minimize()`. Fullscreen убран, остался `maximize()`. **Перепроверить на билде.** |
| 2 | Свернуть/закрыть **долго реагируют** | ⚠️ | `Listener` + отдельная drag-зона. Нужна проверка на билде. |
| 3 | Валюта **налезает на Close** | ⚠️ | Padding `right: 140` в Treasury/Sandbox. Может остаться на других экранах с actions. |
| 4 | Кнопка **Отмена** в диалогах налезает на Close | ⚠️ | `AddTransactionDialog` получил `insetPadding` с отступом на `kTitleBarHeight`. Остальные диалоги — проверить. |
| 5 | При старте **полный экран**, сейчас окно | ⚠️ | Договорились: `maximize()`, **без** `setFullScreen(true)` — taskbar виден, minimize работает штатно. Код приведён в соответствие. |
| 6 | Убрать **маленький лого + «WesiOS»** из title bar | ✅ | Title bar пустой слева, только кнопки окна. |

### Home / навигация

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 7 | Bottom tabs **сразу** в экраны, без «Открыть Treasury» | ✅ | `IndexedStack`: Tasks / Treasury / Analytics / Settings. |
| 8 | Home **Продажа** → сразу экран/диалог продажи | ⚠️ | `_showAddTransaction` открывает `AddTransactionDialog` напрямую. Раньше не компилировалось (`setState` в `StatelessWidget`) — теперь собирается. Проверить на билде. |
| 9 | Home **Траты** → сразу окно трат | ⚠️ | То же. Баланс на дашборде обновляется после сохранения. |
| 10 | Кошелёк только через **Финансы** снизу | ✅ | Tab Treasury. |
| 11 | Hover на лого: подсказка **рядом**, не поверх | ✅ | Карточка справа + `IgnorePointer`. |
| 12 | Мерцание на углу лого | ✅ | Fix IgnorePointer. |
| 13 | **Анимация смены bottom-вкладок лагает**, неприятно глазу | ⚠️ | Вкладки строятся лениво (`Set<int> _built`, непосещённые — `SizedBox.shrink()`) + cross-fade 170 мс. Раньше все 5 экранов строились на первом кадре. Проверить на билде. |

### Treasury

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 14 | Кнопки «Всего доходов/расходов» → **Продажа / Траты** | ✅ | |
| 15 | Категории на **русском** (EN только в EN-локали) | ✅ | В диалоге добавления. |
| 16 | Кнопка **Операции**: список всех, **edit + delete** | ⚠️ | `OperationsScreen` (поиск, фильтр, сортировка, swipe-delete). Edit теперь настоящий: диалог предзаполняется и пишет по тому же `id`, а не delete + добавление с новым `id`. Проверить на билде. |
| 17 | Реальный **курс**, не только символ | ⚠️ | В карточке баланса Treasury — «1 $ = 90,12 ₽ · Курс ЦБ на дд.мм.гггг». Если сработал fallback, строка помечается оранжевым. |
| 18 | Курс с **гос. сайта** | ⚠️ | `cbr.ru/scripts/XML_daily.asp` — официальный источник. Тело в windows-1251, парсится через latin1 + regex по `CharCode`/`Nominal`/`Value`, без новых зависимостей. Fallback: exchangerate.host → зашитые курсы. |

### Forecast

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 19 | Тогглы диапазон / тренд **ничего не меняют** | ⚠️ | В коде влияют на `lineBarsData`. Перепроверить на билде. |
| 20 | Тултипы **P10 / P50 / P90** | ✅ | |
| 21 | Аномалии на русском | ✅ | |
| 22 | **Календарь** ручного диапазона | ⚠️ | Chip с иконкой календаря рядом с 7/14/30/60/90 → `showDateRangePicker` в тёмной теме; выбранный диапазон задаёт число дней (clamp 1–365). |
| 23 | Смена периода без дёрганья экрана | ✅ | Только opacity графика. |
| 24 | Даты на оси X | ✅ | |
| 25 | Более детальные графики | ⚠️ | Вернулись режимы: прогноз / структура (bar по категориям) / тренд (дневное нетто). Переключение не перестраивает экран. |

### Calculator

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 26 | Блюр с **зависаниями** → плавный | ⚠️ | Убран BackdropFilter из роутера, затемнение `Colors.black54`. На слабых GPU всё ещё может быть тяжело. |
| 27 | **Убрать блюр** (toggle) | ✅ | Кнопка blur on/off. |
| 28 | **Перемещать** окно калькулятора | ✅ | `onPanUpdate` → offset. |
| 29 | **Закрепить (pin)** — живёт поверх вкладок | ⚠️ | Калькулятор поднят в глобальный оверлей в `app.dart` (`CalculatorOverlay`), рядом с `WindowControls`. Закреплённый переживает смену вкладок и **не рисует backdrop**, поэтому не перехватывает клики по приложению. Проверить на билде. |
| 30 | **Resize** с сохранением пропорций | ⚠️ | Ручка в правом нижнем углу (`onPanUpdate`, усреднение по осям), тот же clamp 0.7–1.4, что и у кнопок +/−. |
| 31 | **ESC** закрывает если не pinned | ✅ | |
| 32 | **Delete** очищает (не только C) | ✅ | |

### Settings / Locale

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 33 | Смена языка **не обновляет** сами настройки | ⚠️ | Добавлен `WesiLocale.localeNotifier`. `HomeScreen` слушает его и подмешивает язык в key каждой вкладки, поэтому пересоздаются все пять, а не только Settings. Проверить на билде. |

### Аватарки / иконки

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 34 | Иконки/аватар меняются **только после рестарта** | ⚠️ | `WesiAvatar` → `ValueListenableBuilder` + `Hive.listenable(keys: ['avatar_index', 'avatar_custom'])`. |
| 35 | Аватарки **старые, поменять** набор | ⚠️ | Новый сет: 10 пресетов, многоточечные градиенты и другие глифы. Проверить глазами на билде. |
| 36 | **Своя ава** (upload) | ⚠️ | `file_picker` (уже был в pubspec) → байты в Hive `avatar_custom`, приоритет над пресетом. В Profile — «Загрузить свою» и «Вернуть пресет». |

### First-run / Firebase

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 37 | Подсказки **где взять ключ** при наведении на first-run | ⚠️ | Tooltip у всех семи полей `FirstRunScreen` (Measurement ID был последним без подсказки). |

### Splash

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 38 | Оранжевый свет **ярче** | ✅ | |
| 39 | Убрать иконку по центру | ✅ | |
| 40 | Кольца толще/меньше, **ниже** шкалы | ✅ | |

### Sandbox

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 41 | Убрать слова **«Сценарий»** | ✅ | Баннер: mode + isolation + no impact. |

### Валюты

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 42 | EUR, GBP, CNY, UAH, BYN, KZT | ✅ | В `CurrencyService.currencies`. |

### Клавиатура

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 43 | Стрелки между кнопками UI | ⚠️ | `HoverButton`, `HoverIconButton` и быстрые действия Home переведены на `FocusableActionDetector`: попадают в обход фокуса (стрелки работают штатным `DirectionalFocusIntent`), Enter/Space активируют, фокус-рамка заметнее hover. Остальные `GestureDetector` по экранам — не охвачены. |

### Profile

| # | Запрос | Статус | Комментарий |
|---|--------|--------|-------------|
| 44 | Автосохранение без кнопки | ✅ | Debounce 600ms. |

---

## Сводка: что чинить в первую очередь

Все 15 пунктов реализованы в коде и собираются. ⚠️ = ждёт подтверждения
пользователем на живом билде — ✅ ставим только после этого.

### P0
1. **Minimize** — ⚠️ убран startup-fullscreen (вероятная причина).
2. **Fullscreen/maximize при старте** — ⚠️ только `maximize()`.
3. **Home Продажа/Траты → диалог сразу** — ⚠️ работало в коде, но не компилировалось.
4. **Экран Операции** (все tx, edit + delete) — ⚠️ edit стал настоящим.
5. **FirstRun** подробные tooltip по Firebase-ключам — ⚠️ все семь полей.
6. **Лаг анимации bottom-tabs** — ⚠️ ленивые вкладки + cross-fade.

### P1
7. Глобальный locale rebuild — ⚠️ `localeNotifier` + key по языку.
8. Курсы с ЦБ + реальный курс и дата — ⚠️ cbr.ru, fallback сохранён.
9. Календарь диапазона в Forecast — ⚠️ `showDateRangePicker`.
10. Новые пресеты аватарок + upload — ⚠️ 10 пресетов + своя картинка.
11. Pin калькулятора как global overlay — ⚠️ `CalculatorOverlay` в `app.dart`.
12. Resize калькулятора drag-corner — ⚠️ ручка в углу.
13. Keyboard arrow focus traversal — ⚠️ `FocusableActionDetector` на общих кнопках.

### P2
14. Отмена в диалогах vs title bar overlap — ⚠️ `insetPadding` в `AddTransactionDialog`.
15. Продвинутые графики / больше метрик — ⚠️ режимы прогноз / структура / тренд.

### Что осталось незакрытым
- Пункт 3 (валюта налезает на Close) — правился только для Treasury/Sandbox, на других экранах с `actions` может воспроизводиться.
- Пункт 43 — стрелками охвачены общие кнопки; отдельные `GestureDetector` по экранам нет.
- UAH: ЦБ её не публикует, курс остаётся зашитым.
- `pubspec.lock` в репозиторий не добавлен (вопрос конвенции проекта — решать пользователю).

---

## Правила для AI

1. Не удалять дублирование Sandbox/Treasury.
2. Не возвращать лого в title bar.
3. Только `MainAxisSize.min`, никогда `MainAxis.min`.
4. Overlay-тултипы → всегда `IgnorePointer`.
5. Forecast period change → не full-screen loader.
6. После правок — обновить **этот** STATUS.md (статус строк таблицы).
7. Не ставить ✅ без проверки на Windows-билде пользователем.
8. Локально проверяй `flutter analyze` — он должен давать **0** замечаний. Windows-билд на Linux собрать нельзя, только через CI (`workflow_dispatch` на ветке).
9. Нативные папки `windows/` и `android/` — неполные шаблоны. Прежде чем чинить платформенный баг правкой там, сверься с п. 5 «Архитектуры».

---

## Ключевые файлы

| Что | Путь |
|-----|------|
| Title bar | `lib/core/widgets/window_controls.dart` |
| App start window | `lib/main.dart` |
| Currency | `lib/core/services/currency_service.dart` |
| Rates | `lib/core/services/exchange_rate_service.dart` |
| Locale | `lib/core/localization/wesi_locale.dart` |
| Avatar | `lib/core/widgets/wesi_avatar.dart` |
| Home | `lib/features/home/home_screen.dart` |
| Treasury | `lib/features/treasury/treasury_screen.dart` |
| Sandbox | `lib/features/treasury/sandbox_screen.dart` |
| Forecast | `lib/features/treasury/forecast_chart_screen.dart` |
| Calculator | `lib/features/calculator/calculator_screen.dart` |
| Profile | `lib/features/profile/profile_screen.dart` |
| First run | `lib/features/first_run/first_run_screen.dart` |
| Settings | `lib/features/settings/settings_screen.dart` |
| Splash | `lib/features/splash/splash_screen.dart` |
| Операции | `lib/features/treasury/operations_screen.dart` |
| Диалог транзакции | `lib/features/treasury/widgets/add_transaction_dialog.dart` |
| Общие кнопки (фокус) | `lib/core/widgets/hover_button.dart` |
| CI | `.github/workflows/build.yml` |
| Android-ресурсы | `android/app/src/main/res/` |
