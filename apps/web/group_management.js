"use strict";

(function installGroupManagement(root, factory) {
  const api = factory();
  if (typeof module !== "undefined" && module.exports) module.exports = api;
  if (root !== null && root !== undefined) root.MinAppGroupManagement = api;
})(typeof globalThis === "undefined" ? null : globalThis, () => {
  const HOSTED_ID_PATTERN = /^[0-9a-f]{32}$/;
  const INVITE_CODE_PATTERN =
    /^[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}-?[23456789ABCDEFGHJKLMNPQRSTUVWXYZ]{4}$/;

  function requireFunction(value, label) {
    if (typeof value !== "function") throw new TypeError(`${label} must be a function.`);
    return value;
  }

  function validateGroupName(value, maxLength = 60) {
    if (!Number.isInteger(maxLength) || maxLength < 1) {
      throw new TypeError("maxLength must be a positive integer.");
    }
    if (typeof value !== "string" || value.length < 1 || value.length > maxLength || value !== value.trim()) {
      throw new Error(`グループ名は前後に空白を入れず、1〜${maxLength}文字で入力してください。`);
    }
    if ([...value].some((char) => char.charCodeAt(0) < 0x20 || char.charCodeAt(0) === 0x7f)) {
      throw new Error("グループ名に使用できない制御文字が含まれています。");
    }
    return value;
  }

  function validateHostedId(value, label = "group id") {
    if (typeof value !== "string" || !HOSTED_ID_PATTERN.test(value)) {
      throw new Error(`${label} is invalid.`);
    }
    return value;
  }

  function normalizeInviteCode(value) {
    if (typeof value !== "string") throw new TypeError("invite code must be a string.");
    const normalized = value.trim().toUpperCase();
    if (!INVITE_CODE_PATTERN.test(normalized)) {
      throw new Error("グループIDは XXXX-XXXX-XXXX の形式で入力してください。");
    }
    return normalized;
  }

  function createSelectionModel({ getId, getName }) {
    requireFunction(getId, "getId");
    requireFunction(getName, "getName");

    let groups = [];
    let selectedId = null;

    function validateGroups(nextGroups) {
      if (!Array.isArray(nextGroups)) throw new TypeError("groups must be an array.");
      const seen = new Set();
      return nextGroups.map((group) => {
        const id = getId(group);
        const name = getName(group);
        if (typeof id !== "string" || id.length === 0) throw new Error("Group id must be a non-empty string.");
        if (typeof name !== "string" || name.length === 0) throw new Error("Group name must be a non-empty string.");
        if (seen.has(id)) throw new Error(`Duplicate group id: ${id}`);
        seen.add(id);
        return group;
      });
    }

    function setGroups(nextGroups, preferredId = selectedId) {
      groups = validateGroups(nextGroups);
      if (groups.length === 0) {
        selectedId = null;
        return null;
      }
      if (preferredId !== null && groups.some((group) => getId(group) === preferredId)) {
        selectedId = preferredId;
      } else {
        selectedId = getId(groups[0]);
      }
      return active();
    }

    function select(id) {
      if (typeof id !== "string" || id.length === 0) throw new Error("Selected group id must be a non-empty string.");
      if (!groups.some((group) => getId(group) === id)) {
        throw new Error("Selected group is no longer available.");
      }
      selectedId = id;
      return active();
    }

    function active() {
      if (selectedId === null) return null;
      const group = groups.find((candidate) => getId(candidate) === selectedId);
      if (group === undefined) throw new Error("Selected group is no longer available.");
      return group;
    }

    function populateSelect(select) {
      if (
        typeof HTMLSelectElement !== "undefined" &&
        !(select instanceof HTMLSelectElement)
      ) {
        throw new TypeError("select must be an HTMLSelectElement.");
      }
      if (select === null || typeof select !== "object" || typeof select.replaceChildren !== "function") {
        throw new TypeError("select must support replaceChildren.");
      }
      select.replaceChildren();
      for (const group of groups) {
        const option = document.createElement("option");
        option.value = getId(group);
        option.textContent = getName(group);
        select.append(option);
      }
      select.disabled = groups.length === 0;
      if (selectedId !== null) select.value = selectedId;
    }

    return Object.freeze({
      get groups() {
        return [...groups];
      },
      get selectedId() {
        return selectedId;
      },
      setGroups,
      select,
      active,
      populateSelect,
    });
  }

  return Object.freeze({
    HOSTED_ID_PATTERN,
    INVITE_CODE_PATTERN,
    validateGroupName,
    validateHostedId,
    normalizeInviteCode,
    createSelectionModel,
  });
});
