const READ = "READ";
const WRITE = "WRITE";
const DESTRUCTIVE = "DESTRUCTIVE";

const TOOL_SPECS = {
  github_repositories_list: {risk: READ, scopes: ["repo"]},
  github_branches_list: {risk: READ, scopes: ["repo"]},
  github_commits_list: {risk: READ, scopes: ["repo"]},
  github_file_read: {risk: READ, scopes: ["repo"]},
  github_actions_runs: {risk: READ, scopes: ["repo"]},
  github_issues_list: {risk: READ, scopes: ["repo"]},
  github_pull_requests_list: {risk: READ, scopes: ["repo"]},
  github_branch_create: {risk: WRITE, scopes: ["repo"]},
  github_file_upsert: {risk: WRITE, scopes: ["repo"]},
  github_pull_request_create: {risk: WRITE, scopes: ["repo"]},
  github_issue_create: {risk: WRITE, scopes: ["repo"]},
  github_issue_comment: {risk: WRITE, scopes: ["repo"]},
  github_branch_delete: {risk: DESTRUCTIVE, scopes: ["repo"]},
  github_pull_request_merge: {risk: DESTRUCTIVE, scopes: ["repo"]},
  github_workflow_dispatch: {risk: DESTRUCTIVE, scopes: ["repo", "workflow"]},
};

function spec(name) {
  const raw = TOOL_SPECS[String(name || "")];
  if (!raw) return null;
  return {risk: raw.risk, scopes: raw.scopes.slice()};
}

function oauthScopes() {
  return ["repo", "read:user", "workflow"];
}

function hasScopes(actual, required) {
  const set = new Set(Array.isArray(actual) ? actual.map(String) : []);
  return (required || []).every((scope) => set.has(scope));
}

function validOwner(value) {
  return /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})$/.test(String(value || ""));
}
function validRepo(value) {
  return /^[A-Za-z0-9_.-]{1,100}$/.test(String(value || ""));
}
function validBranch(value) {
  const v = String(value || "");
  return v.length > 0 && v.length <= 180 && !v.startsWith("-") && !v.endsWith("/") &&
    !v.includes("..") && !v.includes("//") && !/[~^:?*[\\\s]/.test(v) && !v.endsWith(".lock");
}
function validPath(value) {
  const v = String(value || "");
  return v.length > 0 && v.length <= 500 && !v.startsWith("/") && !v.includes("\\") &&
    !v.split("/").some((part) => !part || part === "." || part === "..");
}
function staticProtectedBranch(value) {
  return ["main", "master", "trunk", "production", "stable"].includes(String(value || "").toLowerCase());
}
function limit(value, fallback, max) {
  const n = Math.trunc(Number(value || fallback));
  return Math.max(1, Math.min(max, Number.isFinite(n) ? n : fallback));
}

module.exports = {
  READ, WRITE, DESTRUCTIVE,
  spec, oauthScopes, hasScopes,
  validOwner, validRepo, validBranch, validPath, staticProtectedBranch, limit,
  toolNames: () => Object.keys(TOOL_SPECS),
};
