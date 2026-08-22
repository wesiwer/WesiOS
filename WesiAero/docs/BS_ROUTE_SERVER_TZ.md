# Wesi Aero — ТЗ: БС / Route Server / автоматический failover

Дата фиксации: 2026-08-22.

Статусы:
- `[ ]` — не начато;
- `[~]` — в работе / реализовано частично;
- `[x]` — реализовано и покрыто проверками на уровне компонента;
- production-ready допускается только после реального E2E через Android/Windows tunnel.

## Цель

Построить серверную систему выбора Wesi Aero узлов класса «липкий сервер + смена при смерти», которая не ограничивается HTTP health-check, а учитывает качество узла, реальную загрузку, историю деградаций, клиентский E2E и протокольные fallback-цепочки. Система должна работать для всех восьми протоколов Wesi Aero и не хранить VPN private credentials в Route Server.

## P0 — корректный выбор узла и отказоустойчивость

- [~] **P0.1 Sticky assignment.** Реализовано сохранение выбранного узла на TTL; здоровый sticky route сохраняется даже если другой узел немного быстрее. Полное закрытие — после E2E и проверки restart/deploy.
- [~] **P0.2 Failure/recovery thresholds.** Реализованы независимые consecutive failure/success thresholds и накопительная история outcomes. Требуется CI/E2E подтверждение.
- [~] **P0.3 Randomized probe schedule.** Фиксированный общий `setInterval(20s)` удалён. Для каждого узла планируется отдельный `setTimeout` с настраиваемым jitter (`intervalMs ± jitterRatio`). Добавлены deterministic unit tests границ jitter; CI-gate создан, результат run нужно подтвердить.
- [~] **P0.4 Multi-target health.** Реализованы `healthUrls[]`, `connectivityUrls[]`, sampling, quorum и expected HTTP statuses. Важно: server-side health не считается доказательством VPN E2E; для `Ирландия БС` сейчас проверяется инфраструктура того же VPS, а не внешний `generate_204` как будто это здоровье узла. Нужен Node Agent/реальный protocol health.
- [~] **P0.5 Rich quality score.** Реализованы RTT, jitter, failure/error rate, recent failure penalty, administrative cost и server-load hook. Реальный load пока статический/из конфигурации — Node Agent ещё не подключён.
- [~] **P0.6 Persistent state.** Sticky bindings, health history, penalties и maintenance state сохраняются атомарно в локальный state file и восстанавливаются после рестарта. Общий storage для нескольких Route Server instances ещё не реализован.
- [~] **P0.7 Drain mode.** Реализованы состояния `online`, `draining`, `offline` и API изменения maintenance. Draining исключён из новых назначений, но существующий здоровый sticky client остаётся на узле.
- [ ] **P0.8 Explicit emergency fallback.** Если в основном pool нет пригодных узлов, должна быть настраиваемая цепочка fallback pools/regions вместо случайного default route.

## P0 — реальная проверка VPN, а не только инфраструктуры

- [ ] **P0.9 Client E2E verification.** После запуска backend клиент обязан выполнить outbound probe через фактический туннель. Только после этого статус может стать `Connected`.
- [ ] **P0.10 Continuous client E2E.** После подключения клиент периодически проверяет туннель. Route Server health и client E2E считаются разными сигналами.
- [ ] **P0.11 Failure classification.** Различать как минимум: `DEVICE_CONNECTIVITY_DOWN`, `NODE_DOWN`, `PROTOCOL_BLOCKED_OR_BROKEN`, `TUNNEL_EGRESS_FAILED`, `DNS_FAILED`, `CONTROL_PLANE_FAILED`.
- [ ] **P0.12 Client quality report.** Клиент может отправлять обезличенный результат RTT/jitter/loss по выбранному route. Нельзя отправлять домены, URL пользователя, DNS history или browsing metadata.

## P1 — protocol-aware failover

- [ ] **P1.1 Protocol fallback graph.** Failover должен происходить не только `node A -> node B`, но и `protocol A -> protocol B` по policy. Пример: VLESS/REALITY -> Hysteria2 -> TUIC -> VMess/Trojan -> emergency route.
- [ ] **P1.2 Network-aware preference.** TCP/443 и UDP-протоколы должны иметь разные приоритеты в зависимости от результата реального client E2E на текущей сети.
- [ ] **P1.3 Engine-aware fallback.** Для протоколов с несколькими backend (Xray/sing-box/native) допускается fallback backend без создания новой лицензии/ключа, если серверный профиль это позволяет.
- [ ] **P1.4 Existing connection policy.** При смене route должна быть политика: новые соединения идут через новый route; живые существующие можно сохранить, если backend позволяет; при фактической смерти старого route выполняется force reconnect.

## P1 — телеметрия узлов

- [ ] **P1.5 Node Agent.** На каждом Wesi-owned VPN node нужен агент, который отдаёт CPU, RAM, load average, network throughput, active tunnels/sessions, uptime и состояние Xray/sing-box/native services.
- [~] **P1.6 Load-aware score.** Формула Route Server уже учитывает `load`, но источник пока конфигурационный. Полное закрытие после P1.5.
- [ ] **P1.7 Capacity.** Admin задаёт hard/soft capacity; превышение soft capacity увеличивает penalty, hard capacity исключает узел из новых назначений.
- [ ] **P1.8 Version/health inventory.** Admin видит версии Xray/sing-box/AWG и время последнего успешного agent heartbeat.

## P1 — Route Server HA

- [~] **P1.9 Multi-instance readiness.** Process-local `Map` больше не является единственным источником долговременного состояния: введён persistent state file. Для настоящего multi-instance нужен shared storage.
- [ ] **P1.10 Shared persistence.** При запуске нескольких Route Server instances sticky/maintenance/penalties должны быть общими.
- [~] **P1.11 Safe restart.** Sticky и health metadata восстанавливаются из state file; нужно подтвердить CI и реальным restart test.
- [~] **P1.12 API authentication.** Служебные API Route Server закрываются отдельным Bearer token. VPN credentials в Route Server не передаются. mTLS/HMAC можно добавить позже как production hardening.

## P1 — Admin

- [ ] **P1.13 Pool management.** Wesi Aero Admin управляет pools, region/country, priority, cost, capacity, protocols, fallback chains.
- [~] **P1.14 Maintenance controls.** Backend API уже умеет `online/draining/offline` и `release`; UI Admin ещё не подключён.
- [~] **P1.15 Monitoring.** API уже возвращает health, RTT, jitter, failureRate, score, load, maintenance, lastError. Admin UI и human-readable failover event log ещё не реализованы.

## P2 — маршрутизация и DNS профиля

- [ ] **P2.1 Routing policy.** Поддерживать `VPN / Direct / Block`, LAN/private ranges, domain/app rules и BitTorrent policy.
- [ ] **P2.2 DNS policy.** Auto/Wesi Secure/Custom; IPv4/IPv6/Auto; защита от DNS leak; DNS failure должен отличаться от tunnel failure.
- [ ] **P2.3 Full Xray JSON compatibility.** Импорт полноценного Xray JSON (`outbounds`, `routing`, `dns`, observatory) с нормализацией в собственную модель Wesi Aero, а не хранением чужого JSON как единственного source of truth.

## P2 — тестирование и acceptance

- [~] **P2.4 Deterministic unit tests.** Добавлены tests для jitter bounds, thresholds/history, rich scoring, drain+sticky и persistence. Quorum/fallback graph ещё требуют отдельных тестов. Добавлен `.github/workflows/wesi-aero-route-server-ci.yml` с `node --check` и `node --test`; успешный workflow run ещё нужно подтвердить.
- [~] **P2.5 Failure simulation.** Unit tests уже моделируют failures/recovery и unstable-vs-clean scoring; timeout/network/all-primary-down/restart integration scenarios ещё не закрыты.
- [ ] **P2.6 Android E2E.** Реальный Android: VpnService -> backend -> E2E probe -> failover -> восстановление без утечки трафика при Kill Switch.
- [ ] **P2.7 Windows E2E.** Аналогичный тест Windows tunnel host.
- [ ] **P2.8 Production gate.** Нельзя считать БС production-ready только по `/healthz`, unit tests или successful deploy. Нужен реальный tunnel E2E минимум на двух узлах и двух типах сети.

## Текущий первый узел

- Pool ID: `ireland-bs`
- Node ID: `ireland-bs-01`
- Display name: **Ирландия БС**
- VPS: существующий foreign Wesi relay host
- VLESS + REALITY bind: `8443/TCP`, чтобы не конфликтовать с Wesi AI HTTPS на `443/TCP`
- REALITY target/SNI по умолчанию: `www.cloudflare.com:443` / `www.cloudflare.com`
- Route Server локальный порт на этом VPS/контуре: `8793`, потому что `8792` уже занят Wesi AI streaming gateway.
- Wesi AI services на VPS не должны изменяться deploy-скриптом Aero.

## Выполненный implementation batch 1

Реализовано в коде ветки:

1. randomized per-node probe scheduler;
2. multi-sample metrics: RTT + jitter + failure/error ratio;
3. richer score: RTT + jitter + loss/error + recent failure penalty + load + cost;
4. persistent sticky/health/maintenance state с atomic replace;
5. `online/draining/offline` и maintenance API;
6. unit tests для core-логики;
7. dedicated Route Server CI workflow;
8. перенос Route Server default port с конфликтующего `8792` на `8793`;
9. исправлено разделение global connectivity probe и node-specific infrastructure health.

## Следующий implementation batch

1. explicit fallback pools/regions;
2. client E2E verification + continuous E2E;
3. failure classification;
4. Node Agent + реальный load/capacity;
5. подключение Route Server к `lease.create` control plane;
6. Admin UI для maintenance/monitoring;
7. quorum/fallback/integration tests и подтверждение CI.
