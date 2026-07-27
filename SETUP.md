# Настройка окружения для разработки

## Требования

- [Flutter SDK 3.19+](https://docs.flutter.dev/get-started/install)
- [Android Studio](https://developer.android.com/studio) (для Android)
- [Visual Studio 2022](https://visualstudio.microsoft.com/) с "Desktop development with C++" (для Windows)
- [Git](https://git-scm.com/)

## Установка

### 1. Клонирование репозитория

```bash
git clone https://github.com/wesiwer/WesiOS.git
cd WesiOS
```

### 2. Установка зависимостей

```bash
flutter pub get
```

### 3. Первый запуск (Firebase)

При первом запуске приложение покажет экран **«Первоначальная настройка»**.

Введи данные из Firebase Console → Project Settings → Your apps → Web app (firebaseConfig):
- API Key
- App ID
- Project ID
- Messaging Sender ID

(опционально: Auth Domain, Storage Bucket, Measurement ID)

Данные сохраняются в защищённое хранилище устройства.

Можно нажать **«Пропустить (локальный режим без Firebase)»** — приложение запустится без бэкенда.

Для Android всё ещё можно положить `google-services.json` в `android/app/` (fallback).

### 4. Сборка

**Windows:**
```bash
flutter build windows --release
```
Исполняемый файл: `build/windows/x64/runner/Release/WesiOS.exe`

**Android:**
```bash
flutter build apk --release
```
APK файл: `build/app/outputs/flutter-apk/app-release.apk`

**Запуск в dev:**
```bash
flutter run -d windows
# или
flutter run -d android
```

## Структура папок

```
WesiOS/
├── android/              # Android-конфигурация
├── windows/              # Windows-конфигурация
├── lib/                  # Исходный код Dart
│   ├── core/             # theme, routes, services
│   ├── features/         # экраны
│   └── widgets/
├── assets/               # Ресурсы
├── .github/workflows/    # CI/CD
├── pubspec.yaml
└── README.md
```

## Решение проблем

### Приложение не стартует / белый экран
1. `flutter pub get`
2. `flutter clean && flutter pub get`
3. Проверь, что Visual Studio C++ установлен (для Windows)

### Firebase не инициализируется
- На первом запуске введи корректные данные Web app из Firebase Console
- Или нажми «Пропустить» для локального режима

### Ошибка сборки Windows
Убедись, что установлен Visual Studio 2022 с компонентом "Desktop development with C++".

### Ошибка сборки Android
1. Android SDK установлен
2. `ANDROID_HOME` настроен
3. `flutter doctor --android-licenses`
