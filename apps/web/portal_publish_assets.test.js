"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

test("production portal publisher includes every Web Authoring asset referenced by Girls", () => {
  const repoRoot = path.resolve(__dirname, "..", "..");
  const html = fs.readFileSync(path.join(__dirname, "girls.html"), "utf8");
  const publisher = fs.readFileSync(path.join(repoRoot, "scripts", "publish-portal.ps1"), "utf8");

  const assets = [
    "hosted_authoring_portal.css",
    "authoring_host_adapter.js",
    "hosted_authoring_portal.js",
    "girls_authoring_portal.js",
  ];

  for (const asset of assets) {
    assert.match(html, new RegExp(`(?:href|src)=\"/${asset.replaceAll(".", "\\.")}\"`));
    assert.match(publisher, new RegExp(`\"${asset.replaceAll(".", "\\.")}\"`));
  }
});
