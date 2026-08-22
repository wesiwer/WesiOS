# Wesi Aero — ТЗ: БС / Route Server / автоматический failover

Дата актуализации: 2026-08-22.

Статусы:
- `[ ]` — не начато;
- `[~]` — код/контракт реализован частично, требуется следующий слой или E2E;
- `[x]` — реализовано на уровне компонента и есть regression coverage/валидация;
- production-ready допускается только после реального Android/Windows tunnel E2E.

## Цель

Построить систему «одна кнопка Подключить»: выбор route/protocol/engine/profile выполняется автоматически, sticky-сессия сохраняется до подтверждённого отказа, деградация классифицируется, а перегруженные/неисправные узлы исключаются. Route Server не хранит VPN private credentials.

КРИТИЧЕСКО ДЛЯ ТЕКУЩЕГО ЭТАПА: автоматический режим разрешён только для `ireland-bs`. Второй сервер не должен участвовать в auto pool/fallback без отдельного явного решения пользователя.

## P0 — выбор узла и отказоустойчивость

- [x] **P0.1 Sticky assignment.** Sticky route хранится по client/pool/protocol и отдельно для auto-mode; состояние переживает рестарт через persistent state.
- [x] **P0.2 Failure/recovery thresholds.** Consecutive success/failure thresholds + история outcomes.
- [x] **P0.3 Randomized probe schedule.** Per-node `setTimeout` с jitter вместо синхронного `setInterval(20s)`.
- [x] **P0.4 Multi-target health.** `healthUrls[]`, `connectivityUrls[]`, sampling, quorum, expected status codes.
- [x] **P0.5 Rich quality score.** RTT + jitter + failure rate + recent failure penalty + cost + live load + overload penalty.
- [x] **P0.6 Persistent state.** Atomic state file: sticky, health history, penalties, maintenance, telemetry snapshot.
- [x] **P0.7 Drain mode.** `online/draining/offline`; draining не получает новых клиентов, существующий healthy sticky сохраняется.
- [~] **P0.8 Explicit emergency fallback.** Generic auto-route умеет упорядоченные pool/protocol candidates. Для `ireland-bs` включён строгий allowlist `poolPriority=[ireland-bs]`, `includeUnlistedPools=false`; второй сервер намеренно исключён. Live fallback пока невозможен, пока в этом же разрешённом контуре нет второго физического Ireland node или второго реально поднятого протокола.

## P0 — реальный VPN health

- [~] **P0.9 Client E2E verification.** `TunnelHealthService` выполняет HTTP egress probe после перехода клиента в Connected. Для production gate нативный backend ещё должен доказать, что этот probe действительно проходит через TUN, а не bypass-путь приложения.
- [~] **P0.10 Continuous client E2E.** Flutter wiring применён: только для `ireland-bs` probe запускается при переходе в Connected и повторяется каждые 25 секунд. Следующий gate — реальный Android/Windows tunnel E2E.
- [x] **P0.11 Failure classification backend.** Route Server принимает/нормализует `DEVICE_CONNECTIVITY_DOWN`, `NODE_DOWN`, `PROTOCOL_BLOCKED_OR_BROKEN`, `TUNNEL_EGRESS_FAILED`, `DNS_FAILED`, `CONTROL_PLANE_FAILED`.
- [x] **P0.12 Client quality report contract.** Route Server имеет `/v1/client-health`, control plane secure action `route.health.report` применён, Flutter-клиент отправляет обезличенный результат только для `ireland-bs`. Browsing domains/history не передаются. Реальная корректность signal требует E2E.

## P1 — protocol-aware failover

- [~] **P1.1 Protocol fallback graph.** `auto-route.mjs` имеет `protocolPriority` и pool priority. Сейчас для Ireland разрешён только реально поднятый `vless-reality`; фиктивные fallback-протоколы рекламировать запрещено.
- [ ] **P1.2 Network-aware preference.** Нужна накопленная client E2E статистика по типу сети/доступности TCP/UDP без сбора browsing metadata.
- [~] **P1.3 Engine-aware fallback.** Клиент `ireland-bs` принудительно использует `TunnelEngine.automatic`; конкретный backend выбирается существующей engine policy. Нужен verified retry Xray/sing-box при реальном backend failure.
- [ ] **P1.4 Existing connection policy.** Нужна нативная политика soft handoff/new-connections vs force reconnect.

## P1 — Node Agent / capacity

- [~] **P1.5 Node Agent.** Реализован отдельный `WesiAero/node-agent`: CPU load ratio, RAM, load average, network throughput, uptime, systemd service health. Есть systemd deploy для `ireland-bs`. Active tunnel count/version inventory ещё добавить.
- [x] **P1.6 Load-aware score.** Node Agent telemetry обновляет `node.load`; score учитывает load + overload.
- [x] **P1.7 Capacity.** `softCapacity` создаёт дополнительный penalty; `hardCapacity` исключает узел из новых назначений, не обрывая существующий sticky route.
- [~] **P1.8 Version/health inventory.** Service state/heartbeat/uptime доступны. Версии Xray/sing-box/AWG и active tunnels ещё не возвращаются.

## P1 — Route Server HA/security

- [~] **P1.9 Multi-instance readiness.** Долговременное состояние вынесено из process-only Map в persistent state. Shared storage ещё не реализован.
- [ ] **P1.10 Shared persistence.** Для нескольких Route Server instances нужен Redis/Postgres/другой shared store.
- [x] **P1.11 Safe restart.** Sticky/health/maintenance/telemetry snapshot восстанавливаются после рестарта.
- [x] **P1.12 API authentication baseline.** Bearer token поддерживается; сервис по умолчанию bind на `127.0.0.1:8793`. VPN credentials Route Server не получает. Production remote access должен идти через защищённый private/TLS/mTLS контур, а не открытый 8793.

## P1 — Control Plane / Admin

- [x] **P1.13 Lease routing contract.** `server-node` имеет `RouteServerClient`; `api.mjs` вызывает Route Server в обычном `/v1/leases` и secure `lease.create` только когда сервер содержит `transportConfig.routePoolId`.
- [x] **P1.14 Ireland isolation.** `ireland-bs` содержит `routePoolId=ireland-bs`; второй сервер без `routePoolId` проходит старый lease path и не затрагивается.
- [~] **P1.15 Maintenance controls/monitoring.** Backend API возвращает health, RTT, jitter, failureRate, score, load, hard-capacity, telemetry, maintenance, lastError. Admin UI ещё не подключён.
- [ ] **P1.16 Pool management UI.** Admin должен управлять pool/priority/cost/capacity/maintenance/fallback policy без редактирования JSON.

## P2 — routing/DNS/profile compatibility

- [~] **P2.1 Routing policy.** Ireland Xray profile блокирует BitTorrent и отправляет private ranges direct. Полная модель `VPN/Direct/Block` для app/domain/ip ещё требует нормализации.
- [ ] **P2.2 DNS policy.** Auto/Wesi Secure/Custom, IPv4/IPv6/Auto, leak protection, отдельная DNS failure classification на клиенте.
- [ ] **P2.3 Full Xray JSON compatibility.** Нужен импорт полного Xray JSON с нормализацией в собственную модель Wesi Aero.

## P2 — тестирование

- [x] **P2.4 Core unit tests.** Jitter bounds, thresholds/history, score, sticky+drain, persistence, hard capacity, isolated auto pools.
- [~] **P2.5 Failure simulation.** Есть component scenarios. Нужны integration scenarios: network timeout, service death, route-server restart, node recovery, all-allowed-routes-down.
- [ ] **P2.6 Android E2E.** Реальный `VpnService -> backend -> outbound probe -> failure -> recovery`, Kill Switch без leak.
- [ ] **P2.7 Windows E2E.** Аналогичный тест Windows tunnel host.
- [ ] **P2.8 Production gate.** Нельзя считать БС production-ready только по `/healthz`, CI или systemd active. Нужен реальный tunnel E2E.

## Ирландия БС — текущая production-схема

- Node/Pool ID: `ireland-bs`
- Display name: **Ирландия БС**
- VPS: существующий foreign Wesi relay host (`178.236.247.194`)
- VLESS + REALITY: `8443/TCP`
- Wesi AI `443/8787/8792` не изменяются
- Route Server: `127.0.0.1:8793`
- REALITY SNI/target: автоматически выбирается и TLS-проверяется deploy-скриптом из candidate pool; private key/UUID/shortId остаются на VPS
- Client policy: `oneTapAutomatic=true`, protocol/engine = Auto, ручные selectors для этого узла блокируются/скрываются
- Auto routing allowlist: только `ireland-bs`; второй сервер не используется
- Required backend service: `wesi-aero-ireland-bs`

## Deployment

`deploy-wesi-aero-ireland-bs.yml` теперь валидирует и разворачивает единый стек:

1. проверяет, что Wesi AI на 443/8787 жив и не будет затронут;
2. тестирует Route Server unit tests/syntax;
3. выбирает REALITY target на фактическом VPS;
4. ставит Route Server systemd;
5. ставит/обновляет Xray Ireland BS;
6. ставит Node Agent systemd;
7. проверяет все три сервиса и listener `8443`;
8. client URI остаётся root-only на VPS.

## Следующий обязательный batch

1. расширить Node Agent: Xray version + active sessions + network capacity baseline;
2. Admin UI: maintenance, load, RTT/jitter/loss, service health;
3. client-side network-aware protocol/engine retry;
4. нативно подтвердить, что E2E probe проходит именно через TUN;
5. Android real tunnel E2E, затем Windows;
6. только после E2E переводить P0.9/P0.10/P2.8 в `[x]`.
