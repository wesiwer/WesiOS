const ROOT_ORG = "org_wesi_inc";
const MODULES = ["treasury", "forecast", "sandbox", "analytics"];

function payload(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function hasModule(ctx) {
  return ctx.isOwner || MODULES.some((name) => ctx.modules.indexOf(name) >= 0);
}

function access(e, ctx) {
  let orgRows = [];
  let grantRows = [];
  try {
    orgRows = e.app.findRecordsByFilter("wesios_records", "owner={:owner} && coll='organizations' && deleted=false", "id", 0, 0, {owner: ctx.ownerId});
  } catch (_) {}
  try {
    grantRows = e.app.findRecordsByFilter("wesios_records", "owner={:owner} && coll='organization_grants' && deleted=false", "id", 0, 0, {owner: ctx.ownerId});
  } catch (_) {}

  const orgs = {};
  const parents = {};
  for (const row of orgRows) {
    const p = payload(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    orgs[id] = {id: id, name: String(p.name || id), baseCurrency: String(p.baseCurrency || "RUB").toUpperCase()};
    parents[id] = p.parentId == null || String(p.parentId || "") === "" ? null : String(p.parentId);
  }

  const own = [];
  if (!ctx.isOwner) {
    for (const row of grantRows) {
      const p = payload(row);
      if (String(p.employeeId || "") === ctx.employeeId) own.push(p);
    }
  }

  function allowed(orgId) {
    if (ctx.isOwner) return true;
    let cursor = orgId;
    let first = true;
    while (cursor) {
      for (const g of own) {
        if (String(g.organizationId || "") !== cursor) continue;
        if (!first && g.includeSubtree !== true) continue;
        const permissions = Array.isArray(g.permissions) ? g.permissions.map(String) : [];
        if (permissions.indexOf("view_finance") >= 0) return true;
      }
      first = false;
      cursor = parents[cursor];
    }
    return false;
  }

  const financeOrgIds = {};
  for (const id of Object.keys(orgs)) if (allowed(id)) financeOrgIds[id] = true;
  return {orgs: orgs, financeOrgIds: financeOrgIds};
}

function select(accessState, requested) {
  const raw = String(requested || "").trim();
  if (raw) {
    if (accessState.financeOrgIds[raw] === true && accessState.orgs[raw]) return raw;
    const folded = raw.toLocaleLowerCase();
    const byName = Object.keys(accessState.orgs).filter((id) =>
      accessState.financeOrgIds[id] === true &&
      String(accessState.orgs[id].name || "").trim().toLocaleLowerCase() === folded
    );
    if (byName.length === 1) return byName[0];
    return "";
  }
  if (accessState.financeOrgIds[ROOT_ORG] === true && accessState.orgs[ROOT_ORG]) return ROOT_ORG;
  const ids = Object.keys(accessState.financeOrgIds).filter((id) => accessState.financeOrgIds[id] === true && accessState.orgs[id]);
  return ids.length ? ids[0] : "";
}

module.exports = {ROOT_ORG, payload, hasModule, access, select};