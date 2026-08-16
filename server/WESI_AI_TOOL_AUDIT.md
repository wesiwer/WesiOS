# Wesi AI — Tool Audit

Дата аудита: 2026-08-16

## Охват

Проверяется полный центральный реестр Wesi AI: 58 tools из 16 adapters, включая условные GitHub tools в состоянии подключённого connector account.

Постоянные CI-gates:

- `server/pb_hooks/wesi_ai_tools_contract.test.js`
  - каждый adapter имеет `definitions()` и `execute()`;
  - tool names уникальны и валидны;
  - JSON-описания аргументов структурно валидны;
  - capability registry и полный набор definitions совпадают;
  - центральный registry не теряет доступные tools;
  - GitHub tools корректно скрываются без подключённого credential и полностью проверяются при эмуляции подключённого credential;
  - READ executors проходят safe smoke-path;
  - risk/confirmation metadata согласованы.
- `server/pb_hooks/wesi_ai_mutating_safety.test.js`
  - каждый WRITE/DESTRUCTIVE tool fail-closed на пустом вызове;
  - пустой/неполный mutating call не может выполнить save/delete.
- Relay tests проверяют provider/model routing и финансовую семантику.
- Main streaming tests проверяют tool protocol/handoff, скрытие служебного JSON и verified result flow.
- Flutter tests проверяют клиентский разбор verified tool results.

## Найденные и исправленные дефекты

1. `calendar_create` генерировал id до проверки обязательных `title/startAt`. Теперь malformed call отклоняется до любых побочных действий.
2. Старый Relay regression ошибочно считал recurring financial template фактическим расходом. Тест приведён к текущей семантике: фактический `currentBalance/net` отделён от `recurringExpense`.
3. Live/final tool activity теряла безопасное человеческое `message` и оставляла только технический `code`. Gateway и Flutter client теперь сохраняют `code + message`, а final verified result не затирает detail.

## Что сознательно не делается в CI

CI не выполняет реальные destructive/write операции в production-данных и не создаёт реальные GitHub issues/PR/commits. Такие проверки выполняются fail-closed harness-ом без side effects. Внешние connector tools дополнительно зависят от фактически настроенных credentials и доступности внешнего API.

Это ограничение намеренное: автоматический аудит должен доказывать корректность registry/policy/executor/transport/client contract без изменения реальных рабочих данных.
