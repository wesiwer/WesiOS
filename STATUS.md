# WesiOS — STATUS / ТЗ для AI-агентов

**Обновлено:** 2026-08-02 (сессия 10 — полный restore редактора Knowledge + спецсимволы)  
**Репо:** https://github.com/wesiwer/WesiOS · **ветка:** `main` · **UI:** v0.11.9 α · **build:** 25  

Читай этот файл **перед** любыми правками.

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

**Статус редактора:** полностью восстановлен (форматирование, emoji, спецсимволы, медиа, таблицы, графики, папки, секции, теги, сохранение). Leftover `article_editor_part_a.dart` (PLACEHOLDER) удалён.

**Чего НЕ делать:** не удалять `special_chars.dart` / `emoji_data.dart` / media/charts helpers; билд только по запросу.

---

## Правило: релизы/билды — только по запросу пользователя

Мелкие фиксы накапливаем в main. Release — только по явному запросу.

## Правило: журнал STATUS.md вести всегда

После каждого изменения обновлять этот файл.

## Правило: flutter_quill 9.6.0

Старый API: `QuillEditorConfigurations`, `DefaultTextBlockStyle` (4 args), без EmbedContext.
