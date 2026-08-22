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

- [~] **P0.1 Sticky assignment.** Один клиент/lease должен сохранять выбранный узел, пока тот остаётся пригодным. Небольшое преимущество другого узла по RTT не должно вызывать переключение.
- [~] **P0.2 Failure/recovery thresholds.** Один неудачный probe не должен убивать узел; возврат в healthy также требует нескольких подтверждений.
- [ ] **P0.3 Randomized probe schedule.** Запрещён синхронный фиксированный `setInterval(20s)` для всех узлов. Каждый следующий probe должен планироваться с jitter в настраиваемом диапазоне, например 15–27 секунд.
- [ ] **P0.4 Multi-target health.** Узел проверяется минимум по нескольким независимым target URL. Должен задаваться quorum (например 2/3) и ожидаемые HTTP status codes.
- [ ] **P0.5 Rich quality score.** Выбор узла должен учитывать минимум RTT, jitter, packet/error loss, recent failure penalty, server load и административный cost. Чистый RTT недостаточен.
- [ ] **P0.6 Persistent state.** Sticky bindings, health history, penalties и maintenance state должны переживать рестарт Route Server. Минимум — атомарный локальный state file/SQLite; production target — общий storage для нескольких instances.
- [ ] **P0.7 Drain mode.** Узел имеет состояния `online`, `draining`, `offline`. Draining не получает новых клиентов, но существующие sticky leases не рвутся принудительно.
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
- [ ] **P1.6 Load-aware score.** Route Server применяет server-load penalty и не назначает новые leases на перегруженный узел.
- [ ] **P1.7 Capacity.** Admin задаёт hard/soft capacity; превышение soft capacity увеличивает penalty, hard capacity исключает узел из новых назначений.
- [ ] **P1.8 Version/health inventory.** Admin видит версии Xray/sing-box/AWG и время последнего успешного agent heartbeat.

## P1 — Route Server HA

- [ ] **P1.9 Multi-instance readiness.** Route Server не должен зависеть от process-local `Map` как единственного источника истины.
- [ ] **P1.10 Shared persistence.** При запуске нескольких Route Server instances sticky/maintenance/penalties должны быть общими.
- [ ] **P1.11 Safe restart.** Рестарт или deploy Route Server не должен массово перераспределять здоровые sticky clients.
- [ ] **P1.12 API authentication.** Служебные API закрыты отдельным Bearer/HMAC/mTLS контуром; VPN credentials в Route Server не передаются.

## P1 — Admin

- [ ] **P1.13 Pool management.** Wesi Aero Admin управляет pools, region/country, priority, cost, capacity, protocols, fallback chains.
- [ ] **P1.14 Maintenance controls.** Admin может переводить node в draining/offline, принудительно release sticky assignment и видеть причину деградации.
- [ ] **P1.15 Monitoring.** Показывать health, RTT, jitter, loss/error rate, load, active assignments, agent heartbeat и последние failover events понятными названиями без технического мусора.

## P2 — маршрутизация и DNS профиля

- [ ] **P2.1 Routing policy.** Поддерживать `VPN / Direct / Block`, LAN/private ranges, domain/app rules и BitTorrent policy.
- [ ] **P2.2 DNS policy.** Auto/Wesi Secure/Custom; IPv4/IPv6/Auto; защита от DNS leak; DNS failure должен отличаться от tunnel failure.
- [ ] **P2.3 Full Xray JSON compatibility.** Импорт полноценного Xray JSON (`outbounds`, `routing`, `dns`, observatory) с нормализацией в собственную модель Wesi Aero, а не хранением чужого JSON как единственного source of truth.

## P2 — тестирование и acceptance

- [ ] **P2.4 Deterministic unit tests.** Проверить hysteresis, thresholds, jitter scheduling bounds, quorum, scoring, persistence, drain, fallback graph.
- [ ] **P2.5 Failure simulation.** Автотесты: timeout, packet/error loss, slow node, overloaded node, route-server restart, node recovery, all-primary-down.
- [ ] **P2.6 Android E2E.** Реальный Android: VpnService -> backend -> E2E probe -> failover -> восстановление без утечки трафика при Kill Switch.
- [ ] **P2.7 Windows E2E.** Аналогичный тест Windows tunnel host.
- [ ] **P2.8 Production gate.** Нельзя считать БС production-ready только по `/healthz`, unit tests или successful deploy. Нужен реальный tunnel E2E минимум на двух узлах и двух типах сети.

## Текущий первый узел

- ID: `ireland-bs`
- Display name: **Ирландия БС**
- VPS: существующий foreign Wesi relay host
- VLESS + REALITY bind: `8443/TCP`, чтобы не конфликтовать с Wesi AI HTTPS на `443/TCP`
- REALITY target/SNI по умолчанию: `www.cloudflare.com:443` / `www.cloudflare.com`
- Wesi AI services на VPS не должны изменяться deploy-скриптом Aero.

## Ближайший implementation batch

В текущем проходе реализовать вместе:

1. randomized per-node probe scheduler;
2. multi-sample quality metrics: RTT + jitter + failure/loss ratio;
3. richer score с recent-failure penalty и server-load hook;
4. persistent sticky/health/maintenance state;
5. `online/draining/offline` и исключение draining из новых назначений;
6. tests для перечисленного;
7. обновить README/config example и этот файл по фактическому результату.
