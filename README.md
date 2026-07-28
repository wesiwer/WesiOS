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
- Treasury (продажа/траты, multi-currency, delete)
- Sandbox (изолированные сценарии, без «Сценарий:» в баннере)
- Forecast P10/P50/P90 без дёрганья при смене периода
- Calculator pin/ESC/Delete/blur
- Profile auto-save + Firebase tips
- Settings locale live
- Live avatars (Hive listenable)

### Очередь
- Upload custom avatar, calendar range в forecast
- Edit транзакций, operations screen
- Keyboard arrow navigation
- Tasks/Analytics/CRM deep features

Полный чеклист и правила для AI → **STATUS.md**

## Сборка

```bash
flutter pub get
flutter build windows --release
flutter build apk --release
```

CI: push в `main` → GitHub Actions (Windows + Android).

## Версия

v0.1.2 α — Private, Wesi Inc.
