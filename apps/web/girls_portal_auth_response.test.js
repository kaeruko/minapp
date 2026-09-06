"use strict";

const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const source = fs.readFileSync(path.join(__dirname, "girls_portal.js"), "utf8");

test("Girls portal allows Cognito refresh_token in authenticated response", () => {
  assert.match(
    source,
    /new Set\(\["state", "access_token", "token_type", "expires_in", "refresh_token"\]\)/,
  );
  assert.match(
    source,
    /if \(payload\.refresh_token !== undefined\) requireString\(payload\.refresh_token, "refresh_token"\);/,
  );
});

test("Girls portal persists auth and refreshes access tokens", () => {
  assert.match(source, /minapp_girls_portal_refresh_token/);
  assert.match(source, /minapp_girls_portal_access_expires_at/);
  assert.match(source, /localStorage/);
  assert.match(source, /\/auth\/refresh/);
  assert.match(source, /REFRESH_SKEW_MS = 60 \* 1000/);
  assert.match(source, /globalThis\.fetch = persistentFetch/);
});
