## Сессия 14 (RELEASE) — 2026-08-03 21:19 MSK

### ✅ Релиз v0.2.0-alpha.14 — ЗЕЛЁНЫЙ

| Проверка | Статус |
|----------|--------|
| Android APK | ✅ Собран и загружен |
| Windows ZIP | ✅ Собран и загружен |
| CI #545 | ✅ Успех |

**Релиз:** https://github.com/wesiwer/WesiOS/releases/tag/v0.2.0-alpha.14

### Что вошло в релиз

**База знаний — 26 новых статей:**
- 💰 Деньги: Долги, Страхование, Пенсия, Психология денег
- 💼 Работа: Обучение, Смена профессии, Переговоры, Удалёнка
- 🧠 Голова: Стресс, Общение, Одиночество, Сравнение
- 🎯 Привычки: Формирование, Цифровой минимализм, Решения
- 🏠 Жизнь: Дом, Отдых, Опыт vs вещи, Юридические вещи
- 🚀 Фриланс: Первые клиенты, Когда отказывать, Бухгалтерия, Стабильность
- 📋 Мета: Как пользоваться базой, Чеклист квартала

**Фиксы компиляции (session 14 fix):**
- `app_theme.dart` — восстановлен из оригинала `fbb9a26c`
- `AnimatedThemeProvider` — сделан public
- `quote_mind_charge.dart` — `AppTheme.` префиксы
- `article_editor_screen.dart` — `ListenableBuilder` с правильной сигнатурой

---

## Сессия 14 (fix) — 2026-08-03 20:02 MSK

### ✅ Исправления компиляции

| Файл | Ошибка | Фикс |
|------|--------|------|
| `lib/app.dart` | `_AnimatedThemeProvider` private | Убран `show`, класс сделан public |
| `lib/core/theme/app_theme.dart` | `_AnimatedThemeProvider` private | Переименован в `AnimatedThemeProvider` |
| `lib/core/widgets/quote_mind_charge.dart` | Цвета без `AppTheme.` | Добавлены префиксы `AppTheme.` |
| `lib/features/knowledge/screens/article_editor_screen.dart` | `QuillController` не `ValueListenable` | `ValueListenableBuilder` → `ListenableBuilder` |

---

## Сессия 14 — 2026-08-03 15:52 MSK

### ✅ Сделано

| Задача | Статус | Примечание |
|--------|--------|------------|
| База знаний: 26 новых статей | ✅ Запушено | 7 папок, 26 статей, Quill Delta JSON |
| Коммит builtin_articles.dart | ✅ | +82KB, commit 8e93dd4 |

**Новые статьи:**
- **Деньги**: Долги, Страхование, Пенсия, Психология денег
- **Работа**: Обучение без выгорания, Смена профессии, Переговоры, Удалёнка
- **Голова**: Стресс и тревога, Общение, Одиночество и круг, Сравнение с другими
- **Привычки**: Формирование привычек, Цифровой минимализм, Решения
- **Жизнь**: Дом и быт, Отдых, Опыт vs вещи, Юридические вещи
- **Фриланс**: Первые клиенты, Когда отказывать, Бухгалтерия, Выход на стабильность
- **Мета**: Как пользоваться базой, Чеклист квартала

---

# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-08-03 (сессия 13 — Windows OTA install fix)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** `main` · **UI:** v0.11.11 α · **build:** 27  

Читай этот файл **перед** любыми правками.

---

## Сессия 13 (2026-08-03) — Windows OTA: файлы не подменялись

### Симптом
Скачивание OK → приложение закрывается → снова открывается → версия старая.
Причина: `_installWindows` bat глотал ошибки `xcopy` (Defender / CFA / silent fail) и всё равно делал `start` старого exe.

### Фикс (`lib/core/services/app_update_service.dart`)
- `ensureWindowsDefenderExclusions()` — best-effort `Add-MpPreference` для exeDir + Temp + process (до exit)
- Bat: лог `%TEMP%\\wesios_update.log` на каждый шаг
- `Expand-Archive` с проверкой errorlevel
- Определение SRC: корень zip (CI `Release/*`) или одна вложенная папка
- `robocopy /E /R:5 /W:2` вместо silent xcopy
- При fail (RC≥8 или нет exe) — **не** стартовать приложение, оставить лог + zip
- Константа `windowsDefenderHelp` для UI

### Версия
- `0.11.11+27` (pubspec + AppVersion)

### Важно (куриный-яичный момент)
Текущая установленная сборка всё ещё со **старым** bat. Чтобы получить новый установщик:
1. Один раз вручную поставить zip из свежего Publish, **или**
2. Добавить папку установки + Temp в исключения Defender → попробовать OTA ещё раз (старый xcopy может пройти)

После того как 0.11.11+27 окажется на диске — дальнейшие OTA идут уже через robocopy+лог.

### Следующий шаг
- [ ] Запустить **Publish WesiOS Release** (workflow_dispatch) для 0.11.11+27
- [ ] Smoke: OTA с 0.11.10 → 0.11.11 (или ручная распаковка zip)
- [ ] При fail — читать `%TEMP%\\wesios_update.log`

---

## Сессия 11 (2026-08-02) — OTA, Windows Defender, CI на GitHub-hosted

### Версия
- `pubspec.yaml` / `AppVersion`: **0.11.10+26** (superseded by 0.11.11+27)
- OTA: постоянный тег `app-latest` + `app-manifest.json` (перезаписывается `--clobber`)
- Release workflow: `.github/workflows/release-app.yml` — только `workflow_dispatch`

### Редактор Knowledge (ArticleEditorScreen) — DONE
| Что | Файл / место | Статус |
|---|---|---|
| Toolbar + Quill 9.6 API | `lib/features/knowledge/screens/article_editor_screen.dart` | DONE |
| Спецсимволы (Word-like) | `special_chars.dart` + панель в editor | DONE |
| Emoji | `emoji_data.dart` | DONE |
| Media (image/video/audio URL+device) | `article_editor_media.dart` / helpers | DONE |
| Tables | insert table в editor | DONE |
| Charts (bar/line/pie/area) | `article_editor_charts.dart` | DONE |
| Папки / секции / теги / save | editor screen | DONE |
| **WYSIWYG embeds в editor** | `embedBuilders: knowledgeEmbedBuilders()` | DONE |
| Shared embed builders | `lib/features/knowledge/widgets/article_embeds.dart` | DONE |
| Body view использует те же builders | `article_body_view.dart` | DONE |

**Правило flutter_quill 9.6.0 / 9.3.12:**  
`QuillEditorConfigurations`, controller в configurations, `DefaultTextBlockStyle` (4 args), без EmbedContext. Не поднимать API без явного решения.

**Чего НЕ делать:** не удалять `special_chars.dart` / `emoji_data.dart` / media/charts helpers / `article_embeds.dart`.

### OTA / AppUpdateService (актуально после сессии 13)
- Механизм: `app-manifest.json` с тега `app-latest` → version+build → download → install.
- Windows: zip → bat (wait → Defender exclusion → Expand → robocopy → restart / log on fail).
- Android: signed APK → MethodChannel `wesios/updater`.

### CI / Release (GitHub-hosted, НЕ self-hosted)
**Правило:** билды **только** на `windows-2022` + `ubuntu-latest`. Self-hosted — отказ.

| Job | Runner | Артефакт |
|---|---|---|
| `version` | ubuntu-latest | version/build из pubspec |
| `build-windows` | windows-2022 | `wesios-windows-x64.zip` |
| `build-android` | ubuntu-latest | `wesios-android.apk` |
| `publish-manifest` | ubuntu-latest | `app-manifest.json` только если обе OK |

**Секреты Android:** `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

Ссылка Actions: https://github.com/wesiwer/WesiOS/actions/workflows/release-app.yml

---

## Сессия 12 — 2026-08-03

1. Релиз #51 SUCCESS (quill controller fix + assets)
2. Knowledge: labeled toolbar + insert drawer
3. QuoteMindCharge layout fix

---

## Сессия 10 (2026-08-02) — Special characters + full editor restore

| Что | Файл | Описание |
|---|---|---|
| Кнопка «Спецсимволы» | `article_editor_screen.dart` | `Icons.text_fields` в toolbar рядом с Emoji |
| Панель спецсимволов | тот же файл | высота 260, чипы категорий, сетка 12 колонок |
| Набор символов | `special_chars.dart` | 10 категорий как в Word Symbol |
| Emoji data | `emoji_data.dart` | вынесен из editor |
| Media helpers | `article_editor_media.dart` | image/video/audio, link, table |
| Chart dialog | `article_editor_charts.dart` | bar/line/pie/area |

---

## Правила для AI-агентов

1. **Релизы/билды — только по явному запросу пользователя.** Мелкие фиксы копятся в `main`.
2. **STATUS.md обновлять после каждого значимого изменения.**
3. **flutter_quill 9.3.12 / 9.6** — не ломать API (controller в configurations).
4. **Билд только на GitHub-hosted runners** — не предлагать self-hosted.
5. **Не коммитить secrets, keystore, PFX.** Только через GitHub Secrets.
6. **Не удалять** shared Knowledge helpers (`article_embeds`, special_chars, emoji_data, media/charts).

---

## Открытые / follow-up

- [ ] **Publish** workflow_dispatch для **0.11.11+27** (OTA Windows fix)
- [ ] Smoke: ручная установка zip один раз, затем OTA на следующую сборку
- [ ] Опционально: `WINDOWS_CERT_PFX` / подпись в CI (SmartScreen)
- [ ] При OTA-fail — смотреть `%TEMP%\\wesios_update.log`


## Сессия 12 — 2026-08-03 (04:50 МСК)

### Сделано
1. **Релиз #51** — ✅ SUCCESS (зелёный)
   - Исправлен `flutter_quill` 9.3.12 API: `controller` в `QuillEditorConfigurations`

2. **Редактор Knowledge** — подписи к кнопкам + выдвижной drawer
   - `_toolLabeled()` — кнопки с подписями под иконками (8px текст)
   - `_insertDrawer()` — выдвижная панель вставки медиа/таблиц/графиков
   - Медиа-кнопки (фото, видео, аудио, график, таблица) спрятаны в drawer

3. **QuoteMindCharge** — исправлен layout
   - Увеличена ширина карточки: `maxWidth: 200` → `maxWidth: 230`
   - Текст "Зарядись умными мыслями" в одну строку (убран перенос)
   - Увеличены отступы: `padding: 10,8` → `padding: 12,10`

4. **Редактор Knowledge — UX улучшения**
   - Клавиатура убирается при открытии emoji/спецсимволов, возвращается при закрытии
   - Toggle-форматирование: жирный/курсив/подчёркнутый/зачёркнутый — вкл/выкл по тапу
   - Курсор смещается после вставки emoji/спецсимвола

5. **Treasury — выбор даты**
   - `showDatePicker` в диалоге транзакции (2020-2030)
   - Будущие даты → бейдж "Запланировано" (оранжевый)
   - Дата сохраняется в транзакции

6. **Уведомления — read/unread**
   - `Alert.read` — флаг прочитанности
   - `AlertService.markAllRead()` — пометить все прочитанными
   - `AlertService.unreadCount` — ValueNotifier с числом непрочитанных
   - При открытии AlertsSheet — автоматически markAllRead
   - Бейдж "Прочитано" (зелёный) на прочитанных уведомлениях
   - Badge у колокольчика — только непрочитанные

### Коммиты
- `fix(quill): v9.3.12 API — controller in configurations, not .basic()`
- `feat(knowledge): labeled toolbar buttons + slide-out insert drawer in build()`
- `fix(quote): widen mind-charge card, fix text overflow layout`
- `feat(editor): keyboard hide/show on emoji/special chars, toggle formatting, cursor move`
- `feat(treasury): date picker in transaction dialog (past/future/planned)`
- `feat(treasury): date picker UI in dialog + date in save result`
- `fix(quote): reactive theme colors — read AppTheme inside ThemeNotifier builder`
- `feat(alerts): read/unread tracking, unreadCount notifier, markAllRead`
- `feat(alerts): auto-mark-read on open, read badge, unread-only bell badge`

### Следующий релиз
- Запустить релиз #53 для проверки всех изменений

---

## Сессия 13 — 2026-08-03 (05:37 МСК) — Калькулятор

### Сделано
1. **Калькулятор — свёрнутый бар перемещается**
   - `Positioned(left: _offset.dx, top: _offset.dy)` вместо `left/right/bottom`
   - Бар можно перетаскивать по всему экрану в свёрнутом режиме

2. **Калькулятор — единый знак деления**
   - `_isValidInput()` теперь принимает `'÷'`, `'×'`, `'−'` (юникод)
   - Раньше numpad `/` → `'÷'` → `_isValidInput('÷')` = false → игнорировалось

3. **Кнопки масштаба** — уже были в свёрнутом баре и в заголовке развёрнутого
   - Оставлены как есть (в свёрнутом баре управляют `_scale`, но он применяется только к развёрнутому виду — это ожидаемо)

### Коммиты
- `fix(calc): draggable minimized bar + unicode ops in _isValidInput`

### Следующий шаг
- Запустить релиз #54 для проверки калькулятора + всех накопленных изменений
