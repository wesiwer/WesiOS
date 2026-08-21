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
    const filename = `${user.id}.${lease.node.id}.${lease.protocol}.json`;
    const profilePath = path.join(this.profileDirectory, filename);
    let stat;
    try {
      stat = fs.statSync(profilePath);
    } catch (error) {
      if (error.code === 'ENOENT') {
        throw new ProvisioningError(
          'PROFILE_NOT_PROVISIONED',
          'Tunnel profile is not provisioned for this user and node',
        );
      }
      throw error;
    }
    if (!stat.isFile() || stat.size > 131_072) {
      throw new ProvisioningError('INVALID_PROFILE_FILE', 'Profile file is invalid');
    }

    let profile;
    try {
      profile = JSON.parse(fs.readFileSync(profilePath, 'utf8'));
    } catch {
      throw new ProvisioningError('INVALID_PROFILE_JSON', 'Profile JSON is invalid');
    }
    validateProfile(profile, lease.protocol);
    return profile;
  }
}

function validateProfile(profile, protocol) {
  if (!profile || typeof profile !== 'object' || Array.isArray(profile)) {
    throw new ProvisioningError('INVALID_PROFILE', 'Profile must be an object');
  }
  if (profile.protocol !== protocol) {
    throw new ProvisioningError('INVALID_PROFILE', 'Profile protocol mismatch');
  }
  if (typeof profile.clientConfig !== 'string' || profile.clientConfig.length < 16) {
    throw new ProvisioningError('INVALID_PROFILE', 'clientConfig is required');
  }
}

