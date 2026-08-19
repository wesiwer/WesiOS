import assert from "node:assert/strict";
import {createRequire} from "node:module";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";

const require = createRequire(import.meta.url);
const revision = require(path.resolve("server/pb_hooks/wesi_sync_revision.js"));

function row({
  id,
  coll,
  rid,
  nonce,
  stamp = "2026-08-18T03:00:00.000Z",
}) {
  return {
    id,
    get(name) {
      if (name === "payload") return nonce == null ? {} : {nonce};
      return null;
    },
    getString(name) {
      if (name === "coll") return coll || "";
      if (name === "rid") return rid || "";
      if (name === "stamp") return stamp;
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
        assert.equal(sort, "-stamp,-id");
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
    "company=marker:company-nonce|latest:empty|private=marker:private-nonce|latest:empty",
  );
});

test("owner account does not need a duplicate private marker", () => {
  const app = appWith({
    owner: [row({id: "m1", coll: revision.markerCollection, rid: revision.markerRid, nonce: "one"})],
  });
  assert.equal(
    revision.readForContext(app, "owner", "owner"),
    "company=marker:one|latest:empty|private=marker:one|latest:empty",
  );
});

test("duplicate historical markers are deterministic and all affect the token", () => {
  const app = appWith({
    company: [
      row({id: "a", coll: revision.markerCollection, rid: revision.markerRid, nonce: "z"}),
      row({id: "b", coll: revision.markerCollection, rid: revision.markerRid, nonce: "a"}),
    ],
  });
  assert.equal(
    revision.readOwner(app, "company"),
    "marker:a,z|latest:empty",
  );
});

test("marker logical stamp advances even when two writes share one millisecond", () => {
  const previous = "2999-01-01T00:00:00.123Z";
  const next = revision.nextMarkerStamp([
    row({
      id: "m1",
      coll: revision.markerCollection,
      rid: revision.markerRid,
      nonce: "old",
      stamp: previous,
    }),
  ]);

  assert.equal(Date.parse(next), Date.parse(previous) + 1);
  assert.notEqual(next, previous);
});

test("duplicate markers advance from the newest previous logical stamp", () => {
  const a = "2999-01-01T00:00:00.100Z";
  const b = "2999-01-01T00:00:00.900Z";
  const next = revision.nextMarkerStamp([
    row({id: "a", stamp: a}),
    row({id: "b", stamp: b}),
  ]);
  assert.equal(Date.parse(next), Date.parse(b) + 1);
});

test("marker stays above an allowed future business stamp for legacy revision", () => {
  const previousMarker = "2999-01-01T00:00:00.100Z";
  const futureBusiness = "2999-01-01T00:05:00.000Z";
  const next = revision.nextMarkerStamp(
    [row({id: "m", stamp: previousMarker})],
    futureBusiness,
  );

  assert.equal(Date.parse(next), Date.parse(futureBusiness) + 1);
  assert.ok(Date.parse(next) > Date.parse(previousMarker));
});

test("pre-marker installations fall back to latest business stamp until first write", () => {
  const app = appWith({}, {
    company: [row({
      id: "business-row",
      coll: "tasks",
      rid: "t1",
      stamp: "2026-08-18T04:00:00.000Z",
    })],
  });
  assert.equal(
    revision.readOwner(app, "company"),
    "legacy:business-row|2026-08-18T04:00:00.000Z",
  );
});

test("latest business stamp remains a fallback when marker nonce is unchanged", () => {
  const marker = {
    company: [row({id: "m1", coll: revision.markerCollection, rid: revision.markerRid, nonce: "stable-marker"})],
  };
  const before = appWith(marker, {
    company: [row({
      id: "a",
      coll: "tasks",
      rid: "a",
      stamp: "2026-08-18T04:00:00.000Z",
    })],
  });
  const after = appWith(marker, {
    company: [row({
      id: "b",
      coll: "tasks",
      rid: "b",
      stamp: "2026-08-18T04:00:01.000Z",
    })],
  });

  assert.notEqual(
    revision.readOwner(before, "company"),
    revision.readOwner(after, "company"),
  );
});

test("revision fallback never queries optional PocketBase updated field", () => {
  const source = fs.readFileSync(
    path.resolve("server/pb_hooks/wesi_sync_revision.js"),
    "utf8",
  );
  assert.doesNotMatch(source, /["']-updated,-id["']/);
  assert.doesNotMatch(source, /getString\(["']updated["']\)/);
  assert.match(source, /latestBusinessByStamp\(app, owner\)/);
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

test("legacy profile_private POST is rejected while old GET data stays migratable", () => {
  const hook = fs.readFileSync(
    path.resolve("server/pb_hooks/wesi_sync_revision.pb.js"),
    "utf8",
  );
  assert.match(
    hook,
    /routerAdd\("POST",\s*"\/api\/wesi\/sync\/profile_private"/,
  );
  assert.match(hook, /устаревший формат профиля/);
  assert.doesNotMatch(
    hook,
    /routerAdd\("GET",\s*"\/api\/wesi\/sync\/profile_private"/,
    "legacy read remains owned by the generic collection route for migration",
  );
});

test("revision-v2 no longer derives its primary token from one max row", () => {
  const runtime = fs.readFileSync(
    path.resolve("server/pb_hooks/wesi_sync_extra_runtime.js"),
    "utf8",
  );
  assert.match(runtime, /wesi_sync_revision\.js/);
  assert.match(runtime, /readForContext/);
  const revisionFunction = runtime.slice(runtime.indexOf("function revision(e)"));
  assert.equal(revisionFunction.includes('"-updated,-id"'), false);
});
