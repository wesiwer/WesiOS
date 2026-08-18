import assert from "node:assert/strict";
import {createRequire} from "node:module";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const revision = require(path.resolve("server/pb_hooks/wesi_sync_revision.js"));

function row({id, coll, rid, nonce, updated = "2026-08-18 03:00:00.000Z"}) {
  return {
    id,
    get(name) {
      if (name === "payload") return nonce == null ? {} : {nonce};
      return null;
    },
    getString(name) {
      if (name === "coll") return coll || "";
      if (name === "rid") return rid || "";
      if (name === "updated") return updated;
      return "";
    },
  };
}

function appWith(markers = {}, legacy = {}) {
  return {
    findRecordsByFilter(collection, filter, sort, maxRecords, offset, params) {
      assert.equal(collection, "wesios_records");
      const owner = String(params?.owner || "");
      if (params?.coll === revision.markerCollection) {
        const rows = markers[owner] || [];
        return rows.slice(offset, offset + maxRecords);
      }
      if (params?.marker === revision.markerCollection) {
        const rows = legacy[owner] || [];
        return rows.slice(offset, offset + maxRecords);
      }
      return [];
    },
  };
}

test("company and private scopes produce one composite revision", () => {
  const app = appWith({
    company: [row({id: "m1", coll: revision.markerCollection, rid: revision.markerRid, nonce: "company-nonce"})],
    private: [row({id: "m2", coll: revision.markerCollection, rid: revision.markerRid, nonce: "private-nonce"})],
  });

  assert.equal(
    revision.readForContext(app, "company", "private"),
    "company=marker:company-nonce|private=marker:private-nonce",
  );
});

test("owner account does not need a duplicate private marker", () => {
  const app = appWith({
    owner: [row({id: "m1", coll: revision.markerCollection, rid: revision.markerRid, nonce: "one"})],
  });
  assert.equal(
    revision.readForContext(app, "owner", "owner"),
    "company=marker:one|private=marker:one",
  );
});

test("duplicate historical markers are deterministic and all affect the token", () => {
  const app = appWith({
    company: [
      row({id: "a", coll: revision.markerCollection, rid: revision.markerRid, nonce: "z"}),
      row({id: "b", coll: revision.markerCollection, rid: revision.markerRid, nonce: "a"}),
    ],
  });
  assert.equal(revision.readOwner(app, "company"), "marker:a,z");
});

test("pre-marker installations fall back to legacy state until first write", () => {
  const app = appWith({}, {
    company: [row({id: "business-row", coll: "tasks", rid: "t1", updated: "2026-08-18 04:00:00.000Z"})],
  });
  assert.equal(
    revision.readOwner(app, "company"),
    "legacy:business-row|2026-08-18 04:00:00.000Z",
  );
});

test("record hook covers create, update and delete while excluding marker recursion", () => {
  const hook = fs.readFileSync(
    path.resolve("server/pb_hooks/wesi_sync_revision.pb.js"),
    "utf8",
  );
  assert.match(hook, /onRecordAfterCreateSuccess/);
  assert.match(hook, /onRecordAfterUpdateSuccess/);
  assert.match(hook, /onRecordAfterDeleteSuccess/);
  assert.match(hook, /revision\.isMarker\(e\.record\)/);
  assert.match(hook, /revision\.touch\(e\.app, e\.record\.getString\("owner"\)\)/);
});

test("revision-v2 no longer derives its token from one max row", () => {
  const runtime = fs.readFileSync(
    path.resolve("server/pb_hooks/wesi_sync_extra_runtime.js"),
    "utf8",
  );
  assert.match(runtime, /wesi_sync_revision\.js/);
  assert.match(runtime, /readForContext/);
  const revisionFunction = runtime.slice(runtime.indexOf("function revision(e)"));
  assert.equal(revisionFunction.includes('"-updated,-id"'), false);
});
