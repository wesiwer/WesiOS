# Wesi AI — Implementation Status

**Дата:** 2026-08-15  
**Источник требований:** `docs/WESI_AI_MASTER_SPEC.md` и связанные Wesi AI specs.  
**Правило:** этот файл фиксирует только фактически реализованное/проверенное состояние. Целевые возможности остаются в Master Spec.

## В main и проверено

Блок `Projects + Camera + AI client hardening + Large Attachments` влит в `main` через PR #153, squash commit `3c126b156a5a36b3d5a609fb22334879e91d4855`.

Реализовано:
- AI Projects: несколько чатов в проекте, «Без проекта», создание/переименование/закрепление/удаление, описание и инструкции проекта, перенос чата;
- сохранение `projectId` при внутренней передаче Зейн ↔ Нирвана;
- embedded camera внутри WesiOS с CameraPreview и Android CAMERA permission;
- безопасная миграция старого локального AI state, recovery повреждённого Hive state, orphan cleanup, согласование active project/chat;
- attachment retry с transient RAM-cache без сохранения bytes/local path в истории;
- path-backed file picker (`withData: false`) для больших файлов;
- Universal Attachments transport: до 4 файлов;
- inline transport: до 15 MiB на файл / 18 MiB суммарно;
- staged upload: до 256 MiB на файл / 512 MiB на сообщение, chunk 1 MiB;
- Main Server хранит только owner-scoped upload metadata и пересылает chunks на подписанный Relay;
- Relay собирает staged file во временном private storage и выдаёт opaque capability reference;
- staged text/archive обрабатывается bounded extractor;
- большие image/audio/video/PDF передаются Gemini через Files API;
- provider files и staged temp files очищаются после успешного ответа и ошибок;
- staged storage resource protection: максимум 32 активные upload-сессии и 1 GiB суммарно заявленного активного staged storage на Relay;
- `WAI_UPLOAD_CAPACITY` возвращает контролируемую ошибку вместо бесконтрольного заполнения диска.

Проверки для этого блока:
- Node/Relay test suite — green;
- staged upload assembly/capability/cleanup/capacity regression tests — green;
- `flutter analyze` — green;
- Flutter tests — green;
- Android debug build — green;
- Windows release build — green до последних server-only resource-limit правок; после этих правок Flutter source не менялся;
- signed production release workflow автоматически запущен на `main` после merge и отслеживается отдельно.

## Внешний production blocker

`ai.wesi-wf.su` пока нельзя считать production-ready end-to-end из-за внешнего DNS.

Наблюдаемое состояние на момент фиксации:
- в панели AEZA домен `wesi-wf.su` активен;
- настроены NS `a.aeza-dns.net` / `b.aeza-dns.net`;
- создана A-запись `ai -> 178.236.247.194`;
- публичные DNS ранее возвращали `NXDOMAIN` для `wesi-wf.su` / `ai.wesi-wf.su`;
- Let's Encrypt из-за этого не может выпустить HTTPS-сертификат;
- локальный Relay на сервере уже проходил health-check, поэтому текущий blocker находится до HTTPS/Relay — на уровне публичной DNS-делегации/публикации зоны.

До исправления AEZA нельзя считать завершёнными production E2E проверки `Fast / Pro / Ultra` через публичный `https://ai.wesi-wf.su`.

После появления публичного DNS выполнить последовательно:
1. проверить authoritative/public DNS;
2. выпустить/проверить TLS certificate;
3. проверить `https://ai.wesi-wf.su/health`;
4. проверить Main Server -> Relay signed path;
5. провести реальные текстовые smoke-tests Fast / Pro / Ultra;
6. провести attachment smoke-tests: image, PDF, Markdown, archive и staged large file;
7. проверить retry/error UX с телефона и desktop.

## Отложено до стабилизации обычного чата

Тяжёлый агентный слой сейчас намеренно не считается следующим обязательным production-блоком. После стабильного ordinary chat / attachments / projects вернуться к:
- Local Runtime / Remote Worker;
- Runtime Packs и Environment Scanner;
- terminal/tools/self-debug;
- connectors;
- Persona Co-Agent handoff;
- dynamic subagents;
- тяжёлым media pipelines.

PR #149 (`feat(ai): add local runtime and remote worker foundation`) оставлен как отложенная работа. Он был stacked поверх старого PR #148; перед продолжением тяжёлого блока его изменения нужно перенести/перебазировать на актуальный `main`, а не мержить старый stack как есть.

PR #148 закрыт как superseded PR #153.
