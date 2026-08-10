# WesiOS — Product Discovery: финальная контрольная точка 49–50/50

**Статус:** нормативное продолжение `TZ_PRODUCT_DISCOVERY_50Q.md`  
**Дата:** 2026-08-10  
**Связанные документы:** `TZ_PRODUCT_DISCOVERY_50Q.md`, `TZ_ORG_HIERARCHY_V1.md`, `TZ_ORG_HIERARCHY_V1_AUDIT_BACKLOG.md`.

Этот документ закрывает Product Discovery 50Q и добавляет ответы 49–50. Все ответы 1–48 и выведенные из них invariants сохраняют силу, если ниже явно не указано обратное.

---

## 49/50. Сбои, резервные копии и аварийное управление

**Ответ:** D — полноценный контур устойчивости и Emergency Control Center.

Требования:

- versioned backups;
- point-in-time recovery;
- регулярная автоматическая проверка того, что backup действительно можно восстановить;
- экспорт критических данных в открытых форматах;
- защита от массового ошибочного удаления и массового повреждения данных;
- Health / Status Center для состояния основных сервисов и контуров WesiOS;
- disaster-recovery procedures должны быть документированы и доступны уполномоченным ролям;
- аварийные действия всегда попадают в неизменяемый audit trail.

### Emergency Control Center CEO

CEO/root emergency-role получает отдельный аварийный контур, позволяющий при инциденте:

- отозвать все активные пользовательские сессии;
- отозвать/заморозить ключи и интеграционные credentials;
- временно заморозить финансовые операции;
- отключить внешние интеграции;
- отключить Employee AI Agents;
- остановить Workflow Engine / автоматизации;
- перевести WesiOS в безопасный режим с ограниченным набором разрешённых действий;
- видеть причину, actor, время, security-context и последствия каждого emergency-действия;
- восстанавливать работу только через явную контролируемую процедуру.

Emergency mode не является скрытым способом обхода обычного аудита: действия CEO в нём также полностью аудируются.

---

## 50/50. Когда WesiOS считается готовой?

**Ответ:** A — когда реализованы текущие экраны и отсутствуют ошибки сборки.

Зафиксированное пользовательское определение готовности:

1. предусмотренные текущим продуктовым состоянием экраны реализованы;
2. поддерживаемые сборки проходят без build errors;
3. после выполнения этих двух условий WesiOS может называться `готовой` в смысле выбранного критерия 50A.

### Важное разграничение терминов

Ответ 50A задаёт **критерий продуктовой/сборочной готовности**, но сам по себе не отменяет ответы 1–49, security invariants, финансовые invariants, audit requirements или ранее найденные дефекты.

Поэтому в дальнейшей работе используются два разных статуса:

- **Build/Product Ready (50A):** текущие экраны реализованы, заявленные сборки проходят без ошибок;
- **Requirements/Compliance Complete:** реализация действительно соответствует всем применимым требованиям Product Discovery, основного ТЗ и audit backlog.

Эти статусы нельзя подменять друг другом. Зелёный build не является доказательством отсутствия security, authorization, data-integrity или domain-logic дефектов.

---

## Финальные обязательные invariants Product Discovery 50Q

1. WesiOS — ежедневная корпоративная ОС для сотрудников, а не только CEO-dashboard.
2. Активная RoleAssignment/ProjectRoleAssignment является реальным security-context; права неактивных ролей не суммируются.
3. ProjectRoleAssignment действует только внутри проекта и не расширяет organization permissions.
4. Tasks, CRM, Documents, Search, AI, Reports, Notifications и Workflows обязаны использовать единый authorization pipeline.
5. Object visibility никогда не расширяет базовые permissions.
6. Salary/employee-finance и organization-finance являются разными чувствительными контурами.
7. Финансы организации, Treasury, budgets, recurring commitments, Expense Flow и approvals являются organization-aware.
8. Money Event хранит организацию, валюту и корректный FX context; raw суммы разных валют не складываются напрямую.
9. InterOrgTransfer атомарен; внутренние потоки исключаются из консолидации.
10. Horizon анализирует, объясняет и рекомендует, но сам не исполняет действия.
11. Employee AI Agent может действовать только от имени и с правами активного security-context.
12. AI memory изолируется между personal / RoleAssignment / Organization / Project контурами.
13. Workflow Engine не получает скрытых superuser-прав и сохраняет security-context каждого шага.
14. Offline режим по ответу 44 — read-only cache; запись требует online.
15. Security включает MFA/passkeys, device/session management, re-auth, emergency revoke и усиленную защиту привилегированных ролей.
16. Security & Audit Center должен позволять восстановить цепочку `кто → в каком контексте → что видел/изменил → почему имел право`.
17. Metadata-driven кастомизация не может отключить hard security/finance/audit invariants.
18. Архитектура должна масштабироваться без обязательной загрузки всей базы на клиент.
19. Disaster recovery, backups и Emergency Control Center являются частью нормативной архитектуры.
20. Статус Build/Product Ready по 50A не должен использоваться как утверждение о полном соответствии требованиям или отсутствии security/data-integrity дефектов.

---

## Discovery status

**50/50 завершено.**

Следующий этап после discovery — свести `TZ_PRODUCT_DISCOVERY_50Q.md`, этот финальный checkpoint, `TZ_ORG_HIERARCHY_V1.md` и `TZ_ORG_HIERARCHY_V1_AUDIT_BACKLOG.md` в единый implementation backlog/roadmap, не меняя production и не выполняя merge/release без отдельного разрешения.