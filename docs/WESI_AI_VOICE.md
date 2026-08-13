# Wesi AI Voice — обязательное голосовое общение Зейна и Нирваны

> **Статус:** обязательная часть `docs/WESI_AI_SPEC.md`.
>
> **Канонический источник голосов и характеров:**
> - `docs/wesi_ai/personas/ZANE_PERSONA.md`
> - `docs/wesi_ai/personas/NIRVANA_PERSONA.md`
> - `docs/wesi_ai/personas/ZANE_VOICE.md`
> - `docs/wesi_ai/personas/NIRVANA_VOICE.md`
>
> Исходная спецификация характеров и системных промптов v2.0 утверждена владельцем и является источником истины. Character/rules из Persona Bible нельзя смягчать или переписывать без прямого решения владельца.

---

# 1. Голос — обязательная часть Wesi AI

И Зейн, и Нирвана должны уметь вести полноценный естественный голосовой разговор.

Это не простой TTS поверх текстового сообщения. Voice Mode должен ощущаться как разговор с двумя постоянными участниками Wesi AI.

Общие требования:

- естественное человеческое звучание;
- приятное длительное прослушивание;
- эмоциональная подача;
- отсутствие роботизированной монотонности;
- узнаваемая постоянная voice identity каждого персонажа;
- характер должен быть слышен не только в словах, но и в интонации;
- text/reasoning provider может меняться, канонический голос персонажа — нет.

Ориентир — качество современных conversational voice assistants. Нельзя строить продукт на копировании узнаваемого голоса другого ассистента или публичного человека. Wesi AI должен иметь собственные голоса.

---

# 2. Канонический голос Зейна

Дословное описание владельца хранится в `ZANE_PERSONA.md` и `ZANE_VOICE.md`.

Смысл для реализации:

- молодой мужской голос;
- приятный;
- слегка низкий;
- харизматичный;
- резкий и прямолинейный по манере;
- умеет естественно передавать иронию, чёрный юмор, разговорность и эмоциональность Зейна;
- при техническом анализе остаётся уверенным, ясным и разборчивым.

Voice layer не имеет права сглаживать Зейна до нейтрального корпоративного диктора.

---

# 3. Канонический голос Нирваны

Дословное описание владельца хранится в `NIRVANA_PERSONA.md`.

Смысл для реализации:

- женский голос;
- приятная и нежная подача;
- эмпатичная;
- утонченная;
- искренняя;
- спокойная и естественная интонация;
- в творческих и душевных разговорах допускается более тёплая и выразительная подача;
- в рабочих ответах сохраняются ясность и разборчивость.

Voice layer не должен делать Нирвану холодной, грубой или циничной.

---

# 4. Голос является частью Persona Engine

Архитектура:

```text
User voice
  ↓
Streaming STT / realtime speech
  ↓
Conversation + Context Builder
  ↓
Persona Engine
  ↓
Gemini / Claude / другой разрешённый provider
  ↓
semantic response + speech directives
  ↓
Zane/Nirvana Voice Engine
  ↓
streaming audio
```

При переключении модели:

- conversation id сохраняется;
- persona сохраняется;
- memory/context сохраняются;
- voice identity сохраняется;
- пользователь не начинает новый разговор.

---

# 5. Полноценный Voice Mode

Минимальные функции:

- запуск голосового разговора из текущего чата;
- microphone input;
- live transcription;
- streaming response;
- streaming audio playback;
- stop/mute/end;
- text → voice → text без потери context;
- transcript сохраняется в обычном conversation timeline;
- voice messages и text messages являются одной историей;
- возможность продолжить тот же разговор после перезапуска приложения.

---

# 6. Barge-in / перебивание

Пользователь должен иметь возможность перебить Зейна или Нирвану во время голосового ответа.

Система должна:

1. быстро остановить или приглушить текущую озвучку;
2. начать принимать новую реплику;
3. сохранить уже произнесённую часть ответа как часть состояния разговора;
4. передать следующему model turn факт прерывания, если это релевантно.

Нельзя заставлять пользователя ждать конца длинного монолога.

---

# 7. VAD и конец реплики

Voice Mode должен отличать естественную короткую паузу от окончания фразы.

Нужны:

- voice activity detection;
- end-of-turn logic;
- настройка под русскую естественную речь;
- защита от случайного обрыва длинной мысли пользователя;
- корректная работа в умеренно шумной среде.

---

# 8. Минимальная задержка

Предпочтительный pipeline:

```text
speech
→ partial STT
→ model processing
→ partial semantic response
→ streaming TTS
```

Цель — ощущение живого разговора, а не сценарий «записал аудиофайл → долго подождал → получил озвученный текст».

---

# 9. Эмоциональная подача

Persona Engine может выдавать provider-neutral speech directives, например:

```text
emotion
energy
pace
emphasis
pause hints
```

Адаптер конкретного voice provider переводит их в поддерживаемые параметры.

Бизнес-логика не должна зависеть от proprietary названий эмоций одного TTS API.

Speech directives не могут менять:

- факты;
- суммы;
- даты;
- tool results;
- permission decision;
- смысл ответа.

---

# 10. Русский язык и смешанный контент

Голос должен хорошо произносить:

- естественную русскую речь;
- имена сотрудников;
- WesiOS;
- Wesi AI;
- Wesi Horizon;
- названия модулей;
- названия технологий и моделей;
- даты;
- суммы;
- проценты;
- валюты;
- сокращения;
- английские термины внутри русского предложения.

Большие фрагменты кода по умолчанию лучше показать текстом и объяснить голосом, а не зачитывать каждый символ, если пользователь не попросил обратного.

---

# 11. Voice + WesiOS Actions

Голосовой режим имеет те же permission-aware tools, что текстовый Wesi AI.

Пример:

```text
«Зейн, поставь Ивану завтра задачу проверить рекламу»
```

Pipeline:

```text
STT
→ intent/tool request
→ Action Broker
→ employee identity
→ organization scope
→ permission check
→ risk/confirmation gate
→ TaskService
→ ActionResult
→ голосовой и текстовый ответ
```

Voice Mode никогда не является обходом permissions.

Если сотрудник не имеет права назначать задачи, голосовая команда также блокируется.

---

# 12. Голосовые подтверждения действий

Для significant/critical actions нельзя полагаться на случайно распознанное короткое «да».

Risk Policy может потребовать:

- явное повторение действия;
- явное голосовое подтверждение;
- UI confirmation;
- повтор ключевых параметров перед выполнением.

Для критических действий UI confirmation может быть обязательным независимо от voice input.

---

# 13. Voice Lobby

В Lobby пользователь должен различать Зейна и Нирвану на слух.

Правила:

- у каждого свой голос;
- активный speaker отображается в UI;
- голоса не смешиваются;
- внутренние turns ограничены;
- пользователь может перебить Lobby в любой момент;
- Зейн и Нирвана сохраняют канонические отношения и характеры из Persona Bible;
- их ответы могут быть адресованы друг другу и пользователю;
- Lobby не является третьей смешанной личностью.

---

# 14. Voice Handoff

При передаче разговора Зейн ↔ Нирвана:

- conversation остаётся тем же;
- handoff package сохраняет задачу и context;
- меняется активная persona;
- меняется голос;
- пользователь не повторяет исходную задачу.

Переключение должно ощущаться как передача разговора другому участнику общего дома Wesi AI.

---

# 15. Provider-neutral архитектура

Рекомендуемые интерфейсы:

```text
VoiceSessionController
SpeechToTextProvider
TextToSpeechProvider
RealtimeVoiceProvider
SpeechPlanner
AudioPlaybackController
```

Если provider поддерживает realtime speech-to-speech, это можно использовать как оптимизацию.

Но под контролем Wesi AI остаются:

- Persona Bible;
- context ownership;
- employee identity;
- organization scope;
- permissions;
- WesiOS tool execution;
- audit;
- risk gates.

Voice provider не получает право самостоятельно выполнять WesiOS actions.

---

# 16. Gateway

Voice provider вызывается только через зарубежный Wesi AI Gateway.

Клиент не содержит provider API keys.

Capabilities могут включать:

```text
speechToText
textToSpeech
realtimeVoice
voiceCatalog
```

Конкретный provider и технический voice id не должны быть жёстко зашиты в UI.

---

# 17. Приватность

По умолчанию голосовой разговор не означает бессрочное хранение сырого microphone audio.

Разделяются:

- transient audio для STT/realtime processing;
- transcript, который входит в conversation history;
- optional audio artifact, только если такая функция будет отдельно введена.

Запрещено:

- писать raw microphone audio в обычные логи;
- писать provider secrets;
- автоматически хранить raw audio бессрочно;
- смешивать voice history разных сотрудников.

Cloud-save чата не должен автоматически означать сохранение исходной аудиозаписи, если пользователь отдельно этого не выбрал.

---

# 18. Fallback

Если realtime voice временно недоступен:

```text
streaming STT
→ text model
→ streaming TTS
```

Если озвучивание недоступно полностью, пользователь всё равно получает текстовый ответ в том же разговоре.

Persona/context не сбрасываются при fallback.

---

# 19. Текущий статус

- `[DONE SPEC]` Канонические характеры Зейна и Нирваны восстановлены из утверждённой спецификации v2.0.
- `[DONE SPEC]` Каноническое описание голоса Зейна восстановлено.
- `[DONE SPEC]` Каноническое описание голоса Нирваны восстановлено.
- `[DONE SPEC]` Создан `ZANE_PERSONA.md`.
- `[DONE SPEC]` Создан `NIRVANA_PERSONA.md`.
- `[DONE SPEC]` Создан `ZANE_VOICE.md`.
- `[DONE SPEC]` Создан указатель `NIRVANA_VOICE.md`; дословная каноническая формулировка хранится в `NIRVANA_PERSONA.md`.
- `[TODO]` Подобрать/создать техническую реализацию двух голосов, соответствующую Voice Bible.
- `[TODO]` Streaming STT.
- `[TODO]` Streaming TTS.
- `[TODO]` Realtime voice transport.
- `[TODO]` Voice Session Controller.
- `[TODO]` VAD/end-of-turn.
- `[TODO]` Barge-in.
- `[TODO]` Voice transcript в conversation timeline.
- `[TODO]` Voice handoff.
- `[TODO]` Voice Lobby.
- `[TODO]` Voice WesiOS actions через Action Broker.
- `[TODO]` Voice confirmation policy.
- `[TODO]` Voice privacy tests.
- `[TODO]` Android/Windows latency and quality tests.

---

# 20. Acceptance criteria

Voice layer не готов, пока одновременно не выполнено:

1. У Зейна и Нирваны два разных стабильных голоса согласно их Voice/Persona Bible.
2. Оба голоса приятны для длительного общения и утверждены владельцем по фактическому звучанию.
3. Character каждого персонажа слышен в подаче.
4. Text → voice → text не теряет conversation/context.
5. Пользователь может перебить AI.
6. VAD не обрывает естественную короткую паузу.
7. Ответ начинает звучать потоково с приемлемой задержкой.
8. Voice command может читать реальные разрешённые данные WesiOS.
9. Voice command может выполнять разрешённые WesiOS actions.
10. Запрещённый action блокируется теми же permissions, что и текстовый.
11. Critical action защищён от случайного подтверждения.
12. В Lobby Зейн и Нирвана различимы по голосу.
13. Transcript сохраняется в локальном разговоре.
14. Provider keys отсутствуют в клиенте.
15. Raw audio не хранится бессрочно по умолчанию.
16. Есть рабочий fallback при проблеме voice provider.
17. Android и Windows проходят функциональные voice tests.
