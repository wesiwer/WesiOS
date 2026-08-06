# WesiOS

**WesiOS** — Business Operating System для Wesi Inc.

> Актуальный прогресс для людей и AI: см. **[STATUS.md](STATUS.md)**

## Основатель

**Байдин Владислав Евгеньевич (Wesi)**

## Стек

- Flutter 3.19+ / Dart
- Firebase Core (config из профиля)
- Hive (offline-first)
- window_manager (кастомный title bar)
- fl_chart, math_expressions, http

## Быстрый статус (кратко)

### Готово
- Desktop window controls, splash, home IndexedStack
- Treasury/Sandbox (продажа/траты, multi-currency, edit/delete, identical engine)
- Forecast — bootstrap Monte-Carlo с сезонностью по дню недели и проекцией
  регулярных платежей, P10/P50/P90 без дёрганья при смене периода;
  Cash Gap Risk Score, What-If сценарии, DCF-дисконтирование
- Мульти-движковый прогноз: Wesi Horizon (родной) / Prophet / SARIMAX —
  независимые тумблеры, режим сравнения (график+таблица), Combined-режим
  (среднее по посчитавшимся движкам). Windows-only, устанавливаются по
  требованию (баннер на Forecast + раздел в Settings) — скачивание с
  прогресс-баром/скоростью/этапами, плавающий индикатор поверх всех экранов
- Operations screen (поиск/фильтр/сортировка/edit)
- Calculator: global overlay, pin/ESC/Delete/blur/resize
- Profile auto-save + Firebase tips, upload custom avatar
- Settings locale live (пересобирает все вкладки)
- Live avatars (Hive listenable)

### Очередь
- Tasks/Analytics/CRM deep features
- Автоматический запуск processRecurringPayments (сейчас доступен, но нигде не вызывается)

Полный чеклист и правила для AI → **STATUS.md**

## Сборка

```bash
flutter pub get
flutter build windows --release
flutter build apk --release
```

CI: push в `main` → GitHub Actions (Windows + Android).

## Версия

v0.19.1 α — Private, Wesi Inc.
