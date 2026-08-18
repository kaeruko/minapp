"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const css = fs.readFileSync(path.join(__dirname, "portal_shell.css"), "utf8");

test("only the role root mounted inside portal shell content is forced visible", () => {
  assert.match(
    css,
    /body\.portal-shell-active \.portal-shell-content > \.teacher-portal,\s*body\.portal-shell-active \.portal-shell-content > \.student-portal\s*\{[^}]*display:\s*block\s*!important;/s,
  );
  assert.doesNotMatch(
    css,
    /body\.portal-shell-active \.teacher-portal\s*\{[^}]*display:\s*block\s*!important;/s,
  );
  assert.doesNotMatch(
    css,
    /body\.portal-shell-active \.student-portal\s*\{[^}]*display:\s*block\s*!important;/s,
  );
});
