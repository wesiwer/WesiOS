import { randomBytes, randomUUID } from 'node:crypto';

import {
  createLicenseCredential,
  hashSecret,
  parseLicenseKey,
  verifySecret,
} from './credentials.mjs';
import { RepositoryError } from './repository.mjs';

export const durationOptions = Object.freeze([7, 30, 90, 180, 365]);
export const ipModeOptions = Object.freeze(['shared', 'dedicated']);
export const paymentProviderOptions = Object.freeze([
  'mock',
  'yookassa',
  'crypto_pay',
]);

const defaultPricing = Object.freeze({
  shared: {
    7: { base: 14900, extraDevice: 5900 },
    30: { base: 34900, extraDevice: 12900 },
    90: { base: 79900, extraDevice: 29900 },
    180: { base: 139000, extraDevice: 49900 },
    365: { base: 239000, extraDevice: 89900 },
  },
  dedicated: {
    7: { base: 34900, extraDevice: 7900 },
    30: { base: 79900, extraDevice: 17900 },
    90: { base: 199000, extraDevice: 44900 },
    180: { base: 349000, extraDevice: 79900 },
    365: { base: 599000, extraDevice: 139000 },
  },
});

export class CommerceError extends Error {
  constructor(code, message, statusCode = 400) {
    super(message);
    this.name = 'CommerceError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class CommerceRepository {
  constructor(database, gatewayRepository, {
    now = () => Date.now(),
    secretVault,
  } = {}) {
    this.database = database;
    this.gatewayRepository = gatewayRepository;
    this.now = now;
    this.secretVault = secretVault;
  }

  seedDefaults() {
    const existing = this.database.prepare('SELECT COUNT(*) AS count FROM plans').get().count;
    if (existing === 0) {
      this.upsertPlan({
        id: 'aero-flex',
        name: 'Aero Flex',
        description: 'Гибкий доступ с выбором IP, срока и числа устройств.',
        currency: 'RUB',
        enabled: true,
        sortOrder: 10,
        pricing: defaultPricing,
      });
    }
    const settings = this.database.prepare(
      'SELECT COUNT(*) AS count FROM payment_settings',
    ).get().count;
    if (settings === 0) {
      this.setPaymentSetting({
        provider: 'mock',
        enabled: true,
        testMode: true,
        publicConfig: { label: 'Тестовая оплата' },
      });
      this.setPaymentSetting({
        provider: 'yookassa',
        enabled: false,
        testMode: true,
        publicConfig: { label: 'СБП' },
      });
      this.setPaymentSetting({
        provider: 'crypto_pay',
        enabled: false,
        testMode: true,
        publicConfig: { label: 'Криптовалюта' },
      });
    }
  }

  get revision() {
    return Number.parseInt(
      this.database.prepare(
        "SELECT value FROM app_meta WHERE key = 'catalog_revision'",
      ).get()?.value ?? '1',
      10,
    );
  }

  bumpRevision() {
    this.database.prepare(`
      UPDATE app_meta
      SET value = CAST(CAST(value AS INTEGER) + 1 AS TEXT)
      WHERE key = 'catalog_revision'
    `).run();
    return this.revision;
  }

  publicCatalog() {
    return {
      revision: this.revision,
      generatedAt: new Date(this.now()).toISOString(),
      plans: this.listPlans({ onlyEnabled: true }),
      servers: this.listServers({ onlyOnline: true }).map(publicServer),
      paymentMethods: this.listPaymentSettings({ onlyEnabled: true }).map((item) => ({
        provider: item.provider,
        label: item.publicConfig.label ?? providerLabel(item.provider),
        testMode: item.testMode,
      })),
      options: {
        ipModes: ipModeOptions,
        deviceLimits: [1, 2, 3, 4, 5],
        durationDays: durationOptions,
      },
    };
  }

  upsertServer(input) {
    const node = this.gatewayRepository.upsertNode(input);
    const displayName = cleanText(input.displayName ?? `${node.city} · ${node.country}`, 2, 80);
    const capacity = integerInRange(input.capacity ?? 0, 0, 1_000_000, 'capacity');
    const tags = Array.isArray(input.tags)
      ? input.tags.map((value) => cleanText(value, 1, 32)).slice(0, 20)
      : [];
    const notes = optionalText(input.notes, 2000);
    const transport = plainObject(input.transportConfig ?? {}, 'transportConfig');
    this.database.prepare(`
      INSERT INTO node_admin (
        node_id, display_name, capacity, tags_json, notes, transport_json, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(node_id) DO UPDATE SET
        display_name = excluded.display_name,
        capacity = excluded.capacity,
        tags_json = excluded.tags_json,
        notes = excluded.notes,
        transport_json = excluded.transport_json,
        updated_at = excluded.updated_at
    `).run(
      node.id,
      displayName,
      capacity,
      JSON.stringify(tags),
      notes,
      JSON.stringify(transport),
      this.now(),
    );
    this.bumpRevision();
    return this.getServer(node.id);
  }

  getServer(id) {
    const row = this.database.prepare(`
      SELECT n.*, a.display_name, a.capacity, a.tags_json,
             a.notes, a.transport_json
      FROM nodes n
      LEFT JOIN node_admin a ON a.node_id = n.id
      WHERE n.id = ?
    `).get(id);
    return row ? mapServer(row) : null;
  }

  listServers({ onlyOnline = false } = {}) {
    const where = onlyOnline ? 'WHERE n.online = 1' : '';
    return this.database.prepare(`
      SELECT n.*, a.display_name, a.capacity, a.tags_json,
             a.notes, a.transport_json
      FROM nodes n
      LEFT JOIN node_admin a ON a.node_id = n.id
      ${where}
      ORDER BY n.recommended DESC, n.online DESC, n.load ASC, n.city ASC
    `).all().map(mapServer);
  }

  deleteServer(id) {
    const deleted = this.gatewayRepository.deleteNode(id);
    if (deleted) this.bumpRevision();
    return deleted;
  }

  upsertPlan(input) {
    const id = cleanIdentifier(input.id, 'plan id');
    const name = cleanText(input.name, 2, 80);
    const description = optionalText(input.description, 500);
    const currency = cleanCurrency(input.currency ?? 'RUB');
    const pricing = validatePricing(input.pricing);
    const sortOrder = integerInRange(input.sortOrder ?? 0, -10000, 10000, 'sortOrder');
    const enabled = input.enabled !== false;
    this.database.prepare(`
      INSERT INTO plans (
        id, name, description, currency, enabled, pricing_json, sort_order, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        name = excluded.name,
        description = excluded.description,
        currency = excluded.currency,
        enabled = excluded.enabled,
        pricing_json = excluded.pricing_json,
        sort_order = excluded.sort_order,
        updated_at = excluded.updated_at
    `).run(
      id,
      name,
      description,
      currency,
      enabled ? 1 : 0,
      JSON.stringify(pricing),
      sortOrder,
      this.now(),
    );
    this.bumpRevision();
    return this.getPlan(id);
  }

  getPlan(id) {
    const row = this.database.prepare('SELECT * FROM plans WHERE id = ?').get(id);
    return row ? mapPlan(row) : null;
  }

  listPlans({ onlyEnabled = false } = {}) {
    const where = onlyEnabled ? 'WHERE enabled = 1' : '';
    return this.database.prepare(`
      SELECT * FROM plans ${where}
      ORDER BY sort_order DESC, name ASC
    `).all().map(mapPlan);
  }

  deletePlan(id) {
    const uses = this.database.prepare(`
      SELECT
        (SELECT COUNT(*) FROM licenses WHERE plan_id = ?) +
        (SELECT COUNT(*) FROM payments WHERE plan_id = ?) AS count
    `).get(id, id).count;
    if (uses > 0) {
      throw new CommerceError(
        'PLAN_IN_USE',
        'Plan is referenced by licenses or payments; disable it instead',
        409,
      );
    }
    const deleted = this.database.prepare('DELETE FROM plans WHERE id = ?').run(id).changes === 1;
    if (deleted) this.bumpRevision();
    return deleted;
  }

  quote({ planId, ipMode, deviceLimit, durationDays }) {
    validateSelection({ ipMode, deviceLimit, durationDays });
    const plan = this.getPlan(planId);
    if (!plan || !plan.enabled) {
      throw new CommerceError('PLAN_UNAVAILABLE', 'Tariff plan is unavailable', 404);
    }
    const rate = plan.pricing[ipMode]?.[String(durationDays)];
    if (!rate) {
      throw new CommerceError('PRICE_UNAVAILABLE', 'Price is not configured', 409);
    }
    const amountMinor = rate.base + rate.extraDevice * (deviceLimit - 1);
    return {
      planId: plan.id,
      planName: plan.name,
      ipMode,
      deviceLimit,
      durationDays,
      amountMinor,
      currency: plan.currency,
      displayAmount: formatMoney(amountMinor, plan.currency),
    };
  }

  createLicense({
    planId = null,
    ipMode,
    deviceLimit,
    durationDays,
    source = 'admin',
    paymentId = null,
    note = '',
  }) {
    validateSelection({ ipMode, deviceLimit, durationDays });
    if (!['payment', 'admin', 'migration'].includes(source)) {
      throw new CommerceError('INVALID_LICENSE_SOURCE', 'Invalid license source');
    }
    if (planId !== null && !this.getPlan(planId)) {
      throw new CommerceError('PLAN_UNAVAILABLE', 'Tariff plan is unavailable', 404);
    }
    return this.#transaction(() => this.#createLicenseRecord({
      planId,
      ipMode,
      deviceLimit,
      durationDays,
      source,
      paymentId,
      note: optionalText(note, 500),
    }));
  }

  #createLicenseRecord({
    planId,
    ipMode,
    deviceLimit,
    durationDays,
    source,
    paymentId,
    note,
  }) {
    const user = this.gatewayRepository.createUser({
      displayName: `Aero ${source} license`,
      maxSessions: deviceLimit,
      quotaBytes: 0,
    });
    const credential = createLicenseCredential();
    const issuedAt = this.now();
    const expiresAt = issuedAt + durationDays * 86_400_000;
    this.database.prepare(`
      INSERT INTO licenses (
        id, user_id, key_prefix, key_salt, key_hash, encrypted_key, plan_id, source,
        ip_mode, device_limit, duration_days, status, issued_at, expires_at,
        payment_id, note
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'active', ?, ?, ?, ?)
    `).run(
      credential.licenseId,
      user.id,
      credential.prefix,
      credential.salt,
      credential.hash,
      this.#sealLicenseKey(credential.licenseId, credential.key),
      planId,
      source,
      ipMode,
      deviceLimit,
      durationDays,
      issuedAt,
      expiresAt,
      paymentId,
      note,
    );
    return {
      key: credential.key,
      license: this.getLicense(credential.licenseId),
    };
  }

  authenticateLicense(key, { allowExpired = false } = {}) {
    const parsed = parseLicenseKey(key);
    if (!parsed) return null;
    const row = this.database.prepare(`
      SELECT l.*, u.display_name, u.max_sessions, u.quota_bytes, u.enabled
      FROM licenses l
      JOIN users u ON u.id = l.user_id
      WHERE l.id = ?
    `).get(parsed.licenseId);
    if (!row || row.enabled !== 1 ||
        !verifySecret(parsed.secret, row.key_salt, row.key_hash)) return null;
    const license = mapLicense(row, this.deviceCount(row.id));
    if (!allowExpired) this.assertLicenseActive(license);
    return {
      license,
      user: {
        id: row.user_id,
        displayName: row.display_name,
        maxSessions: row.max_sessions,
        quotaBytes: row.quota_bytes,
      },
    };
  }

  assertLicenseActive(license) {
    if (license.status !== 'active') {
      throw new CommerceError('LICENSE_REVOKED', 'License key was revoked', 403);
    }
    if (Date.parse(license.expiresAt) <= this.now()) {
      throw new CommerceError('LICENSE_EXPIRED', 'License key has expired', 403);
    }
  }

  bindDevice({ key, deviceId, deviceName, platform }) {
    validateDeviceId(deviceId);
    const authenticated = this.authenticateLicense(key);
    if (!authenticated) {
      throw new CommerceError('INVALID_LICENSE_KEY', 'Invalid license key', 401);
    }
    const licenseId = authenticated.license.id;
    const now = this.now();
    return this.#transaction(() => {
      const existing = this.database.prepare(`
        SELECT revoked_at FROM license_devices
        WHERE license_id = ? AND device_id = ?
      `).get(licenseId, deviceId);
      if (existing && existing.revoked_at === null) {
        this.database.prepare(`
          UPDATE license_devices
          SET device_name = ?, platform = ?, last_seen_at = ?
          WHERE license_id = ? AND device_id = ?
        `).run(
          cleanText(deviceName || 'Unknown device', 1, 100),
          cleanText(platform || 'unknown', 1, 40),
          now,
          licenseId,
          deviceId,
        );
      } else {
        const count = this.deviceCount(licenseId);
        if (count >= authenticated.license.deviceLimit) {
          throw new CommerceError(
            'DEVICE_LIMIT_EXCEEDED',
            `License allows ${authenticated.license.deviceLimit} device(s)`,
            409,
          );
        }
        if (existing) {
          this.database.prepare(`
            UPDATE license_devices
            SET device_name = ?, platform = ?, first_seen_at = ?,
                last_seen_at = ?, revoked_at = NULL
            WHERE license_id = ? AND device_id = ?
          `).run(
            cleanText(deviceName || 'Unknown device', 1, 100),
            cleanText(platform || 'unknown', 1, 40),
            now,
            now,
            licenseId,
            deviceId,
          );
        } else {
          this.database.prepare(`
            INSERT INTO license_devices (
              license_id, device_id, device_name, platform,
              first_seen_at, last_seen_at
            ) VALUES (?, ?, ?, ?, ?, ?)
          `).run(
            licenseId,
            deviceId,
            cleanText(deviceName || 'Unknown device', 1, 100),
            cleanText(platform || 'unknown', 1, 40),
            now,
            now,
          );
        }
      }
      return {
        license: this.getLicense(licenseId),
        device: this.database.prepare(`
          SELECT * FROM license_devices
          WHERE license_id = ? AND device_id = ?
        `).get(licenseId, deviceId),
      };
    });
  }

  assertDeviceBound(licenseId, deviceId) {
    validateDeviceId(deviceId);
    const row = this.database.prepare(`
      SELECT 1 FROM license_devices
      WHERE license_id = ? AND device_id = ? AND revoked_at IS NULL
    `).get(licenseId, deviceId);
    if (!row) {
      throw new CommerceError(
        'DEVICE_NOT_REGISTERED',
        'Register this device with the license before connecting',
        403,
      );
    }
    this.database.prepare(`
      UPDATE license_devices SET last_seen_at = ?
      WHERE license_id = ? AND device_id = ?
    `).run(this.now(), licenseId, deviceId);
  }

  deviceCount(licenseId) {
    return this.database.prepare(`
      SELECT COUNT(*) AS count FROM license_devices
      WHERE license_id = ? AND revoked_at IS NULL
    `).get(licenseId).count;
  }

  listDevices(licenseId) {
    return this.database.prepare(`
      SELECT device_id, device_name, platform, first_seen_at,
             last_seen_at, revoked_at
      FROM license_devices WHERE license_id = ?
      ORDER BY revoked_at IS NULL DESC, last_seen_at DESC
    `).all(licenseId).map(mapDevice);
  }

  revokeDevice(licenseId, deviceId) {
    const changed = this.database.prepare(`
      UPDATE license_devices SET revoked_at = ?
      WHERE license_id = ? AND device_id = ? AND revoked_at IS NULL
    `).run(this.now(), licenseId, deviceId).changes;
    return changed === 1;
  }

  getLicense(id) {
    const row = this.database.prepare('SELECT * FROM licenses WHERE id = ?').get(id);
    return row ? mapLicense(row, this.deviceCount(id)) : null;
  }

  revealLicenseKey(id) {
    const row = this.database.prepare(`
      SELECT encrypted_key FROM licenses WHERE id = ?
    `).get(id);
    if (!row) throw new CommerceError('LICENSE_NOT_FOUND', 'License not found', 404);
    return this.#openLicenseKey(id, row.encrypted_key);
  }

  listLicenses() {
    return this.database.prepare(`
      SELECT l.*, COUNT(CASE WHEN d.revoked_at IS NULL THEN 1 END) AS device_count
      FROM licenses l
      LEFT JOIN license_devices d ON d.license_id = l.id
      GROUP BY l.id
      ORDER BY l.issued_at DESC
    `).all().map((row) => mapLicense(row, row.device_count));
  }

  revokeLicense(id) {
    return this.#transaction(() => {
      const row = this.database.prepare('SELECT user_id FROM licenses WHERE id = ?').get(id);
      if (!row) return false;
      this.database.prepare(`
        UPDATE licenses SET status = 'revoked' WHERE id = ?
      `).run(id);
      this.database.prepare(`
        UPDATE leases SET ended_at = ?, end_reason = 'license_revoked'
        WHERE user_id = ? AND ended_at IS NULL
      `).run(this.now(), row.user_id);
      return true;
    });
  }

  createPayment({
    provider,
    planId,
    ipMode,
    deviceLimit,
    durationDays,
    customerRef = null,
    idempotencyKey,
  }) {
    if (!paymentProviderOptions.includes(provider)) {
      throw new CommerceError('INVALID_PAYMENT_PROVIDER', 'Unsupported payment provider');
    }
    if (typeof idempotencyKey !== 'string' || idempotencyKey.length < 8 ||
        idempotencyKey.length > 128) {
      throw new CommerceError('INVALID_IDEMPOTENCY_KEY', 'Invalid idempotency key');
    }
    const existing = this.database.prepare(
      'SELECT * FROM payments WHERE idempotency_key = ?',
    ).get(idempotencyKey);
    if (existing) return mapPayment(existing);
    const setting = this.getPaymentSetting(provider);
    if (!setting?.enabled) {
      throw new CommerceError('PAYMENT_METHOD_UNAVAILABLE', 'Payment method is disabled', 409);
    }
    const quote = this.quote({ planId, ipMode, deviceLimit, durationDays });
    const id = randomUUID();
    const claimToken = randomBytes(32).toString('base64url');
    const claimSalt = randomBytes(16);
    const now = this.now();
    this.database.prepare(`
      INSERT INTO payments (
        id, provider, status, amount_minor, currency, plan_id, ip_mode,
        device_limit, duration_days, customer_ref, idempotency_key,
        claim_salt, claim_hash, created_at, updated_at
      ) VALUES (?, ?, 'pending', ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run(
      id,
      provider,
      quote.amountMinor,
      quote.currency,
      planId,
      ipMode,
      deviceLimit,
      durationDays,
      customerRef,
      idempotencyKey,
      claimSalt,
      hashSecret(claimToken, claimSalt),
      now,
      now,
    );
    return { ...this.getPayment(id), claimToken };
  }

  verifyPaymentClaim(id, claimToken) {
    const row = this.database.prepare(`
      SELECT claim_salt, claim_hash FROM payments WHERE id = ?
    `).get(id);
    return Boolean(row && typeof claimToken === 'string' &&
      verifySecret(claimToken, row.claim_salt, row.claim_hash));
  }

  attachProviderPayment(id, { externalId, checkoutUrl, providerData = {} }) {
    const result = this.database.prepare(`
      UPDATE payments
      SET external_id = ?, checkout_url = ?, provider_json = ?, updated_at = ?
      WHERE id = ? AND status = 'pending'
    `).run(
      externalId,
      checkoutUrl,
      JSON.stringify(plainObject(providerData, 'providerData')),
      this.now(),
      id,
    );
    if (result.changes !== 1) {
      throw new CommerceError('PAYMENT_NOT_PENDING', 'Payment is not pending', 409);
    }
    return this.getPayment(id);
  }

  getPayment(id) {
    const row = this.database.prepare('SELECT * FROM payments WHERE id = ?').get(id);
    return row ? mapPayment(row) : null;
  }

  getPaymentByExternal(provider, externalId) {
    const row = this.database.prepare(`
      SELECT * FROM payments WHERE provider = ? AND external_id = ?
    `).get(provider, externalId);
    return row ? mapPayment(row) : null;
  }

  listPayments() {
    return this.database.prepare(`
      SELECT * FROM payments ORDER BY created_at DESC
    `).all().map(mapPayment);
  }

  fulfillPayment(id, providerData = {}) {
    return this.#transaction(() => {
      const payment = this.getPayment(id);
      if (!payment) throw new CommerceError('PAYMENT_NOT_FOUND', 'Payment not found', 404);
      if (payment.status === 'paid' && payment.licenseId) {
        return { payment, license: this.getLicense(payment.licenseId), key: null };
      }
      if (payment.status !== 'pending') {
        throw new CommerceError('PAYMENT_NOT_PENDING', 'Payment is not pending', 409);
      }
      const issued = this.#createLicenseRecord({
        planId: payment.planId,
        ipMode: payment.ipMode,
        deviceLimit: payment.deviceLimit,
        durationDays: payment.durationDays,
        source: 'payment',
        paymentId: payment.id,
        note: '',
      });
      this.database.prepare(`
        UPDATE payments
        SET status = 'paid', license_id = ?, provider_json = ?, updated_at = ?
        WHERE id = ?
      `).run(
        issued.license.id,
        JSON.stringify(plainObject(providerData, 'providerData')),
        this.now(),
        id,
      );
      return { payment: this.getPayment(id), ...issued };
    });
  }

  updatePaymentStatus(id, status, providerData = {}) {
    if (!['canceled', 'expired', 'failed'].includes(status)) {
      throw new CommerceError('INVALID_PAYMENT_STATUS', 'Invalid terminal payment status');
    }
    const result = this.database.prepare(`
      UPDATE payments
      SET status = ?, provider_json = ?, updated_at = ?
      WHERE id = ? AND status = 'pending'
    `).run(
      status,
      JSON.stringify(plainObject(providerData, 'providerData')),
      this.now(),
      id,
    );
    if (result.changes !== 1) {
      throw new CommerceError('PAYMENT_NOT_PENDING', 'Payment is not pending', 409);
    }
    return this.getPayment(id);
  }

  consumeWebhook(provider, eventId) {
    if (typeof eventId !== 'string' || eventId.length < 3 || eventId.length > 200) {
      throw new CommerceError('INVALID_WEBHOOK_EVENT', 'Invalid webhook event id');
    }
    try {
      this.database.prepare(`
        INSERT INTO processed_webhooks (provider, event_id, received_at)
        VALUES (?, ?, ?)
      `).run(provider, eventId, this.now());
      return true;
    } catch (error) {
      if (String(error.message).includes('UNIQUE constraint failed')) return false;
      throw error;
    }
  }

  setPaymentSetting({ provider, enabled, testMode, publicConfig = {} }) {
    if (!paymentProviderOptions.includes(provider)) {
      throw new CommerceError('INVALID_PAYMENT_PROVIDER', 'Unsupported payment provider');
    }
    this.database.prepare(`
      INSERT INTO payment_settings (
        provider, enabled, test_mode, public_json, updated_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(provider) DO UPDATE SET
        enabled = excluded.enabled,
        test_mode = excluded.test_mode,
        public_json = excluded.public_json,
        updated_at = excluded.updated_at
    `).run(
      provider,
      enabled === true ? 1 : 0,
      testMode !== false ? 1 : 0,
      JSON.stringify(plainObject(publicConfig, 'publicConfig')),
      this.now(),
    );
    this.bumpRevision();
    return this.getPaymentSetting(provider);
  }

  getPaymentSetting(provider) {
    const row = this.database.prepare(`
      SELECT * FROM payment_settings WHERE provider = ?
    `).get(provider);
    return row ? mapPaymentSetting(row) : null;
  }

  listPaymentSettings({ onlyEnabled = false } = {}) {
    const where = onlyEnabled ? 'WHERE enabled = 1' : '';
    return this.database.prepare(`
      SELECT * FROM payment_settings ${where}
      ORDER BY provider ASC
    `).all().map(mapPaymentSetting);
  }

  adminSnapshot() {
    const now = this.now();
    const counts = this.database.prepare(`
      SELECT
        (SELECT COUNT(*) FROM nodes) AS servers,
        (SELECT COUNT(*) FROM nodes WHERE online = 1) AS servers_online,
        (SELECT COUNT(*) FROM licenses) AS licenses,
        (SELECT COUNT(*) FROM licenses WHERE status = 'active' AND expires_at > ?) AS licenses_active,
        (SELECT COUNT(*) FROM license_devices WHERE revoked_at IS NULL) AS devices,
        (SELECT COUNT(*) FROM payments) AS payments,
        (SELECT COUNT(*) FROM payments WHERE status = 'paid') AS payments_paid,
        (SELECT COALESCE(SUM(amount_minor), 0) FROM payments WHERE status = 'paid') AS revenue_minor
    `).get(now);
    return {
      revision: this.revision,
      generatedAt: new Date(now).toISOString(),
      counts: {
        servers: counts.servers,
        serversOnline: counts.servers_online,
        licenses: counts.licenses,
        licensesActive: counts.licenses_active,
        devices: counts.devices,
        payments: counts.payments,
        paymentsPaid: counts.payments_paid,
        revenueMinor: counts.revenue_minor,
        currency: 'RUB',
      },
      servers: this.listServers(),
      plans: this.listPlans(),
      licenses: this.listLicenses(),
      payments: this.listPayments(),
      paymentSettings: this.listPaymentSettings(),
    };
  }

  #sealLicenseKey(id, key) {
    if (!this.secretVault) {
      throw new CommerceError('SECRET_VAULT_UNAVAILABLE', 'Secret vault is unavailable', 503);
    }
    return this.secretVault.seal(key, `license:${id}`);
  }

  #openLicenseKey(id, envelope) {
    if (!this.secretVault) {
      throw new CommerceError('SECRET_VAULT_UNAVAILABLE', 'Secret vault is unavailable', 503);
    }
    return this.secretVault.open(envelope, `license:${id}`);
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

function mapServer(row) {
  return {
    id: row.id,
    displayName: row.display_name ?? `${row.city} · ${row.country}`,
    city: row.city,
    country: row.country,
    countryCode: row.country_code,
    endpoint: row.endpoint,
    protocols: JSON.parse(row.protocols_json),
    load: row.load,
    online: row.online === 1,
    recommended: row.recommended === 1,
    capacity: row.capacity ?? 0,
    tags: row.tags_json ? JSON.parse(row.tags_json) : [],
    notes: row.notes ?? '',
    transportConfig: row.transport_json ? JSON.parse(row.transport_json) : {},
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

function publicServer(server) {
  const { notes, transportConfig, ...safe } = server;
  return safe;
}

function mapPlan(row) {
  return {
    id: row.id,
    name: row.name,
    description: row.description,
    currency: row.currency,
    enabled: row.enabled === 1,
    pricing: JSON.parse(row.pricing_json),
    sortOrder: row.sort_order,
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

function mapLicense(row, deviceCount) {
  return {
    id: row.id,
    maskedKey: `${row.key_prefix}-••••••••`,
    planId: row.plan_id,
    source: row.source,
    ipMode: row.ip_mode,
    deviceLimit: row.device_limit,
    deviceCount,
    durationDays: row.duration_days,
    status: row.status,
    issuedAt: new Date(row.issued_at).toISOString(),
    expiresAt: new Date(row.expires_at).toISOString(),
    paymentId: row.payment_id,
    dedicatedIp: row.dedicated_ip,
    note: row.note,
  };
}

function mapDevice(row) {
  return {
    deviceId: row.device_id,
    deviceName: row.device_name,
    platform: row.platform,
    firstSeenAt: new Date(row.first_seen_at).toISOString(),
    lastSeenAt: new Date(row.last_seen_at).toISOString(),
    revokedAt: row.revoked_at === null ? null : new Date(row.revoked_at).toISOString(),
  };
}

function mapPayment(row) {
  return {
    id: row.id,
    provider: row.provider,
    status: row.status,
    amountMinor: row.amount_minor,
    currency: row.currency,
    planId: row.plan_id,
    ipMode: row.ip_mode,
    deviceLimit: row.device_limit,
    durationDays: row.duration_days,
    checkoutUrl: row.checkout_url,
    externalId: row.external_id,
    licenseId: row.license_id,
    customerRef: row.customer_ref,
    createdAt: new Date(row.created_at).toISOString(),
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

function mapPaymentSetting(row) {
  return {
    provider: row.provider,
    enabled: row.enabled === 1,
    testMode: row.test_mode === 1,
    publicConfig: JSON.parse(row.public_json),
    updatedAt: new Date(row.updated_at).toISOString(),
  };
}

function validateSelection({ ipMode, deviceLimit, durationDays }) {
  if (!ipModeOptions.includes(ipMode)) {
    throw new CommerceError('INVALID_IP_MODE', 'ipMode must be shared or dedicated');
  }
  integerInRange(deviceLimit, 1, 5, 'deviceLimit');
  if (!durationOptions.includes(durationDays)) {
    throw new CommerceError('INVALID_DURATION', 'Unsupported subscription duration');
  }
}

function validatePricing(value) {
  const pricing = plainObject(value, 'pricing');
  const result = {};
  for (const mode of ipModeOptions) {
    const modeValue = plainObject(pricing[mode], `pricing.${mode}`);
    result[mode] = {};
    for (const duration of durationOptions) {
      const rate = plainObject(modeValue[String(duration)], `pricing.${mode}.${duration}`);
      result[mode][duration] = {
        base: integerInRange(rate.base, 0, 100_000_000, 'base price'),
        extraDevice: integerInRange(
          rate.extraDevice,
          0,
          100_000_000,
          'extra device price',
        ),
      };
    }
  }
  return result;
}

function plainObject(value, field) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) {
    throw new CommerceError('INVALID_INPUT', `${field} must be an object`);
  }
  return value;
}

function cleanIdentifier(value, field) {
  if (typeof value !== 'string' || !/^[a-z0-9][a-z0-9-]{1,63}$/i.test(value)) {
    throw new CommerceError('INVALID_INPUT', `Invalid ${field}`);
  }
  return value.toLowerCase();
}

function cleanText(value, min, max) {
  if (typeof value !== 'string') {
    throw new CommerceError('INVALID_INPUT', 'Expected text value');
  }
  const text = value.trim();
  if (text.length < min || text.length > max) {
    throw new CommerceError('INVALID_INPUT', `Text length must be ${min}..${max}`);
  }
  return text;
}

function optionalText(value, max) {
  if (value === undefined || value === null) return '';
  if (typeof value !== 'string' || value.length > max) {
    throw new CommerceError('INVALID_INPUT', `Text length must not exceed ${max}`);
  }
  return value.trim();
}

function integerInRange(value, min, max, field) {
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new CommerceError('INVALID_INPUT', `${field} must be ${min}..${max}`);
  }
  return value;
}

function cleanCurrency(value) {
  if (typeof value !== 'string' || !/^[A-Z]{3}$/.test(value)) {
    throw new CommerceError('INVALID_CURRENCY', 'Currency must be ISO 4217 code');
  }
  return value;
}

function validateDeviceId(deviceId) {
  if (typeof deviceId !== 'string' || !/^[a-zA-Z0-9._:-]{8,128}$/.test(deviceId)) {
    throw new CommerceError('INVALID_DEVICE_ID', 'Invalid deviceId');
  }
}

function formatMoney(amountMinor, currency) {
  return `${(amountMinor / 100).toFixed(2)} ${currency}`;
}

function providerLabel(provider) {
  if (provider === 'yookassa') return 'СБП';
  if (provider === 'crypto_pay') return 'Криптовалюта';
  return 'Тестовая оплата';
}

export function toRepositoryError(error) {
  if (error instanceof CommerceError) {
    return new RepositoryError(error.code, error.message, error.statusCode);
  }
  return error;
}
