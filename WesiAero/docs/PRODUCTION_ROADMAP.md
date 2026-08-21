# Дорожная карта до production

## Текущее состояние — Foundation

- готов UI-каркас и адаптивная дизайн-система;
- работает безопасный demo engine;
- реализован control plane с токенами, lease, session limit и quota;
- control plane покрыт тестами;
- определены Android/Windows host contracts;
- реальный data plane намеренно не активируется.

## M1 — Android AmneziaWG

- интегрировать pinned официальный AmneziaWG engine;
- реализовать `VpnService`, foreground notification и network callbacks;
- полный TUN для IPv4/IPv6, TCP/UDP и проверка DNS leaks;
- allowlist/denylist приложений;
- Always-on VPN guidance и проверка Kill Switch;
- QR/text/file import с secure storage;
- instrumented tests на Android 10–16.

Готово, когда 24-часовой soak test переживает Wi‑Fi ↔ LTE, sleep/wake и captive
portal без утечки исходного IP.

## M2 — Windows AmneziaWG

- подписанная Windows Service;
- Wintun lifecycle и локальный authenticated IPC;
- WFP Kill Switch с crash/reboot recovery;
- split routing по IP/domain и documented ограничения per-app routing;
- installer, service upgrade и rollback;
- тесты Windows 10 22H2 и поддерживаемых Windows 11 builds.

Готово, когда service crash не открывает маршрут в обход policy и uninstall
гарантированно удаляет WFP filters и adapter.

## M3 — VLESS + REALITY

- pinned Xray-core на клиенте и сервере;
- TUN → local core bridge без утечки DNS;
- REALITY profile provisioning и overlap rotation;
- Xray stats collector в control plane;
- interoperability suite для Android/Windows и выбранного transport;
- fallback на AmneziaWG только по прозрачной политике, без бесконечных retry.

## M4 — Server Node production

- PostgreSQL/Redis для нескольких control-plane replicas;
- data-plane counters, reconciliation и quota enforcement;
- минимум два узла и автоматический drain;
- mTLS между collector и control plane;
- secrets manager вместо файловых профилей;
- SBOM, pinned digests, dependency scanning и воспроизводимые сборки;
- SLO 99.9%, synthetic probes и incident runbooks.

## M5 — Release hardening

- внешний security review и mobile/desktop penetration test;
- signed APK/AAB, signed MSIX/installer и signed update manifest;
- защита от downgrade/replay;
- privacy policy, retention matrix и процедура удаления аккаунта;
- нагрузочные тесты и p50/p95 latency overhead;
- accessibility audit: keyboard, screen reader, text scaling, reduced motion.

## Решения, которые ещё нужны от владельца продукта

1. финальные package identifiers и юридически проверенная версия логотипа Wesi Aero;
2. регионы первого набора Server Node;
3. модель выдачи доступа: ручные ключи, аккаунт или subscription link;
4. лимиты сессий/трафика и период квоты;
5. способ дистрибуции Android (Play Store, private APK или оба) и Windows;
6. операторская политика хранения технических событий и срок retention.
