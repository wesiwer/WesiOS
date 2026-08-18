// Shared authoritative writer for Wesi AI tools that mutate wesios_records.
//
// AI tools build a candidate payload after reading a snapshot. A device may
// commit another field before the AI tool reaches the writer lock, so saving
// that whole snapshot directly would lose the device update. This helper
// computes the AI field delta and rebases it onto the transaction-current row
// before running the same live permission policy used by normal sync.

const base = typeof __hooks !== "undefined" ? __hooks + "/" : "./";
const atomic = require(base + "wesi_sync_atomic.js");
const authz = require(base + "wesi_sync_authz.js");
const genericPolicy = require(base + "wesi_sync_generic_policy.js");
const crmPolicy = require(base + "wesi_sync_crm_runtime.js");

const crmCollections = {
  crm_clients: true,
  crm_deals: true,
  crm_interactions: true,
};

function same(a, b) {
  return JSON.stringify(a == null ? null : a) ===
      JSON.stringify(b == null ? null : b);
}

function cloneMap(value) {
  const source = value && typeof value === "object" && !Array.isArray(value)
    ? value
    : {};
  const out = {};
  for (const key of Object.keys(source)) out[key] = source[key];
  return out;
}

function delta(before, next) {
  const a = cloneMap(before);
  const b = cloneMap(next);
  const out = {};
  for (const key of Object.keys(b)) {
    if (!Object.prototype.hasOwnProperty.call(a, key) || !same(a[key], b[key])) {
      out[key] = b[key];
    }
  }
  // Current Wesi AI mutation tools preserve unspecified keys by cloning the
  // old payload first. Fail closed if a future tool starts removing keys:
  // represent an explicit removal as null instead of silently reviving stale
  // data from the transaction-current row.
  for (const key of Object.keys(a)) {
    if (!Object.prototype.hasOwnProperty.call(b, key)) out[key] = null;
  }
  return out;
}

function requireModule(ctx, coll) {
  if (ctx.isOwner) return;
  const modules = Array.isArray(ctx.modules) ? ctx.modules.map(String) : [];
  const needed = coll === "calendar_events" ? "calendar"
    : coll === "tasks" ? "tasks"
    : coll === "articles" ? "knowledge"
    : coll === "roadmap_projects" || coll === "roadmap_items" ? "roadmap"
    : crmCollections[coll] ? "crm"
    : coll === "audio_beats" ? "audio"
    : coll === "transactions" || coll === "accounts" || coll === "inter_org_transfers"
      ? null
      : null;
  if (needed && modules.indexOf(needed) < 0) {
    throw new ForbiddenError("Раздел больше не открыт этому сотруднику");
  }
}

function authorize(txApp, existing, input, requestCtx) {
  const fresh = authz.refresh(txApp, requestCtx);
  requireModule(fresh, input.coll);

  if (crmCollections[input.coll]) {
    if (input.coll === "crm_clients") {
      crmPolicy.authorizeClient(txApp, existing, input, fresh);
    } else if (input.coll === "crm_deals") {
      crmPolicy.authorizeDeal(txApp, existing, input, fresh);
    } else {
      crmPolicy.authorizeInteraction(txApp, existing, input, fresh);
    }
    return;
  }
  genericPolicy.authorize(txApp, existing, input, fresh);
}

function write(e, requestCtx, options) {
  const coll = String(options.coll || "").trim();
  const rid = String(options.rid || "").trim();
  if (!coll || !rid || rid.length > 180) {
    throw new BadRequestError("Некорректная Wesi AI sync-запись");
  }

  const before = cloneMap(options.before);
  const next = cloneMap(options.next);
  const deleted = options.deleted === true;
  const creating = options.creating === true;
  const patch = creating ? cloneMap(next) : delta(before, next);
  const stamp = new Date().toISOString();
  let authoritativePayload = null;

  const result = atomic.commit(e.app, {
    owner: requestCtx.ownerId,
    org: "wesi-inc",
    coll: coll,
    rid: rid,
    payload: next,
    stamp: stamp,
    deleted: deleted,
    rebase: function(txApp, existing, input) {
      if (creating && existing && !existing.getBool("deleted")) {
        throw new BadRequestError("Wesi AI запись уже существует");
      }
      if (deleted) return;
      if (!existing || existing.getBool("deleted")) {
        input.payload = cloneMap(next);
        return;
      }
      const current = atomic.payloadOf(existing);
      input.payload = Object.assign({}, current, patch);
    },
    authorize: function(txApp, existing, input) {
      authorize(txApp, existing, input, requestCtx);
      authoritativePayload = input.deleted
        ? (existing ? atomic.payloadOf(existing) : cloneMap(input.payload))
        : cloneMap(input.payload);
    },
  });

  return {
    applied: result.applied,
    reason: result.reason,
    stamp: result.stamp,
    payload: authoritativePayload || cloneMap(next),
  };
}

module.exports = {write, delta, cloneMap};
