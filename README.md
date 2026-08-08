# WesiOS

**WesiOS** — Business Operating System для Wesi Inc.

> Актуальный прогресс для людей и AI: см. **[STATUS.md](STATUS.md)**  
> Авторизация, email OTP, сеансы и production-блокеры: **[SECURITY_STATUS.md](SECURITY_STATUS.md)**

## Основатель

**Байдин Владислав Евгеньевич (Wesi)**

## Стек

- Flutter 3.19+ / Dart
- Firebase Core (production-конфигурация поставляется со сборкой; ручного ввода ключей нет)
- Hive (offline-first; auth token/session ID в Hive не хранятся)
- flutter_secure_storage (remembered WesiOS session)
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
- Profile auto-save, custom avatar, защищённый вход и управление активными сеансами
- Обязательная почта сотрудника и двухэтапный вход: пароль → 6-значный код по email
- Отзывные WesiOS-сеансы: удалённое завершение и автоматический выход при удалении сотрудника
- Remembered auth token + WesiOS session ID хранятся в platform secure storage; legacy plaintext Hive session мигрируется и удаляется
- Android launcher icon привязан к реальному WesiOS resource на всех поддерживаемых API
- Windows release поддерживает установщик вместо ручной распаковки ZIP
- Settings locale live (пересобирает все вкладки)
- Live avatars (Hive listenable)

### Внешний production-блокер
- Логика email OTP и server hooks опубликованы, но на production пока нет рабочего SMTP/sendmail/mail API credential. Авторизация намеренно fail-closed до подключения реального почтового провайдера. Подробности → `SECURITY_STATUS.md`.

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

v0.19.8 α — Private, Wesi Inc.
