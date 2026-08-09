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
- Treasury Dashboard — реальные баланс/KPI/операции, поиск, recurring, anomalies,
  Treasury Signals и 30-дневный P10/P50/P90 forecast без demo-цифр
- Регулярные Treasury-операции автоматически материализуются при запуске и
  возврате WesiOS из background; single-flight/throttle исключают дубли
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
- Audio Vault — архив битов, локальный player/FFT, аренды и календарные сроки,
  Ableton `.als` links, Music Hub/Spotify Connect и локальная ветвь
  Wesi AI Audio Quick Analysis v2
- Audio Vault quick actions — `ALS` открывает проект прямо из карточки архива,
  `AI <score>` запускает/показывает локальный анализ, верхняя AI-кнопка пакетно
  анализирует все новые или изменённые WAV без актуального отчёта
- Mobile Audio Vault — одна читаемая колонка на узких экранах и переносимый
  footer MP3/WAV/TRACK/ALS/AI без RenderFlex overflow
- Calendar — Month/Week/Year, собственные события CRUD, all-day/длительность,
  daily/weekly/monthly/yearly repeat, системные напоминания, реальные дедлайны
  Tasks и recurring Treasury; собственные события синхронизируются между
  WesiOS-устройствами
- Time Center по нажатию на часы Home — device-local будильники, напоминания,
  persistent timer и секундомер с кругами; расписания восстанавливаются на
  launch/resume. Android scheduled notifications переживают process death/reboot;
  Windows регистрирует будущие срабатывания в Task Scheduler и запускает WesiOS
  в notification-only режиме, поэтому будильник/напоминание работают и при
  закрытом обычном окне приложения
- Knowledge Base linked charts — `forecast`/`analytics`/`treasury` получают
  реальные данные WesiOS вместо захардкоженных demo-серий
- Home mobile — безопасный avatar/Hive bootstrap, компактная шапка и адаптивные
  GlassCard-заголовки/действия; regression test покрывает Android 360×800
- Profile auto-save, custom avatar, защищённый вход и управление активными сеансами
- Обязательная почта сотрудника и двухэтапный вход: пароль → 6-значный код по email
- Отзывные WesiOS-сеансы: удалённое завершение и автоматический выход при удалении сотрудника
- Remembered auth token + WesiOS session ID хранятся в platform secure storage; legacy plaintext Hive session мигрируется и удаляется
- Android launcher icon привязан к реальному WesiOS resource на всех поддерживаемых API
- Windows fresh install: Inno Setup `wesios-windows-x64-setup.exe`, smoke-tested install/uninstall
- Windows auto-update: portable ZIP остаётся отдельным совместимым каналом для встроенного updater
- Production release pipeline: signed Android + Windows ZIP → GitHub `app-latest` → PocketBase `pb_public/artifacts` → публичная проверка → Windows installer
- Settings locale live (пересобирает все вкладки)
- Live avatars (Hive listenable)

### Внешний production-блокер
- Self-hosted Postfix/OpenDKIM уже подняты, исходящий TCP/25 открыт, PTR настроен. Осталось опубликовать DNS для `mail.wesi-inc.ru` (A/SPF/DKIM/DMARC), после чего workflow `Activate WesiOS Local Mail` проверит DNS/transport и fail-closed включит PocketBase SMTP на локальный Postfix. Подробности → `SECURITY_STATUS.md`.

### Очередь
- Tasks/Analytics/CRM deep features

Полный чеклист и правила для AI → **STATUS.md**

## Сборка

```bash
flutter pub get
flutter build windows --release
flutter build apk --release
```

Обычный CI: push/PR → GitHub Actions (analyze/tests + Windows + Android).

### Production release

Единственная каноническая точка production-выпуска:

**GitHub Actions → `Publish WesiOS Production`** (`.github/workflows/publish-wesios-production.yml`).

Она делает полный цикл:

1. вызывает низкоуровневый `Publish WesiOS Release` с `deploy_to_server=false`;
2. собирает подписанный Android APK и Windows portable ZIP;
3. обновляет GitHub Release `app-latest` и `app-manifest.json`;
4. скачивает ровно опубликованные assets;
5. выкладывает ZIP/APK в `/opt/pocketbase/pb_public/artifacts`;
6. проверяет публичный `https://api.wesi-inc.ru/artifacts/app/app-manifest.json` и размеры Windows/Android файлов;
7. запускает `Publish WesiOS Windows Installer`;
8. собирает Inno Setup `wesios-windows-x64-setup.exe`, делает silent install/uninstall smoke-test, публикует installer в `app-latest` и PocketBase и проверяет публичный файл.

**Важно:** `app-manifest.json` для Windows продолжает указывать на ZIP, потому что встроенный `AppUpdateService` обновляет текущую установку через `Expand-Archive`. `.exe` — отдельный fresh-install канал; это не ломает существующее автообновление.

`release-app.yml` остаётся внутренним builder-workflow. Для обычного production release запускайте `Publish WesiOS Production`, а не его legacy server-deploy ветку.

## Версия

v0.19.14 α — Private, Wesi Inc.
