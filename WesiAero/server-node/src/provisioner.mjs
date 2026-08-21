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
        if (!stat.isFile() || stat.size > 131_072) {
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
    return {
      ...profile,
      // Always expose the canonical protocol to new clients, even when the
      // actual static file came from a pre-migration prototype name.
      protocol: lease.protocol,
    };
  }
}

function profileProtocolCandidates(protocol) {
  if (protocol === 'vmess') return ['vmess', 'vmess-xray'];
  // The prototype previously mislabeled its standard WireGuard profile as
  // amneziawg. Keep it readable only as a migration fallback. Real AmneziaWG
  // never falls back to a standard WireGuard profile.
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
  const migrationCompatible =
    protocol === 'wireguard' && profile.protocol === 'amneziawg';
  if (profileProtocol !== protocol && !migrationCompatible) {
    throw new ProvisioningError('INVALID_PROFILE', 'Profile protocol mismatch');
  }
  if (typeof profile.clientConfig !== 'string' || profile.clientConfig.length < 16) {
    throw new ProvisioningError('INVALID_PROFILE', 'clientConfig is required');
  }
}
