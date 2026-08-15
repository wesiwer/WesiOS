const RISK_READ = "READ";
const RISK_WRITE = "WRITE";
const RISK_DESTRUCTIVE = "DESTRUCTIVE";

const CAPABILITIES = {
  tasks_list: {module: "tasks", action: "read", risk: RISK_READ, entityType: "task"},
  tasks_create: {module: "tasks", action: "create", risk: RISK_WRITE, entityType: "task"},
  tasks_update: {module: "tasks", action: "update", risk: RISK_WRITE, entityType: "task"},
  tasks_archive: {module: "tasks", action: "archive", risk: RISK_DESTRUCTIVE, entityType: "task"},

  finance_summary: {module: "treasury", action: "read_summary", risk: RISK_READ, entityType: "finance"},
  finance_transactions: {module: "treasury", action: "read_transactions", risk: RISK_READ, entityType: "transaction"},
  finance_transaction_create: {module: "treasury", action: "create", risk: RISK_WRITE, entityType: "transaction"},
  finance_transaction_update: {module: "treasury", action: "update", risk: RISK_WRITE, entityType: "transaction"},
  finance_transaction_delete: {module: "treasury", action: "delete", risk: RISK_DESTRUCTIVE, entityType: "transaction"},

  organizations_list: {module: "organizations", action: "read", risk: RISK_READ, entityType: "organization"},
  team_list: {module: "contacts", action: "read_team", risk: RISK_READ, entityType: "employee"},

  calendar_events: {module: "calendar", action: "read", risk: RISK_READ, entityType: "calendar_event"},
  calendar_create: {module: "calendar", action: "create", risk: RISK_WRITE, entityType: "calendar_event"},
  calendar_update: {module: "calendar", action: "update", risk: RISK_WRITE, entityType: "calendar_event"},
  calendar_delete: {module: "calendar", action: "delete", risk: RISK_DESTRUCTIVE, entityType: "calendar_event"},

  knowledge_search: {module: "knowledge", action: "search", risk: RISK_READ, entityType: "knowledge_article"},
  knowledge_article: {module: "knowledge", action: "read", risk: RISK_READ, entityType: "knowledge_article"},
  knowledge_create: {module: "knowledge", action: "create", risk: RISK_WRITE, entityType: "knowledge_article"},
  knowledge_update: {module: "knowledge", action: "update", risk: RISK_WRITE, entityType: "knowledge_article"},
  knowledge_archive: {module: "knowledge", action: "archive", risk: RISK_DESTRUCTIVE, entityType: "knowledge_article"},

  crm_clients: {module: "crm", action: "read_clients", risk: RISK_READ, entityType: "crm_client"},
  crm_deals: {module: "crm", action: "read_deals", risk: RISK_READ, entityType: "crm_deal"},
  crm_pipeline_summary: {module: "crm", action: "read_pipeline", risk: RISK_READ, entityType: "crm_deal"},
  crm_client_create: {module: "crm", action: "create_client", risk: RISK_WRITE, entityType: "crm_client"},
  crm_client_update: {module: "crm", action: "update_client", risk: RISK_WRITE, entityType: "crm_client"},
  crm_client_archive: {module: "crm", action: "archive_client", risk: RISK_DESTRUCTIVE, entityType: "crm_client"},
  crm_deal_create: {module: "crm", action: "create_deal", risk: RISK_WRITE, entityType: "crm_deal"},
  crm_deal_update: {module: "crm", action: "update_deal", risk: RISK_WRITE, entityType: "crm_deal"},
  crm_deal_archive: {module: "crm", action: "archive_deal", risk: RISK_DESTRUCTIVE, entityType: "crm_deal"},
  crm_interaction_create: {module: "crm", action: "create_interaction", risk: RISK_WRITE, entityType: "crm_interaction"},

  roadmap_list: {module: "roadmap", action: "read", risk: RISK_READ, entityType: "roadmap_item"},
  roadmap_create: {module: "roadmap", action: "create", risk: RISK_WRITE, entityType: "roadmap_item"},
  roadmap_update: {module: "roadmap", action: "update", risk: RISK_WRITE, entityType: "roadmap_item"},
  roadmap_archive: {module: "roadmap", action: "archive", risk: RISK_DESTRUCTIVE, entityType: "roadmap_item"},

  audio_vault_list: {module: "audio", action: "read", risk: RISK_READ, entityType: "audio_vault_item"},
  audio_vault_update: {module: "audio", action: "update", risk: RISK_WRITE, entityType: "audio_vault_item"},

  horizon_snapshot: {module: "horizon", action: "read_snapshot", risk: RISK_READ, entityType: "horizon_snapshot"},

  render_table: {module: "presentation", action: "render", risk: RISK_READ, entityType: "presentation"},
  render_chart: {module: "presentation", action: "render", risk: RISK_READ, entityType: "presentation"},
  render_diagram: {module: "presentation", action: "render", risk: RISK_READ, entityType: "presentation"},
  generate_image: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_music: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},
  generate_video: {module: "media", action: "generate", risk: RISK_WRITE, entityType: "media"},


  github_repositories_list: {module: "connectors", action: "github_repositories_list", risk: RISK_READ, entityType: "github_repository"},
  github_branches_list: {module: "connectors", action: "github_branches_list", risk: RISK_READ, entityType: "github_branch"},
  github_commits_list: {module: "connectors", action: "github_commits_list", risk: RISK_READ, entityType: "github_commit"},
  github_file_read: {module: "connectors", action: "github_file_read", risk: RISK_READ, entityType: "github_file"},
  github_actions_runs: {module: "connectors", action: "github_actions_runs", risk: RISK_READ, entityType: "github_action_run"},
  github_issues_list: {module: "connectors", action: "github_issues_list", risk: RISK_READ, entityType: "github_issue"},
  github_pull_requests_list: {module: "connectors", action: "github_pull_requests_list", risk: RISK_READ, entityType: "github_pull_request"},
  github_branch_create: {module: "connectors", action: "github_branch_create", risk: RISK_WRITE, entityType: "github_branch"},
  github_file_upsert: {module: "connectors", action: "github_file_upsert", risk: RISK_WRITE, entityType: "github_file"},
  github_pull_request_create: {module: "connectors", action: "github_pull_request_create", risk: RISK_WRITE, entityType: "github_pull_request"},
  github_issue_create: {module: "connectors", action: "github_issue_create", risk: RISK_WRITE, entityType: "github_issue"},
  github_issue_comment: {module: "connectors", action: "github_issue_comment", risk: RISK_WRITE, entityType: "github_comment"},
  github_branch_delete: {module: "connectors", action: "github_branch_delete", risk: RISK_DESTRUCTIVE, entityType: "github_branch"},
  github_pull_request_merge: {module: "connectors", action: "github_pull_request_merge", risk: RISK_DESTRUCTIVE, entityType: "github_pull_request"},
  github_workflow_dispatch: {module: "connectors", action: "github_workflow_dispatch", risk: RISK_DESTRUCTIVE, entityType: "github_action_run"},
};

function copyMeta(name, raw) {
  if (!raw) return null;
  return {
    name: String(name),
    module: String(raw.module || ""),
    action: String(raw.action || ""),
    risk: String(raw.risk || RISK_READ),
    entityType: String(raw.entityType || "wesi_ai_action"),
    confirmationRequired: String(raw.risk || RISK_READ) === RISK_DESTRUCTIVE,
  };
}

module.exports = {
  RISK_READ: RISK_READ,
  RISK_WRITE: RISK_WRITE,
  RISK_DESTRUCTIVE: RISK_DESTRUCTIVE,
  get: function(name) { return copyMeta(name, CAPABILITIES[String(name || "")]); },
  decorateDefinition: function(definition) {
    if (!definition || typeof definition !== "object") return definition;
    const meta = module.exports.get(definition.name);
    if (!meta) return null;
    const out = {};
    for (const key of Object.keys(definition)) out[key] = definition[key];
    out.wesiCapability = {module: meta.module, action: meta.action, risk: meta.risk, confirmationRequired: meta.confirmationRequired};
    return out;
  },
  registeredNames: function() { return Object.keys(CAPABILITIES); },
};
