# WesiOS — ТЗ: обязательные доработки по итогам независимого постреализационного аудита

**Связано с:** `TZ_ORG_HIERARCHY_V1.md` v1.1  
**Статус:** обязательное нормативное дополнение к ТЗ  
**Дата аудита:** 2026-08-10  
**Правило приёмки:** реализация иерархии организаций и персональных финансовых контуров не считается завершённой, пока блокирующие пункты ниже не закрыты кодом и негативными/интеграционными тестами.

---

## 0. Общий вывод аудита

Фундамент реализации уже существует: дерево организаций, `Wesi Inc` как root, `Wesi Beats` как child, миграция legacy-данных, `only/subtree`, базовый Treasury scope, My Finance, inter-org сущность, большая часть Horizon-интеграции и sync ownership.

Однако независимый аудит после реализации выявил ряд несоответствий ТЗ, которые зелёный CI не обнаружил. Основные риски находятся в четырёх областях:

1. изоляция организаций и сотрудников;
2. privilege escalation и неполный enforcement прав;
3. атомарность и математическая целостность финансов;
4. независимость прогнозных контуров Horizon.

Ниже все замечания считаются частью ТЗ и должны быть закрыты до финальной приёмки.

---

# A. BLOCKER — права доступа и безопасность

## A1. Запрет privilege escalation через `manage_members`

### Найденная проблема

Пользователь с `manage_members` может изменять grant и потенциально выдать себе или другому сотруднику права шире собственных: `includeSubtree`, `manage_org_settings`, `manage_members`, `view_finance`, `view_forecast` и другие.

### Требуемое поведение

- пользователь не может выдавать право, которого сам не имеет;
- пользователь не может расширять grant за пределы собственного access scope;
- `includeSubtree=true` разрешён только если actor сам имеет соответствующий subtree scope;
- нельзя редактировать собственный grant так, чтобы повысить собственные полномочия;
- root owner сохраняет полный доступ без этих ограничений;
- желательно разделить `manage_members` и право выдачи административных permissions, если это улучшает безопасность.

### Приёмка

Негативные тесты должны доказать, что руководитель `IT only` не может:

- выдать себе `IT subtree`;
- получить доступ к `Studio A` без внешней выдачи права;
- назначить себе `manage_org_settings`, если его не было;
- назначить другому сотруднику permission выше собственного.

---

## A2. `OrganizationService` обязан проверять права на domain/service layer

### Найденная проблема

`create/update/archive/restore` защищаются в основном UI-проверками, но сам сервис не enforce-ит `manage_org_settings`.

### Требуемое поведение

Любой production-вызов изменения дерева обязан проходить domain-level permission validation. UI не является security boundary.

### Приёмка

Прямой вызов сервиса без разрешения должен завершаться отказом. Это должно быть покрыто тестами без участия UI.

---

## A3. Исправить изменение ownership транзакции

### Найденная проблема

При update транзакции проверяется право на старую организацию, но новое `organizationId` может быть принято без полноценной проверки новой организации и прав на неё.

### Требуемое поведение

При любом изменении `organizationId`:

- новая org должна существовать и быть active;
- actor должен иметь `edit_transactions`/необходимые права в старой и новой org;
- account должен принадлежать новой org;
- операция не должна становиться orphan/cross-org inconsistent.

### Приёмка

Нельзя переместить финансовую операцию из разрешённой org в недоступную через service API, sync или UI.

---

## A4. `manage_recurring` должен быть реальным permission boundary

### Найденная проблема

Permission существует, но recurring-операции фактически создаются/изменяются через обычные `create_transactions`/`edit_transactions`.

### Требуемое поведение

Создание, изменение, отключение и удаление recurring schedule должно требовать `manage_recurring` либо явно определённого эквивалентного правила.

### Приёмка

Пользователь с `create_transactions`, но без `manage_recurring`, не может создать или изменить регулярную операцию.

---

# B. BLOCKER — Tasks / CRM / legacy UI scope

## B1. Сделать Tasks org-aware и employee-aware

### Найденная проблема

Основные методы `TaskService` и `TasksScreen` используют глобальный список задач и не применяют `OrganizationContext`/AccessGrant как обязательный boundary.

### Требуемое поведение

- ordinary employee видит только разрешённые задачи согласно продуктовой политике;
- manager видит задачи только своей org/subtree;
- создание/редактирование/удаление задачи проверяет org permission;
- глобальные raw reads доступны только явно для migration/admin/internal use;
- `summary`, `upcoming`, `dueOn`, board и search используют тот же scope.

### Приёмка

Сотрудник Studio A не видит и не может изменить задачи Studio B без grant.

---

## B2. Сделать CRM org-aware и employee-aware

### Найденная проблема

Основной CRM UI загружает глобальные `clients/deals/interactions/summary`, хотя существуют частично scoped helpers.

### Требуемое поведение

- CRM читает текущий org/scope;
- ordinary employee не получает чужой персональный pipeline, если продуктовая политика это запрещает;
- manager видит только выданный org/subtree;
- CRUD проверяет grants на service layer;
- summary, pipeline, activity и clients используют одну и ту же access policy.

### Приёмка

Пользователь Studio A не видит CRM Studio B без соответствующего grant.

---

## B3. Удалить обход через legacy `TeamStatsScreen`

### Найденная проблема

Старый экран использует legacy `canSeeOthersStats` и глобальный `TaskService.getAll()`, что может обходить новую организационную модель.

### Требуемое поведение

- либо экран переводится на org/subtree grants;
- либо заменяется новым manager/team view;
- никакой legacy permission не должен расширять org scope.

### Приёмка

`canSeeOthersStats=true` не даёт доступ к людям и задачам вне разрешённой ветки.

---

# C. BLOCKER — персональные финансовые контуры

## C1. `teamBreakdown` должен требовать одновременно правильный org finance scope и team-finance право

### Найденная проблема

`canViewTeamFinance=true` может существовать при отсутствии `view_finance`, а сервис не везде требует обе части модели доступа.

### Требуемое поведение

Для просмотра персональных строк команды нужны одновременно:

- доступ к организации;
- право на соответствующий org/subtree finance contour;
- `canViewTeamFinance=true`.

### Приёмка

Grant `team=true`, `view_finance=false` не раскрывает персональные финансовые строки.

---

## C2. `selfForecast` обязан уважать `canViewSelfFinance`

### Найденная проблема

Self metrics могут быть скрыты флагом, но self forecast строится отдельно и может остаться доступным.

### Требуемое поведение

Единая политика `self finance` применяется к metrics, risks, forecast, history и будущим self-функциям.

### Приёмка

При `canViewSelfFinance=false` ни один self financial endpoint/UI не возвращает персональные показатели или прогноз.

---

## C3. Team breakdown: переход в карточку сотрудника

### Найденная проблема

ТЗ требует клика внутрь карточки сотрудника, но текущие строки My Finance не имеют полноценного drill-down.

### Требуемое поведение

При наличии `canViewTeamFinance` руководитель может открыть карточку сотрудника с детализацией доступных персональных финансовых показателей в текущем org/scope.

### Приёмка

Клик по строке сотрудника открывает детальную карточку; без права строка и карточка недоступны.

---

# D. BLOCKER — inter-org финансовая целостность

## D1. Реальная атомарность `InterOrgTransfer`

### Найденная проблема

Создание выполняет debit → credit → transfer record с best-effort rollback. Cancellation также выполняется несколькими независимыми write-операциями.

### Требуемое поведение

Система должна гарантировать согласованное состояние после crash/error между любыми шагами. Допустимые варианты:

- transaction journal + recovery;
- explicit pending/committed state machine;
- idempotent reconciliation;
- иной механизм, который доказуемо не оставляет одну ногу перевода.

### Приёмка

Fault-injection тесты после каждого шага создания/отмены должны завершаться либо полностью проведённым, либо полностью отменённым переводом после recovery.

---

## D2. Полный inter-org flow из ТЗ

### Найденная проблема

В UI не закрыты обязательные части: выбор даты и отдельное подтверждение. Также нужен понятный history/cancel flow.

### Требуемое поведение

Flow:

1. from org + account;
2. to org + account;
3. type;
4. amount;
5. date/time;
6. comment;
7. review/confirmation;
8. запись в history/audit;
9. согласованная отмена обеих сторон.

### Приёмка

Пользователь может открыть transfer history, увидеть обе стороны, автора, дату, значения в валютах и выполнить разрешённую согласованную отмену.

---

## D3. Subtree KPI должен устранять внутренние переводы

### Найденная проблема

В consolidated subtree dashboard внутренний transfer может увеличивать gross income и expense, хотя net остаётся нулём.

### Требуемое поведение

В consolidated KPI внутренние inter-org legs выбранного subtree исключаются из внешнего income/expense/net cash-flow. В локальных org деталях обе ноги сохраняются.

### Приёмка

`IT → Studio A 100k` не добавляет +100k income и +100k expense в consolidated IT subtree KPI.

---

## D4. Account picker в subtree не должен падать на дочерних счетах

### Найденная проблема

Счета descendants показываются, но selection logic разрешает только account текущего узла.

### Требуемое поведение

Нужно выбрать однозначную продуктовую модель:

- либо subtree account bar показывает все дочерние счета и их можно фильтровать;
- либо bar показывает только счета текущей org, а дочерние доступны через breakdown.

UI и service validation должны соответствовать одной модели.

### Приёмка

Ни один отображаемый счёт не вызывает `account is outside current organization` при нормальном пользовательском действии.

---

# E. BLOCKER — валюты и модель ликвидности

## E1. Определить единую базовую денежную арифметику

### Найденная проблема

`Organization.baseCurrency` и `Account.currency` существуют, но обычный Treasury складывает суммы как единый double; у Transaction нет собственного currency/base equivalent contract.

### Требуемое поведение

Нужно формально зафиксировать:

- в какой валюте хранится `Transaction.amount`;
- где хранится original currency;
- где хранится normalized/base amount;
- в какой currency считается org balance;
- в какой currency считается subtree consolidated balance;
- какой курс и timestamp используются;
- как обрабатываются исторические операции после изменения курса.

### Приёмка

Тест с `Wesi Inc RUB`, дочерней `Studio EUR` и межорг переводом должен давать математически корректные локальные и consolidated balances без сложения RUB и EUR как одинаковых единиц.

---

## E2. Устранить две конкурирующие модели Account liquidity

### Найденная проблема

Поля `currency/minimumBalance/allowNetting` есть в `AccountModel`, но Horizon использует отдельный `AccountLiquidityMeta` box с дублирующими значениями. Этот box не синхронизируется как часть основного SyncCodec.

### Требуемое поведение

Должен существовать один authoritative source для:

- currency;
- minimum balance;
- allowNetting;
- FX haircut;
- transfer delay.

Если дополнительные risk-поля остаются отдельной сущностью, ownership и sync должны быть явными, а дублирования значений быть не должно.

### Приёмка

Два устройства после sync получают одинаковый risk profile счёта; невозможно иметь `Account.currency=EUR` и одновременно authoritative liquidity currency=RUB для того же счёта без явной причины.

---

# F. BLOCKER — recurring и background processing

## F1. Background recurring должен обслуживать все нужные организации

### Найденная проблема

Recurring automation использует текущий визуальный `OrganizationContext`, поэтому расписания других org могут не обрабатываться.

### Требуемое поведение

Background lifecycle pass обрабатывает все организации, которые должны обслуживаться данной owner/session политикой, независимо от того, какой экран/узел сейчас выбран.

### Приёмка

Если приложение открыто на `Wesi Inc only`, due recurring Studio A всё равно корректно материализуется, если это разрешено архитектурой.

---

# G. BLOCKER — Horizon multi-org independence

## G1. Background prediction registry обязан сохранять правильный org/scope

### Найденная проблема

Background Horizon maintenance может записывать prediction record с default `Wesi Inc/only`, хотя прогноз был построен в другом контексте.

### Требуемое поведение

Каждый prediction/snapshot обязан иметь корректные:

- `organizationId`;
- `scope`;
- при self прогнозе — `ownerEmployeeId/view context`;
- версию модели/калибровки при необходимости.

### Приёмка

Фоновый forecast Studio A никогда не появляется как prediction Wesi Inc.

---

## G2. Engine championship / learning не должны быть глобальными между org без обоснования

### Найденная проблема

Champion хранится глобально и может выбрать движок для одной организации по backtest другой организации.

### Требуемое поведение

Нужно определить стратегию явно:

- per-org + per-scope championship;
- либо hierarchical/global prior + local override;
- либо иная документированная модель.

Но одна организация не должна незаметно менять champion другой без продуктового решения.

### Приёмка

Backtest Studio A не меняет выбранный engine Wesi Inc, если это не предусмотрено явной общей моделью.

---

## G3. `view_forecast` должен применяться к эффективному forecast scope

### Найденная проблема

Permission проверяется на current node, а данные subtree могут включать descendants с иным permission set.

### Требуемое поведение

Forecast effective org set строится по `view_forecast`, а не только по `view_finance`/visible organizations.

### Приёмка

Пользователь не получает forecast-вывод, основанный на org, на которую у него отсутствует `view_forecast`.

---

# H. Audit и критичные изменения

## H1. Расширить audit coverage

### Найденная проблема

Transaction audit существует, но критичные изменения системы покрыты не полностью.

### Требуемое поведение

Audit должен фиксировать как минимум:

- update/delete финансовой операции;
- inter-org create/cancel/recovery;
- изменение account risk/ownership/archival;
- изменение организации и parent;
- изменение access grants и team-finance flags;
- при необходимости просмотр/экспорт чувствительных team financial данных.

Для каждой записи нужны actor, timestamp, affected org, before/after, reason/source.

### Приёмка

Администратор может восстановить хронологию любого критичного финансового или permission изменения.

---

# I. Sync integrity

## I1. Sync не должен обходить domain invariants

### Найденная проблема

Generic sync применяет decoded model прямым `box.put`, что потенциально позволяет обойти cycle checks, parent checks, account/org consistency и permission integrity.

### Требуемое поведение

Remote data проходит validation/reconciliation перед commit.

Минимум проверять:

- exactly one root;
- no cycles;
- valid parent;
- valid employee/org grants;
- transaction account belongs to transaction org;
- inter-org linked references существуют или recoverable;
- ownership non-null/effective invariant;
- invalid remote state не повреждает локальное дерево.

### Приёмка

Негативные sync tests с cyclic tree, dangling parent, bad grant и cross-org account/transaction должны fail-closed или корректно quarantine/reconcile данные.

---

# J. Ownership schema hardening

## J1. Новые financial records не должны физически создаваться без org ownership

### Найденная проблема

`organizationId` остаётся nullable в части моделей ради legacy compatibility, а `effectiveOrganizationId` подставляет root.

### Требуемое поведение

Legacy decode допускает отсутствие поля только как migration compatibility. Все новые записи после migration должны физически сохранять `organizationId`.

### Приёмка

Тест сканирует новые Account/Transaction/Recurring/Task/CRM financial entities и доказывает отсутствие новых `organizationId == null`.

---

# K. UI/UX gaps исходного ТЗ

## K1. Создание организации: optional members

Мастер создания должен позволять опционально назначить участников/первичные grants сразу при создании либо ТЗ должно явно закрепить двухшаговый flow как новое решение владельца продукта.

## K2. Inter-org date + confirmation

Добавить обязательные date/time и review/confirmation до проведения.

## K3. Team drill-down

Добавить карточку сотрудника из manager finance breakdown.

## K4. Subtree breakdown semantics

Зафиксировать, что именно пользователь может раскрывать/фильтровать внутри breakdown: org → accounts → operations → people, чтобы разные экраны не реализовали несовместимые схемы.

---

# L. Тестовая стратегия после аудита

Текущие source-string contract tests не считаются достаточным доказательством реализации ТЗ.

До финальной приёмки обязательны новые категории тестов:

### L1. Negative permission tests

- self privilege escalation;
- permission grant above actor;
- team=true without finance;
- selfFinance=false;
- forecast permission mismatch;
- update transaction to forbidden org;
- Tasks/CRM cross-org read/write denial;
- legacy TeamStats bypass.

### L2. Fault-injection finance tests

Искусственное падение после каждого write inter-org create/cancel + recovery verification.

### L3. Multi-currency tests

RUB/EUR/USD org/accounts, historical FX, transfer, local balance, subtree consolidation.

### L4. Background tests

- recurring due in non-current org;
- Horizon background prediction ownership;
- per-org model championship/learning.

### L5. Sync corruption tests

- cycle;
- duplicate root;
- missing parent;
- invalid grant;
- dangling account;
- transaction/account org mismatch;
- half inter-org transfer.

### L6. UI behavioral tests

Не `contains('text')`, а реальные действия:

- switch org;
- switch only/subtree;
- open team employee card;
- hidden/visible finance based on grant;
- select subtree account;
- execute/review/cancel inter-org flow.

---

# M. Что уже считается сохранённым фундаментом

Следующие решения не следует ломать без отдельного продуктового решения:

- `Wesi Inc` — полноценный единственный root;
- `Wesi Beats` — отдельный child, legacy история туда не переносится автоматически;
- дерево произвольной глубины;
- root нельзя архивировать;
- цикл запрещён;
- `OrganizationContext.currentOrganizationId + only/subtree`;
- legacy data без ownership мигрируют в `Wesi Inc`;
- CEO/root owner всегда сохраняет отдельный режим `Мои`;
- org finance и self finance являются разными контурами;
- `ownerEmployeeId` — дополнительная attribution, а не замена organization ownership;
- внутренние inter-org потоки исключаются только из consolidated contour, но остаются в локальной истории обеих сторон;
- реальная будущая точность Horizon не считается доказанной только зелёными тестами.

---

# N. Новая граница финальной приёмки

Функция «Иерархия организаций + персональные финансовые контуры» может считаться полностью выполненной только после:

1. закрытия всех BLOCKER A–G;
2. закрытия audit/sync integrity H–J;
3. принятия продуктовых решений по K;
4. прохождения negative/fault-injection/multi-currency/background/sync/UI behavioral suite;
5. повторного независимого аудита по исходному ТЗ + этому приложению;
6. отдельной проверки миграции на копии реальных пользовательских данных.

До этого статус реализации: **частично готово, фундамент пригоден для продолжения, финальная приёмка запрещена**.
