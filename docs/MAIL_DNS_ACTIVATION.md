# WesiOS self-hosted mail — финальная DNS-активация

Статус на 2026-08-09:

- Postfix active;
- OpenDKIM active;
- PocketBase active;
- outbound TCP/25 OPEN;
- PTR уже `mail.wesi-inc.ru`;
- публичные A/SPF/DKIM/DMARC пока не опубликованы;
- DNS обслуживают `a.aeza-dns.net` / `b.aeza-dns.net`;
- PocketBase SMTP намеренно выключен, пока DNS не прошёл проверки.

## 1. Получить IP и публичный DKIM TXT

На production VPS под root/sudo:

```bash
echo "PUBLIC_IP=$(curl -4fsS https://api.ipify.org)"
echo
sudo cat /etc/opendkim/keys/wesi-inc.ru/wesios.txt
```

Нужен только `wesios.txt` — это **публичная** DNS-запись. Файл `.private` не копировать, не отправлять и не публиковать.

## 2. Записи в Aéza DNS

### A

- Type: `A`
- Name/Host: `mail`
- Value: IPv4 из `PUBLIC_IP`

### SPF

- Type: `TXT`
- Name/Host: `@`
- Value:

```text
v=spf1 ip4:<PUBLIC_IP> -all
```

### DKIM

- Type: `TXT`
- Name/Host: `wesios._domainkey`
- Value: склеенное значение из `wesios.txt`, начинающееся с `v=DKIM1; ... p=...`

### DMARC

- Type: `TXT`
- Name/Host: `_dmarc`
- Value:

```text
v=DMARC1; p=quarantine; rua=mailto:postmaster@wesi-inc.ru; adkim=s; aspf=s
```

PTR не менять, если reverse DNS уже возвращает `mail.wesi-inc.ru`.

## 3. Не включать SMTP вручную до проверки

После публикации DNS использовать GitHub Actions workflow:

**`Activate WesiOS Local Mail`**

Он сам fail-closed проверит:

- A;
- PTR;
- SPF;
- DKIM TXT;
- `opendkim-testkey`;
- DMARC;
- Postfix/OpenDKIM;
- outbound TCP/25.

Только после зелёных проверок он включит PocketBase SMTP на `127.0.0.1:25`, восстановит временный конфигурационный hook и потребует `200 ready=true smtpReady=true` от `/api/wesi/auth/mail-ready`.

## 4. После активации

Обязателен реальный end-to-end тест на внешний почтовый ящик:

`password → email OTP → verify → revocable WesiOS session → revoke`.

До успешного E2E вход остаётся fail-closed. Recovery/bypass вход не возвращать.
