function readConfig() {
  try {
    const raw = $os.readFile(__hooks + "/.wesi-connectors.json");
    const text = typeof raw === "string" ? raw : String.fromCharCode.apply(null, raw || []);
    const cfg = JSON.parse(text || "{}");
    const url = String(cfg.url || "").replace(/\/$/, "");
    const sharedSecret = String(cfg.sharedSecret || "");
    return {ready: /^http:\/\/127\.0\.0\.1:\d+$/.test(url) && sharedSecret.length >= 32, url: url, sharedSecret: sharedSecret};
  } catch (_) { return {ready: false, url: "", sharedSecret: ""}; }
}

function call(ctx, method, path, body) {
  const cfg = readConfig();
  if (!cfg.ready) return {ok: false, code: "CONNECTORS_NOT_CONFIGURED", message: "Wesi Connectors ещё не настроены"};
  let response;
  try {
    response = $http.send({
      url: cfg.url + path,
      method: method,
      headers: {
        "Content-Type": "application/json",
        "X-Wesi-Connector-Secret": cfg.sharedSecret,
        "X-Wesi-Owner-Id": String(ctx.ownerId || "")
      },
      body: body == null ? undefined : JSON.stringify(body),
      timeout: 60
    });
  } catch (_) { return {ok: false, code: "CONNECTOR_UNAVAILABLE", message: "Сервис подключений временно недоступен"}; }
  const json = response && response.json && typeof response.json === "object" ? response.json : {};
  if (!response || response.statusCode < 200 || response.statusCode >= 300 || json.ok !== true) {
    return {ok: false, code: String(json.code || "CONNECTOR_FAILED"), message: "Операция коннектора не выполнена"};
  }
  return {ok: true, result: json.result != null ? json.result : json};
}

function githubRequest(ctx, method, path, body, policy) {
  return call(ctx, "POST", "/v1/connectors/github/request", {
    method: method,
    path: path,
    body: body == null ? null : body,
    policy: policy || {read: true, write: true, destructive: false, directProtectedBranchPush: false}
  });
}

module.exports = {
  definitions: function(e, ctx) {
    if (!ctx || !ctx.isOwner) return [];
    const status = call(ctx, "GET", "/v1/connectors/github/status", null);
    if (!status.ok || !status.result.connected) return [];
    return [
      {name: "github_list_repositories", description: "Показать репозитории подключённого GitHub аккаунта.", arguments: {type: "object", properties: {page: {type: "integer"}}}},
      {name: "github_get_contents", description: "Прочитать файл или каталог GitHub-репозитория.", arguments: {type: "object", required: ["owner", "repo", "path"], properties: {owner: {type: "string"}, repo: {type: "string"}, path: {type: "string"}, ref: {type: "string"}}}},
      {name: "github_create_branch", description: "Создать рабочую ветку в GitHub-репозитории.", arguments: {type: "object", required: ["owner", "repo", "branch", "sha"], properties: {owner: {type: "string"}, repo: {type: "string"}, branch: {type: "string"}, sha: {type: "string"}}}},
      {name: "github_put_file", description: "Создать или обновить файл в рабочей ветке. Прямые изменения main/master запрещены политикой.", arguments: {type: "object", required: ["owner", "repo", "path", "branch", "message", "contentBase64"], properties: {owner: {type: "string"}, repo: {type: "string"}, path: {type: "string"}, branch: {type: "string"}, message: {type: "string"}, contentBase64: {type: "string"}, sha: {type: "string"}}}},
      {name: "github_create_pull_request", description: "Создать pull request после проверенных изменений.", arguments: {type: "object", required: ["owner", "repo", "title", "head", "base"], properties: {owner: {type: "string"}, repo: {type: "string"}, title: {type: "string"}, body: {type: "string"}, head: {type: "string"}, base: {type: "string"}}}}
    ];
  },

  context: function(e, ctx) {
    if (!ctx || !ctx.isOwner) return {};
    const status = call(ctx, "GET", "/v1/connectors/github/status", null);
    return {connectors: {github: status.ok && status.result.connected === true}};
  },

  execute: function(e, ctx, name, args) {
    if (!ctx || !ctx.isOwner) return {ok: false, code: "FORBIDDEN"};
    const a = args && typeof args === "object" ? args : {};
    const cleanRepo = function(v) { const x = String(v || ""); return /^[-A-Za-z0-9_.]{1,100}$/.test(x) ? x : ""; };
    if (name === "github_list_repositories") {
      const page = Math.max(1, Math.min(Number(a.page || 1), 100));
      return githubRequest(ctx, "GET", "/user/repos?per_page=100&page=" + page + "&sort=updated", null, {read: true});
    }
    const owner = cleanRepo(a.owner), repo = cleanRepo(a.repo);
    if (!owner || !repo) return {ok: false, code: "INVALID_REPOSITORY"};
    if (name === "github_get_contents") {
      const p = String(a.path || "").replace(/^\/+/, "");
      if (p.length > 500 || p.indexOf("..") >= 0) return {ok: false, code: "INVALID_PATH"};
      const ref = String(a.ref || "").trim();
      const suffix = ref ? "?ref=" + encodeURIComponent(ref) : "";
      return githubRequest(ctx, "GET", "/repos/" + owner + "/" + repo + "/contents/" + p + suffix, null, {read: true});
    }
    if (name === "github_create_branch") {
      const branch = String(a.branch || "").trim();
      const sha = String(a.sha || "").trim();
      if (!/^[A-Za-z0-9._\/-]{1,180}$/.test(branch) || !/^[a-f0-9]{40}$/i.test(sha)) return {ok: false, code: "INVALID_BRANCH"};
      return githubRequest(ctx, "POST", "/repos/" + owner + "/" + repo + "/git/refs", {ref: "refs/heads/" + branch, sha: sha}, {write: true});
    }
    if (name === "github_put_file") {
      const p = String(a.path || "").replace(/^\/+/, "");
      const branch = String(a.branch || "").trim();
      const message = String(a.message || "").slice(0, 240);
      const content = String(a.contentBase64 || "");
      if (!p || p.indexOf("..") >= 0 || p.length > 500 || !branch || branch === "main" || branch === "master" || !message || content.length > 8 * 1024 * 1024) return {ok: false, code: "INVALID_FILE_WRITE"};
      const body = {message: message, content: content, branch: branch};
      if (/^[a-f0-9]{40}$/i.test(String(a.sha || ""))) body.sha = String(a.sha);
      return githubRequest(ctx, "PUT", "/repos/" + owner + "/" + repo + "/contents/" + p, body, {write: true, directProtectedBranchPush: false});
    }
    if (name === "github_create_pull_request") {
      const head = String(a.head || "").trim(), base = String(a.base || "").trim();
      const title = String(a.title || "").trim().slice(0, 240);
      if (!head || !base || !title) return {ok: false, code: "INVALID_PULL_REQUEST"};
      return githubRequest(ctx, "POST", "/repos/" + owner + "/" + repo + "/pulls", {title: title, body: String(a.body || "").slice(0, 12000), head: head, base: base}, {write: true});
    }
    return {ok: false, code: "UNKNOWN_TOOL"};
  }
};
