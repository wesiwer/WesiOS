const ROOT_ORG = "org_wesi_inc";

function payload(record) {
  if (!record) return {};
  try {
    const raw = record.get("payload");
    if (raw && typeof raw === "object" && !Array.isArray(raw)) return raw;
    if (typeof raw === "string" && raw.trim()) return JSON.parse(raw);
  } catch (_) {}
  return {};
}

function hasForecastModule(ctx) {
  return ctx.isOwner || ctx.modules.indexOf("forecast") >= 0;
}

function access(e, ctx) {
  let orgRows = [];
  let grantRows = [];
  try {
    orgRows = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll='organizations' && deleted=false",
      "id",
      0,
      0,
      {owner: ctx.ownerId},
    );
  } catch (_) {}
  try {
    grantRows = e.app.findRecordsByFilter(
      "wesios_records",
      "owner={:owner} && coll='organization_grants' && deleted=false",
      "id",
      0,
      0,
      {owner: ctx.ownerId},
    );
  } catch (_) {}

  const orgs = {};
  const parents = {};
  for (const row of orgRows) {
    const p = payload(row);
    const id = String(p.id || row.getString("rid") || "");
    if (!id || String(p.status || "active") === "archived") continue;
    orgs[id] = {
      id: id,
      name: String(p.name || id),
      baseCurrency: String(p.baseCurrency || "RUB").toUpperCase(),
    };
    parents[id] = p.parentId == null || String(p.parentId || "") === ""
      ? null
      : String(p.parentId);
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
      for (const grant of own) {
        if (String(grant.organizationId || "") !== cursor) continue;
        if (!first && grant.includeSubtree !== true) continue;
        const permissions = Array.isArray(grant.permissions)
          ? grant.permissions.map(String)
          : [];
        if (
          permissions.indexOf("view_forecast") >= 0 &&
          permissions.indexOf("view_finance") >= 0
        ) return true;
      }
      first = false;
      cursor = parents[cursor];
    }
    return false;
  }

  const forecastOrgIds = {};
  for (const id of Object.keys(orgs)) {
    if (allowed(id)) forecastOrgIds[id] = true;
  }
  return {orgs: orgs, forecastOrgIds: forecastOrgIds};
}

function select(state, requested) {
  const requestedId = String(requested || "").trim();
  if (requestedId) {
    return state.forecastOrgIds[requestedId] === true && state.orgs[requestedId]
      ? requestedId
      : "";
  }
  if (state.forecastOrgIds[ROOT_ORG] === true && state.orgs[ROOT_ORG]) {
    return ROOT_ORG;
  }
  const ids = Object.keys(state.forecastOrgIds).filter(
    (id) => state.forecastOrgIds[id] === true && state.orgs[id],
  );
  return ids.length ? ids[0] : "";
}

module.exports = {ROOT_ORG, payload, hasForecastModule, access, select};
