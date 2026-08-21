# Foreign Relay WesiOS: найденная инфраструктура для Wesi Aero

Дата проверки: 20 августа 2026 года.

## Результат

В WesiOS найден не основной backend, а отдельный зарубежный AI Relay:

| Поле | Найденное значение | Статус |
| --- | --- | --- |
| Public hostname | `wesi-ai-178-236-247-194.nip.io` | присутствует в Flutter-клиенте и deploy workflows |
| IP из nip.io hostname | `178.236.247.194` | публичный адрес целевого VPS |
| HTTPS | `443/TCP` | занят nginx Wesi AI Relay |
| AI Relay | `127.0.0.1:8787` | внутренний Node.js service |
| AI Stream gateway | `127.0.0.1:8792` | внутренний streaming service |
| Live health | `ok=true`, `service=wesi-ai-relay`, `ready=true` | подтверждено запросом `/health` |

Основной сервер `api.wesi-inc.ru` намеренно не используется как целевой Server
Node Wesi Aero.

## Откуда это следует

- `lib/features/ai/wesi_ai_api.dart` задаёт foreign relay как production default;
- `.github/workflows/deploy-wesi-ai.yml` и
  `.github/workflows/deploy-wesi-ai-streaming.yml` используют тот же public host
  и отдельные SSH secrets;
- `server/wesi-ai-relay/deploy-relay.sh` слушает loopback `8787`;
- `server/wesi-ai-stream/deploy-stream-gateway.sh` слушает loopback `8792`;
- `server/wesi-ai-relay/nginx-relay.conf` занимает внешний HTTPS `443`.

README внутри Wesi AI Relay всё ещё содержит старую фразу о том, что узел не
развёрнут. Live `/health` и текущие production defaults показывают, что эта часть
документации устарела.

## Что найдено в secrets

В репозитории есть только имена GitHub Secrets, а не их значения:

- `WESI_RELAY_SSH_HOST`;
- `WESI_RELAY_SSH_USER`;
- `WESI_RELAY_SSH_KEY`;
- `WESI_RELAY_SSH_KNOWN_HOSTS`;
- `WESI_MAIN_SHARED_SECRET`;
- `GEMINI_API_KEY` и дополнительные provider keys.

GitHub Actions намеренно не позволяет получить сохранённые secret values обратно.
Поэтому foundation не копирует закрытые ключи и не имитирует доступ к VPS.

## Telegram: важный нюанс

В текущей ветке `main` Telegram hooks всё ещё обращаются к Telegram API с
основного контура. Workflow
`.github/workflows/agent-telegram-foreign-relay-migrator.yml` описывает перенос
Telegram на foreign relay, однако runtime-файлы этой миграции в текущем `main`
отсутствуют. Следовательно, найденный VPS уже является посредником для Gemini,
но пока нельзя считать его действующим Telegram relay.

## Безопасный план совместного размещения

Существующий `443/TCP` нельзя просто отдать Xray: это сломает Wesi AI HTTPS.
Foundation использует непересекающиеся значения:

| Wesi Aero компонент | Предлагаемый bind | Условие запуска |
| --- | --- | --- |
| Control plane | `127.0.0.1:8790` | публиковать только через отдельный TLS route |
| VLESS + REALITY | `0.0.0.0:8443/TCP` | открыть firewall и выпустить реальный профиль |
| AmneziaWG | `0.0.0.0:51820/UDP` | открыть firewall и создать peer keys |

Перед deployment нужно подтвердить свободные порты, ресурсы VPS, правила
провайдера, IP forwarding и наличие резервного узла. Для 99.9% uptime один VPS
всё равно недостаточен.

## Чего здесь намеренно нет

- SSH private key и username;
- Gemini/Telegram tokens;
- HMAC shared secret;
- UUID пользователей, REALITY private key и AmneziaWG private keys;
- утверждения, что VPN уже поднят на найденном сервере.
