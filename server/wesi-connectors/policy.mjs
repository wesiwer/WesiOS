export const Permission = Object.freeze({
  READ: 'read',
  WRITE: 'write',
  DESTRUCTIVE: 'destructive',
});

const DEFAULT_POLICY = Object.freeze({
  github: {
    read: true,
    write: true,
    destructive: false,
    directProtectedBranchPush: false,
  },
});

export function policyFor(connector, overrides = {}) {
  const base = DEFAULT_POLICY[connector] || {read: false, write: false, destructive: false};
  const source = overrides && typeof overrides === 'object' ? overrides : {};
  return {...base, ...source};
}

export function requirePermission(connector, permission, policy = {}) {
  const current = policyFor(connector, policy);
  if (!Object.values(Permission).includes(permission)) {
    const error = new Error('UNKNOWN_PERMISSION');
    error.code = 'UNKNOWN_PERMISSION';
    throw error;
  }
  if (current[permission] !== true) {
    const error = new Error('CONNECTOR_FORBIDDEN');
    error.code = 'CONNECTOR_FORBIDDEN';
    throw error;
  }
  return current;
}

export function assertSafeGitHubWrite({method, path, policy = {}}) {
  const normalizedMethod = String(method || 'GET').toUpperCase();
  const normalizedPath = String(path || '');
  const destructive = normalizedMethod === 'DELETE';
  requirePermission('github', destructive ? Permission.DESTRUCTIVE : Permission.WRITE, policy);

  if (normalizedPath.includes('/git/refs/heads/main') || normalizedPath.includes('/git/refs/heads/master')) {
    if (policyFor('github', policy).directProtectedBranchPush !== true) {
      const error = new Error('PROTECTED_BRANCH_WRITE_REQUIRES_APPROVAL');
      error.code = 'PROTECTED_BRANCH_WRITE_REQUIRES_APPROVAL';
      throw error;
    }
  }
}
