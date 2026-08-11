# WesiOS — Organization Hierarchy v1: полный remediation-status

**Статус документа:** обязательное нормативное приложение к `TZ_ORG_HIERARCHY_V1.md`, `TZ_ORG_HIERARCHY_V1_IMPLEMENTATION_DECISIONS.md` и исходному независимому audit backlog.  
**Назначение:** зафиксировать весь объём исправлений после независимого аудита, текущие implementation-инварианты, evidence requirements и оставшиеся acceptance-gates.  
**Рабочий контур:** PR #104 `fix: organization hierarchy audit remediation`, branch `agent/org-hierarchy-remediation-1`, base `agent/org-hierarchy-v1`.  
**Правило:** этот документ не является future-roadmap. Будущие функции WesiOS живут отдельно в `TZ_WESIOS_FUTURE_ROADMAP.md`.

---

## 1. Главный принцип текущей доработки

Иерархия организаций не принимается по факту зелёной сборки или наличия экранов. Для текущего org-v1 обязательны одновременно:

1. service/domain-level authorization;
2. отсутствие cross-org/cross-employee bypass;
3. целостная monetary ownership model;
4. crash-safe inter-org transfers;
5. корректная multi-currency arithmetic;
6. независимые org/scope contours Horizon;
7. sync validation и защита referential integrity;
8. live reaction на revoke/change permissions;
9. behavioral/negative/fault-injection tests;
10. exact-head CI;
11. повторный независимый source-level audit;
12. отдельная миграционная проверка на копии реальных данных перед production rollout, когда такая копия доступна.

До прохождения всех обязательных gates PR остаётся draft. Merge/release не выполняются автоматически.

---

# 2. Полная матрица замечаний независимого аудита

Статусы ниже означают состояние **реализации в remediation-ветке**, а не финальную приёмку. Даже пункт `IMPLEMENTED` считается окончательно закрытым только после exact-head CI + повторного аудита.

## A. Authorization / privilege escalation

### A1. `manage_members` privilege escalation — IMPLEMENTED, PENDING FINAL EVIDENCE

Обязательные инварианты:

- actor не может выдать permission, которого сам не имеет;
- actor не может выдать subtree scope шире собственного;
- `canViewTeamFinance` нельзя выдать выше собственной effective capability;
- self-grant не может повысить собственные permissions/scope/finance flags;
- переданный `createdBy` не подменяет authenticated actor;
- owner/root — явное полноправное исключение.

Evidence:

- negative tests на self-elevation;
- grant-above-actor;
- subtree escalation;
- team-finance escalation;
- owner exception.

### A2. `OrganizationService` service-level authorization — IMPLEMENTED, PENDING FINAL EVIDENCE

`create/update/archive/restore` обязаны enforce-ить `manage_org_settings` в сервисе.

Дополнительно:

- create child требует права на parent;
- re-parent требует права на текущую org и новый parent;
- root/cycle/tree invariants действуют независимо от UI.

### A3. Transaction re-ownership — IMPLEMENTED, PENDING FINAL EVIDENCE

При смене `organizationId`:

- старая и новая org должны проходить authorization;
- новая org должна существовать и быть active;
- account должен принадлежать новой org;
- нельзя использовать update как cross-org data bridge.

### A4. `manage_recurring` — IMPLEMENTED, PENDING FINAL EVIDENCE

Создание/изменение/удаление recurring schedule требует `manage_recurring` дополнительно к обычным transaction permissions.

---

## B. Tasks / CRM / legacy UI isolation

### B1. Tasks org-aware + employee-aware — IMPLEMENTED, PENDING FINAL EVIDENCE

- `TaskService.getAll()` не является глобальным пользовательским read;
- ordinary employee ограничен active org context и собственным work ownership;
- manager может видеть более широкий people-scope только внутри разрешённой org/subtree;
- save/delete проверяют текущий и целевой ownership;
- raw reads остаются только для migration/admin/internal use.

### B2. CRM org-aware + employee-aware — IMPLEMENTED, PENDING FINAL EVIDENCE

- main CRM reads используют active org context;
- ordinary employee ограничен разрешённым ownership;
- manager scope не выходит за grants;
- Client/Deal organization должна совпадать;
- Interaction не может открыть скрытый parent;
- CRUD проверяет org scope на service layer.

### B3. Legacy `TeamStatsScreen` bypass — IMPLEMENTED, PENDING FINAL EVIDENCE

- `canSeeOthersStats` не расширяет org scope;
- people и Tasks считаются только внутри `only/subtree` effective context;
- экран слушает изменения organization grants;
- live revoke обязан немедленно пересчитать видимые данные.

---

## C. Personal / team finance

### C1. Team rows требуют `view_finance + canViewTeamFinance` — IMPLEMENTED, PENDING FINAL EVIDENCE

- один boolean `canViewTeamFinance` не является достаточным;
- проверка выполняется отдельно для каждой effective organization;
- parent grant не раскрывает child people rows через mixed-grant subtree.

### C2. Self-finance единая политика — IMPLEMENTED, PENDING FINAL EVIDENCE

`canViewSelfFinance=false` закрывает:

- self metrics;
- self comparison;
- self risks;
- self forecast;
- дальнейшие self-finance endpoints.

### C3. Employee finance drill-down — IMPLEMENTED, PENDING FINAL EVIDENCE

- строка сотрудника открывает детальную карточку только при разрешении;
- permission re-check выполняется непосредственно перед открытием;
- live revoke не позволяет stale UI открыть уже закрытые данные.

---

## D. Inter-org / Treasury integrity

### D1. InterOrgTransfer crash safety — IMPLEMENTED THROUGH JOURNAL + RECONCILIATION, PENDING FINAL EVIDENCE

Принята модель:

- durable write-ahead intent;
- idempotent reconciliation;
- active transfer сходится к двум legs;
- cancelled transfer сходится к нулю legs;
- обычный transaction flow не удаляет одну leg;
- recovery фиксируется в audit;
- fault injection выполняется после существенных write create/cancel.

Важно: Hive не предоставляет cross-box ACID transaction, поэтому нормативная гарантия org-v1 — **eventual crash-safe atomic logical state через durable journal/recovery**, а не физическая ACID-транзакция между Hive boxes.

### D2. Полный InterOrg UI flow — IMPLEMENTED, PENDING FINAL EVIDENCE

Обязательный flow:

1. from organization/account;
2. to organization/account;
3. transfer type;
4. amount/currency/base equivalents;
5. date/time;
6. comment;
7. review/confirmation;
8. history;
9. cancel обеих сторон через transfer entity.

### D3. Subtree internal-transfer elimination — IMPLEMENTED, PENDING FINAL EVIDENCE

- consolidated subtree income/expense/net исключает обе внутренние legs;
- локальные histories организаций сохраняют обе legs;
- history и local accounting не уничтожаются ради consolidation.

### D4. Descendant account selection — IMPLEMENTED, PENDING FINAL EVIDENCE

Принята модель: subtree Account Bar показывает доступные descendant accounts, и любой показанный account должен быть selectable.

---

## E. Money model / liquidity

### E1. Canonical multi-currency model — IMPLEMENTED FOR ORG-V1, PENDING FINAL EVIDENCE

Нормативная модель текущей версии:

- reporting currency org-v1 = `RUB` для совместимости с legacy history;
- `Transaction.amount` = frozen reporting amount;
- `originalAmount/originalCurrency` сохраняют исходную сумму;
- `organizationBaseAmount/organizationBaseCurrency` сохраняют frozen local-org equivalent;
- `fxRateToReporting/fxRateAt/fxSource` сохраняют used conversion contract;
- historical transaction не пересчитывается задним числом;
- subtree arithmetic выполняется только в reporting currency;
- raw RUB/EUR/USD не складываются как одинаковые единицы.

### E2. Единственный authoritative Account liquidity source — IMPLEMENTED, PENDING FINAL EVIDENCE

Authoritative поля находятся в `AccountModel`:

- currency;
- minimumBalance;
- allowNetting;
- fxHaircut;
- transferDelayDays.

Legacy `AccountLiquidityService` — compatibility facade и migration bridge, но не второй источник истины.

### E3. Account organization ownership immutable при существующих ссылках — NEW RE-AUDIT REQUIREMENT, IMPLEMENTED/PENDING FINAL EVIDENCE

Повторный аудит выявил дополнительный инвариант:

`Transaction.organizationId == Account.organizationId` должен оставаться истинным для уже созданной истории.

Обычный `AccountService.save()` не может перенести используемый account в другую organization, если на него уже ссылаются ledger/inter-org records. Такой перенос возможен только отдельным migration/reclassification flow с dependency migration и audit.

---

## F. Background recurring

### F1. Recurring не зависит от визуального org context — IMPLEMENTED, PENDING FINAL EVIDENCE

- owner maintenance охватывает active tree;
- non-owner maintenance ограничена `manage_recurring` policy;
- due recurring child org должен материализоваться даже если UI находится в другой org/`only`.

---

## G. Horizon multi-org independence

### G1. Prediction ownership org/scope — IMPLEMENTED, PENDING FINAL EVIDENCE

Background и interactive prediction обязаны явно сохранять корректные `organizationId + scope`.

### G2. Learning/championship isolation — IMPLEMENTED, PENDING FINAL EVIDENCE

Storage и in-flight keys разделяются как минимум по `organizationId + scope`.

Одна org не должна неявно менять champion/calibration другой.

### G3. Effective forecast permission — IMPLEMENTED, PENDING FINAL EVIDENCE

Forecast org-set строится по effective `view_forecast`, а `view_forecast` сам является действенным только вместе с `view_finance`.

Malformed/legacy grant `view_forecast` без `view_finance` обязан fail-closed.

---

## H. Audit coverage

### H1. Critical audit — IMPLEMENTED FOR CURRENT MUTATION SET, PENDING FINAL EVIDENCE

Обязательный audit минимум:

- organization create/update/archive/restore;
- grant create/update/revoke;
- account create/update/archive/delete;
- transaction update/delete/re-ownership;
- inter-org intent/commit/cancel/recovery;
- source/reason/actor/before/after где применимо.

Transaction audit read также подчиняется finance permission и не может раскрывать скрытые org financial data.

Если позже появляется отдельный sensitive-view/export flow, его access audit добавляется в рамках соответствующей функции, а не считается автоматически покрытым mutation audit.

---

## I. Sync integrity

### I1. Sync apply validation — IMPLEMENTED, PENDING FINAL EVIDENCE

До remote commit проверяются:

- root/tree/parent/cycle invariants;
- active organization references;
- grant employee/org/permission integrity;
- transaction/account organization consistency;
- InterOrg linked references/recoverability;
- physical ownership compatibility;
- malformed state fail-closed.

### I2. Synced grant anti-forgery — NEW RE-AUDIT HARDENING, IMPLEMENTED/PENDING FINAL EVIDENCE

- transport `createdBy=sync` / `untrusted-sync` никогда не является actor;
- normal remote grant принимается только если реальный actor локально мог его выдать;
- legacy migration marker допускается только в exact deterministic shape, которую реально мог создать `ensureLegacyGrants()`;
- migration marker не может mint admin rights;
- owner migration grant допускается только как exact full-root-subtree grant.

### I3. Destructive sync / tombstones — NEW RE-AUDIT REQUIREMENT, IMPLEMENTED/PENDING FINAL EVIDENCE

Remote delete не может разрушить referential integrity.

Минимально запрещается physical remote delete:

- root organization;
- org с children;
- org, на которую ссылаются Account/Transaction/Grant/InterOrgTransfer;
- Account, на который ссылается Transaction/InterOrgTransfer.

Исторические финансовые/organizational entities должны архивироваться либо проходить отдельный согласованный migration flow.

---

## J. Physical ownership / migration

### J1. Новые записи физически получают organization ownership — IMPLEMENTED, PENDING FINAL EVIDENCE

Nullable `organizationId` допускается только как legacy read compatibility.

После migration/service normalization новые records не должны создаваться с `organizationId == null`.

Проверяются минимум:

- Accounts;
- Transactions;
- recurring;
- Tasks;
- CRM Client/Deal;
- InterOrgTransfer;
- grants.

### J2. Legacy migration target — LOCKED

- все legacy data без ownership → `Wesi Inc`;
- `Wesi Beats` остаётся отдельным child;
- старая история в Wesi Beats автоматически не мигрирует.

---

## K. UI gaps исходного org-v1

### K1. Organization create + optional members — IMPLEMENTED, PENDING FINAL EVIDENCE

Wizard позволяет выбрать сотрудников сразу. Стартовое назначение выдаёт только безопасный базовый `view`; дополнительные права задаются отдельно.

### K2. Inter-org date/confirmation/history/cancel — IMPLEMENTED, PENDING FINAL EVIDENCE

### K3. Team-finance employee card — IMPLEMENTED, PENDING FINAL EVIDENCE

### K4. Subtree breakdown semantics — LOCKED IN IMPLEMENTATION DECISIONS

Порядок раскрытия:

`organization → accounts → operations`, а people-level finance остаётся отдельным My Finance contour с `canViewTeamFinance`.

---

# 3. Дополнительные edge cases, найденные уже во время remediation

Эти пункты считаются частью текущего ТЗ, даже если отсутствовали в первом audit backlog.

## R1. Live permission revocation

Любой уже открытый sensitive screen обязан реагировать на grant revision без перезапуска приложения.

Проверять минимум:

- My Finance;
- TeamStats;
- employee drill-down;
- дальнейшие экраны с cached sensitive org data.

## R2. Account re-ownership cannot break old ledger

Account с existing financial references нельзя обычным update перенести между organizations.

## R3. Destructive sync cannot create dangling references

Tombstones проходят referential-integrity validation так же строго, как create/update.

## R4. Exact legacy migration grant sync

Миграционный grant принимается только в форме, детерминированно выводимой из legacy Employee permissions; marker `migration` сам по себе не является доверенным полномочием.

## R5. Temporary verification workflows are not product code

Любые one-shot/patch verification workflows, созданные для remediation, должны быть удалены из final product diff до merge. В постоянном репозитории остаются только необходимые reusable CI workflows.

---

# 4. Обязательная тестовая матрица

Source-string/`contains()` tests не являются достаточным evidence.

Минимальный behavioral suite:

1. privilege escalation / self-elevation denial;
2. grant-above-actor denial;
3. service-level org mutation denial;
4. Tasks cross-org read/write denial;
5. CRM cross-org read/write denial;
6. TeamStats only/subtree isolation;
7. TeamStats live revoke;
8. self-finance=false;
9. team=true + view_finance=false;
10. mixed subtree finance grants;
11. My Finance employee drill-down + revoke;
12. transaction re-ownership denial;
13. account re-ownership with existing ledger refs denial;
14. manage_recurring denial;
15. inter-org create fault injection;
16. inter-org cancel fault injection;
17. repeated recovery idempotency;
18. subtree internal-flow elimination;
19. descendant account UI selection;
20. RUB/EUR/USD local + consolidated arithmetic;
21. original/base/reporting currency persistence;
22. non-current-org recurring processing;
23. explicit Horizon child org/scope tagging;
24. per-org championship/learning isolation;
25. view_forecast without view_finance denial;
26. sync cycle/dangling-parent/fake-root rejection;
27. bad/forged grant rejection;
28. exact legacy migration-grant acceptance and escalation rejection;
29. transaction/account cross-org sync rejection;
30. forged/half InterOrg sync rejection/recovery;
31. destructive org/account tombstone referential-integrity rejection;
32. physical ownership scan;
33. realistic legacy migration rehearsal;
34. UI organization switch;
35. UI only/subtree switch;
36. UI finance hidden/visible by grant;
37. UI InterOrg review/execute/cancel.

---

# 5. Exact-head CI gate

Один и тот же final remediation SHA обязан пройти:

- `flutter analyze --no-fatal-infos`;
- targeted remediation/security/integrity/UI/fault-injection suite;
- полный `flutter test`;
- Android build;
- Windows release build.

Если после зелёного run меняется хотя бы один production/test/migration/CI файл, evidence считается устаревшим и exact-head CI запускается снова.

---

# 6. Repeat independent audit gate

После зелёного exact-head CI проводится новый source-level аудит с нуля.

Он обязан отдельно искать обходы через:

- raw APIs;
- service APIs;
- stale cached UI;
- background jobs;
- sync create/update/tombstones;
- malformed/legacy grants;
- cross-org transaction/account re-ownership;
- linked InterOrg legs;
- mixed-currency arithmetic;
- migration paths;
- temporary verification code/workflows.

Повторный аудит не должен считать предыдущие утверждения об исправлении доказательством самими по себе.

---

# 7. Migration production gate

Fixture/rehearsal является обязательным automated evidence, но не заменяет тест на копии реальных пользовательских данных.

Перед production rollout, когда доступна безопасная копия real dataset:

1. выполнить migration на копии;
2. подтвердить legacy → Wesi Inc ownership;
3. подтвердить отсутствие автоматического переноса старой истории в Wesi Beats;
4. проверить dangling references;
5. сравнить balances и operation counts до/после;
6. сохранить migration log;
7. проверить recovery/rollback procedure.

Если real dataset не предоставлен, release report обязан явно назвать этот gate непроверенным внешним условием.

---

# 8. Definition of remediation complete

Текущая org-hierarchy remediation может получить статус `ACCEPTED` только когда одновременно выполнены все условия:

- все пункты A–K и R1–R5 реализованы;
- тестовая матрица имеет behavioral evidence;
- final diff не содержит one-shot patch/helper workflow;
- exact-head CI полностью зелёный;
- повторный независимый source audit не обнаруживает blocker/high integrity issue;
- migration fixture/rehearsal зелёный;
- реальный migration-data gate либо пройден, либо явно отражён как внешний pre-production blocker/condition.

После `ACCEPTED` merge/release всё равно является отдельным действием и выполняется только по явному решению владельца проекта.
