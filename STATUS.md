# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-08-02 (сессия 11 — OTA + CI + редактор Knowledge)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** `main` · **UI:** v0.11.10 α · **build:** 26  

Читай этот файл **перед** любыми правками.

---

## Сессия 11 (2026-08-02) — OTA, Windows Defender, CI на GitHub-hosted

### Версия
- `pubspec.yaml` / `AppVersion`: **0.11.10+26**
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

**Правило flutter_quill 9.6.0:**  
`QuillEditorConfigurations`, `DefaultTextBlockStyle` (4 args), без EmbedContext. Не поднимать API без явного решения.

**Чего НЕ делать:** не удалять `special_chars.dart` / `emoji_data.dart` / media/charts helpers / `article_embeds.dart`; leftover PLACEHOLDER part-файлы уже удалены.

### OTA / AppUpdateService
- Механизм: чтение `app-manifest.json` с тега `app-latest` → сравнение version+build → download asset → install.
- Windows: portable zip → `.bat` (ждёт exit процесса → Expand-Archive → xcopy поверх exeDir → restart).
- Android: signed APK → MethodChannel `wesios/updater` → системный installer.
- Репозиторий публичный; auth headers через `GitHubAuthService` (для приватных сценариев).

### Windows Defender / SmartScreen (проблема обновления)
**Симптом:** OTA на Windows падал с Access Denied / блокировкой файлов (Controlled Folder Access, Defender real-time) или SmartScreen на неподписанный exe.

**Решение (частично в коде / в плане):**
1. **Defender exclusions (UAC):**  
   - Скрипт: `scripts/windows/add-defender-exclusion.ps1`  
   - Исключения: каталог установки приложения, Temp, процесс WesiOS.  
   - Вызов: `AppUpdateService.ensureWindowsDefenderExclusions()` перед `_installWindows` (если ещё не влит — добавить).  
   - При Access Denied — показывать `windowsDefenderHelp` с инструкцией.
2. **Authenticode (опционально в CI):**  
   - Скрипт: `scripts/windows/sign-windows-release.ps1` (`signtool` + RFC3161 timestamp).  
   - Secrets: `WINDOWS_CERT_PFX`, `WINDOWS_CERT_PASSWORD`.  
   - Без секретов подпись пропускается; пользователь может «Подробнее → Выполнить в любом случае».
3. **Постоянное:** без code signing SmartScreen будет периодически мешать — это известный trade-off portable unsigned builds.

### CI / Release (GitHub-hosted, НЕ self-hosted)
**Правило:** билды **только на серверах GitHub** (`windows-2022` + `ubuntu-latest`). Self-hosted / локальный runner на ПК пользователя — **отказ** (ошибки runner, нестабильность).

| Job | Runner | Артефакт |
|---|---|---|
| `version` | ubuntu-latest | version/build из pubspec |
| `build-windows` | windows-2022 | `wesios-windows-x64.zip` → Release + artifact |
| `build-android` | ubuntu-latest | `wesios-android.apk` (signed keystore secrets) |
| `publish-manifest` | ubuntu-latest | `app-manifest.json` только если обе сборки OK |

**Секреты Android (обязательны):**  
`ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`

**Недавние CI-фиксы:**  
- Android перенесён на `ubuntu-latest` (не Windows).  
- Разделение bash (ubuntu) / PowerShell (windows).  
- `clean: false`, `fetch-depth: 1` на checkout.  
- SDK licenses / keystore verify через keytool.  
- Windows: wipe stub `windows/` → `flutter create --platforms=windows`.

**Статус релизов (2026-08-02 вечер):**  
- #44 (0.11.10+26, commit version bump) — failure (старый yml).  
- #45 (после CI-фиксов runner/Android) — in progress / проверять.  
- Успешные прецеденты OTA: #26, #24, #23…

Ссылка Actions: https://github.com/wesiwer/WesiOS/actions/workflows/release-app.yml

---

## Сессия 10 (2026-08-02) — Special characters + full editor restore

| Что | Файл | Описание |
|---|---|---|
| Кнопка «Спецсимволы» | `article_editor_screen.dart` | `Icons.text_fields` в toolbar рядом с Emoji |
| Панель спецсимволов | тот же файл | высота 260, чипы категорий, сетка 12 колонок, mutually exclusive с emoji |
| Набор символов | `special_chars.dart` | 10 категорий как в Word Symbol |
| Emoji data | `emoji_data.dart` | вынесен из editor |
| Media helpers | `article_editor_media.dart` | image/video/audio (URL + device), link, table |
| Chart dialog | `article_editor_charts.dart` | bar/line/pie/area, manual + linked sources |

**Категории спецсимволов:** Пунктуация · Валюта · Математика · Стрелки · Греческий · Латиница · Кириллица · Бизнес/Право · Фигуры · Разное

---

## Правила для AI-агентов

1. **Релизы/билды — только по явному запросу пользователя.** Мелкие фиксы копятся в `main`.
2. **STATUS.md обновлять после каждого значимого изменения.**
3. **flutter_quill 9.6.0** — не ломать API (см. выше).
4. **Билд только на GitHub-hosted runners** — не предлагать self-hosted / локальный runner на ПК.
5. **Не коммитить secrets, keystore, PFX.** Только через GitHub Secrets.
6. **Не удалять** shared Knowledge helpers (`article_embeds`, special_chars, emoji_data, media/charts).

---

## Открытые / follow-up

- [ ] Дождаться успешного Publish WesiOS Release для 0.11.10+26 → проверить OTA в приложении.
- [ ] Убедиться, что `ensureWindowsDefenderExclusions` + help-текст реально в `app_update_service.dart` и вызываются перед install (если нет — долить).
- [ ] Опционально: добавить `WINDOWS_CERT_PFX` / `WINDOWS_CERT_PASSWORD` и шаг подписи в `release-app.yml`.
- [ ] После зелёного релиза — smoke: Windows zip install + Android APK update.
