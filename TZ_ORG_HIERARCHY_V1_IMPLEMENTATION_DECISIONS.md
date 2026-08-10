# WesiOS — Organization Hierarchy v1: implementation decisions

Статус: **нормативное приложение к `TZ_ORG_HIERARCHY_V1.md` и `TZ_ORG_HIERARCHY_V1_AUDIT_BACKLOG.md` для текущей реализации**.

Этот документ не является future-roadmap. Он фиксирует решения, необходимые для однозначной реализации и повторной приёмки уже разработанной иерархии организаций.

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
- `view_forecast` не может быть шире финансовой видимости: эффективный forecast permission требует `view_forecast + view_finance`.
- `canViewTeamFinance` проверяется отдельно для каждой organization; флаг на parent не раскрывает персональные строки child, если соответствующая effective grant-политика этого не разрешает.

### Treasury account bar

Принято решение: **в subtree account bar показывает доступные счета всех effective organizations выбранной ветки, и каждый показанный счёт должен быть реально selectable**.

- `AccountService.getAll()` возвращает только счета effective context.
- `AccountService.select(id)` разрешает любой счёт из этого же scoped набора.
- выбор descendant account фильтрует операции по этому счёту;
- отображаемый счёт не может завершиться ошибкой `account is outside current organization` при нормальном пользовательском выборе.

### Subtree finance breakdown

- Верхний consolidated KPI показывает внешние для выбранного subtree денежные потоки.
- Обе ноги transfer, полностью находящегося внутри subtree, исключаются из consolidated income/expense/net.
- Локальная история каждой организации обе ноги сохраняет.
- Breakdown раскрывает organization-level balances; Accounts Bar даёт следующий уровень `organization → account → operations`.
- Персональные строки людей не являются частью обычного Treasury breakdown и доступны только через My Finance при `canViewTeamFinance`.

## 2. Personal finance semantics

Personal finance и organization finance — независимые контуры.

- `canViewSelfFinance` управляет self metrics, risks, history и self forecast.
- `view_finance` не даёт автоматически чужие персональные строки.
- `canViewTeamFinance` без `view_finance` неэффективен.
- Team breakdown строится отдельно по каждой effective organization.
- Employee drill-down доступен только из уже разрешённого team-finance contour и повторно проверяет разрешение при открытии.

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

- локальный balance организации может быть представлен в `Organization.baseCurrency` через `organizationBaseAmount`;
- consolidated subtree arithmetic выполняется в canonical reporting RUB;
- сырые EUR/USD/RUB никогда не складываются как одинаковые единицы.

### Account currency

`Account.currency` описывает физическую валюту liquidity location. Authoritative risk-поля хранятся в `AccountModel`:

- `currency`;
- `minimumBalance`;
- `allowNetting`;
- `fxHaircut`;
- `transferDelayDays`.

Отдельный legacy `AccountLiquidityService` является compatibility facade и не имеет второго authoritative набора этих полей.

## 4. InterOrgTransfer durability contract

Inter-org transfer является одной логической финансовой операцией, хотя Hive не предоставляет cross-box ACID transaction.

Гарантия реализуется через **durable write-ahead journal + idempotent reconciliation**:

- journal/intent записывается до ledger legs;
- active transfer после recovery обязан сходиться к двум связанным legs;
- cancelled transfer после recovery обязан сходиться к нулю legs;
- отдельную leg нельзя удалить обычным transaction flow;
- fault-injection после каждого write create/cancel обязан восстанавливаться в согласованное состояние;
- recovery фиксируется в critical audit.

В consolidated subtree обе legs внутреннего transfer исключаются из внешнего cash-flow, но остаются в локальных histories.

## 5. Background processing

Background maintenance не использует визуальный org context как список организаций для обслуживания.

- recurring processing проходит все organizations, разрешённые maintenance/session policy;
- owner обслуживает весь active tree;
- background Horizon строится per organization и сохраняет explicit `organizationId + scope`;
- learning/championship storage разделён как минимум по `organizationId + scope`;
- одна organization не меняет незаметно champion другой.

## 6. Sync boundary

Remote sync не является доверенным domain actor.

До `box.put` org-sensitive entities проходят integrity validation:

- exactly one root / no cycles / valid parent;
- valid organization references;
- account belongs to transaction organization;
- grants refer to existing employee/org and satisfy permission integrity;
- magic `createdBy=sync` не является способом создать privilege;
- inter-org references должны быть согласованными/recoverable;
- invalid remote state fail-closed и не повреждает локальный tree.

## 7. Physical ownership after migration

Nullable `organizationId` сохраняется в schema только для чтения legacy records.

После org-v1 migration все новые записи, создаваемые обычными сервисами, физически получают organization ownership. `effectiveOrganizationId` не должен использоваться как оправдание для создания новых `organizationId == null` records.

Legacy data без ownership мигрирует только в **Wesi Inc**. **Wesi Beats** остаётся отдельным child и не получает старую историю автоматически.

## 8. Acceptance evidence

Source-string contract tests не считаются доказательством этих решений.

Обязательные behavioral suites включают:

- negative permission/access tests;
- Tasks/CRM/legacy TeamStats cross-org denial;
- self/team finance negative cases;
- inter-org fault injection create/cancel;
- multi-currency local/consolidated arithmetic;
- non-current-org recurring;
- explicit Horizon org/scope ownership;
- per-org championship isolation;
- sync corruption rejection;
- physical ownership scan;
- realistic legacy migration rehearsal;
- widget tests с реальными UI actions: organization switch, only/subtree switch, subtree account selection, team-finance hidden/visible + employee card, inter-org review/execute/cancel.

Ни зелёная сборка, ни этот документ сами по себе не доказывают будущую прогнозную точность Horizon.
