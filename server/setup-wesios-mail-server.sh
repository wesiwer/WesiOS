#!/usr/bin/env bash
set -euo pipefail

# WesiOS self-hosted outbound mail server.
# Run once as root on the production VPS:
#   sudo bash server/setup-wesios-mail-server.sh
#
# This configures a SEND-ONLY Postfix instance. It doesn't expose a mailbox
# service and doesn't accept remote mail. PocketBase uses /usr/sbin/sendmail
# when its SMTP setting is disabled.

DOMAIN="${WESI_MAIL_DOMAIN:-wesi-inc.ru}"
MAIL_HOST="${WESI_MAIL_HOST:-mail.$DOMAIN}"
SELECTOR="${WESI_DKIM_SELECTOR:-wesios}"
SENDER="${WESI_MAIL_SENDER:-security@$DOMAIN}"

if [[ ${EUID:-$(id -u)} -ne 0 ]]; then
  echo "Run this script as root." >&2
  exit 1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends postfix opendkim opendkim-tools ca-certificates curl dnsutils

# Send-only Postfix: local applications may submit mail; the VPS does not act
# as an open relay and doesn't expose SMTP as a mailbox service.
postconf -e "myhostname = $MAIL_HOST"
postconf -e "myorigin = $DOMAIN"
postconf -e "mydestination ="
postconf -e "inet_interfaces = loopback-only"
postconf -e "inet_protocols = ipv4"
postconf -e "mynetworks = 127.0.0.0/8"
postconf -e "relayhost ="
postconf -e "smtp_tls_security_level = may"
postconf -e "smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt"
postconf -e "smtp_helo_name = $MAIL_HOST"
postconf -e "smtp_header_checks = regexp:/etc/postfix/wesios_header_checks"
postconf -e "non_smtpd_milters = inet:127.0.0.1:8891"
postconf -e "smtpd_milters = inet:127.0.0.1:8891"
postconf -e "milter_default_action = accept"
postconf -e "milter_protocol = 6"

cat >/etc/postfix/wesios_header_checks <<EOF
/^From:.*/ PREPEND X-WesiOS-Mail: transactional
EOF

DKIM_DIR="/etc/opendkim/keys/$DOMAIN"
install -d -m 0750 -o opendkim -g opendkim "$DKIM_DIR"
if [[ ! -s "$DKIM_DIR/$SELECTOR.private" ]]; then
  opendkim-genkey -b 2048 -d "$DOMAIN" -D "$DKIM_DIR" -s "$SELECTOR" -v
fi
chown opendkim:opendkim "$DKIM_DIR/$SELECTOR.private" "$DKIM_DIR/$SELECTOR.txt"
chmod 0600 "$DKIM_DIR/$SELECTOR.private"

cat >/etc/opendkim.conf <<EOF
Syslog                  yes
UMask                   007
Canonicalization        relaxed/simple
Mode                    sv
SubDomains              no
OversignHeaders         From
Socket                  inet:8891@127.0.0.1
PidFile                 /run/opendkim/opendkim.pid
UserID                  opendkim
KeyTable                /etc/opendkim/KeyTable
SigningTable            refile:/etc/opendkim/SigningTable
ExternalIgnoreList      refile:/etc/opendkim/TrustedHosts
InternalHosts           refile:/etc/opendkim/TrustedHosts
EOF

cat >/etc/opendkim/KeyTable <<EOF
$SELECTOR._domainkey.$DOMAIN $DOMAIN:$SELECTOR:$DKIM_DIR/$SELECTOR.private
EOF
cat >/etc/opendkim/SigningTable <<EOF
*@$DOMAIN $SELECTOR._domainkey.$DOMAIN
EOF
cat >/etc/opendkim/TrustedHosts <<EOF
127.0.0.1
localhost
$MAIL_HOST
EOF

systemctl enable --now opendkim postfix
systemctl restart opendkim postfix

SENDMAIL="$(command -v sendmail || true)"
[[ -n "$SENDMAIL" ]] || { echo "sendmail interface is missing" >&2; exit 1; }
postfix check
systemctl is-active --quiet postfix
systemctl is-active --quiet opendkim

PUBLIC_IP="$(curl -4fsS --max-time 10 https://api.ipify.org || true)"
DKIM_RECORD="$(tr -d '\n\t\"' < "$DKIM_DIR/$SELECTOR.txt" | sed -E 's/^[^(]*\((.*)\)[^)]*$/\1/' | sed -E 's/[[:space:]]+/ /g')"

cat <<EOF

WesiOS local mail transport is installed.
Sender: $SENDER
Host:   $MAIL_HOST
sendmail: $SENDMAIL

REQUIRED DNS / PROVIDER SETTINGS
1. A record:
   $MAIL_HOST -> ${PUBLIC_IP:-<SERVER_PUBLIC_IPV4>}

2. SPF TXT for $DOMAIN:
   v=spf1 ip4:${PUBLIC_IP:-<SERVER_PUBLIC_IPV4>} -all

3. DKIM TXT name:
   $SELECTOR._domainkey.$DOMAIN
   Value is stored in: $DKIM_DIR/$SELECTOR.txt
   Current generated record:
   $DKIM_RECORD

4. DMARC TXT name:
   _dmarc.$DOMAIN
   v=DMARC1; p=quarantine; rua=mailto:postmaster@$DOMAIN; adkim=s; aspf=s

5. Ask the VPS provider to set reverse DNS (PTR) of ${PUBLIC_IP:-<SERVER_PUBLIC_IPV4>} to:
   $MAIL_HOST

6. IMPORTANT: outbound TCP/25 must be open. Test with:
   timeout 8 bash -c 'cat < /dev/null > /dev/tcp/gmail-smtp-in.l.google.com/25'

After DNS/PTR propagation, test delivery:
   printf 'Subject: WesiOS mail test\nFrom: WesiOS <$SENDER>\nTo: YOUR_EMAIL\n\nWesiOS mail transport works.\n' | sendmail -v YOUR_EMAIL
EOF
