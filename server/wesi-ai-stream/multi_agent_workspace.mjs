export const MULTI_AGENT_WORKSPACE_PROTOCOL = 'wesi.multi-agent-workspace.v1';
export const MAX_WORKSPACE_FILES = 64;
export const MAX_WORKSPACE_FILE_CHARS = 120000;
export const MAX_WORKSPACE_TOTAL_CHARS = 400000;

function cleanText(value, maxChars) {
  const text = String(value || '').replace(/\u0000/g, '');
  return text.length <= maxChars ? text : text.slice(0, maxChars);
}

function cleanId(value) {
  return String(value || '').trim().slice(0, 180).replace(/[^a-zA-Z0-9_.:-]/g, '_');
}

function cleanPath(value) {
  const path = String(value || '').replace(/\\/g, '/').replace(/^\/+/, '').trim();
  if (!path || path.includes('\u0000') || path.split('/').some((part) => part === '..')) return '';
  return path.slice(0, 500);
}

function cloneFile(file) {
  return {path: file.path, content: file.content, revision: file.revision, lastAgentId: file.lastAgentId || ''};
}

function totalChars(files) {
  let total = 0;
  for (const file of files.values()) total += String(file.content || '').length;
  return total;
}

export function createConflictSafeWorkspace(input = {}) {
  const workspaceId = cleanId(input.workspaceId) || `workspace_${Date.now()}`;
  const files = new Map();
  let revision = Math.max(0, Number(input.revision || 0) || 0);
  for (const raw of Array.isArray(input.files) ? input.files : []) {
    if (!raw || typeof raw !== 'object' || files.size >= MAX_WORKSPACE_FILES) continue;
    const path = cleanPath(raw.path);
    if (!path || files.has(path)) continue;
    const content = cleanText(raw.content, MAX_WORKSPACE_FILE_CHARS);
    files.set(path, {path, content, revision: Math.max(0, Number(raw.revision ?? revision) || 0), lastAgentId: cleanId(raw.lastAgentId)});
  }
  if (totalChars(files) > MAX_WORKSPACE_TOTAL_CHARS) throw new Error('WAI_WORKSPACE_TOO_LARGE');
  return {
    protocol: MULTI_AGENT_WORKSPACE_PROTOCOL,
    workspaceId,
    revision,
    files,
    journal: [],
  };
}

export function workspaceSnapshot(workspace, paths = []) {
  validateWorkspace(workspace);
  const filter = new Set((Array.isArray(paths) ? paths : []).map(cleanPath).filter(Boolean));
  const files = [];
  for (const file of workspace.files.values()) {
    if (filter.size && !filter.has(file.path)) continue;
    files.push(cloneFile(file));
  }
  return {
    protocol: MULTI_AGENT_WORKSPACE_PROTOCOL,
    workspaceId: workspace.workspaceId,
    revision: workspace.revision,
    files: files.slice(0, MAX_WORKSPACE_FILES),
  };
}

export function validateWorkspace(workspace) {
  if (!workspace || workspace.protocol !== MULTI_AGENT_WORKSPACE_PROTOCOL || !(workspace.files instanceof Map) || !cleanId(workspace.workspaceId)) {
    throw new Error('WAI_WORKSPACE_INVALID');
  }
  return true;
}

export function applySubagentWorkspaceEdits(workspace, {agentId, allowedPaths = [], edits = []} = {}) {
  validateWorkspace(workspace);
  const actor = cleanId(agentId);
  if (!actor) throw new Error('WAI_WORKSPACE_AGENT_REQUIRED');
  const allowed = new Set((Array.isArray(allowedPaths) ? allowedPaths : []).map(cleanPath).filter(Boolean));
  const applied = [];
  const conflicts = [];
  const rejected = [];

  for (const raw of Array.isArray(edits) ? edits : []) {
    if (!raw || typeof raw !== 'object') continue;
    const path = cleanPath(raw.path);
    if (!path || !allowed.has(path)) {
      rejected.push({path: path || String(raw.path || '').slice(0, 500), code: 'PATH_NOT_ALLOWED'});
      continue;
    }
    const operation = String(raw.operation || 'replace').trim().toLowerCase();
    if (operation !== 'replace' && operation !== 'create') {
      rejected.push({path, code: 'OPERATION_NOT_ALLOWED'});
      continue;
    }
    const current = workspace.files.get(path) || null;
    const expectedRevision = Math.max(0, Number(raw.baseRevision || 0) || 0);
    const actualRevision = current ? current.revision : 0;
    if (expectedRevision !== actualRevision) {
      conflicts.push({
        path,
        code: 'REVISION_CONFLICT',
        expectedRevision,
        actualRevision,
        lastAgentId: current?.lastAgentId || '',
      });
      continue;
    }
    if (operation === 'create' && current) {
      conflicts.push({path, code: 'ALREADY_EXISTS', expectedRevision, actualRevision, lastAgentId: current.lastAgentId || ''});
      continue;
    }
    if (operation === 'replace' && !current) {
      conflicts.push({path, code: 'MISSING_FILE', expectedRevision, actualRevision: 0, lastAgentId: ''});
      continue;
    }
    const content = cleanText(raw.content, MAX_WORKSPACE_FILE_CHARS);
    const projected = totalChars(workspace.files) - String(current?.content || '').length + content.length;
    if (projected > MAX_WORKSPACE_TOTAL_CHARS) {
      rejected.push({path, code: 'WORKSPACE_SIZE_LIMIT'});
      continue;
    }
    workspace.revision += 1;
    const next = {path, content, revision: workspace.revision, lastAgentId: actor};
    workspace.files.set(path, next);
    const entry = {agentId: actor, path, operation, fromRevision: actualRevision, toRevision: workspace.revision};
    workspace.journal.push(entry);
    if (workspace.journal.length > 200) workspace.journal.splice(0, workspace.journal.length - 200);
    applied.push({...entry});
  }

  return {
    ok: conflicts.length === 0 && rejected.length === 0,
    workspaceId: workspace.workspaceId,
    revision: workspace.revision,
    applied,
    conflicts,
    rejected,
  };
}

export function workspaceJournal(workspace) {
  validateWorkspace(workspace);
  return workspace.journal.map((item) => ({...item}));
}
