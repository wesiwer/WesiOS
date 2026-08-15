# Wesi AI — Important Chat Backup + Encrypted LAN/Wi‑Fi D2D

**Статус:** normative  
**Дата:** 2026-08-15  
**Этап:** 4/16

## 1. Цель

Пользователь должен явно отметить важные чаты Wesi AI и иметь два независимых способа сохранить их:

1. локальный зашифрованный backup-файл;
2. прямой зашифрованный перенос между двумя устройствами WesiOS в одной LAN/Wi‑Fi сети.

Перенос и backup обязаны включать не только текст сообщений, но и связанный AI context:
- выбранные важные conversations;
- сообщения этих conversations;
- rolling summary и task state этих conversations;
- долговременную memory, необходимую для сохранения контекста;
- связанные AI Projects;
- локальные артефакты сообщений, когда файл реально существует на устройстве и проходит лимиты безопасности.

Smart Queue/pending operations в backup не включаются: переносить незавершённые execution requests между устройствами опасно и семантически неверно.

## 2. Явное включение

Backup не должен молча копировать все диалоги.

У conversation появляется backward-compatible флаг `importantForBackup=false`.
Пользователь сам включает/выключает его из UI.

Экспорт Important Backup должен завершаться понятной ошибкой, если ни один чат не отмечен.

## 3. Канонический пакет

До шифрования данные собираются в один versioned package:

- `manifest.json`;
- `artifacts/...` — реальные бинарные файлы без base64-дублирования в history.

Формат package — ZIP только как контейнер. ZIP никогда не считается trust boundary: import обязан проверять имена entries, размер, количество файлов и запрещать absolute path / `..` / traversal.

Manifest содержит:
- schema/version;
- employeeId;
- createdAt;
- projects;
- conversations;
- messages;
- memoryEntries;
- memorySettings;
- conversationMemory;
- artifact mapping.

Только manifest определяет, к какому conversation/message относится artifact.

## 4. Изоляция сотрудника

Backup/D2D относится к тому же WesiOS employee account.

Import обязан fail-closed, если `employeeId` package не совпадает с текущим employeeId. Нельзя автоматически перепривязывать чужие AI chats/memory к текущему сотруднику.

## 5. Local backup encryption

Файл backup на диске всегда зашифрован.

- encryption: AES-256-GCM;
- key derivation: PBKDF2-HMAC-SHA256;
- отдельная случайная salt на каждый backup;
- отдельный 96-bit nonce на каждый ciphertext;
- passphrase не сохраняется в Hive/metadata/файл;
- AES-GCM authentication failure = import failure без partial merge.

Формат ciphertext versioned и имеет magic header, чтобы приложение не пыталось расшифровывать случайный файл.

## 6. D2D encryption

LAN/Wi‑Fi discovery не является доверием.

Sender создаёт одноразовую transfer session:
- случайный sessionId;
- случайный 256-bit session key;
- TTL максимум 10 минут;
- одно успешное скачивание;
- после success/expiry listener закрывается, ключ забывается.

Canonical package шифруется AES-256-GCM session key до отправки в сеть. Plaintext package по HTTP не передаётся.

Receiver получает out-of-band transfer descriptor, содержащий:
- private-LAN sender address;
- ephemeral port;
- sessionId;
- one-time key;
- короткий fingerprint для визуальной проверки.

Request к sender дополнительно аутентифицируется HMAC-SHA256 от sessionId/session key. Простое угадывание URL не должно выдавать ciphertext.

## 7. LAN boundary

Sender слушает ephemeral port только на время transfer session.

Допустимый network path:
- loopback для тестов;
- RFC1918 IPv4/private LAN addresses;
- link-local/private device environment, если платформа возвращает такой адрес безопасно.

Публичный relay/VPS для Stage 4 не нужен: это именно D2D.

## 8. Artifact policy

В package попадают только реальные local artifacts, явно связанные с selected messages через trusted local metadata.

Обязательные ограничения:
- regular file only;
- canonical path читается приложением, но в package сохраняется только safe basename + generated artifact id;
- один artifact ≤ 64 MiB;
- суммарно artifacts ≤ 256 MiB;
- максимум 128 artifacts;
- symlink/traversal/absolute archive paths не допускаются;
- импорт пишет файлы только в managed Wesi AI import directory внутри application documents/support storage.

Удалённые HTTP media URLs не скачиваются автоматически ради backup.

## 9. Merge policy

Import не должен стирать локальные данные.

- project/conversation/message IDs merge-ятся идемпотентно;
- при совпадении conversation ID выбирается более свежая metadata, а `importantForBackup` объединяется через OR;
- messages dedup по message ID;
- memory entries dedup по id и нормализованному scope/text;
- более новая memory entry сохраняет приоритет, pinned/manual не теряются;
- per-chat memory state выбирается по большему `summarizedMessageCount`, если оба валидны;
- imported local artifact path заменяет только путь соответствующего imported message;
- pending Smart Queue не импортируется.

Повторный импорт того же package не должен дублировать чаты/сообщения/память.

## 10. UI

Минимальные пользовательские действия:
- отметить/снять «Важный backup» у чата;
- создать encrypted backup важных чатов;
- импортировать encrypted backup;
- запустить «Передать по Wi‑Fi/LAN»;
- принять transfer descriptor и импортировать D2D package;
- видеть TTL/fingerprint/статус transfer session.

Backup/D2D не должен запускать production deploy или server release.

## 11. Regression gates

Перед merge Stage 4:
- crypto roundtrip + wrong-passphrase/tamper rejection;
- package traversal/size/employee isolation tests;
- idempotent merge tests;
- artifact path restore test;
- D2D one-time/TTL/auth tests;
- Important-only selection test;
- existing Memory Engine + Smart Queue regressions;
- full `flutter analyze` + full `flutter test`;
- Android debug APK build;
- Windows release build.
