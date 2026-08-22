export class RouteServerError extends Error {
  constructor(code, message, statusCode = 503) {
    super(message);
    this.name = 'RouteServerError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class RouteServerClient {
  constructor({ baseUrl = null, token = null, timeoutMs = 2500 } = {}) {
    this.baseUrl = baseUrl ? String(baseUrl).replace(/\/$/, '') : null;
    this.token = token || null;
    this.timeoutMs = timeoutMs;
  }

  get enabled() {
    return Boolean(this.baseUrl);
  }

  async select({ clientId, poolId, protocol }) {
    if (!this.enabled) {
      throw new RouteServerError('ROUTE_SERVER_DISABLED', 'Route Server is not configured');
    }
    return this.#request('/v1/select', {
      clientId,
      poolId,
      protocol,
    });
  }

  async release({ clientId, poolId, protocol }) {
    if (!this.enabled) return { released: false };
    return this.#request('/v1/release', {
      clientId,
      poolId,
      protocol,
    });
  }

  async reportClientHealth({ clientId, poolId, nodeId, protocol, result }) {
    if (!this.enabled) return { accepted: false };
    return this.#request('/v1/client-health', {
      clientId,
      poolId,
      nodeId,
      protocol,
      result,
    });
  }

  async #request(path, payload) {
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), this.timeoutMs);
    try {
      const response = await fetch(`${this.baseUrl}${path}`, {
        method: 'POST',
        signal: controller.signal,
        headers: {
          'content-type': 'application/json',
          ...(this.token ? { authorization: `Bearer ${this.token}` } : {}),
        },
        body: JSON.stringify(payload),
      });
      let body = null;
      try { body = await response.json(); } catch { body = null; }
      if (!response.ok) {
        throw new RouteServerError(
          body?.error || 'ROUTE_SERVER_ERROR',
          body?.message || `Route Server returned HTTP ${response.status}`,
          response.status >= 400 && response.status < 600 ? response.status : 503,
        );
      }
      return body ?? {};
    } catch (error) {
      if (error instanceof RouteServerError) throw error;
      const code = error?.name === 'AbortError' ? 'ROUTE_SERVER_TIMEOUT' : 'ROUTE_SERVER_UNAVAILABLE';
      throw new RouteServerError(code, 'Route Server is temporarily unavailable');
    } finally {
      clearTimeout(timeout);
    }
  }
}
