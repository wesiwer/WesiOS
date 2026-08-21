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
  `);
  return database;
}

