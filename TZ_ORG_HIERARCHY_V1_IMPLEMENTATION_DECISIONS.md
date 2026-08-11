# WesiOS — Organization Hierarchy v1: implementation decisions

Статус: **обязательное нормативное приложение к `TZ_ORG_HIERARCHY_V1.md` для текущей реализации и её повторной приёмки**.  
Состояние приёмки: **remediation in progress; merge/release запрещены до прохождения acceptance gate из этого документа**.

Этот документ не является future-roadmap. Он фиксирует решения, инварианты безопасности, integrity-правила, обязательные UI-сценарии и доказательства, необходимые для однозначной реализации уже разработанной иерархии организаций.

---

## 1. Subtree semantics

`OrganizationContext = organizationId + scope(only|subtree)` задаёт пользовательский контур, но сам по себе не является разрешением на данные.

Фактический набор данных всегда строится как пересечение:

`requested context ∩ effective permission set ∩ object/service invariant`.

### `only`

- Treasury, Accounts, Tasks, CRM, Finance, Horizon и другие org-aware сервисы работают только с выбранной организацией.
- Наличие прав на дочерние организации не добавляет их данные в `only`.

### `subtree`

- Контур включает выбранную организацию и её descendants.
- Каждый модуль дополнительно пересекает subtree со своим permission set.
- `view_finance` управляет финансовыми данными каждой effective organization.
- `view_forecast` не может быть шире финансовой видимости: эффективный forecast permission требует одновременно `view_forecast + view_finance`.
- `canViewTeamFinance` проверяется отдельно для каждой organization; флаг на parent не раскрывает персональные строки child, если соответствующая effective grant-политика этого не разрешает.

### Treasury account bar

Принято решение: **в subtree account bar показывает доступные счета всех effective organizations выбранной ветки, и каждый показанный счёт должен быть реально selectable**.

- `AccountService.getAll()` возвращает только счета effective context.
- `AccountService.select(id)` разрешает любой счёт из этого же scoped набора.
- Выбор descendant account фильтрует операции по этому счёту.
- Отображаемый счёт не может завершиться ошибкой `account is outside current organization` при нормальном пользовательском выборе.

### Subtree finance breakdown

- Верхний consolidated KPI показывает внешние для выбранного subtree денежные потоки.
- Обе ноги transfer, полностью находящегося внутри subtree, исключаются из consolidated income/expense/net.
- Локальная история каждой организации обе ноги сохраняет.
- Breakdown раскрывает organization-level balances; Accounts Bar даёт следующий уровень `organization → account → operations`.
- Персональные строки людей не являются частью обычного Treasury breakdown и доступны только через My Finance при `canViewTeamFinance`.

---

## 2. Personal finance semantics

Personal finance и organization finance — независимые контуры.

- `canViewSelfFinance` управляет self metrics, risks, history и self forecast.
- `view_finance` не даёт автоматически чужие персональные строки.
- `canViewTeamFinance` без `view_finance` неэффективен.
- Team breakdown строится отдельно по каждой effective organization.
- Employee drill-down доступен только из уже разрешённого team-finance contour и повторно проверяет разрешение при открытии.
- Смешанные grants в subtree не могут использовать parent-флаг `canViewTeamFinance` для раскрытия персональных строк child, у которого нет соответствующего эффективного разрешения.

### Live permission revocation

Чувствительные экраны обязаны реагировать на `OrganizationAccessService.revision` без перезапуска приложения.

- После revoke/изменения grant уже открытый экран не продолжает показывать устаревшие чувствительные данные.
- `My Finance`, legacy `TeamStatsScreen` и аналогичные экраны обязаны перезагружать scope при изменении organization grants.
- Перед открытием персональной карточки/чувствительного drill-down permission проверяется повторно в момент действия, чтобы stale UI не использовал уже отозванное право.

---

## 3. Canonical money model v1

Для совместимости с существующей историей WesiOS принята единая reporting currency **RUB** для Organization Hierarchy v1.

### Transaction

`TransactionModel.amount` — canonical reporting amount в RUB.

Дополнительно сохраняются:

- `originalAmount` — исходная сумма пользовательского/внешнего события;
- `originalCurrency` — исходная валюта;
- `organizationBaseAmount` — зафиксированный эквивалент в `Organization.baseCurrency`;
- `organizationBaseCurrency`;
- `fxRateToReporting` — использованный курс в reporting currency;
- `fxRateAt` — дата/время курса;
- `fxSource` — источник/механизм курса.

Историческая операция не пересчитывается задним числом при изменении текущего FX-rate: её нормализованные значения уже зафиксированы в записи.

### Organization balance

- Локальный balance организации может быть представлен в `Organization.baseCurrency` через `organizationBaseAmount`.
- Consolidated subtree arithmetic выполняется в canonical reporting RUB.
- Сырые EUR/USD/RUB никогда не складываются как одинаковые единицы.

### Account currency

`Account.currency` описывает физическую валюту liquidity location. Authoritative risk-поля хранятся в `AccountModel`:

- `currency`;
- `minimumBalance`;
- `allowNetting`;
- `fxHaircut`;
- `transferDelayDays`.

Отдельный legacy `AccountLiquidityService` является compatibility facade и не имеет второго authoritative набора этих полей.

### Money ownership invariant

Для каждого финансового объекта выполняется:

`Transaction.organizationId == Account.organizationId`.

Нельзя «перетащить» уже используемый Account в другую organization так, чтобы существующие Transaction/InterOrgTransfer начали ссылаться на счёт другой организации.

- Если Account уже имеет ledger references, изменение `organizationId` запрещается.
- Если когда-либо понадобится перенос счёта между организациями, это должен быть отдельный migration/reclassification flow с явным переносом/переоформлением зависимостей и audit, а не обычный `AccountService.save()`.
- Новая Transaction обязана иметь валидные active Organization и Account одной организации.
- Re-ownership Transaction из одной org в другую — двухсторонняя authorization boundary: actor должен иметь право редактировать как исходную, так и целевую organization; целевой Account обязан принадлежать целевой org.

---

## 4. InterOrgTransfer durability contract

Inter-org transfer является одной логической финансовой операцией, хотя Hive не предоставляет cross-box ACID transaction.

Гарантия реализуется через **durable write-ahead journal + idempotent reconciliation**:

- journal/intent записывается до ledger legs;
- active transfer после recovery обязан сходиться к двум связанным legs;
- cancelled transfer после recovery обязан сходиться к нулю legs;
- отдельную leg нельзя удалить обычным transaction flow;
- fault-injection после каждого write create/cancel обязан восстанавливаться в согласованное состояние;
- recovery фиксируется в critical audit;
- repeated recovery должен быть idempotent и не создавать дубликаты проводок.

В consolidated subtree обе legs внутреннего transfer исключаются из внешнего cash-flow, но остаются в локальных histories.

### InterOrg UI contract

Flow обязан включать:

1. from organization + account;
2. to organization + account;
3. type;
4. amount/currency и base amounts при необходимости;
5. date/time;
6. comment;
7. отдельный confirmation/review step;
8. history;
9. согласованную отмену обеих проводок через transfer, а не удаление отдельной leg.

---

## 5. Background processing

Background maintenance не использует визуальный org context как список организаций для обслуживания.

- Recurring processing проходит все organizations, разрешённые maintenance/session policy.
- Owner обслуживает весь active tree.
- `manage_recurring` является реальной service-level границей для пользовательского создания/редактирования recurring schedules.
- Background Horizon строится per organization и сохраняет explicit `organizationId + scope`.
- Learning/championship storage разделён как минимум по `organizationId + scope`.
- Одна organization не меняет незаметно champion другой.
- Background prediction не может по умолчанию записаться как `Wesi Inc / only`, если фактически рассчитана для child org.

---

## 6. Authorization boundary

UI никогда не является единственной защитой. Все критические права проверяются в domain/service layer.

### Organization grants / `manage_members`

Actor не может выдать больше полномочий, чем имеет сам.

- Нельзя grant permission, которого нет у actor в целевой organization.
- Нельзя grant `includeSubtree=true`, если actor не имеет эквивалентной subtree capability.
- Нельзя grant `canViewTeamFinance`, если actor сам не имеет такого effective права.
- Self-grant не может повысить собственные permissions, scope или finance flags.
- `createdBy`, переданный вызывающим кодом, не заменяет authenticated actor при обычной пользовательской операции.
- Owner является явным исключением с full root-subtree authority.

### `OrganizationService`

Create/update/archive/restore должны проверять `manage_org_settings` внутри сервиса.

- Create child требует manage право на parent.
- Re-parent требует authorization и на текущий узел, и на новый parent.
- Tree invariants (`one root`, no cycle, no root archive) действуют независимо от UI.

### Tasks

Tasks являются org-aware уже в текущей реализации.

- `getAll()` не является глобальным обходом authorization.
- Обычный сотрудник видит только доступные ему org + собственные/разрешённые задачи.
- Manager получает более широкий people-scope только в пределах разрешённого org context.
- CRUD повторно проверяет organization и ownership.
- Нельзя создать/переназначить задачу в недоступную organization или другому сотруднику без соответствующего manager capability.

### CRM

Основной CRM UI и сервисы работают через scoped reads/writes.

- `clients/deals/interactions/summary` не раскрывают глобальные данные вне active org context.
- Обычный сотрудник ограничен своими client/deal ownership rules.
- Manager может работать шире только внутри разрешённого org scope.
- Deal и Client должны принадлежать одной organization.
- Interaction не может использовать скрытый parent как обход доступа.

### Legacy TeamStats

`canSeeOthersStats` не является глобальным bypass.

- Он разрешает показатели других людей только внутри текущего доступного `only/subtree` context.
- Tasks для расчёта берутся через org-scoped `TaskService`.
- Live revoke grant обязан немедленно пересчитать список людей/задач.

---

## 7. Sync boundary

Remote sync не является доверенным domain actor.

До `box.put` org-sensitive entities проходят integrity validation:

- exactly one root / no cycles / valid parent;
- valid active organization references;
- Account belongs to Transaction organization;
- grants refer to existing employee/org and satisfy permission integrity;
- magic `createdBy=sync` не является способом создать privilege;
- InterOrg references должны быть согласованными/recoverable;
- invalid remote state fail-closed и не повреждает локальный tree.

### Synced grants

Transport identity не является authorization principal.

- `createdBy=sync` / `untrusted-sync` не может создать или повысить grant.
- Обычный synced grant принимается только если реальный actor существует и на текущем локальном состоянии мог выдать все входящие permissions/scope/finance flags.
- Legacy migration-grant допускается только в **точной детерминированной форме**, которую `ensureLegacyGrants()` мог создать из уже синхронизированного legacy Employee.
- Migration marker не может использоваться для произвольного admin grant.
- Owner legacy migration grant допускает только exact full-root-subtree shape.

### Destructive sync / tombstones

Remote delete не должен разрушать referential integrity.

Запрещается принять tombstone, если удаление оставит dangling references или нарушит дерево. Минимально:

- root organization удалять нельзя;
- organization с child organizations удалять нельзя;
- organization, на которую ссылаются Accounts, Transactions, Grants или InterOrgTransfer, физически удалять нельзя;
- Account, на который ссылается Transaction или InterOrgTransfer, физически удалять нельзя;
- финансовая/организационная история должна архивироваться или проходить отдельный согласованный migration flow вместо silent remote delete.

---

## 8. Physical ownership after migration

Nullable `organizationId` сохраняется в schema только для чтения legacy records.

После org-v1 migration все новые записи, создаваемые обычными сервисами, физически получают organization ownership. `effectiveOrganizationId` не должен использоваться как оправдание для создания новых `organizationId == null` records.

Legacy data без ownership мигрирует только в **Wesi Inc**. **Wesi Beats** остаётся отдельным child и не получает старую историю автоматически.

Обязательная физическая ownership проверка охватывает как минимум:

- Accounts;
- Transactions;
- recurring records;
- Tasks;
- CRM Client/Deal;
- InterOrgTransfer;
- organization grants.

---

## 9. Critical audit

Критические действия обязаны оставлять audit, а не зависеть только от текущего состояния объектов.

Audit нужен как минимум для:

- organization create/update/archive/restore;
- grant create/update/revoke;
- Account create/update/archive/delete;
- Transaction update/delete и sensitive re-ownership;
- InterOrg intent/commit/cancel/recovery;
- других security/finance изменений, добавляемых в этот контур.

Audit должен содержать минимум:

- actor;
- timestamp;
- entity id/type;
- organization id;
- before/after для mutation, где применимо;
- reason/source для recovery/system/migration действий.

Чтение финансового audit также подчиняется `view_finance`; audit не может стать обходным каналом для скрытых финансовых данных.

---

## 10. UI requirements уже текущего org-v1

Это не future-roadmap; перечисленное входит в текущий org hierarchy acceptance.

- Organization switcher: `only/subtree`.
- Organizations screen: tree, create child, edit, archive/restore, members/permissions.
- Organization creation wizard: optional member assignment; стартовое назначение даёт только базовый `view`, дополнительные права настраиваются отдельно.
- Treasury subtree: корректные consolidated KPI без double-count внутренних transfer.
- Descendant Account из Accounts Bar реально selectable.
- My Finance: self/org/subtree, team rows только при effective `view_finance + canViewTeamFinance`, employee drill-down с повторной permission check.
- InterOrg: date/time, confirmation, history, cancel flow.
- Legacy TeamStats: org-scoped people/tasks и live grant revocation.

---

## 11. Acceptance evidence

Source-string contract tests не считаются доказательством этих решений.

Обязательные behavioral suites включают:

- negative privilege escalation/self-elevation tests;
- service-level Organization authorization;
- Tasks/CRM/legacy TeamStats cross-org denial;
- live permission revocation;
- self/team finance negative cases и mixed-grant subtree;
- transaction re-ownership denial;
- Account ownership immutability при существующих ledger references;
- `manage_recurring` negative tests;
- inter-org create/cancel fault injection после каждого существенного write;
- multi-currency local/consolidated arithmetic;
- subtree internal-transfer elimination;
- non-current-org recurring;
- explicit Horizon org/scope ownership;
- effective `view_forecast + view_finance` requirement;
- per-org championship isolation;
- sync corruption rejection;
- synced grant anti-forgery;
- destructive sync/tombstone referential-integrity tests;
- physical ownership scan;
- realistic legacy migration rehearsal;
- widget tests с реальными UI actions: organization switch, only/subtree switch, subtree account selection, team-finance hidden/visible + employee card, live revoke, inter-org review/execute/cancel.

### Exact-head CI gate

Перед повторной приёмкой **один и тот же финальный commit SHA** обязан пройти:

1. `flutter analyze --no-fatal-infos`;
2. targeted remediation/security/integrity/UI/fault-injection suite;
3. полный `flutter test`;
4. Android build;
5. Windows release build.

Зелёный CI на более старом SHA не считается доказательством финального состояния.

### Independent re-audit gate

После зелёного exact-head CI проводится повторный source-level аудит с нуля. Он должен отдельно проверить не только наличие тестов, но и возможность обхода через:

- raw/service APIs;
- stale UI state;
- background jobs;
- sync apply/tombstones;
- malformed/legacy grants;
- cross-org re-ownership;
- linked InterOrg legs;
- multi-currency arithmetic;
- legacy migration.

Только после этого можно менять статус remediation на accepted и отдельно запрашивать решение о merge/release.

---

## 12. Migration acceptance

Автоматический fixture/rehearsal обязателен, но не равен проверке на реальных пользовательских данных.

Перед production rollout необходимо, когда доступна безопасная копия реальных данных:

1. прогнать org-v1 migration на копии;
2. проверить, что вся legacy history без ownership физически стала `Wesi Inc`;
3. подтвердить, что `Wesi Beats` не получил старую историю автоматически;
4. проверить absence dangling account/transaction/task/CRM references;
5. сверить balances/operation counts до и после migration;
6. сохранить migration log и rollback/recovery evidence.

Если реальный dataset не предоставлен, это явно отмечается в release report как непроверенное внешнее условие, а не считается автоматически выполненным.

---

## 13. Текущий remediation status

Рабочий PR: **#104 `fix: organization hierarchy audit remediation`**, ветка `agent/org-hierarchy-remediation-1`, base `agent/org-hierarchy-v1`.

На момент записи этого раздела:

- PR остаётся draft и не merged;
- основные blocker-классы из независимого аудита перенесены в service/domain invariants и behavioral tests;
- в ходе повторного source review дополнительно найдены и внесены в ТЗ edge-case’ы live revocation, account re-ownership и destructive sync/tombstones;
- текущий exact-head verification ещё **не принят**: после последнего hardening CI должен быть снова доведён до полностью зелёного состояния;
- merge и production release до прохождения раздела 11 запрещены.

Ни зелёная сборка сама по себе, ни этот документ сами по себе не доказывают будущую прогнозную точность Horizon.
