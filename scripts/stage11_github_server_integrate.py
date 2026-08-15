from pathlib import Path

TOOLS = Path('server/pb_hooks/wesi_ai_tools.js')
REGISTRY = Path('server/pb_hooks/wesi_ai_capability_registry.js')

tools = TOOLS.read_text()
needle = '    require(base + "wesi_ai_team_tools.js"),\n'
insert = needle + '    require(base + "wesi_ai_github_tools.js"),\n'
if 'wesi_ai_github_tools.js' not in tools:
    if needle not in tools:
        raise SystemExit('tools anchor missing')
    tools = tools.replace(needle, insert, 1)
TOOLS.write_text(tools)

registry = REGISTRY.read_text()
anchor = '  horizon_snapshot: {module: "horizon", action: "read_snapshot", risk: RISK_READ, entityType: "horizon_snapshot"},\n'
block = '''  github_repositories_list: {module: "github", action: "read_repositories", risk: RISK_READ, entityType: "github_repository"},
  github_file_read: {module: "github", action: "read_file", risk: RISK_READ, entityType: "github_file"},
  github_branches_list: {module: "github", action: "read_branches", risk: RISK_READ, entityType: "github_branch"},
  github_commits_list: {module: "github", action: "read_commits", risk: RISK_READ, entityType: "github_commit"},
  github_pull_requests_list: {module: "github", action: "read_pull_requests", risk: RISK_READ, entityType: "github_pull_request"},
  github_issues_list: {module: "github", action: "read_issues", risk: RISK_READ, entityType: "github_issue"},
  github_actions_list: {module: "github", action: "read_actions", risk: RISK_READ, entityType: "github_action_run"},

'''
if 'github_repositories_list:' not in registry:
    if anchor not in registry:
        raise SystemExit('registry anchor missing')
    registry = registry.replace(anchor, block + anchor, 1)
REGISTRY.write_text(registry)
