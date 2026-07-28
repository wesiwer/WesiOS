# WesiOS — статус для AI-агентов

**Обновлено:** 2026-07-28  
**Репо:** https://github.com/wesiwer/WesiOS  
**Ветка:** main  
**Версия UI:** v0.1.2 α

Этот файл — единый источник правды: что уже сделано, что в работе, что нельзя ломать.

---

## Архитектурные решения (не «баги»)

1. **SandboxService ≠ TreasuryService** — намеренное дублирование. Песочница работает на вымышленных данных и не трогает реальные транзакции.
2. **Валюта хранится в RUB-эквиваленте**, отображение через `CurrencyService.fromRub` / `toRub`.
3. **Кастомный title bar** (`WindowControls`) — системный title bar скрыт (`TitleBarStyle.hidden`).
4. **Курсы** — `ExchangeRateService` тянет exchangerate.host при старте; fallback — зашитые курсы.

---

## ✅ Сделано

### Окно / desktop
- [x] Кастомный title bar без лого/надписи WesiOS
- [x] Minimize / maximize / close с мгновенным откликом (`Listener`)
- [x] Drag-зона отдельно от кнопок окна
- [x] Старт: maximize (не true-fullscreen — на Windows глючит)
- [x] Кнопка валюты не перекрывает close (padding right: 140)

### Splash
- [x] Яркий оранжевый ambient glow
- [x] Убрана центральная W
- [x] Кольца толще/меньше, **ниже** progress bar

### Home
- [x] Bottom tabs → IndexedStack (Tasks / Treasury / Analytics / Settings сразу, без placeholder)
- [x] Кнопки «Продажа» / «Траты»
- [x] Лого: hover-карточка справа, без мерцания (`IgnorePointer` на overlay)

### Treasury
- [x] Кнопки действий: **Продажа** / **Траты** (не «Всего доходов»)
- [x] Категории на русском при RU-локали
- [x] Удаление транзакций
- [x] Multi-currency cycle (RUB/USD/EUR/GBP/CNY/UAH/BYN/KZT)
- [x] Отображение баланса в выбранной валюте
- [x] Вход в Sandbox и Forecast

### Sandbox
- [x] Изолированные данные, сценарии (startup/freelancer/crisis/clone)
- [x] Удаление транзакций
- [x] Баннер без слова «Сценарий:» (только режим + изоляция)
- [x] Намеренное дублирование сервиса

### Forecast
- [x] P10/P50/P90 + тултипы
- [x] Смена периода **без** полноэкранного лоадера (только график)
- [x] Тогглы диапазон / полосы / тренд реально влияют на chart
- [x] Даты на оси X
- [x] Аномалии на русском

### Calculator
- [x] ESC закрывает (если не pinned)
- [x] Delete очищает
- [x] Pin / blur on-off / drag / scale
- [x] Без тяжёлого BackdropFilter в роутере (плавный fade)

### Profile
- [x] Автосейв всех полей (debounce 600ms)
- [x] Подсказки где взять Firebase-ключи
- [x] Выбор пресет-аватарок
- [x] Live-аватар через ValueListenableBuilder (без рестарта)

### Settings
- [x] Все строки через WesiLocale
- [x] Смена языка → setState, UI обновляется на месте

### Валюты / курсы
- [x] 8 валют в CurrencyService
- [x] ExchangeRateService при старте

### Локализация
- [x] WesiLocale ru/en, ключи в Hive

### Прочее
- [x] Hover flicker лого пофикшен

---

## 🔄 В очереди / частично

- [ ] **Upload своей аватарки** (кнопка есть, file_picker ещё не подключён до конца)
- [ ] **Календарь ручного диапазона** в Forecast (chips 7/14/30/60/90 есть)
- [ ] **Продажа/Траты с Home** → сразу диалог добавления (сейчас открывает `/treasury`)
- [ ] **Клавиатура**: стрелки между кнопками UI
- [ ] **Редактирование** транзакции (delete есть, edit нет)
- [ ] **Отдельный экран всех операций** с фильтрами
- [ ] Курсы: при отсутствии сети — только fallback (ок); UI «обновлено в …» нет
- [ ] Tasks / Analytics / CRM / Roadmap — в основном заглушки
- [ ] Голосовой ввод, Command Palette, Privacy Mode — не начаты

---

## ⚠️ Известные ограничения среды

- CI/local build Windows: CMake deprecation warning (не блокер)
- True fullscreen на Windows не используем
- Firebase Auth/Firestore на desktop Windows ограничен

---

## Правила для следующего AI

1. **Не удалять** дублирование Sandbox/Treasury.
2. **Не возвращать** лого в title bar.
3. **Не ставить** `MainAxis.min` — только `MainAxisSize.min`.
4. Overlay-тултипы всегда с `IgnorePointer`.
5. При смене периода Forecast — **не** ставить `_isLoading = true` на весь экран.
6. После крупных UI-правок — обновить **этот** STATUS.md.
7. Коммиты в `main` через GitHub API / push; пользователь гоняет билды сам.

---

## Ключевые пути

| Что | Файл |
|-----|------|
| Title bar | `lib/core/widgets/window_controls.dart` |
| Валюта | `lib/core/services/currency_service.dart` |
| Курсы | `lib/core/services/exchange_rate_service.dart` |
| Локаль | `lib/core/localization/wesi_locale.dart` |
| Аватар | `lib/core/widgets/wesi_avatar.dart` |
| Treasury UI | `lib/features/treasury/treasury_screen.dart` |
| Sandbox UI | `lib/features/treasury/sandbox_screen.dart` |
| Forecast | `lib/features/treasury/forecast_chart_screen.dart` |
| Calculator | `lib/features/calculator/calculator_screen.dart` |
| Profile | `lib/features/profile/profile_screen.dart` |
| Home | `lib/features/home/home_screen.dart` |
