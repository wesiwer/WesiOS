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

### 3. Настройка Firebase

1. Скачай `google-services.json` из Firebase Console
2. Помести файл в `android/app/google-services.json`

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

## Структура папок

```
WesiOS/
├── android/              # Android-конфигурация
├── windows/              # Windows-конфигурация
├── lib/                  # Исходный код Dart
├── assets/               # Ресурсы (изображения, аудио, шрифты)
├── .github/workflows/    # CI/CD конфигурация
├── pubspec.yaml          # Зависимости
└── README.md             # Документация
```

## Решение проблем

### Ошибка: `google-services.json` не найден

Скачай файл из Firebase Console и помести в `android/app/`.

### Ошибка сборки Windows

Убедись, что установлен Visual Studio 2022 с компонентом "Desktop development with C++".

### Ошибка сборки Android

Убедись, что:
1. Android SDK установлен
2. Переменная окружения `ANDROID_HOME` настроена
3. Приняты лицензии: `flutter doctor --android-licenses`
