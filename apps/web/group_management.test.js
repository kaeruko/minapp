"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  createSelectionModel,
  normalizeInviteCode,
  validateGroupName,
  validateHostedId,
} = require("./group_management.js");

test("selection model preserves a still-valid selection", () => {
  const model = createSelectionModel({
    getId: (group) => group.id,
    getName: (group) => group.name,
  });
  const groups = [
    { id: "a", name: "A" },
    { id: "b", name: "B" },
  ];
  model.setGroups(groups);
  model.select("b");
  model.setGroups([
    { id: "b", name: "B2" },
    { id: "c", name: "C" },
  ]);
  assert.equal(model.selectedId, "b");
  assert.equal(model.active().name, "B2");
});

test("selection model fails instead of accepting an unknown selection", () => {
  const model = createSelectionModel({
    getId: (group) => group.id,
    getName: (group) => group.name,
  });
  model.setGroups([{ id: "a", name: "A" }]);
  assert.throws(() => model.select("missing"), /no longer available/);
});

test("group validation is strict", () => {
  assert.equal(validateGroupName("放課後アプリ部"), "放課後アプリ部");
  assert.throws(() => validateGroupName(" 放課後"), /前後に空白/);
  assert.equal(
    validateHostedId("0123456789abcdef0123456789abcdef"),
    "0123456789abcdef0123456789abcdef",
  );
  assert.throws(() => validateHostedId("ABC"), /invalid/);
});

test("invite codes normalize without inventing another format", () => {
  assert.equal(normalizeInviteCode("abcd-efgh-jklm"), "ABCD-EFGH-JKLM");
  assert.throws(() => normalizeInviteCode("OOOO-OOOO-OOOO"), /形式/);
});
