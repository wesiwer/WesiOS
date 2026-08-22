# Wesi Aero Route Server

Отдельный сервис выбора маршрута для Wesi Aero. Он не хранит VPN-ключи и не заменяет основной control plane. Его задача — постоянно проверять доступность узлов, измерять RTT, удерживать выбранный узел за клиентом и менять его только при подтверждённой деградации.

## Что реализовано

- периодические health-check проверки, по умолчанию каждые 20 секунд;
- timeout проверки 2 секунды и несколько samples на цикл;
- отдельная connectivity-проверка, чтобы отличать смерть VPN-узла от проблем сети самого route-server;
- failure/recovery thresholds против переключения из-за одиночного packet loss;
- least-load выбор по RTT с дополнительным `cost`;
- sticky binding клиента к узлу;
- hysteresis: более быстрый узел не вытесняет текущий из-за небольшой разницы RTT;
- автоматическое переключение только если текущий узел перестал быть пригодным;
- фильтрация по протоколу;
- API для статуса, выбора и освобождения sticky-привязки;
- Bearer token для служебных маршрутов.

## Граница ответственности

Route Server хранит только безопасные метаданные узлов: id, endpoint, health URL, список протоколов и optional `profileRef`.

VPN credentials, UUID, REALITY private material, WireGuard keys и готовые client profiles остаются в Wesi Aero control plane / secret storage. `profileRef` должен быть непрозрачным идентификатором профиля, а не самим секретом.

## Запуск

```bash
cp config.example.json config.json
export WESI_AERO_ROUTE_TOKEN='replace-with-a-long-random-token'
node src/index.mjs
```

По умолчанию сервис слушает `127.0.0.1:8792`. В production его следует ставить за TLS reverse proxy или держать в приватной сети рядом с основным control plane.

Docker:

```bash
docker build -t wesi-aero-route-server .
docker run --rm \
  -p 127.0.0.1:8792:8792 \
  -e WESI_AERO_ROUTE_TOKEN='replace-with-a-long-random-token' \
  -v "$PWD/config.json:/config/config.json:ro" \
  wesi-aero-route-server
```

Если контейнер должен быть доступен извне самого контейнера, в `config.json` задайте `listenHost: "0.0.0.0"`, а наружу всё равно публикуйте его через защищённый reverse proxy.

## API

### `GET /healthz`

Публичная минимальная проверка процесса.

### `GET /v1/nodes`

Текущий health state всех узлов. Требует Bearer token, если `WESI_AERO_ROUTE_TOKEN` задан.

### `POST /v1/select`

```json
{
  "clientId": "device-or-lease-id",
  "poolId": "kg-auto",
  "protocol": "vless-reality"
}
```

Пример ответа:

```json
{
  "poolId": "kg-auto",
  "nodeId": "kg-02",
  "endpoint": "vpn-kg-02.example.com:443",
  "protocols": ["vless-reality"],
  "countryCode": "KG",
  "rttMs": 41,
  "healthy": true,
  "sticky": true,
  "profileRef": "kg-02-vless"
}
```

При последующих вызовах тот же клиент получает тот же узел, пока он здоров и остаётся в допустимом RTT. Если узел подтверждённо умер, следующий вызов автоматически вернёт лучший живой узел.

### `POST /v1/release`

Сбрасывает sticky binding клиента, например при ручной смене сервера.

## Как связать с Wesi Aero

Рекомендуемый production flow:

1. Приложение просит основной control plane создать lease.
2. Control plane вызывает Route Server `/v1/select` с `deviceId/leaseId`, pool и protocol.
3. Route Server возвращает `nodeId`/`profileRef` выбранного живого узла.
4. Control plane выдаёт клиенту профиль именно этого узла.
5. Клиент запускает Xray/sing-box/native backend и выполняет собственную end-to-end verification через туннель.
6. При деградации клиент запрашивает новый route selection. Sticky binding сохраняется, если текущий узел жив, и меняется только при его отказе.

Это намеренно оставляет финальную проверку туннеля на устройстве. Серверный health-check показывает состояние инфраструктуры, но не может доказать, что конкретный мобильный оператор или Wi-Fi пользователя пропускает выбранный протокол.

## Соответствие исходной Xray-схеме

- `burstObservatory` → periodic node probes + sampling + failure/recovery thresholds;
- `leastLoad` → сортировка живых кандидатов по RTT + cost;
- «липкий» сервер → sticky binding + hysteresis;
- «смена при смерти» → текущий binding отбрасывается только когда узел признан unhealthy;
- `connectivity` probe → отдельная глобальная проверка доступа в Интернет;
- `destination` probe → `healthUrl` конкретного Wesi-узла;
- routing/DNS остаются в клиентском engine profile, потому что именно клиент управляет системным TUN.
