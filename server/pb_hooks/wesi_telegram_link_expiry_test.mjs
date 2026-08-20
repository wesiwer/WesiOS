import assert from "node:assert/strict";
import {createRequire} from "node:module";

const require = createRequire(import.meta.url);
const store = require("./wesi_telegram_store.js");

const base = Date.parse("2026-08-20T12:00:00.000Z");
const ttl = store.CODE_TTL_MS;

assert.equal(ttl, 10 * 60 * 1000);

// New tickets use numeric server epochs and stay valid for the whole TTL.
const numeric = {
  createdAtMs: base,
  expiresAtMs: base + ttl,
  createdAt: "1999-01-01T00:00:00.000Z",
  expiresAt: "1999-01-01T00:00:00.000Z",
};
assert.equal(store.linkCodeExpiresAtMs(numeric), base + ttl);
assert.equal(store.isLinkCodeExpired(numeric, base), false);
assert.equal(store.isLinkCodeExpired(numeric, base + ttl - 1), false);
assert.equal(store.isLinkCodeExpired(numeric, base + ttl), true);

// Old persisted tickets remain compatible; derive TTL from creation time first.
const legacy = {
  createdAt: "2026-08-20T12:00:00.000Z",
  expiresAt: "2026-08-20T12:10:00.000Z",
};
assert.equal(store.linkCodeExpiresAtMs(legacy), base + ttl);
assert.equal(store.isLinkCodeExpired(legacy, base + 60_000), false);
assert.equal(store.isLinkCodeExpired(legacy, base + ttl), true);

// Malformed timing fails closed rather than creating an unlimited ticket.
assert.equal(store.isLinkCodeExpired({}, base), true);
assert.equal(store.isLinkCodeExpired({expiresAtMs: "bad"}, base), true);

console.log("TELEGRAM_LINK_EXPIRY_OK");
