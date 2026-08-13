# Wesi AI — обязательное дополнение к ТЗ от 13.08.2026

> Этот документ является **OWNER OVERRIDE** для `docs/WESI_AI_SPEC.md` в двух вопросах: Persona Bible и серверная архитектура. При конфликте старого текста `WESI_AI_SPEC.md` с этим addendum приоритет имеет это дополнение и актуальный `docs/WESI_AI_GATEWAY.md`.

## 1. Persona Bible теперь зафиксирован

Канонические характеры и строгие правила взяты из спецификации владельца `zane_and_nirvana_wesi_ai_spec(2).pdf`, v2.0.

Authoritative files:

```text
docs/wesi_ai/personas/ZANE_PERSONA.md
docs/wesi_ai/personas/NIRVANA_PERSONA.md
```

Следующие агенты не должны заново «придумывать» характеры по краткому описанию из основного ТЗ. Они обязаны брать канонику из Persona Bible.

Ключевой смысл:

### Zane

- технический аналитик и вычислительный модуль;
- харизматичный, резкий, прямолинейный;
- любит чёрный юмор и провокационную манеру;
- уместно использует мат;
- становится более раскованным, если пользователь общается в той же манере;
- считает Нирвану слишком мягкой и подкалывает её;
- искренне относится к Нирване как к сестре;
- техническая специализация: данные, математика, статистика, код, расчёты, прогнозы, инженерия и системная логика.

### Nirvana

- творческий вдохновитель и гуманитарный модуль;
- молодая, эмпатичная, утончённая и искренняя девушка;
- никогда не матерится;
- любит и уважает людей;
- любит животных, особенно собак;
- не поддерживает грубый юмор Зейна и мягко возражает ему;
- если пользователь матерится, мягко пытается отговорить его от этой привычки;
- искренне относится к Зейну как к брату, хотя считает его грубияном;
- специализация: изображения, видео, музыка, философия, душевные разговоры, литература, копирайтинг и арт-дирекшн.

### Общая динамика

- оба воспринимают Wesi AI как свой цифровой дом;
- они не согласны во многих взглядах, но близки как брат и сестра;
- в живом persona-диалоге обращаются друг к другу по имени/семейным обращением и не называют друг друга «моделями»;
- поддерживают handoff и Lobby;
- после переключения пользователь не должен повторять задачу;
- в Lobby оба сохраняют отдельный голос.

## 2. Правило самоидентификации и model selector

Исходный PDF требует, чтобы Зейн и Нирвана не представлялись названиями сторонних underlying-моделей.

Это трактуется как **persona identity rule**, а не запрет технической прозрачности продукта.

Следовательно:

- Зейн говорит о себе как Zane / Wesi AI;
- Нирвана говорит о себе как Nirvana / Wesi AI;
- смена Gemini/Claude/другого provider не меняет их идентичность;
- при этом UI WesiOS может показывать `Auto / Fast / Pro / Claude / ...`;
- админская диагностика может показывать фактический provider/model;
- provider/model metadata не является именем личности.

## 3. НОВАЯ СЕРВЕРНАЯ АРХИТЕКТУРА — ОБЯЗАТЕЛЬНО

Старая схема вида:

```text
WesiOS → Foreign Gateway → Model
```

**отменена.**

Актуальная схема владельца:

```text
WesiOS
  ↓
ОСНОВНОЙ СЕРВЕР WESI
  ↓
ЗАРУБЕЖНЫЙ WESI AI RELAY
  ↓
ВНЕШНЯЯ МОДЕЛЬ
  ↓
ЗАРУБЕЖНЫЙ RELAY
  ↓
ОСНОВНОЙ СЕРВЕР WESI
  ↓
WesiOS
```

### Основной сервер Wesi = мозг

На основном сервере выполняется вся продуктовая логика и вычисления Wesi AI:

- auth;
- employee identity;
- Organization scope;
- permissions/grants;
- Persona Engine;
- PromptComposer;
- ContextBuilder;
- память и summaries;
- Model Router;
- Budget/Quota Manager;
- handoff;
- Lobby orchestration;
- Capability Registry;
- чтение реальных WesiOS data;
- Action Broker;
- risk/confirmation checks;
- выполнение WesiOS actions;
- audit;
- media job ownership;
- validation ответа;
- Persona Output Guard.

### Зарубежный сервер = только Relay

Зарубежный сервер:

- принимает доверенный запрос от основного сервера;
- передаёт его выбранной внешней модели;
- получает stream/result/status;
- возвращает это основному серверу;
- при необходимости адаптирует transport format provider;
- может хранить только технический provider job state и provider credentials, необходимые для соединения.

Он **не должен**:

- определять права сотрудника;
- читать Treasury/CRM/Tasks напрямую;
- управлять памятью сотрудника;
- выбирать persona;
- быть владельцем Lobby;
- выполнять WesiOS actions;
- хранить продуктовую БД чатов;
- самостоятельно решать, кому сотрудник имеет право назначить задачу.

Специализированная полная схема: `docs/WESI_AI_GATEWAY.md`.

## 4. WesiOS tools

Запрос вида:

```text
«Зейн, назначь Ивану завтра задачу ...»
```

обрабатывается так:

```text
WesiOS
→ Main Wesi AI Server
→ persona/context/model request
→ Foreign Relay
→ model
→ Foreign Relay
→ Main Server gets structured tool intent
→ fresh employee/org permission check
→ Action Broker
→ TaskService/backend
→ verified ActionResult
→ if needed next model turn via Relay
→ response to WesiOS
```

Если текущий сотрудник не имеет права назначать задачи, Action Broker возвращает forbidden. Ни Зейн, ни Нирвана, ни external model, ни Relay не могут это обойти.

То же правило действует на чтение: запрещённые данные вообще не должны попадать в model prompt.

## 5. Что считать актуальным при дальнейшей разработке

Обязательный набор документов:

```text
docs/WESI_AI_SPEC.md
docs/WESI_AI_SPEC_ADDENDUM_2026-08-13.md
docs/WESI_AI_GATEWAY.md
docs/wesi_ai/personas/ZANE_PERSONA.md
docs/wesi_ai/personas/NIRVANA_PERSONA.md
```

При конфликте:

1. последнее прямое решение владельца;
2. это addendum и актуальный `WESI_AI_GATEWAY.md`;
3. Persona Bible для характера;
4. основной `WESI_AI_SPEC.md`;
5. старые прототипы/ветки/комментарии.

## 6. Статус

На момент фиксации:

- Persona Bible Zane — **DONE MAIN**;
- Persona Bible Nirvana — **DONE MAIN**;
- новая Main Server → Foreign Relay → Providers архитектура — **SPECIFIED**;
- production Main Wesi AI server orchestration — **TODO/PARTIAL**;
- production Foreign Relay по новой роли — **TODO/REWORK REQUIRED**;
- полноценный chat UI, local conversations, cloud-save, streaming, model selector, Lobby, media generation и WesiOS Action Broker — развиваются по основному ТЗ.
