# WesiOS — поэтапный план развития на будущее

**Статус:** канонический Future Roadmap  
**Дата:** 2026-08-10  
**Источник решений:** Product Discovery 50Q  
**Связанные документы:** `TZ_PRODUCT_DISCOVERY_50Q.md`, `TZ_PRODUCT_DISCOVERY_50Q_FINAL.md`, `TZ_ORG_HIERARCHY_V1.md`, `TZ_ORG_HIERARCHY_V1_AUDIT_BACKLOG.md`.

---

## 0. Назначение документа

Этот документ переводит все решения Product Discovery 50Q в **логичную последовательность будущего развития WesiOS**.

Главный принцип: новые крупные функции нельзя просто добавлять по очереди в произвольном порядке. Каждый следующий уровень должен опираться на уже устойчивый предыдущий фундамент, иначе WesiOS придётся многократно переделывать при росте продукта.

Поэтому roadmap построен по зависимостям:

```text
стабильная текущая версия
→ identity / roles / security / audit
→ role-specific corporate workspace
→ tasks / projects
→ communication / documents / search
→ CRM
→ finance foundation
→ advanced finance / approvals / KPI
→ analytics / Horizon
→ personal AI / workflows
→ metadata platform / scale / internationalization
→ full resilience / emergency control
```

### Статус решений 50Q

- ответы **1–49** — планы развития на будущее;
- они не считаются автоматически обязательным scope текущего релиза;
- ответ **50A** — критерий текущего базового этапа: предусмотренные текущей версией экраны реализованы и поддерживаемые сборки проходят без build errors;
- исходные `TZ_PRODUCT_DISCOVERY_50Q*.md` остаются журналом выбранных ответов;
- этот файл является основным документом, определяющим **порядок их реализации**;
- текущие security/data-integrity дефекты из audit backlog не откладываются как «будущие функции»: дефекты существующей реализации исправляются до наращивания следующего слоя.

---

# Этап 0 — стабилизировать текущую WesiOS

**Цель:** получить надёжную базовую версию, на которую можно безопасно наслаивать будущую архитектуру.

**Связанный ответ:** 50A.

## Что сделать

1. Доделать предусмотренные текущей версией экраны.
2. Устранить build errors на поддерживаемых платформах.
3. Исправить известные blocker/security/data-integrity проблемы существующей архитектуры, особенно те, которые будут фундаментом будущих этапов.
4. Не добавлять поверх нестабильного authorization/finance слоя крупные новые модули.
5. Зафиксировать миграционную точку состояния данных перед началом Phase 1.

## Gate 0

Переход к следующему этапу разрешён, когда:

- текущие экраны не имеют известных критических дыр реализации;
- сборки проходят;
- данные существующей версии можно мигрировать без потери;
- известные критические нарушения authorization/data integrity либо исправлены, либо имеют безопасный migration plan.

> `Build/Product Ready` по 50A и `полное соответствие будущему roadmap` — разные понятия.

---

# Этап 1 — Identity, Role Context, Security и Audit Foundation

**Почему первым:** почти все дальнейшие функции зависят от того, кто пользователь, в какой роли он сейчас действует, к какой организации относится эта роль и какие данные реально разрешены. Если этот слой сделать позже, придётся переделывать Tasks, CRM, Finance, Search, AI и Workflows.

**Вопросы:** 4–12, 45–46; фундаментальная часть 49.

## 1.1. Несколько ролей у Employee — Q4

План:

- один Employee может иметь несколько `RoleAssignment`;
- пользователь явно переключает рабочий режим;
- активная роль определяет и интерфейс, и реальные security permissions.

## 1.2. Активная роль — настоящий security-context — Q5

План:

- permissions разных неактивных ролей не суммируются;
- для выполнения действия другой роли пользователь переключает context;
- authorization должен быть одинаковым в UI, service/domain, background jobs, search, AI и workflow.

## 1.3. RoleAssignment привязана к Organization — Q6

План:

- `RoleAssignment.organizationId` обязателен;
- роль имеет допустимый scope (`only` / `subtree` или дальнейшее расширение модели);
- переключение RoleAssignment атомарно меняет и Organization context.

## 1.4. Управление ролями — Q7

План:

- CEO/root owner — полный допустимый контроль;
- Organization Manager — только внутри собственной ветки и не выше своих полномочий;
- HR/Admin — отдельные делегированные права;
- назначающий не может выдать permission/scope выше собственного authority;
- создание, изменение, назначение, отзыв роли всегда аудируются.

## 1.5. Role templates — Q8

План:

- стандартный каталог WesiOS roles;
- custom roles;
- копирование шаблона и адаптация под Organization;
- role template содержит permission profile и workspace profile.

## 1.6. Независимый snapshot назначения — Q9

План:

- существующая RoleAssignment не меняется автоматически при изменении template;
- `sourceTemplateId` остаётся для происхождения и сравнения;
- обновление существующей роли из нового template — отдельное явное действие.

## 1.7. Individual permission overrides — Q10

План:

- разрешить индивидуальную настройку конкретной RoleAssignment;
- показывать diff с шаблоном;
- хранить actor/date/reason/history;
- уметь объяснить происхождение effective permission.

## 1.8. Employee lifecycle — Q11

План:

Минимальные состояния:

```text
active
vacation
on_leave
suspended
terminated
```

Для каждого статуса — своя access policy.

Termination/offboarding:

- завершение сессий;
- отзыв roles/keys/integration access;
- передача tasks/clients/projects/responsibilities;
- сохранение истории;
- контролируемая реактивация там, где она допустима.

## 1.9. Базовая видимость оргструктуры — Q12

План:

Всем сотрудникам видны на базовом уровне:

- структура Wesi;
- имя;
- должность;
- Organization;
- рабочие контакты.

Это не даёт доступа к salary, finance, tasks, CRM, KPI, audit и другим чувствительным данным.

## 1.10. Account/device security — Q45

План:

- password + passkeys;
- несколько MFA методов;
- active sessions/devices;
- remote revoke;
- new login alerts;
- trusted devices;
- session lifetime policies;
- re-authentication перед критическими действиями;
- anomaly detection;
- более строгие правила для CEO/Admin/Finance.

## 1.11. Security & Audit Center — Q46

План:

Неизменяемо фиксировать критические действия и обеспечить расследование цепочки:

```text
кто
→ в какой RoleAssignment / ProjectRoleAssignment
→ в каком Organization / Project context
→ что увидел или изменил
→ на основании какого permission
→ когда и с какой сессии/устройства
```

Дополнительно:

- access reviews;
- suspicious activity;
- session review;
- export;
- retention policies.

## 1.12. Базовая resilience foundation — часть Q49

Уже на этом этапе заложить:

- versioned backups;
- регулярные backups конфигурации roles/security;
- базовую процедуру восстановления;
- проверку того, что backup реально читается.

Полный Emergency Control Center будет завершён позже, когда появятся Finance/AI/Workflows, которыми он должен уметь управлять.

## Gate 1

Перед переходом к Phase 2 должны существовать и быть протестированы:

- ActiveWorkContext;
- role switch;
- anti-escalation;
- service-level authorization;
- employee lifecycle;
- immutable security audit;
- session/device security;
- migration существующих пользователей/permissions.

---

# Этап 2 — Role-specific Corporate Workspace

**Почему после security:** теперь можно безопасно показывать разные рабочие пространства без риска, что UI-переключение будет лишь косметическим.

**Вопросы:** 1–3.

## 2.1. WesiOS как ежедневная корпоративная ОС — Q1

План:

- каждый сотрудник работает в WesiOS ежедневно;
- WesiOS развивается не как только CEO dashboard, а как общий corporate operating workspace.

## 2.2. Существенно разные workspace по ролям — Q2

План:

Примеры:

- Developer → tasks, GitHub, projects, deadlines;
- Sales → CRM, deals, clients, plan;
- Manager → team, org tasks, finance, risks;
- CEO → organizations, consolidated finance, risks, strategy.

## 2.3. Role-specific home screen — Q3

План:

Главная страница строится из workspace profile активной роли, а не из одной универсальной страницы с множеством скрытых блоков.

## Gate 2

- переключение роли меняет home/workspace без перезапуска;
- никакой виджет не получает данных сверх active context;
- role workspace является конфигурацией, а не набором разрозненных hardcoded исключений.

---

# Этап 3 — Tasks и Projects как единый Work Graph

**Почему здесь:** Tasks и Projects должны стать базовыми сущностями, к которым затем будут подключаться CRM, Documents, Chats, Finance, GitHub и AI.

**Вопросы:** 13–17.

## 3.1. Task visibility levels — Q13

План:

```text
private
project
organization
subtree
company
```

Object visibility не может расширять permissions активной роли.

## 3.2. Task как универсальная рабочая сущность — Q14

План:

- subtasks;
- dependencies;
- priorities;
- labels;
- stages/statuses;
- comments;
- attachments;
- watchers;
- mentions;
- multiple participants/assignees;
- complete history.

Task links:

- Project;
- CRM Client/Deal;
- GitHub Issue/PR;
- Document;
- Organization;
- financial request;
- другие entity types.

## 3.3. Project как отдельный work/security-context — Q15

План:

Project содержит:

- owner Organization;
- participating Organizations;
- own team;
- own `ProjectRoleAssignment`;
- own workspace/security rules.

## 3.4. ProjectRoleAssignment строго project-scoped — Q16

Проектная роль не открывает Organization data за пределами Project.

## 3.5. Project не является мостом обхода доступа — Q17

В Project можно использовать только те org resources, которые участник и так имеет право видеть через разрешённый organization context.

## Gate 3

- Tasks и Projects полностью context-aware;
- нет глобальных unscoped CRUD путей;
- background jobs/AI hooks используют те же checks;
- project access не увеличивает ambient org access.

---

# Этап 4 — Communications, Documents, Calendar, Search и Work Inbox

**Почему раньше CRM/AI:** это общий слой совместной работы и навигации, которым затем смогут пользоваться все доменные модули.

**Вопросы:** 20–25 и 21 как отрицательное архитектурное решение.

## 4.1. Internal Messenger — Q20

План:

- direct messages;
- group chats;
- Organization channels;
- Project channels;
- threads;
- files;
- reactions;
- mentions;
- search;
- linked entities;
- message → Task.

## 4.2. Email не строим как отдельный модуль — Q21

План:

- WesiOS не становится встроенным email client;
- архитектура не должна зависеть от собственной email implementation.

## 4.3. Calendar — Q22

План:

- personal calendar;
- Organization calendar.

Сложный resource/project scheduling пока не является обязательной частью выбранного future plan.

## 4.4. Documents — Q23

План:

- folders/files;
- internal documents/notes;
- collaborative editing;
- version history;
- templates;
- approvals;
- comments/mentions;
- links to Projects/Tasks/CRM/Employees/Organizations.

## 4.5. Global Search + Command Palette + AI Search — Q24

План:

Search обязан быть security-trimmed:

- не показывать закрытый объект;
- не показывать закрытый snippet;
- не раскрывать count;
- не намекать на существование закрытой информации.

Command Palette:

- navigation;
- role/context switch;
- allowed actions.

## 4.6. Notification Center + Work Inbox — Q25

План:

Единый inbox для:

- Tasks;
- messages;
- mentions;
- approvals;
- Documents;
- CRM events;
- finance alerts;
- system events.

Дополнительно:

- priorities;
- categories;
- mute/snooze;
- delivery rules;
- inline actions;
- AI summaries только из доступных данных.

## Gate 4

- все linked previews проходят authorization;
- search/indexing respects permission revocation;
- notifications не раскрывают закрытые metadata;
- Documents/Chats имеют consistent audit model.

---

# Этап 5 — CRM Platform

**Почему после общих work entities:** CRM сразу сможет использовать Tasks, Documents, Search, Chats и Work Inbox вместо создания параллельных механизмов.

**Вопросы:** 18–19.

## 5.1. Единая глобальная карточка клиента — Q18

План:

- один real-world Client = одна global Client entity;
- Organization-specific Deals/Notes/Interactions раздельны;
- доступ к каждой организационной CRM части определяется active security-context.

## 5.2. Configurable CRM — Q19

План:

- multiple pipelines per Organization;
- custom fields;
- client/deal types;
- required fields;
- loss reasons;
- SLA;
- automations;
- role-specific views.

## Gate 5

- одна глобальная client identity не приводит к утечке org-specific history;
- CRM CRUD полностью scoped;
- CRM events интегрированы с Tasks/Search/Inbox/Documents.

---

# Этап 6 — Finance Foundation: ownership, salary, accounts, currencies, audit

**Почему finance разбит на два этапа:** сначала нужно сделать математически и юридически однозначную модель денег. Только затем approvals, budgets, subscriptions и advanced finance.

**Вопросы:** 26–28, 32, 35–37.

## 6.1. Employee Finance — Q26

План:

- salary;
- bonuses;
- commissions;
- accruals;
- payouts;
- debts;
- reimbursements;
- expected payouts;
- payout calendar;
- period comparison;
- forecast;
- per-accrual explanation.

Employee Finance — отдельный sensitive contour от Organization Finance.

## 6.2. Salary access — Q27

План:

Точную salary видят:

- сам Employee;
- CEO;
- непосредственный Manager прямого подчинённого.

Доступ определяется актуальной reporting line и active security-context; просмотр аудируется.

## 6.3. Organization Manager Finance — Q28

План:

Manager видит полные income/expense/balance **своей Organization**, но не получает автоматически parent/sibling/subtree finance.

## 6.4. Immutable Financial Audit — Q32

План хранить:

- old/new value;
- actor;
- active role/context;
- Organization;
- device/session;
- approval;
- reason.

## 6.5. Treasury core — Q35

План:

- bank/cash/virtual accounts;
- explicit Organization ownership;
- Account currency;
- minimum balance;
- available balance;
- reserved funds;
- owners/responsibles;
- constraints;
- planned flows;
- cash runway;
- liquidity alerts;
- cash-gap forecast.

## 6.6. Canonical multi-currency model — Q36

Обязательная будущая математическая модель:

```text
Organization.baseCurrency
Account.organizationId != null
Account.currency != null
MoneyEvent.organizationId != null
MoneyEvent.amount
MoneyEvent.currency
MoneyEvent.baseAmount
MoneyEvent.fxRate
MoneyEvent.fxDate
MoneyEvent.fxSource
Consolidation.reportingCurrency
```

Нельзя складывать `100 EUR + 100 USD` как `200`.

## 6.7. Atomic InterOrgTransfer — Q37

План:

- единая transfer entity;
- две связанные legs;
- all-or-nothing posting;
- status;
- dates;
- currencies/FX;
- approvals support;
- reverse/cancel;
- complete audit;
- FX differences;
- internal-flow elimination при consolidation.

## Gate 6

До advanced finance:

- нет nullable/ambiguous money ownership;
- все money events имеют currency semantics;
- cross-org transfer atomic under injected failures;
- employee finance и org finance не смешиваются;
- audit невозможно обойти через alternate service/sync path.

---

# Этап 7 — Advanced Finance, Approvals, Budgets, Recurring и KPI

**Вопросы:** 29–31, 33–34.

## 7.1. Expense Flow — Q29

План:

- personal/corporate expenses;
- receipts/files;
- categories;
- Project/Organization attribution;
- advances;
- partial reimbursement;
- refunds;
- status history;
- limits;
- expense policy.

## 7.2. Approval Engine — Q30

План:

Approval policy зависит от:

- Organization;
- amount;
- category;
- Project;
- payment type;
- risk.

Поддержать:

- sequential approvals;
- parallel approvals;
- absence substitution;
- deadlines;
- escalations;
- audit trail.

## 7.3. Subscription / Recurring Lifecycle — Q31

План:

- contract;
- owner;
- category;
- Organization;
- next charge;
- auto-renew;
- price changes;
- future cash forecast;
- cancellation;
- renewal approval;
- unused/price-anomaly alerts.

## 7.4. KPI Engine — Q33

План:

- goals;
- formulas;
- plan/fact;
- periods;
- owners;
- weights;
- sources from CRM/Tasks/Finance/Projects/GitHub;
- history;
- custom dashboards;
- AI explanations within allowed data.

## 7.5. Hierarchical Budgets — Q34

План:

- Organization/department/Project budgets;
- categories/periods;
- plan/fact;
- versions;
- reserved funds;
- carryover;
- scenarios;
- over-limit approvals.

## Gate 7

- approvals не могут быть bypassed direct service call;
- recurring jobs обрабатывают все нужные Organizations, а не только открытую UI context;
- budgets/liquidity/recurring используют один money model;
- fault-injection tests покрывают payment lifecycle.

---

# Этап 8 — Analytics, Report Builder и Horizon

**Почему до autonomous AI:** сначала система должна научиться правильно объяснять и агрегировать данные в пределах permissions.

**Вопросы:** 38–40.

## 8.1. Report Builder — Q38

План:

Источники:

- Finance;
- CRM;
- Tasks;
- Projects;
- HR;
- GitHub;
- KPI;
- другие разрешённые modules.

Функции:

- formulas;
- groupings;
- filters;
- period comparison;
- saved views;
- scheduled reports;
- dashboards;
- AI explanation.

Все aggregations security-trimmed.

## 8.2. Role-aware Explainable Horizon — Q39

План:

Horizon показывает:

- forecast;
- confidence;
- factors;
- reasons;
- alternative scenarios;
- conditions that could change forecast.

Forecast никогда не строится на данных, недоступных active context.

## 8.3. Horizon остаётся advisor-only — Q40

План:

- Horizon анализирует;
- Horizon прогнозирует;
- Horizon рекомендует;
- Horizon **не исполняет действия самостоятельно**.

## Gate 8

- report aggregates не раскрывают закрытые данные;
- Horizon model selection/configuration не является глобальным cross-org leak;
- background predictions всегда имеют explicit org/scope/security tags;
- explainability позволяет понять источник прогноза без раскрытия forbidden inputs.

---

# Этап 9 — Personal AI Agent и Workflow Engine

**Почему после всех доменных моделей:** AI-агент и workflows должны использовать готовые secure APIs, а не становиться отдельным обходным путём к данным.

**Вопросы:** 41–43.

## 9.1. Employee AI Agent — Q41

План:

AI сотрудника сможет:

- искать разрешённые данные;
- готовить Documents;
- анализировать CRM/Tasks/Finance;
- создавать Tasks;
- работать с GitHub;
- запускать permitted workflows;
- выполнять другие allowed actions.

Ключевое правило: AI действует **как active role**, без hidden superuser rights.

## 9.2. AI Memory Isolation — Q42

План разделить:

- personal memory;
- RoleAssignment memory;
- Organization memory;
- Project memory.

При переключении контекста запрещён неявный перенос/использование закрытой информации.

## 9.3. Workflow Engine — Q43

План:

- triggers;
- conditions;
- branching;
- delays;
- approvals;
- actions;
- notifications;
- versions;
- run journal;
- retries;
- loop protection;
- explicit security-context per step.

Workflow не наследует лишние права создателя.

## Gate 9

- AI/tool calls проходят тот же authorization service, что manual user actions;
- AI memory isolation имеет negative tests;
- workflows replayable/auditable;
- destructive actions имеют safe confirmation/approval policy;
- Horizon остаётся отдельным advisor-only subsystem.

---

# Этап 10 — Metadata-driven Platform, Offline Read Cache и International Scale

**Вопросы:** 44, 47–48.

## 10.1. Read-only Offline Cache — Q44

План:

- без сети доступен просмотр ранее загруженных permitted данных;
- offline writes не являются целевой функцией;
- критические actions требуют online;
- cache encrypted/protected;
- revoked permissions не должны жить в cache бессрочно;
- offline cache не является источником authorization.

## 10.2. Metadata-driven WesiOS — Q47

План настраивать через UI:

- entity types;
- fields;
- forms;
- statuses;
- views;
- dashboards;
- role templates;
- KPI;
- CRM pipelines;
- workflows;
- entity relationships.

Hard security/finance/audit invariants нельзя отключить metadata configuration.

## 10.3. Internationalization and Scale — Q48

План:

- user language/region/timezone;
- Organization business timezone;
- UTC + local business-time context;
- multiple currencies/date/number formats;
- many Organizations/Projects;
- thousands of Employees;
- millions of transactions/messages.

Технические требования:

- server-side pagination;
- server-side filtering;
- indexes/search indexes;
- incremental loading;
- отсутствие обязательного full database scan на клиенте.

## Gate 10

- metadata cannot bypass security;
- performance/load tests подтверждают выбранный target scale;
- timezone/currency migrations deterministic;
- permission revocation корректно отражается на cache/search indexes.

---

# Этап 11 — Full Resilience и CEO Emergency Control Center

**Почему последний как функционально полный этап:** базовые backup/security механизмы закладываются в Phase 1, но полноценный emergency center должен уже понимать все поздние подсистемы: Finance, Integrations, AI, Workflows, Sessions.

**Вопрос:** 49.

## 11.1. Disaster Recovery

План:

- versioned backups;
- point-in-time recovery;
- automated restore verification;
- export critical data to open formats;
- mass-delete/corruption protection;
- Health / Status Center;
- documented DR procedures.

## 11.2. CEO Emergency Control Center

В аварийной ситуации уполномоченная root emergency-role сможет:

- revoke all sessions;
- revoke/freeze keys and integration credentials;
- temporarily freeze financial operations;
- disable external integrations;
- disable Employee AI Agents;
- stop Workflow Engine;
- switch WesiOS to safe mode;
- perform controlled recovery/unfreeze.

Каждое emergency action:

- требует strong re-authentication;
- фиксирует actor/time/reason/session/context;
- попадает в immutable audit;
- не является скрытым способом обойти обычный security model.

## Gate 11

- восстановление из backup реально проверено, а не только описано;
- emergency freeze/unfreeze протестирован;
- audit сохраняется даже в safe mode;
- отказ одной subsystem не приводит к неконтролируемой порче остальных.

---

# Карта вопросов 50Q → этапы

| Вопрос | Решение | Этап |
|---|---|---|
| 1 | WesiOS = corporate OS | 2 |
| 2 | role-specific UI | 2 |
| 3 | role-specific home | 2 |
| 4 | multiple roles | 1 |
| 5 | active role = security-context | 1 |
| 6 | role bound to Organization | 1 |
| 7 | combined role administration | 1 |
| 8 | templates + custom roles | 1 |
| 9 | assignment snapshot | 1 |
| 10 | individual overrides + audit | 1 |
| 11 | employee lifecycle | 1 |
| 12 | global basic org chart | 1 |
| 13 | task visibility levels | 3 |
| 14 | universal Task entity | 3 |
| 15 | Project security-context | 3 |
| 16 | project role project-only | 3 |
| 17 | project does not bypass org permissions | 3 |
| 18 | global Client + org CRM data | 5 |
| 19 | configurable CRM | 5 |
| 20 | internal messenger | 4 |
| 21 | no built-in email client | 4 |
| 22 | personal + org calendar | 4 |
| 23 | Documents as first-class entities | 4 |
| 24 | global/AI search | 4 |
| 25 | Work Inbox | 4 |
| 26 | My Finance | 6 |
| 27 | salary access model | 6 |
| 28 | manager sees own org finance | 6 |
| 29 | Expense Flow | 7 |
| 30 | Approval Engine | 7 |
| 31 | recurring/subscription lifecycle | 7 |
| 32 | immutable finance audit | 6 |
| 33 | KPI Engine | 7 |
| 34 | hierarchical budgets | 7 |
| 35 | Treasury | 6 |
| 36 | multi-currency canonical model | 6 |
| 37 | atomic InterOrgTransfer | 6 |
| 38 | Report Builder | 8 |
| 39 | role-aware Horizon | 8 |
| 40 | Horizon advisor-only | 8 |
| 41 | Employee AI Agent | 9 |
| 42 | AI memory isolation | 9 |
| 43 | Workflow Engine | 9 |
| 44 | read-only offline cache | 10 |
| 45 | account/device security | 1 |
| 46 | Security & Audit Center | 1 |
| 47 | metadata-driven platform | 10 |
| 48 | international scale | 10 |
| 49 | resilience + Emergency Center | 1 foundation + 11 completion |
| 50 | current readiness = current screens + build success | 0 |

---

# Правило перехода между этапами

Следующий этап **не начинается как массовая реализация**, пока предыдущий не прошёл свой Gate.

Разрешены только подготовительные refactor/API contracts, если они не увеличивают пользовательский scope и нужны для безопасного следующего перехода.

Для каждого этапа перед реализацией создаётся отдельный implementation package:

1. architecture/TZ;
2. data model and migrations;
3. service/domain authorization contracts;
4. UI flows;
5. sync/background behavior;
6. audit requirements;
7. negative/security tests;
8. fault-injection tests там, где есть деньги/atomic operations;
9. backwards compatibility;
10. rollback plan;
11. CI/release gate.

---

# Definition of a качественного перехода

Переход `Phase N → Phase N+1` считается правильным, если одновременно выполнено:

1. данные предыдущего этапа имеют однозначную ownership/scope модель;
2. миграция старых данных протестирована;
3. UI не является единственной линией защиты — service/domain слой enforce permissions;
4. background/sync/AI paths не обходят те же invariants;
5. negative tests подтверждают запрет недопустимого доступа;
6. fault-injection подтверждает целостность критических операций;
7. audit способен объяснить критическое действие;
8. нет временного legacy bypass, который следующий этап начнёт использовать как API;
9. есть rollback/recovery path;
10. только после этого новый слой становится основой для следующего.

---

# Что не делать

Чтобы не получить дорогую повторную переделку WesiOS, нельзя:

- сначала делать AI Agent, а потом придумывать permissions;
- сначала делать Report Builder, а потом пытаться фильтровать утечки данных;
- сначала добавлять мультивалютность поверх raw double ledger;
- строить Project access поверх глобальных unscoped Tasks/CRM;
- делать metadata customization до hard security boundaries;
- полагаться на UI-hidden controls вместо service authorization;
- начинать крупный следующий этап, пока предыдущий имеет известные data-integrity blockers.

---

## Итоговая последовательность

```text
Phase 0  — Current stabilization / Build Product Ready
Phase 1  — Identity + Roles + Security + Audit foundation
Phase 2  — Role-specific Corporate Workspace
Phase 3  — Tasks + Projects / Work Graph
Phase 4  — Messenger + Documents + Calendar + Search + Inbox
Phase 5  — CRM Platform
Phase 6  — Finance Foundation + Treasury + Currency + Atomic Transfers
Phase 7  — Expenses + Approvals + Recurring + Budgets + KPI
Phase 8  — Report Builder + Explainable Horizon
Phase 9  — Employee AI Agent + Workflow Engine
Phase 10 — Metadata Platform + Offline Read Cache + International Scale
Phase 11 — Full Disaster Recovery + CEO Emergency Control Center
```

**Это основной порядок будущего развития WesiOS.** Исходные ответы 50Q сохраняются как source-of-decision, но реализация должна идти по этапам и Gates из этого roadmap.