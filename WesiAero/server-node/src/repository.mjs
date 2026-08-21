import { randomUUID } from 'node:crypto';

import {
  createAccessCredential,
  parseAccessToken,
  verifySecret,
} from './credentials.mjs';

export const SUPPORTED_PROTOCOLS = Object.freeze([
  'vless-reality',
  'vmess',
  'trojan',
  'shadowsocks',
  'hysteria2',
  'tuic',
  'wireguard',
  'amneziawg',
]);

const SUPPORTED_PROTOCOL_SET = new Set(SUPPORTED_PROTOCOLS);

export function normalizeProtocol(protocol) {
  // Compatibility with profiles/catalog rows created by the old prototype.
  if (protocol === 'vmess-xray') return 'vmess';
  return protocol;
}

export class RepositoryError extends Error {
  constructor(code, message, statusCode = 400) {
    super(message);
    this.name = 'RepositoryError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class GatewayRepository {
  constructor(database, { leaseTtlSeconds = 120, now = () => Date.now() } = {}) {
    this.database = database;
    this.leaseTtlMs = leaseTtlSeconds * 1000;
    this.now = now;
  }

  createUser({ displayName, maxSessions = 1, quotaBytes = 0 }) {
    if (typeof displayName !== 'string' || displayName.trim().length < 2) {
      throw new RepositoryError('INVALID_NAME', 'displayName is required');
    }
    if (!Number.isSafeInteger(maxSessions) || maxSessions < 1 || maxSessions > 20) {
      throw new RepositoryError('INVALID_SESSION_LIMIT', 'maxSessions must be 1..20');
    }
    if (!Number.isSafeInteger(quotaBytes) || quotaBytes < 0) {
      throw new RepositoryError('INVALID_QUOTA', 'quotaBytes must be a non-negative integer');
    }

    const credential = createAccessCredential();
    this.database.prepare(`
      INSERT INTO users (
        id, display_name, token_salt, token_hash,
        max_sessions, quota_bytes, enabled, created_at
      ) VALUES (?, ?, ?, ?, ?, ?, 1, ?)
    `).run(
      credential.userId,
      displayName.trim(),
      credential.salt,
      credential.hash,
      maxSessions,
      quotaBytes,
      this.now(),
    );
    return {
      id: credential.userId,
      displayName: displayName.trim(),
      maxSessions,
      quotaBytes,
      token: credential.token,
    };
  }

  authenticate(token) {
    const parsed = parseAccessToken(token);
    if (!parsed) return null;
    const row = this.database.prepare(`
      SELECT id, display_name, token_salt, token_hash,
             max_sessions, quota_bytes, enabled
      FROM users WHERE id = ?
    `).get(parsed.userId);
    if (!row || row.enabled !== 1) return null;
    if (!verifySecret(parsed.secret, row.token_salt, row.token_hash)) return null;
    return mapUser(row);
  }

  upsertNode(node) {
    const normalizedNode = {
      ...node,
      protocols: [...new Set(node.protocols.map(normalizeProtocol))],
    };
    validateNode(normalizedNode);
    this.database.prepare(`
      INSERT INTO nodes (
        id, city, country, country_code, endpoint, protocols_json,
        load, online, recommended, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        city = excluded.city,
        country = excluded.country,
        country_code = excluded.country_code,
        endpoint = excluded.endpoint,
        protocols_json = excluded.protocols_json,
        load = excluded.load,
        online = excluded.online,
        recommended = excluded.recommended,
        updated_at = excluded.updated_at
    `).run(
      normalizedNode.id,
      normalizedNode.city,
      normalizedNode.country,
      normalizedNode.countryCode.toUpperCase(),
      normalizedNode.endpoint,
      JSON.stringify(normalizedNode.protocols),
      normalizedNode.load ?? 0,
      normalizedNode.online === false ? 0 : 1,
      normalizedNode.recommended === true ? 1 : 0,
      this.now(),
    );
    return this.getNode(normalizedNode.id);
  }

  getNode(id) {
    const row = this.database.prepare('SELECT * FROM nodes WHERE id = ?').get(id);
    return row ? mapNode(row) : null;
  }

  listNodes() {
    return this.database.prepare(`
      SELECT * FROM nodes
      WHERE online = 1
      ORDER BY recommended DESC, load ASC, city ASC
    `).all().map(mapNode);
  }

  listAllNodes() {
    return this.database.prepare(`
      SELECT * FROM nodes
      ORDER BY recommended DESC, online DESC, load ASC, city ASC
    `).all().map(mapNode);
  }

  deleteNode(id) {
    const active = this.database.prepare(`
      SELECT COUNT(*) AS count FROM leases
      WHERE node_id = ? AND ended_at IS NULL AND expires_at > ?
    `).get(id, this.now()).count;
    if (active > 0) {
      throw new RepositoryError(
        'NODE_HAS_ACTIVE_LEASES',
        'Server node has active sessions',
        409,
      );
    }
    return this.database.prepare('DELETE FROM nodes WHERE id = ?').run(id).changes === 1;
  }

  reserveLease({ user, deviceId, nodeId, protocol }) {
    validateDeviceId(deviceId);
    protocol = normalizeProtocol(protocol);
    if (!SUPPORTED_PROTOCOL_SET.has(protocol)) {
      throw new RepositoryError('INVALID_PROTOCOL', 'Unsupported protocol');
    }

    const node = this.getNode(nodeId);
    if (!node || !node.online) {
      throw new RepositoryError('NODE_UNAVAILABLE', 'Server node is unavailable', 409);
    }
    if (!node.protocols.includes(protocol)) {
      throw new RepositoryError('PROTOCOL_UNAVAILABLE', 'Protocol is unavailable on node', 409);
    }

    const now = this.now();
    const expiresAt = now + this.leaseTtlMs;
    const leaseId = randomUUID();

    return this.#transaction(() => {
      this.database.prepare(`
        UPDATE leases
        SET ended_at = ?, end_reason = 'expired'
        WHERE user_id = ? AND ended_at IS NULL AND expires_at <= ?
      `).run(now, user.id, now);

      this.database.prepare(`
        UPDATE leases
        SET ended_at = ?, end_reason = 'superseded'
        WHERE user_id = ? AND device_id = ?
          AND ended_at IS NULL AND expires_at > ?
      `).run(now, user.id, deviceId, now);

      const active = this.database.prepare(`
        SELECT COUNT(*) AS count
        FROM leases
        WHERE user_id = ? AND ended_at IS NULL AND expires_at > ?
      `).get(user.id, now).count;
      if (active >= user.maxSessions) {
        this.#securityEvent('session_limit_denied', user.id, deviceId, {
          nodeId,
          protocol,
        });
        throw new RepositoryError(
          'SESSION_LIMIT_REACHED',
          'Active session limit reached',
          409,
        );
      }

      const usage = this.getUsage(user.id);
      if (user.quotaBytes > 0 && usage.totalBytes >= user.quotaBytes) {
        this.#securityEvent('quota_denied', user.id, deviceId, {});
        throw new RepositoryError('TRAFFIC_QUOTA_REACHED', 'Traffic quota reached', 403);
      }

      this.database.prepare(`
        INSERT INTO leases (
          id, user_id, device_id, node_id, protocol,
          created_at, last_seen_at, expires_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        leaseId,
        user.id,
        deviceId,
        nodeId,
        protocol,
        now,
        now,
        expiresAt,
      );
      this.#securityEvent('lease_opened', user.id, deviceId, { nodeId, protocol });
      return {
        id: leaseId,
        node,
        protocol,
        createdAt: new Date(now).toISOString(),
        expiresAt: new Date(expiresAt).toISOString(),
      };
    });
  }

  heartbeatLease({ userId, leaseId }) {
    const now = this.now();
    const expiresAt = now + this.leaseTtlMs;
    const result = this.database.prepare(`
      UPDATE leases
      SET last_seen_at = ?, expires_at = ?
      WHERE id = ? AND user_id = ? AND ended_at IS NULL AND expires_at > ?
    `).run(now, expiresAt, leaseId, userId, now);
    if (result.changes !== 1) {
      throw new RepositoryError('LEASE_NOT_FOUND', 'Active lease not found', 404);
    }
    return { expiresAt: new Date(expiresAt).toISOString() };
  }

  closeLease({ userId, leaseId, reason = 'client_disconnect' }) {
    const now = this.now();
    const result = this.database.prepare(`
      UPDATE leases
      SET ended_at = ?, end_reason = ?
      WHERE id = ? AND user_id = ? AND ended_at IS NULL
    `).run(now, reason, leaseId, userId);
    return result.changes === 1;
  }

  discardLease(leaseId) {
    this.database.prepare(`
      UPDATE leases
      SET ended_at = ?, end_reason = 'provisioning_failed'
      WHERE id = ? AND ended_at IS NULL
    `).run(this.now(), leaseId);
  }

  getUsage(userId) {
    const period = currentPeriod(this.now());
    const row = this.database.prepare(`
      SELECT bytes_in, bytes_out
      FROM traffic_usage
      WHERE user_id = ? AND period = ?
    `).get(userId, period);
    const bytesIn = row?.bytes_in ?? 0;
    const bytesOut = row?.bytes_out ?? 0;
    return {
      period,
      bytesIn,
      bytesOut,
      totalBytes: bytesIn + bytesOut,
    };
  }

  recordServerUsage({ userId, bytesIn, bytesOut }) {
    if (!Number.isSafeInteger(bytesIn) || bytesIn < 0 ||
        !Number.isSafeInteger(bytesOut) || bytesOut < 0) {
      throw new RepositoryError('INVALID_USAGE', 'Usage deltas must be non-negative integers');
    }
    const now = this.now();
    const period = currentPeriod(now);
    this.database.prepare(`
      INSERT INTO traffic_usage (user_id, period, bytes_in, bytes_out, updated_at)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(user_id, period) DO UPDATE SET
        bytes_in = bytes_in + excluded.bytes_in,
        bytes_out = bytes_out + excluded.bytes_out,
        updated_at = excluded.updated_at
    `).run(userId, period, bytesIn, bytesOut, now);
    return this.getUsage(userId);
  }

  activeLeaseCount(userId) {
    return this.database.prepare(`
      SELECT COUNT(*) AS count FROM leases
      WHERE user_id = ? AND ended_at IS NULL AND expires_at > ?
    `).get(userId, this.now()).count;
  }

  #securityEvent(eventType, userId, deviceId, details) {
    this.database.prepare(`
      INSERT INTO security_events (
        event_type, user_id, device_id, created_at, details_json
      ) VALUES (?, ?, ?, ?, ?)
    `).run(eventType, userId, deviceId, this.now(), JSON.stringify(details));
  }

  #transaction(operation) {
    this.database.exec('BEGIN IMMEDIATE;');
    try {
      const result = operation();
      this.database.exec('COMMIT;');
      return result;
    } catch (error) {
      this.database.exec('ROLLBACK;');
      throw error;
    }
  }
}

function currentPeriod(now) {
  return new Date(now).toISOString().slice(0, 7);
}

function mapUser(row) {
  return {
    id: row.id,
    displayName: row.display_name,
    maxSessions: row.max_sessions,
    quotaBytes: row.quota_bytes,
  };
}

function mapNode(row) {
  return {
    id: row.id,
    city: row.city,
    country: row.country,
    countryCode: row.country_code,
    endpoint: row.endpoint,
    protocols: [...new Set(JSON.parse(row.protocols_json).map(normalizeProtocol))],
    load: row.load,
    online: row.online === 1,
    recommended: row.recommended === 1,
  };
}

function validateDeviceId(deviceId) {
  if (typeof deviceId !== 'string' || !/^[a-zA-Z0-9._:-]{8,128}$/.test(deviceId)) {
    throw new RepositoryError('INVALID_DEVICE_ID', 'Invalid deviceId');
  }
}

function validateNode(node) {
  if (!node || typeof node !== 'object') {
    throw new RepositoryError('INVALID_NODE', 'Node body is required');
  }
  for (const key of ['id', 'city', 'country', 'countryCode', 'endpoint']) {
    if (typeof node[key] !== 'string' || node[key].trim() === '') {
      throw new RepositoryError('INVALID_NODE', `${key} is required`);
    }
  }
  if (!/^[a-zA-Z0-9-]{2,64}$/.test(node.id)) {
    throw new RepositoryError('INVALID_NODE', 'Invalid node id');
  }
  if (!Array.isArray(node.protocols) || node.protocols.length === 0 ||
      node.protocols.some((value) => !SUPPORTED_PROTOCOL_SET.has(value))) {
    throw new RepositoryError('INVALID_NODE', 'Invalid node protocols');
  }
  if (node.load !== undefined &&
      (typeof node.load !== 'number' || node.load < 0 || node.load > 1)) {
    throw new RepositoryError('INVALID_NODE', 'Node load must be 0..1');
  }
}
