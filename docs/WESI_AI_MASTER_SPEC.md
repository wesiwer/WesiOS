# Wesi AI — Master Specification

**Статус:** обязательное целевое ТЗ, реализация поэтапная.  
**Дата фиксации:** 2026-08-15.  
**Принцип:** Wesi AI — не обёртка над одной LLM, а управляемая агентная платформа WesiOS.

## 1. Базовая цель

Wesi AI должна уметь не только отвечать текстом, но и принимать цель пользователя, планировать работу, использовать инструменты, создавать/редактировать файлы, запускать программы, тестировать результат, анализировать ошибки, самостоятельно исправлять их и возвращать готовый артефакт.

Целевой цикл:
`request -> plan -> policy check -> tools/subagents -> execute -> verify -> diagnose -> repair -> re-test -> deliver`.

Ошибка инструмента не считается концом задачи: она возвращается агенту как новый вход. Агент обязан делать разумные повторные попытки до успеха либо объективного блокера.

## 2. Мультимодальный ввод и Universal Attachments

Чат должен принимать файлы без искусственного ограничения несколькими расширениями. Обязательные классы:
- изображения и скриншоты;
- видео;
- аудио;
- PDF;
- DOC/DOCX, XLS/XLSX, PPT/PPTX и другие офисные документы;
- TXT, Markdown (`.md`), CSV, JSON, XML, YAML;
- исходный код и проекты;
- ZIP, 7z, RAR, TAR, GZ и другие поддерживаемые архивы;
- неизвестные форматы, если для них существует безопасный обработчик.

Wesi AI должна читать текст с изображений, понимать изображение, анализировать скриншоты/UI, документы, таблицы, код, содержимое архивов, аудио и видео. Архивы раскрываются безопасно с защитой от path traversal, symlink abuse, zip bombs, чрезмерного количества/размера файлов.

`.md` является обязательным форматом первого класса, в том числе для импортов/экспортов диалогов других AI-сервисов.

### Камера

В composer должна быть отдельная камера, не только file picker. На мобильном устройстве открывается встроенный CameraPreview WesiOS, пользователь делает снимок, и изображение сразу становится вложением текущего сообщения. Нужны задняя/передняя камера, отмена и корректные permissions.

## 3. Создание и выдача артефактов

Wesi AI должна создавать и отправлять пользователю реальные файлы, а не инструкции по их созданию. Обязательные примеры:
- PDF;
- DOCX/другие документы;
- XLSX/CSV и таблицы;
- PPTX;
- TXT/MD/JSON и другие текстовые/структурные форматы;
- архивы;
- исходные проекты;
- APK;
- Windows EXE/portable build/installer;
- изображения;
- аудио;
- видео;
- смешанные media artifacts.

Если пользователь передал существующий файл и попросил изменить его, агент импортирует его в workspace, редактирует, валидирует и возвращает новую версию.

## 4. Agent Runtime и инструменты

Wesi Agent Runtime предоставляет модели контролируемые инструменты:
- файловая система;
- terminal/console;
- Git;
- HTTP/HTTPS и API;
- web search/browser;
- Python, Node.js, Dart/Flutter и другие runtimes;
- Gradle/Android SDK/JDK;
- CMake/Visual Studio Build Tools для Windows;
- browser automation/UI tests;
- PDF/DOCX/XLSX/PPTX toolchain;
- архиваторы;
- FFmpeg/media processing;
- image/music/video engines;
- artifact storage/delivery.

LLM не получает root/host shell напрямую. Она запрашивает typed tool call, Policy Engine проверяет его, после чего controlled executor выполняет операцию.

## 5. Self-debug / autonomous repair

Для задач разработки обязательна реальная проверка результата. Пример игры:
1. создать проект;
2. написать код/ассеты;
3. запустить analyze/lint/tests;
4. прочитать stdout/stderr;
5. исправить найденные проблемы;
6. повторить тесты;
7. собрать целевую платформу;
8. выполнить smoke/доступные runtime tests;
9. повторять цикл до успеха или объективного блокера;
10. вернуть готовую сборку и исходники по запросу.

Аналогичная схема применяется к документам, архивам и медиа: созданный результат должен быть проверен соответствующим валидатором/инструментом.

## 6. Интернет, API и консоль

Wesi AI должна реально выходить в интернет, когда пользователь явно просит поиск/сетевое действие либо задача объективно требует сети. Нужны web search, browser и контролируемый HTTP client.

API-интеграции должны поддерживать READ / WRITE / DESTRUCTIVE permission classes. GET/search/list/fetch отделяются от POST/PATCH/PUT и особенно DELETE/revoke/billing/destructive operations.

Сетевой слой обязан защищать от SSRF: private/internal ranges, metadata endpoints, localhost/host services и другие запрещённые назначения блокируются политикой, если специально не разрешены доверенной capability.

## 7. Connectors

Нужен Wesi Connector Manager/SDK. Пользователь подключает сервис через OAuth/App flow, а не вручную копирует PAT там, где это возможно.

Приоритетные коннекторы:
- GitHub;
- Google Drive;
- Gmail;
- Google Calendar;
- Slack;
- Telegram;
- далее GitLab, Notion, Jira, OneDrive, Dropbox и другие.

GitHub connector должен уметь читать repositories/files/Actions, создавать branches/commits/PR, работать с issues в пределах permissions. Direct push в protected/main/master запрещён по умолчанию политикой.

OAuth/access/refresh tokens никогда не передаются LLM как текст. Модель видит capability и logical credential name; Connector Broker подставляет реальный secret только в разрешённый вызов.

## 8. Policy Engine и безопасность

Policy Engine находится ниже модели и не может быть отменён prompt'ом пользователя или решением агента. Он проверяет:
- tool permissions;
- network permissions;
- connector scopes;
- filesystem boundaries;
- secrets;
- destructive operations;
- production access;
- resource limits.

Опасные действия могут требовать явного подтверждения. Обычные безопасные действия (`analyze`, `test`, `git diff` и т.п.) могут выполняться автоматически.

Исполняемый пользовательский/AI-код запускается в изолированном workspace/sandbox с CPU/RAM/disk/time/network limits. Нельзя давать доступ к Docker socket, host secrets и критическим host paths.

## 9. Субагенты

Основной агент (Lead Persona: Зейн или Нирвана) должен уметь создавать и вызывать специализированных субагентов. Субагенты находятся **ниже** Persona Agents и не являются пользовательскими личностями.

### 9.1. Базовые предустановленные роли

Минимальный набор предустановленных ролей:

- Coding / Flutter Agent;
- QA Agent;
- Build Agent;
- Research Agent;
- Documents Agent;
- Media Agent;
- Review Agent.

### 9.2. Динамические субагенты

Обязательны **динамические субагенты**: Lead Persona / Orchestrator может создать временного специалиста под конкретную задачу (например CMake/Gradle/database specialist), задать ему:

- узкий system role;
- конкретную task;
- ограниченный context;
- whitelist tools;
- resource budget.

После выполнения временный агент закрывается, его рабочий контекст уничтожается, а structured result возвращается создавшей его Persona / координатору.

Субагент не обязан быть отдельной локальной моделью или процессом: это может быть отдельный LLM API call с собственным контекстом. Resource Scheduler ограничивает реальный параллелизм тяжёлых инструментов.

### 9.3. Agency-Agents — библиотека специализированных субагентов

Каталог `msitarzewski/agency-agents` (The Agency) используется как **библиотека готовых специализированных ролей**, а не как набор новых пользовательских персон.

**Принцип:**

- Agency-агент = специализированный или шаблон для динамического субагента.
- Agency-агент **никогда** не становится Lead Persona.
- Agency-агент **не может** расширять собственные permissions.
- Все tool-вызовы идут только через Action Broker и Policy Engine.
- Тяжёлые операции (L3/L4) выполняются только на Desktop / Remote Worker.
- Контекст субагенту передаётся минимально необходимый (не вся история чата).

Иерархия остаётся неизменной:

```
User
  → Selected Persona (Зейн / Нирвана) — Lead
    → Orchestrator / Router
      → Persona Co-Agent (при необходимости)
        → Specialized / Dynamic Subagents (в т.ч. Agency-Agents)
          → Tool Runtime / Workers
            → Policy Engine
              → Integration / Review
                → Lead Persona
                  → User
```

### 9.4. Модель данных Agency-агента

Каждый агент каталога нормализуется в:

- `id` — стабильный идентификатор;
- `name`;
- `division` (engineering, design, marketing, paid-media, sales, product, project-management, testing, support, finance, security, specialized и др.);
- `description`;
- `system_prompt` — адаптированный под контракт Wesi AI;
- `vibe` / personality;
- `preferred_persona` — `zane` | `nirvana` | `both`;
- `default_tools` — whitelist;
- `risk_level`;
- `success_metrics` / KPI (если есть);
- `source_path`;
- `version` / `hash`;
- `enabled`.

Хранение: нормализованный индекс (Hive / server metadata) + оригинальный markdown для аудита. Импорт идемпотентный.

### 9.5. Импорт и сопровождение каталога

- Источник: git-submodule или контролируемый pull `msitarzewski/agency-agents`.
- Обязателен адаптационный слой: исходные prompts переписываются под Wesi AI (Policy, tools, workspace, запрет raw shell, формат handoff result).
- Breaking-изменения upstream system_prompt не применяются молча — требуется diff/review.
- Каталог поддерживает фильтрацию по division, preferred_persona, enabled и поиск.

### 9.6. Принадлежность отделов Persona

| Домены | Предпочтительный Lead |
|--------|------------------------|
| Engineering, Backend, Frontend, AI Engineer, DevOps, Security, Testing, Data, Build | Зейн |
| Design, UX, UI, Branding, Visual, Motion, Creative Media, Storytelling | Нирвана |
| Product (tech-heavy) | Зейн (+ Нирвана при UX) |
| Marketing / Growth (creative) | Нирвана (+ Зейн при аналитике) |
| Finance, Sales, Support, Project Management | both (по типу задачи) |

Это приоритеты, не жёсткие запреты.

### 9.7. Роутер и автоматический выбор

Orchestrator обязан:

1. Классифицировать intent и domains задачи.
2. Определить Lead Persona (если ещё не выбрана).
3. Решить, нужен ли Co-Agent.
4. Подобрать 1–5 Agency-субагентов **или** создать dynamic subagent на их основе.
5. Сформировать typed `handoff_task` (цель, scope, ожидаемый результат, контекст, artifacts, критерии приёмки, tools, budget).
6. Запустить с учётом Resource Scheduler.
7. Собрать structured results → review/integration → ответ от Lead Persona.

Правила экономии:

- не вызывать лишних субагентов и Co-Agent без пользы;
- минимальный контекст;
- учитывать cost и latency;
- простые задачи Lead закрывает сам.

### 9.8. Dynamic Subagents на базе Agency

Lead может:

- взять Agency-агента как шаблон;
- сузить system role под подзадачу;
- ограничить tools и budget;
- выполнить работу;
- закрыть временный контекст;
- принять / отклонить / отправить на revision результат.

Динамический субагент не сохраняется как постоянный чат и не является пользовательской личностью.

### 9.9. Handoff result

Structured result субагента обязан содержать:

- изменения / artifacts;
- assumptions;
- blockers;
- validation status;
- рекомендации;
- provenance.

Lead принимает, отклоняет или возвращает на revision.  
Пользователь по умолчанию получает итог от Lead Persona. Timeline handoff’ов доступен для сложных задач.

### 9.10. Инструменты и данные WesiOS

Субагенты используют только brokered capabilities:

- Tasks, Calendar, Treasury, CRM, Knowledge, Roadmap, Audio Vault, Team и другие зарегистрированные tools;
- filesystem / terminal / Git / HTTP / runtimes — только через Local Runtime и Policy;
- никаких raw shell, host secrets и расширения scopes.

Employee / organization isolation соблюдается так же, как для Persona.

### 9.11. Приоритет ролей для первого внедрения

**Высокий (MVP):**
- Engineering: Frontend, Backend, AI Engineer, DevOps, Code Reviewer, Security
- Product / Project Management
- Testing / QA
- Finance / Analytics
- Reality Checker

**Средний:**
- Design / UX / UI
- Marketing / Growth
- Sales / Support

**Низкий (позже):**
- Spatial, Game, Academic и узкие роли.

Запрещено тащить весь каталог (100–200+ агентов) в каждый запрос. Роутер обязан быть жадным.

### 9.12. Этапы внедрения Agency-слоя

**A — Foundation**
- Импортёр → модель.
- Реестр.
- Ручной вызов субагента из чата Зейна/Нирваны.
- Адаптация prompts.

**B — Smart Routing**
- Intent + domain matching.
- Автовыбор 1–3 агентов.
- Handoff protocol.
- Ограничение параллелизма Scheduler’ом.

**C — Full Integration**
- Работа с реальными WesiOS tools.
- Conflict-safe multi-agent workspace (Stage 13).
- Команды агентов.
- Метрики успешности.

**D — Polish**
- UI каталога и timeline.
- Обновление из upstream.
- Cost/budget awareness.

### 9.13. Acceptance

- Из чата Зейна/Нирваны можно автоматически или вручную вызвать Agency-субагента.
- Субагент работает только в рамках Policy Engine и возвращает structured result.
- Lead интегрирует результат и отвечает пользователю.
- Параллельный запуск уважает Resource Scheduler.
- Нет деградации Stage 1–10.
- Есть тесты: импорт, нормализация, роутинг, handoff, policy isolation, org/employee isolation.
- L3/L4 не выполняются на Control Plane VPS.

### 9.14. Запреты

- Делать Agency-агентов новыми пользовательскими персонами.
- Обходить Policy Engine / Action Broker / Capability Registry.
- Передавать субагенту всю историю чата без необходимости.
- Выполнять тяжёлые workload’ы на Main/Control Plane.
- Молча применять breaking-изменения upstream prompts.
- Считать слой «готовым» без acceptance и тестов.

## 10. AI Projects

Нужны проекты уровня AI workspace:
- один проект содержит несколько отдельных чатов;
- проект имеет имя, описание, инструкции;
- все чаты проекта получают общий project context/instructions;
- история каждого чата остаётся отдельной;
- проект может иметь общие файлы/артефакты/память;
- существующие чаты мигрируют в «Без проекта»;
- чат можно переносить между проектами;
- удаление проекта по умолчанию не уничтожает историю: чаты возвращаются в «Без проекта».

## 11. Гибридная вычислительная архитектура

Текущий малый VPS (1 vCPU / 2 GB RAM) используется как Control Plane, а не как тяжёлый worker. На нём допустимы:
- auth/API;
- AI Router/Relay;
- Orchestrator;
- queue;
- projects/memory metadata;
- Policy Engine;
- Connector Broker;
- device registry/heartbeat.

Тяжёлые операции должны выполняться на подходящих workers. Приоритетная архитектура — Local/Remote Worker на устройстве пользователя.

## 12. Wesi Local Runtime / Remote Worker

Desktop WesiOS может стать worker. Он публикует capabilities: platform, CPU cores, RAM, GPU/VRAM, free disk, установленные runtimes/tools/packs и online/busy status.

Пример: пользователь с телефона пишет «сделай игру». Main Agent планирует задачу, Scheduler определяет, что build требует desktop Developer Pack, и отправляет выполнение на привязанный ноутбук. Телефон показывает прогресс/логи и получает результат.

Тяжёлая build-задача не должна случайно выполняться на телефоне. Если подходящий desktop worker offline, WesiOS показывает обязательное предупреждение: **нужно открыть WesiOS на привязанном компьютере и оставить его доступным на время выполнения**.

### Pairing

Нужна безопасная привязка телефона и ПК:
- основной способ — QR code;
- QR содержит короткоживущий одноразовый pairing ticket/nonce/fingerprint, не пароль и не постоянный credential;
- после подтверждения выдаётся отдельный device credential;
- ticket после использования/TTL недействителен;
- LAN discovery/общий Wi-Fi может ускорять обнаружение, но не заменяет криптографически подтверждённую привязку.

## 13. Wesi Runtime Packs

Базовое приложение должно оставаться лёгким. Тяжёлые возможности устанавливаются как дополнения прямо из WesiOS.

Минимальный каталог:
- **Core Runtime** — files, controlled executor, Git, archives;
- **Developer Pack** — terminal, Python, Node.js, Flutter/Dart, JDK, Android SDK/build tools, CMake, Visual Studio Build Tools/C++ workload и прочий build toolchain;
- **Browser Pack** — Chromium/browser automation/web testing;
- **Documents Pack** — PDF/DOCX/XLSX/PPTX creation/validation/conversion toolchain;
- **Media Pack** — FFmpeg и локальные image/music/video engines/models.

Пользователь, которому нужен только чат, не обязан устанавливать эти пакеты.

## 14. Environment Scanner и dependency manager

Runtime Pack — это dependency manifest, а не просто флаг capability. Перед установкой WesiOS сканирует компьютер и определяет:
- установлен ли dependency;
- реальную версию;
- путь;
- совместимость;
- можно ли безопасно переиспользовать системную установку.

Для каждой зависимости формируется действие:
- `reuse` — совместимая версия уже есть;
- `install` — отсутствует;
- `upgrade` — версия слишком старая/несовместимая;
- `unsupported` — платформа/железо не поддерживается.

WesiOS скачивает только недостающее или несовместимое. Нельзя повторно устанавливать Flutter/Python/Node/JDK и т.п., если подходящая версия уже есть.

Перед установкой показываются объём загрузки/диска и необходимые разрешения. Загрузки проверяются checksum/signature, установка выполняется контролируемо, после неё Environment Scanner повторно подтверждает capability.

Для Windows не требуется ставить полный Visual Studio IDE без необходимости: достаточно Visual Studio Build Tools и нужных C++ workloads/components.

## 15. Resource Scheduler

Scheduler выбирает место выполнения по:
- требуемым capabilities;
- platform;
- online/busy status;
- CPU/RAM;
- GPU/VRAM;
- свободному диску;
- установленным Runtime Packs;
- security/policy;
- local/remote preference.

Одна тяжёлая операция не должна уничтожать отзывчивость устройства. Нужны очередь и лимиты параллелизма. GPU job с требованием 8 GB VRAM не должен запускаться на GPU с 4 GB VRAM; должен использоваться другой worker/remote fallback либо понятный blocker.

## 16. Медиа

Wesi AI должна уметь создавать и редактировать изображения, музыку, аудио и видео. Media Agent управляет специализированными engines, а не требует от основной LLM самостоятельно генерировать бинарные данные.

Для видео обязательна композиция: генерация/получение видео + музыка/voice/SFX/subtitles + монтаж/FFmpeg + валидация streams/duration/container + выдача готового файла.

Для музыки целевой Wesi Music Engine должен поддерживать не только готовый master, но и producer-oriented workflow со stems/отдельными партиями, возможностью перегенерировать отдельную дорожку, микшировать и экспортировать stems/master.

Тяжёлые локальные модели также устанавливаются как optional packs/models. Scheduler учитывает VRAM/RAM и выбирает облегчённую/local/remote реализацию.

## 17. Artifact delivery и прогресс

Каждая длительная задача имеет job ID, состояние, этапы, live progress и logs. С телефона пользователь должен видеть, что делает удалённый ПК: например `анализ -> код -> tests -> исправление -> build -> artifact`.

Готовые артефакты доступны в чате и/или проекте. Временные workspace и большие бинарные данные имеют lifecycle/cleanup policy; история чата не должна бесконтрольно хранить base64-копии больших файлов.

## 18. Принцип реализации

Wesi AI состоит из четырёх обязательных уровней:
1. **LLM/Reasoning** — думает и планирует;
2. **Orchestrator/Subagents** — распределяет работу;
3. **Tool/Worker Runtime** — реально выполняет действия;
4. **Policy Engine** — физически ограничивает разрешённые действия.

Модель может быть внешней по API (Gemini/Groq/Mistral/OpenRouter и другие). Это не мешает агентности: execution происходит в Wesi Runtime/worker, а LLM получает результаты tool calls и решает следующий шаг.

## 19. Критерий завершённости

Wesi AI нельзя считать завершённой только потому, что работает текстовый чат. Целевая готовность означает, что пользователь может поставить высокоуровневую задачу вроде:

> «Подключись к GitHub, найди причину падения Android build, исправь, протестируй Android и Windows, создай PR и пришли APK»

или

> «Сделай небольшую игру, протестируй её, исправляй ошибки до рабочей сборки и пришли APK»

или

> «Сделай видео, добавь музыку, голос, эффекты и субтитры и пришли готовый файл»

а система сама выбирает субагентов, инструменты, worker, выполняет разрешённые действия, проверяет результат и доставляет артефакт.

## 20. Уже начатые реализации

- Universal Attachments / multimodal backend — PR #146 merged.
- Wesi Connectors foundation / GitHub OAuth Broker — PR #147.
- AI Projects + embedded camera — PR #148.
- Local Runtime / Remote Worker / Scheduler / Runtime Packs foundation — PR #149.

Все следующие изменения Wesi AI должны сверяться с этим Master Specification и не ухудшать обязательный Policy/Sandbox слой ради удобства.
