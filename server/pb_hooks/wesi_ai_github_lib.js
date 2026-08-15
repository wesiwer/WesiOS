const API_ORIGIN = "https://api.github.com";
const DEVICE_CODE_URL = "https://github.com/login/device/code";
const ACCESS_TOKEN_URL = "https://github.com/login/oauth/access_token";
const MAX_RESPONSE_BYTES = 512 * 1024;
const DEFAULT_SCOPES = ["repo", "workflow", "read:user"];

function text(value) {
  return String(value == null ? "" : value).trim();
}

function uniqueScopes(value) {
  const raw = Array.isArray(value) ? value : String(value || "").split(/[ ,]+/g);
  const out = [];
  for (const item of raw) {
    const scope = text(item).toLowerCase();
    if (!scope || !/^[a-z0-9:_-]{1,80}$/.test(scope) || out.indexOf(scope) >= 0) continue;
    out.push(scope);
  }
  return out.slice(0, 32);
}

function validateOwnerRepo(owner, repo) {
  const o = text(owner);
  const r = text(repo);
  const part = /^[A-Za-z0-9_.-]{1,100}$/;
  if (!part.test(o) || !part.test(r) || o === "." || o === ".." || r === "." || r === "..") {
    throw new Error("GITHUB_BAD_REPOSITORY");
  }
  return {owner: o, repo: r};
}

function validateRef(value) {
  const ref = text(value || "HEAD");
  if (!ref || ref.length > 240 || ref.indexOf("\\") >= 0 || ref.indexOf("..") >= 0 || /[\u0000-\u001f]/.test(ref)) {
    throw new Error("GITHUB_BAD_REF");
  }
  return ref;
}

function validateContentPath(value) {
  const input = text(value);
  if (!input || input.length > 1024 || input.startsWith("/") || input.indexOf("\\") >= 0 || /[\u0000-\u001f]/.test(input)) {
    throw new Error("GITHUB_BAD_PATH");
  }
  const parts = input.split("/");
  if (parts.some((part) => !part || part === "." || part === "..")) throw new Error("GITHUB_BAD_PATH");
  return parts.map(encodeURIComponent).join("/");
}

function apiUrl(path, query) {
  const target = text(path);
  if (!target.startsWith("/") || target.length > 1800 || target.indexOf("\\") >= 0 || target.indexOf("..") >= 0) {
    throw new Error("GITHUB_BAD_API_PATH");
  }
  let url = API_ORIGIN + target;
  const params = [];
  const source = query && typeof query === "object" && !Array.isArray(query) ? query : {};
  for (const key of Object.keys(source).sort()) {
    if (!/^[A-Za-z0-9_-]{1,60}$/.test(key)) throw new Error("GITHUB_BAD_QUERY");
    if (source[key] == null || source[key] === "") continue;
    const value = String(source[key]);
    if (value.length > 1024) throw new Error("GITHUB_BAD_QUERY");
    params.push(encodeURIComponent(key) + "=" + encodeURIComponent(value));
  }
  if (params.length) url += "?" + params.join("&");
  return url;
}

function repoApiPath(owner, repo, suffix) {
  const pair = validateOwnerRepo(owner, repo);
  const tail = text(suffix || "");
  if (tail && (!tail.startsWith("/") || tail.indexOf("..") >= 0 || tail.indexOf("\\") >= 0)) {
    throw new Error("GITHUB_BAD_API_PATH");
  }
  return "/repos/" + encodeURIComponent(pair.owner) + "/" + encodeURIComponent(pair.repo) + tail;
}

function requireScopes(granted, required) {
  const have = uniqueScopes(granted);
  const need = uniqueScopes(required);
  for (const scope of need) {
    if (have.indexOf(scope) < 0) return {ok: false, missing: scope, granted: have};
  }
  return {ok: true, granted: have};
}

function parseJsonResponse(response) {
  if (!response || typeof response !== "object") throw new Error("GITHUB_BAD_RESPONSE");
  if (response.json && typeof response.json === "object") return response.json;
  const raw = String(response.raw == null ? "" : response.raw);
  if (raw.length > MAX_RESPONSE_BYTES) throw new Error("GITHUB_RESPONSE_TOO_LARGE");
  try {
    const parsed = JSON.parse(raw || "{}");
    if (!parsed || typeof parsed !== "object") throw new Error("GITHUB_BAD_RESPONSE");
    return parsed;
  } catch (_) {
    throw new Error("GITHUB_BAD_RESPONSE");
  }
}

function boundedResult(value, maxBytes) {
  const limit = Math.max(1024, Math.min(Number(maxBytes || MAX_RESPONSE_BYTES), MAX_RESPONSE_BYTES));
  const raw = JSON.stringify(value == null ? null : value);
  if (raw.length > limit) throw new Error("GITHUB_RESPONSE_TOO_LARGE");
  return value;
}

function safeHeaders(token) {
  const secret = text(token);
  if (secret.length < 20 || secret.length > 512 || /[\r\n]/.test(secret)) throw new Error("GITHUB_BAD_TOKEN");
  return {
    "Accept": "application/vnd.github+json",
    "Authorization": "Bearer " + secret,
    "X-GitHub-Api-Version": "2022-11-28",
    "User-Agent": "WesiOS-GitHub-Connector/1",
  };
}

module.exports = {
  API_ORIGIN,
  DEVICE_CODE_URL,
  ACCESS_TOKEN_URL,
  MAX_RESPONSE_BYTES,
  DEFAULT_SCOPES,
  text,
  uniqueScopes,
  validateOwnerRepo,
  validateRef,
  validateContentPath,
  apiUrl,
  repoApiPath,
  requireScopes,
  parseJsonResponse,
  boundedResult,
  safeHeaders,
};