import fs from 'node:fs';
import path from 'node:path';
import { DatabaseSync } from 'node:sqlite';

export function openDatabase(filename) {
  if (filename !== ':memory:') {
    fs.mkdirSync(path.dirname(filename), { recursive: true, mode: 0o700 });
  }
  const database = new DatabaseSync(filename);
  database.exec('PRAGMA journal_mode = WAL;');
  database.exec('PRAGMA foreign_keys = ON;');
  database.exec('PRAGMA busy_timeout = 5000;');
  database.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      display_name TEXT NOT NULL,
      token_salt BLOB NOT NULL,
      token_hash BLOB NOT NULL,
      max_sessions INTEGER NOT NULL CHECK (max_sessions > 0),
      quota_bytes INTEGER NOT NULL CHECK (quota_bytes >= 0),
      enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
      created_at INTEGER NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS nodes (
      id TEXT PRIMARY KEY,
      city TEXT NOT NULL,
      country TEXT NOT NULL,
      country_code TEXT NOT NULL,
      endpoint TEXT NOT NULL,
      protocols_json TEXT NOT NULL,
      load REAL NOT NULL DEFAULT 0 CHECK (load >= 0 AND load <= 1),
      online INTEGER NOT NULL DEFAULT 1 CHECK (online IN (0, 1)),
      recommended INTEGER NOT NULL DEFAULT 0 CHECK (recommended IN (0, 1)),
      updated_at INTEGER NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS leases (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id),
      device_id TEXT NOT NULL,
      node_id TEXT NOT NULL REFERENCES nodes(id),
      protocol TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      ended_at INTEGER,
      end_reason TEXT
    ) STRICT;
    CREATE INDEX IF NOT EXISTS leases_active_user_idx
      ON leases(user_id, expires_at, ended_at);

    CREATE TABLE IF NOT EXISTS traffic_usage (
      user_id TEXT NOT NULL REFERENCES users(id),
      period TEXT NOT NULL,
      bytes_in INTEGER NOT NULL DEFAULT 0 CHECK (bytes_in >= 0),
      bytes_out INTEGER NOT NULL DEFAULT 0 CHECK (bytes_out >= 0),
      updated_at INTEGER NOT NULL,
      PRIMARY KEY (user_id, period)
    ) STRICT;

    CREATE TABLE IF NOT EXISTS security_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      event_type TEXT NOT NULL,
      user_id TEXT,
      device_id TEXT,
      created_at INTEGER NOT NULL,
      details_json TEXT NOT NULL DEFAULT '{}'
    ) STRICT;

    CREATE TABLE IF NOT EXISTS app_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    ) STRICT;
    INSERT OR IGNORE INTO app_meta (key, value) VALUES ('catalog_revision', '1');

    CREATE TABLE IF NOT EXISTS node_admin (
      node_id TEXT PRIMARY KEY REFERENCES nodes(id) ON DELETE CASCADE,
      display_name TEXT NOT NULL,
      capacity INTEGER NOT NULL DEFAULT 0 CHECK (capacity >= 0),
      tags_json TEXT NOT NULL DEFAULT '[]',
      notes TEXT NOT NULL DEFAULT '',
      transport_json TEXT NOT NULL DEFAULT '{}',
      updated_at INTEGER NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS plans (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      currency TEXT NOT NULL DEFAULT 'RUB',
      enabled INTEGER NOT NULL DEFAULT 1 CHECK (enabled IN (0, 1)),
      pricing_json TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS licenses (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL UNIQUE REFERENCES users(id),
      key_prefix TEXT NOT NULL,
      key_salt BLOB NOT NULL,
      key_hash BLOB NOT NULL,
      encrypted_key TEXT NOT NULL,
      plan_id TEXT REFERENCES plans(id),
      source TEXT NOT NULL CHECK (source IN ('payment', 'admin', 'migration')),
      ip_mode TEXT NOT NULL CHECK (ip_mode IN ('shared', 'dedicated')),
      device_limit INTEGER NOT NULL CHECK (device_limit BETWEEN 1 AND 5),
      duration_days INTEGER NOT NULL CHECK (duration_days IN (7, 30, 90, 180, 365)),
      status TEXT NOT NULL CHECK (status IN ('active', 'revoked')),
      issued_at INTEGER NOT NULL,
      expires_at INTEGER NOT NULL,
      payment_id TEXT,
      dedicated_ip TEXT,
      note TEXT NOT NULL DEFAULT ''
    ) STRICT;
    CREATE INDEX IF NOT EXISTS licenses_prefix_idx ON licenses(key_prefix);
    CREATE INDEX IF NOT EXISTS licenses_status_expiry_idx
      ON licenses(status, expires_at);

    CREATE TABLE IF NOT EXISTS license_devices (
      license_id TEXT NOT NULL REFERENCES licenses(id) ON DELETE CASCADE,
      device_id TEXT NOT NULL,
      device_name TEXT NOT NULL,
      platform TEXT NOT NULL,
      first_seen_at INTEGER NOT NULL,
      last_seen_at INTEGER NOT NULL,
      revoked_at INTEGER,
      PRIMARY KEY (license_id, device_id)
    ) STRICT;

    CREATE TABLE IF NOT EXISTS payments (
      id TEXT PRIMARY KEY,
      provider TEXT NOT NULL CHECK (provider IN ('mock', 'yookassa', 'crypto_pay')),
      status TEXT NOT NULL CHECK (status IN ('pending', 'paid', 'canceled', 'expired', 'failed')),
      amount_minor INTEGER NOT NULL CHECK (amount_minor >= 0),
      currency TEXT NOT NULL,
      plan_id TEXT NOT NULL REFERENCES plans(id),
      ip_mode TEXT NOT NULL CHECK (ip_mode IN ('shared', 'dedicated')),
      device_limit INTEGER NOT NULL CHECK (device_limit BETWEEN 1 AND 5),
      duration_days INTEGER NOT NULL CHECK (duration_days IN (7, 30, 90, 180, 365)),
      checkout_url TEXT,
      external_id TEXT,
      license_id TEXT REFERENCES licenses(id),
      customer_ref TEXT,
      idempotency_key TEXT NOT NULL UNIQUE,
      claim_salt BLOB NOT NULL,
      claim_hash BLOB NOT NULL,
      provider_json TEXT NOT NULL DEFAULT '{}',
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    ) STRICT;
    CREATE UNIQUE INDEX IF NOT EXISTS payments_external_idx
      ON payments(provider, external_id) WHERE external_id IS NOT NULL;

    CREATE TABLE IF NOT EXISTS payment_settings (
      provider TEXT PRIMARY KEY CHECK (provider IN ('mock', 'yookassa', 'crypto_pay')),
      enabled INTEGER NOT NULL DEFAULT 0 CHECK (enabled IN (0, 1)),
      test_mode INTEGER NOT NULL DEFAULT 1 CHECK (test_mode IN (0, 1)),
      public_json TEXT NOT NULL DEFAULT '{}',
      updated_at INTEGER NOT NULL
    ) STRICT;

    CREATE TABLE IF NOT EXISTS processed_webhooks (
      provider TEXT NOT NULL,
      event_id TEXT NOT NULL,
      received_at INTEGER NOT NULL,
      PRIMARY KEY (provider, event_id)
    ) STRICT;
  `);
  return database;
}
