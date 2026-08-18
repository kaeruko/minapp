"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "phase2_transport.js"), "utf8");

test("phase2 ZIP upload delegates to the selected-tenant binary transport", async () => {
  const calls = [];
  const context = {
    phase2BinaryUpload: async () => {
      throw new Error("legacy upload transport must not be called");
    },
    binaryApiRequest: async (...args) => {
      calls.push(args);
      return { ok: true };
    },
  };
  vm.createContext(context);
  vm.runInContext(source, context, { filename: "phase2_transport.js" });

  const file = { name: "app.zip" };
  const result = await context.phase2BinaryUpload("/groups/g1/apps?title=x", file);

  assert.deepEqual(result, { ok: true });
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], "/groups/g1/apps?title=x");
  assert.equal(calls[0][1], file);
  assert.equal(calls[0][2], "application/zip");
});

test("phase2 transport fails fast when the selected-tenant transport is unavailable", () => {
  const context = {
    phase2BinaryUpload: async () => {},
  };
  vm.createContext(context);
  assert.throws(
    () => vm.runInContext(source, context, { filename: "phase2_transport.js" }),
    /binaryApiRequest must be defined/,
  );
});
