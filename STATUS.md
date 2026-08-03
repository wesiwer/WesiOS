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
