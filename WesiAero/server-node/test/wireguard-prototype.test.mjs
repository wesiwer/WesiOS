import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { describe, it } from 'node:test';

const here = path.dirname(fileURLToPath(import.meta.url));
const installerPath = path.resolve(
  here,
  '../scripts/setup-wireguard-prototype.sh',
);
const installer = fs.readFileSync(installerPath, 'utf8');

describe('WireGuard prototype gateway installer', () => {
  it('enables forwarding and NAT instead of creating a local-only tunnel', () => {
    assert.match(installer, /net\.ipv4\.ip_forward=1/);
    assert.match(installer, /POSTROUTING[^\n]+MASQUERADE/);
    assert.match(installer, /FORWARD -i %i -j ACCEPT/);
    assert.match(installer, /FORWARD -o %i/);
  });

  it('creates a full-tunnel encrypted client profile and persistent gateway', () => {
    assert.match(installer, /AllowedIPs = 0\.0\.0\.0\/0/);
    assert.match(installer, /PersistentKeepalive = 25/);
    assert.match(installer, /wg genkey/);
    assert.match(installer, /wg pubkey/);
    assert.match(installer, /systemctl enable "wg-quick@\$\{WG_INTERFACE\}\.service"/);
    assert.match(installer, /systemctl restart "wg-quick@\$\{WG_INTERFACE\}\.service"/);
  });

  it('keeps generated VPN credentials private on disk', () => {
    assert.match(installer, /umask 077/);
    assert.match(installer, /chmod 600 "\$SERVER_CONFIG"/);
    assert.match(installer, /chmod 600 "\$WG_CLIENT_CONFIG"/);
  });
});
