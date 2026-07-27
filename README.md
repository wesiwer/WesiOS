# WesiOS

**WesiOS** — Business Operating System для Wesi Inc.

Кроссплатформенное приложение на Flutter для управления бизнесом, финансами, задачами и командой.

## Основатель

**Байдин Владислав Евгеньевич (Wesi)**

> «Система, которая помогает менять мир!»

## Платформы

| Платформа | Статус | Формат |
|-----------|--------|--------|
| Windows | ✅ Готово | `.exe` |
| Android | ✅ Готово | `.apk` |
| iOS | 🔄 Планируется | `.ipa` |
| macOS | 🔄 Планируется | `.app` |

## Технологический стек

- **Flutter 3.19+** (Dart) — кроссплатформенный UI
- **Firebase** — Authentication, Firestore Database
- **Hive** — локальное кэширование (Offline-First)
- **Telegram Bot API** — персонализированные уведомления
- **GitHub Actions** — автоматическая сборка

## Архитектура проекта

```
lib/
├── core/
│   ├── theme/           # Темы и стили
│   └── routes/          # Навигация
├── features/
│   ├── splash/          # Заставка
│   ├── home/            # Главный экран
│   ├── auth/            # Авторизация
│   ├── treasury/        # Финансовый кабинет (Wesi Treasury)
│   ├── tasks/           # Система задач
│   ├── roadmap/         # Диаграмма Ганта
│   ├── analytics/       # Визуальная аналитика
│   ├── knowledge/       # База знаний
│   ├── settings/        # Настройки
│   ├── calculator/      # Калькулятор
│   ├── audio/           # Audio Vault (биты)
│   ├── crm/             # База клиентов
│   ├── calendar/        # Календарь
│   └── founder/         # История основателя
├── widgets/             # Общие виджеты
└── main.dart            # Точка входа
```

## Функционал

### ✅ Реализовано

- [x] Splash screen с анимацией и загрузочными фразами
- [x] Главный экран с балансом и быстрыми действиями
- [x] Навигация с glassmorphism-эффектами
- [x] Тёмная монохромная тема
- [x] Калькулятор
- [x] Экран истории основателя (ПКМ на логотип)
- [x] GitHub Actions для авто-сборки

### 🔄 В разработке

- [ ] Wesi Treasury (финансовый кабинет)
- [ ] Wesi Shield (AI-автопилот)
- [ ] Система задач (Kanban, Эйзенхауэр)
- [ ] Диаграмма Ганта
- [ ] Аналитика и графики
- [ ] База знаний
- [ ] Audio Vault
- [ ] CRM
- [ ] Telegram-уведомления
- [ ] Голосовой ввод
- [ ] Command Palette (Ctrl+K)
- [ ] Privacy Mode
- [ ] Офлайн-режим
- [ ] AI-ассистент

## Сборка

### Локальная сборка

```bash
# Получить зависимости
flutter pub get

# Сборка для Windows
flutter build windows --release

# Сборка для Android
flutter build apk --release
```

### Автоматическая сборка (GitHub Actions)

При каждом пуше в `main` ветку:
- Собирается `.exe` для Windows
- Собирается `.apk` для Android
- Артефакты доступны в разделе Actions

## Настройка Firebase

1. Создай проект в [Firebase Console](https://console.firebase.google.com)
2. Зарегистрируй Android-приложение (`com.wesi.wesios`)
3. Скачай `google-services.json` и помести в `android/app/`
4. Включи Authentication (Email/Password) и Firestore

## Настройка Telegram

1. Создай бота через [@BotFather](https://t.me/BotFather)
2. Получи Bot Token
3. Добавь токен в переменные окружения или код

## Версия

**v0.1 α** — Начальная версия

## Лицензия

Private — все права принадлежат Wesi Inc.
