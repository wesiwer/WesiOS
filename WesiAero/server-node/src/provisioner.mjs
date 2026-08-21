import fs from 'node:fs';
import path from 'node:path';

export class ProvisioningError extends Error {
  constructor(code, message, statusCode = 503) {
    super(message);
    this.name = 'ProvisioningError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class StaticProfileProvisioner {
  constructor(profileDirectory) {
    this.profileDirectory = profileDirectory;
  }

  async profileFor({ user, lease }) {
    const protocolNames = profileProtocolCandidates(lease.protocol);
    const candidates = [];
    for (const protocol of protocolNames) {
      candidates.push(
        `${user.id}.${lease.node.id}.${protocol}.json`,
        `_default.${lease.node.id}.${protocol}.json`,
      );
    }

    let profilePath = null;
    for (const filename of candidates) {
      const candidate = path.join(this.profileDirectory, filename);
      try {
        const stat = fs.statSync(candidate);
        if (!stat.isFile() || stat.size > 262_144) {
          throw new ProvisioningError('INVALID_PROFILE_FILE', 'Profile file is invalid');
        }
        profilePath = candidate;
        break;
      } catch (error) {
        if (error.code === 'ENOENT') continue;
        throw error;
      }
    }

    if (!profilePath) {
      throw new ProvisioningError(
        'PROFILE_NOT_PROVISIONED',
        'Tunnel profile is not provisioned for this user and node',
      );
    }

    let profile;
    try {
      profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
    } catch {
      throw new ProvisioningError('INVALID_PROFILE_JSON', 'Profile JSON is invalid');
    }
    validateProfile(profile, lease.protocol);

    const result = {
      ...profile,
      protocol: lease.protocol,
      profileFormat: lease.protocol === 'wireguard' || lease.protocol === 'amneziawg'
        ? 'wireguard-ini'
        : 'uri',
    };

    // One lease carries both engine representations. The app can switch
    // Xray <-> sing-box without requesting another credential or session.
    const explicit = profile.singBoxConfig;
    if (typeof explicit === 'string' && explicit.trim().startsWith('{')) {
      result.singBoxConfig = explicit;
    } else if (['vless-reality', 'vmess', 'trojan', 'shadowsocks', 'hysteria2', 'tuic'].includes(lease.protocol)) {
      result.singBoxConfig = buildSingBoxConfig(lease.protocol, profile.clientConfig);
    }
    return result;
  }
}

function profileProtocolCandidates(protocol) {
  if (protocol === 'vmess') return ['vmess', 'vmess-xray'];
  if (protocol === 'wireguard') return ['wireguard', 'amneziawg'];
  return [protocol];
}

function canonicalProfileProtocol(protocol) {
  if (protocol === 'vmess-xray') return 'vmess';
  return protocol;
}

function validateProfile(profile, protocol) {
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
    throw new ProvisioningError('INVALID_PROFILE', 'Profile must be an object');
  }
  const profileProtocol = canonicalProfileProtocol(profile.protocol);
  const migrationCompatible = protocol === 'wireguard' && profile.protocol === 'amneziawg';
  if (profileProtocol !== protocol && !migrationCompatible) {
    throw new ProvisioningError('INVALID_PROFILE', 'Profile protocol mismatch');
  }
  if (typeof profile.clientConfig !== 'string' || profile.clientConfig.length < 16) {
    throw new ProvisioningError('INVALID_PROFILE', 'clientConfig is required');
  }
}

function buildSingBoxConfig(protocol, raw) {
  const proxy = parseSingBoxOutbound(protocol, raw);
  return JSON.stringify({
    log: { level: 'warn', timestamp: true },
    dns: {
      servers: [
        { type: 'tls', tag: 'remote-dns', server: '1.1.1.1', detour: 'proxy' },
      ],
      strategy: 'ipv4_only',
      final: 'remote-dns',
    },
    inbounds: [
      {
        type: 'tun',
        tag: 'tun-in',
        address: ['172.19.0.1/30'],
        mtu: 1420,
        auto_route: true,
        strict_route: true,
        stack: 'mixed',
      },
    ],
    outbounds: [
      { ...proxy, tag: 'proxy' },
      { type: 'direct', tag: 'direct' },
    ],
    route: {
      rules: [
        { action: 'sniff' },
        { protocol: 'dns', action: 'hijack-dns' },
      ],
      default_domain_resolver: 'remote-dns',
      auto_detect_interface: true,
      final: 'proxy',
    },
  });
}

function parseSingBoxOutbound(protocol, raw) {
  switch (protocol) {
    case 'vless-reality': return parseVless(raw);
    case 'vmess': return parseVmess(raw);
    case 'trojan': return parseTrojan(raw);
    case 'shadowsocks': return parseShadowsocks(raw);
    case 'hysteria2': return parseHysteria2(raw);
    case 'tuic': return parseTuic(raw);
    default:
      throw new ProvisioningError(
        'ENGINE_PROFILE_UNAVAILABLE',
        `sing-box profile conversion is not implemented for ${protocol}`,
      );
  }
}

function parseVless(raw) {
  let uri;
  try { uri = new URL(raw); } catch { throw invalidUri('VLESS'); }
  if (uri.protocol !== 'vless:' || !uri.hostname || !uri.port || !uri.username) throw invalidUri('VLESS');
  if (uri.searchParams.get('security') !== 'reality') {
    throw new ProvisioningError('INVALID_PROFILE', 'VLESS profile must use REALITY');
  }
  const serverName = uri.searchParams.get('sni');
  const publicKey = uri.searchParams.get('pbk');
  if (!serverName || !publicKey) {
    throw new ProvisioningError('INVALID_PROFILE', 'VLESS REALITY SNI/public key is missing');
  }
  const outbound = {
    type: 'vless',
    server: uri.hostname,
    server_port: Number(uri.port),
    uuid: decodeURIComponent(uri.username),
    flow: uri.searchParams.get('flow') || 'xtls-rprx-vision',
    tls: {
      enabled: true,
      server_name: serverName,
      utls: { enabled: true, fingerprint: uri.searchParams.get('fp') || 'chrome' },
      reality: {
        enabled: true,
        public_key: publicKey,
        short_id: uri.searchParams.get('sid') || '',
      },
    },
  };
  applyTransport(outbound, uri.searchParams);
  return outbound;
}

function parseVmess(raw) {
  if (!raw.startsWith('vmess://')) throw invalidUri('VMess');
  let decoded;
  try {
    decoded = JSON.parse(Buffer.from(normalizeBase64(raw.slice(8)), 'base64').toString('utf8'));
  } catch { throw invalidUri('VMess'); }
  const port = Number(decoded.port);
  if (!decoded.add || !decoded.id || !Number.isInteger(port) || port < 1 || port > 65535) throw invalidUri('VMess');
  const outbound = {
    type: 'vmess',
    server: decoded.add,
    server_port: port,
    uuid: decoded.id,
    security: decoded.scy || decoded.security || 'auto',
    alter_id: 0,
  };
  const net = String(decoded.net || 'tcp').toLowerCase();
  if (net === 'ws') {
    outbound.transport = {
      type: 'ws',
      path: decoded.path || '/',
      headers: decoded.host ? { Host: decoded.host } : undefined,
    };
  } else if (net === 'grpc') {
    outbound.transport = { type: 'grpc', service_name: decoded.path || decoded.host || '' };
  }
  if (String(decoded.tls || '').toLowerCase() === 'tls') {
    outbound.tls = {
      enabled: true,
      server_name: decoded.sni || decoded.host || decoded.add,
      insecure: String(decoded.allowInsecure || '') === '1',
      utls: { enabled: true, fingerprint: decoded.fp || 'chrome' },
    };
  }
  return outbound;
}

function parseTrojan(raw) {
  let uri;
  try { uri = new URL(raw); } catch { throw invalidUri('Trojan'); }
  if (uri.protocol !== 'trojan:' || !uri.hostname || !uri.port || !uri.username) throw invalidUri('Trojan');
  const outbound = {
    type: 'trojan',
    server: uri.hostname,
    server_port: Number(uri.port),
    password: decodeURIComponent(uri.username),
    tls: {
      enabled: true,
      server_name: uri.searchParams.get('sni') || uri.hostname,
      insecure: uri.searchParams.get('allowInsecure') === '1',
      utls: { enabled: true, fingerprint: uri.searchParams.get('fp') || 'chrome' },
    },
  };
  applyTransport(outbound, uri.searchParams);
  return outbound;
}

function parseShadowsocks(raw) {
  if (!raw.startsWith('ss://')) throw invalidUri('Shadowsocks');
  const body = raw.slice(5).split('#')[0];
  let method;
  let password;
  let host;
  let port;
  if (body.includes('@')) {
    const split = body.split('@');
    const auth = split.shift();
    const endpoint = split.join('@');
    let plainAuth = decodeURIComponent(auth);
    if (!plainAuth.includes(':')) {
      plainAuth = Buffer.from(normalizeBase64(plainAuth), 'base64').toString('utf8');
    }
    const parts = plainAuth.split(':');
    method = parts.shift();
    password = parts.join(':');
    const endpointUrl = new URL(`ss://${endpoint}`);
    host = endpointUrl.hostname;
    port = Number(endpointUrl.port);
  } else {
    const decoded = Buffer.from(normalizeBase64(body.split('?')[0]), 'base64').toString('utf8');
    const match = decoded.match(/^([^:]+):(.+)@([^:]+):(\d+)$/);
    if (!match) throw invalidUri('Shadowsocks');
    [, method, password, host] = match;
    port = Number(match[4]);
  }
  if (!method || !password || !host || !Number.isInteger(port)) throw invalidUri('Shadowsocks');
  return { type: 'shadowsocks', server: host, server_port: port, method, password };
}

function parseHysteria2(raw) {
  let uri;
  try { uri = new URL(raw.replace(/^hy2:/, 'hysteria2:')); } catch { throw invalidUri('Hysteria2'); }
  if (uri.protocol !== 'hysteria2:' || !uri.hostname || !uri.port || !uri.username) throw invalidUri('Hysteria2');
  return {
    type: 'hysteria2',
    server: uri.hostname,
    server_port: Number(uri.port),
    password: decodeURIComponent(uri.username),
    tls: {
      enabled: true,
      server_name: uri.searchParams.get('sni') || uri.hostname,
      insecure: uri.searchParams.get('insecure') === '1',
    },
  };
}

function parseTuic(raw) {
  let uri;
  try { uri = new URL(raw); } catch { throw invalidUri('TUIC'); }
  if (uri.protocol !== 'tuic:' || !uri.hostname || !uri.port || !uri.username) throw invalidUri('TUIC');
  return {
    type: 'tuic',
    server: uri.hostname,
    server_port: Number(uri.port),
    uuid: decodeURIComponent(uri.username),
    password: decodeURIComponent(uri.password || ''),
    congestion_control: uri.searchParams.get('congestion_control') || 'bbr',
    tls: {
      enabled: true,
      server_name: uri.searchParams.get('sni') || uri.hostname,
      insecure: uri.searchParams.get('insecure') === '1',
      alpn: (uri.searchParams.get('alpn') || '').split(',').filter(Boolean),
    },
  };
}

function applyTransport(outbound, params) {
  const type = String(params.get('type') || 'tcp').toLowerCase();
  if (type === 'ws') {
    outbound.transport = {
      type: 'ws',
      path: params.get('path') || '/',
      headers: params.get('host') ? { Host: params.get('host') } : undefined,
    };
  } else if (type === 'grpc') {
    outbound.transport = { type: 'grpc', service_name: params.get('serviceName') || params.get('path') || '' };
  }
}

function normalizeBase64(value) {
  const clean = value.replace(/-/g, '+').replace(/_/g, '/');
  return clean + '='.repeat((4 - clean.length % 4) % 4);
}

function invalidUri(name) {
  return new ProvisioningError('INVALID_PROFILE', `${name} profile is invalid`);
}
