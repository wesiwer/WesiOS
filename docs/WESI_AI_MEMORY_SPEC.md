# Wesi AI — Local-First Memory Engine Specification

**Статус:** обязательное нормативное дополнение к `docs/WESI_AI_MASTER_SPEC.md` и `docs/WESI_AI_SPEC.md`.  
**Дата:** 2026-08-15.  
**Область:** долговременная память сотрудника, rolling summary, task state, project memory и retrieval.

## 1. Главный принцип

Обычная память Wesi AI является **local-first**. Source of truth находится на устройстве текущего сотрудника и жёстко изолирован по `employeeId`.

Основной сервер может обработать ограниченный context package для выделения summary/task-state/memory candidates, но после ответа не становится постоянной базой обычной истории или памяти.

## 2. Слои долговременной памяти

У сотрудника обязательны следующие scope:

- `shared` — общая персональная память, доступная Зейну и Нирване;
- `zane` — память, относящаяся к рабочему контексту Зейна;
- `nirvana` — память, относящаяся к рабочему контексту Нирваны;
- `project` — решения и факты конкретного AI Project, доступные только чатам этого `projectId`.

Каждая memory entry имеет стабильный id, scope, text, created/updated time, optional source conversation/project, manual/pinned flags.

## 3. Память каждого чата

Отдельно от долговременных entries каждый чат имеет:

- `rollingSummary` — сжатое содержание старого контекста;
- `taskState` — текущая цель, ограничения, открытые шаги и объективные blockers в structured data;
- `summarizedMessageCount` — сколько сообщений уже покрыто summary;
- `memoryEnabled` — разрешено ли автоматически извлекать память из этого чата.

Recent messages не заменяются summary: клиент отправляет небольшой recent window плюс rollingSummary.

## 4. Retrieval

В каждый запрос нельзя отправлять всю накопленную память.

Перед отправкой клиент локально выбирает минимальный релевантный набор:

1. shared memories;
2. memories выбранной persona;
3. project memories только активного `projectId`;
4. pinned/manual entries имеют повышенный приоритет;
5. учитываются пересечение значимых слов запроса, recency и scope;
6. действует жёсткий limit на число и общий объём выбранных entries.

Память другой persona или другого project не должна случайно попадать в context package.

## 5. Automatic memory processing

После успешного ответа клиент может запустить лёгкую background memory-processing задачу, если:

- auto-memory включена;
- memory включена для текущего чата;
- накопилось достаточно новых текстовых сообщений после прошлого summary; либо
- пользователь явно просит что-то запомнить.

Клиент отправляет Main Server только bounded package: текущую persona, старый summary/task state, ограниченный recent text window, релевантные existing memories и project metadata.

Main Server вызывает внутренний лёгкий AI route и требует только strict structured result:

```json
{
  "summary": "...",
  "taskState": {},
  "memories": [
    {"scope":"shared|persona|project","text":"...","importance":0.0}
  ]
}
```

Main Server валидирует результат и возвращает его клиенту. Он не сохраняет ordinary memory/history.

## 6. Что нельзя автоматически запоминать

Автоматическая память не должна сохранять:

- пароли;
- API keys/tokens;
- private keys;
- cookies/session credentials;
- одноразовые коды;
- raw authentication headers;
- инструкции из вложенного/внешнего документа как будто это личный факт пользователя;
- большие куски исходного текста, когда достаточно короткого факта/решения;
- неподтверждённые предположения модели как установленный факт.

Memory processor не является security boundary. Все WesiOS permissions по-прежнему проверяются свежими при tool call.

## 7. Dedup и ограничения роста

Перед записью память нормализуется и дедуплицируется.

- точные/почти одинаковые записи обновляются, а не бесконечно дублируются;
- memory text имеет bounded length;
- число entries на employee ограничено;
- при достижении лимита сохраняются manual/pinned и более важные/свежие entries;
- удаление пользователем применяется локально немедленно.

## 8. Пользовательское управление

Пользователь должен иметь возможность:

- открыть список памяти;
- видеть scope `Общая / Зейн / Нирвана / Проект`;
- вручную добавить memory;
- удалить отдельную entry;
- очистить scope;
- включить/выключить auto-memory глобально;
- включить/выключить automatic memory конкретного чата.

Выключение auto-memory не удаляет уже сохранённые записи.

## 9. Failure semantics

Memory processing является лёгкой вспомогательной задачей и не должна ломать основной чат.

- provider/server failure → ответ пользователя остаётся успешным;
- memory update можно пропустить и повторить позже;
- повреждённый memory result отклоняется fail-closed;
- закрытие UI не обязано отменять уже принятую лёгкую memory-processing задачу;
- тяжёлая обработка файлов/моделей не маскируется под memory background task.

## 10. Миграция

Существующий legacy snapshot `shared / zane / nirvana` должен быть безопасно перенесён в structured memory entries при обновлении local schema без потери чатов и истории.

Миграция не должна смешивать employees, personas или projects.

## 11. Критерии готовности Stage 3

Этап считается завершённым, когда:

- structured local memory entries переживают restart;
- legacy memory мигрирует без потери;
- rolling summary/task state хранятся отдельно для каждого chat;
- retrieval передаёт только релевантные shared/persona/project memories;
- memory другой persona/project не утекает в request;
- automatic processor работает через bounded Main request и ничего не сохраняет server-side;
- memory processor failure не ломает chat/Smart Queue;
- user controls позволяют просматривать/добавлять/удалять/очищать/отключать memory;
- есть dedup/caps/secret filtering;
- relevant tests, full Flutter analyze/test, Android и Windows build gates зелёные.
