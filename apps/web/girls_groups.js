"use strict";

(function initGirlsGroups() {
  if (typeof MinAppGroupManagement !== "object" || MinAppGroupManagement === null) {
    throw new Error("Girls group management requires group_management.js.");
  }
  if (typeof MinAppGirlsPortal !== "object" || MinAppGirlsPortal === null) {
    throw new Error("Girls group management requires girls_portal.js.");
  }

  const portal = MinAppGirlsPortal;
  const MAX_GROUP_NAME_LENGTH = 60;
  const MAX_ICON_BYTES = 192 * 1024;

  function requiredElement(id) {
    const element = document.getElementById(id);
    if (element === null) throw new Error(`#${id} was not found.`);
    return element;
  }

  const uploadGroup = requiredElement("girls-upload-group");
  const logoutButton = requiredElement("girls-logout");
  const refreshButton = requiredElement("girls-groups-refresh");
  const createForm = requiredElement("girls-group-create-form");
  const createName = requiredElement("girls-group-name");
  const joinForm = requiredElement("girls-group-join-form");
  const joinCode = requiredElement("girls-group-code");
  const errorElement = requiredElement("girls-groups-error");
  const statusElement = requiredElement("girls-groups-status");
  const listElement = requiredElement("girls-group-list");
  const detailElement = requiredElement("girls-group-detail");
  const detailTitle = requiredElement("girls-group-detail-title");
  const roleElement = requiredElement("girls-group-role");
  const membersElement = requiredElement("girls-group-members");
  const ownerTools = requiredElement("girls-group-owner-tools");
  const renameForm = requiredElement("girls-group-rename-form");
  const renameInput = requiredElement("girls-group-rename");
  const inviteCreate = requiredElement("girls-group-invite-create");
  const inviteCode = requiredElement("girls-group-invite-code");
  const inviteCopy = requiredElement("girls-group-invite-copy");
  const inviteRevoke = requiredElement("girls-group-invite-revoke");
  const iconFile = requiredElement("girls-group-icon-file");
  const iconReset = requiredElement("girls-group-icon-reset");
  const transferOwner = requiredElement("girls-group-transfer-owner");
  const removeGroup = requiredElement("girls-group-remove");

  if (!(uploadGroup instanceof HTMLSelectElement)) throw new Error("#girls-upload-group must be a select.");
  if (!(refreshButton instanceof HTMLButtonElement)) throw new Error("#girls-groups-refresh must be a button.");
  if (!(createForm instanceof HTMLFormElement)) throw new Error("#girls-group-create-form must be a form.");
  if (!(createName instanceof HTMLInputElement)) throw new Error("#girls-group-name must be an input.");
  if (!(joinForm instanceof HTMLFormElement)) throw new Error("#girls-group-join-form must be a form.");
  if (!(joinCode instanceof HTMLInputElement)) throw new Error("#girls-group-code must be an input.");
  if (!(renameForm instanceof HTMLFormElement)) throw new Error("#girls-group-rename-form must be a form.");
  if (!(renameInput instanceof HTMLInputElement)) throw new Error("#girls-group-rename must be an input.");
  if (!(iconFile instanceof HTMLInputElement)) throw new Error("#girls-group-icon-file must be an input.");

  const selection = MinAppGroupManagement.createSelectionModel({
    getId: (group) => group.group_id,
    getName: (group) => group.name,
  });

  let accountUserId = null;
  let storageKey = null;
  let detailGroupId = null;
  let detailMembers = [];
  let busy = false;
  let generation = 0;

  function setError(message) {
    if (message === null) {
      errorElement.textContent = "";
      errorElement.classList.add("hidden");
      return;
    }
    if (typeof message !== "string" || message.length === 0) {
      throw new TypeError("Groups error message must be a non-empty string.");
    }
    errorElement.textContent = message;
    errorElement.classList.remove("hidden");
  }

  function errorMessage(error) {
    if (error instanceof Error && error.message.length > 0) return error.message;
    return String(error);
  }

  function handleError(error) {
    console.error(error);
    setError(errorMessage(error));
    if (error instanceof Error && error.status === 401) logoutButton.click();
  }

  function requirePlainObject(value, label) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new Error(`${label} must be an object.`);
    }
    return value;
  }

  function requireString(value, label) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${label} must be a non-empty string.`);
    }
    return value;
  }

  function normalizeGroup(raw) {
    const group = requirePlainObject(raw, "Hosted group");
    const allowed = new Set(["group_id", "name", "role", "status", "visibility"]);
    for (const field of ["group_id", "name", "role", "status"]) {
      if (!Object.hasOwn(group, field)) throw new Error(`Hosted group is missing field: ${field}`);
    }
    for (const field of Object.keys(group)) {
      if (!allowed.has(field)) throw new Error(`Hosted group contained unexpected field: ${field}`);
    }
    MinAppGroupManagement.validateHostedId(group.group_id, "Hosted group_id");
    const name = requireString(group.name, "Hosted group name");
    if (name !== name.trim() || name.length > MAX_GROUP_NAME_LENGTH) {
      throw new Error("Hosted group name is invalid.");
    }
    if (!["owner", "member"].includes(group.role)) {
      throw new Error(`Unsupported Hosted group role: ${String(group.role)}`);
    }
    if (group.status !== "active") {
      throw new Error(`Unsupported Hosted group status: ${String(group.status)}`);
    }
    return { ...group };
  }

  function normalizeMember(raw) {
    const member = requirePlainObject(raw, "Hosted member");
    const allowed = new Set(["user_id", "login_id", "role", "status", "display_name"]);
    for (const field of ["user_id", "login_id", "role", "status"]) {
      if (!Object.hasOwn(member, field)) throw new Error(`Hosted member is missing field: ${field}`);
    }
    for (const field of Object.keys(member)) {
      if (!allowed.has(field)) throw new Error(`Hosted member contained unexpected field: ${field}`);
    }
    MinAppGroupManagement.validateHostedId(member.user_id, "Hosted member user_id");
    requireString(member.login_id, "Hosted member login_id");
    if (!["owner", "member"].includes(member.role) || member.status !== "active") {
      throw new Error(`Unsupported Hosted member role/status: ${member.role}/${member.status}`);
    }
    if (member.display_name !== undefined && member.display_name !== null) {
      requireString(member.display_name, "Hosted member display_name");
    }
    return { ...member };
  }

  function displayLabel(member) {
    return member.display_name ?? member.login_id;
  }

  async function ensureIdentity() {
    if (accountUserId !== null) return accountUserId;
    const payload = requirePlainObject(
      await portal.request("/hosted/me"),
      "Hosted me response",
    );
    const user = requirePlainObject(payload.user, "Hosted me user");
    accountUserId = MinAppGroupManagement.validateHostedId(
      user.user_id,
      "Hosted current user_id",
    );
    storageKey = `minapp_girls_current_group_${accountUserId}`;
    return accountUserId;
  }

  function storedCurrentGroupId() {
    if (storageKey === null) throw new Error("Current group storage is not initialized.");
    const value = localStorage.getItem(storageKey);
    if (value === null) return null;
    return MinAppGroupManagement.validateHostedId(value, "Stored current group id");
  }

  function persistCurrentGroup() {
    if (storageKey === null) throw new Error("Current group storage is not initialized.");
    const selectedId = selection.selectedId;
    if (selectedId === null) localStorage.removeItem(storageKey);
    else localStorage.setItem(storageKey, selectedId);
  }

  function currentGroup() {
    return selection.active();
  }

  function updateCurrentGroupChrome() {
    globalThis.dispatchEvent(new CustomEvent("minapp:girls-current-group-changed"));
  }

  function renderGroups() {
    listElement.replaceChildren();
    const groups = selection.groups;
    statusElement.textContent = groups.length === 0
      ? "まだ参加しているグループはありません。"
      : `${groups.length}個のグループに参加しています。`;

    for (const group of groups) {
      const card = document.createElement("article");
      card.className = "girls-group-card";
      if (selection.selectedId === group.group_id) card.classList.add("girls-group-card-current");

      const heading = document.createElement("div");
      heading.className = "girls-group-card-heading";
      const title = document.createElement("h3");
      title.textContent = group.name;
      const role = document.createElement("span");
      role.className = "girls-group-role";
      role.textContent = group.role === "owner" ? "オーナー" : "メンバー";
      heading.append(title, role);

      const current = document.createElement("p");
      current.className = "girls-muted";
      current.textContent = selection.selectedId === group.group_id
        ? "● いまのグループ"
        : "このグループを開いて確認できます。";

      const actions = document.createElement("div");
      actions.className = "girls-group-card-actions";

      const selectButton = document.createElement("button");
      selectButton.type = "button";
      selectButton.className = "girls-secondary";
      selectButton.textContent = selection.selectedId === group.group_id
        ? "いま使っています"
        : "このグループを使う";
      selectButton.disabled = selection.selectedId === group.group_id || busy;
      selectButton.addEventListener("click", () => {
        try {
          selection.select(group.group_id);
          persistCurrentGroup();
          renderGroups();
          updateCurrentGroupChrome();
          setError(null);
        } catch (error) {
          handleError(error);
        }
      });

      const manageButton = document.createElement("button");
      manageButton.type = "button";
      manageButton.className = "girls-secondary";
      manageButton.textContent = "管理";
      manageButton.disabled = busy;
      manageButton.addEventListener("click", () => {
        void openGroup(group.group_id);
      });

      actions.append(selectButton, manageButton);
      card.append(heading, current, actions);
      listElement.append(card);
    }
  }

  async function applyGroups(rawGroups) {
    await ensureIdentity();
    if (!Array.isArray(rawGroups)) throw new Error("Hosted groups must be an array.");
    const groups = rawGroups.map(normalizeGroup);
    const storedId = storedCurrentGroupId();
    const previous = selection.selectedId;
    const preferred = previous ?? storedId;
    selection.setGroups(groups, preferred, { fallbackToFirst: false });

    if (
      preferred !== null &&
      selection.selectedId === null &&
      groups.every((group) => group.group_id !== preferred)
    ) {
      localStorage.removeItem(storageKey);
    } else {
      persistCurrentGroup();
    }

    if (detailGroupId !== null && groups.every((group) => group.group_id !== detailGroupId)) {
      detailGroupId = null;
      detailMembers = [];
      detailElement.classList.add("hidden");
    }
    renderGroups();
    updateCurrentGroupChrome();
  }

  async function reloadGroups() {
    const run = ++generation;
    setError(null);
    refreshButton.disabled = true;
    statusElement.textContent = "グループを読み込み中…";
    try {
      const groups = await portal.reloadGroups();
      if (run !== generation) return;
      await applyGroups(groups);
      if (detailGroupId !== null) await openGroup(detailGroupId);
    } catch (error) {
      if (run !== generation) return;
      handleError(error);
      statusElement.textContent = "グループを読み込めませんでした。";
    } finally {
      if (run === generation) refreshButton.disabled = false;
    }
  }

  function activeDetailGroup() {
    if (detailGroupId === null) return null;
    const group = selection.groups.find((candidate) => candidate.group_id === detailGroupId);
    if (group === undefined) throw new Error("Managed group is no longer available.");
    return group;
  }

  async function loadMembers(group) {
    const payload = requirePlainObject(
      await portal.request(`/hosted/groups/${group.group_id}/members`),
      "Hosted members response",
    );
    if (Object.keys(payload).length !== 1 || !Array.isArray(payload.members)) {
      throw new Error("Hosted members response has invalid fields.");
    }
    const members = payload.members.map(normalizeMember);
    const ownerCount = members.filter((member) => member.role === "owner").length;
    if (ownerCount !== 1) throw new Error(`Expected exactly one group owner, got ${ownerCount}.`);
    return members;
  }

  function makeOwnerMemberActions(group, member) {
    if (group.role !== "owner" || member.role === "owner") return [];
    const remove = document.createElement("button");
    remove.type = "button";
    remove.className = "girls-danger girls-group-small-action";
    remove.textContent = "削除";
    remove.disabled = busy;
    remove.addEventListener("click", async () => {
      if (!window.confirm(`「${displayLabel(member)}」をグループから外しますか？`)) return;
      await runMutation(async () => {
        await portal.request(
          `/hosted/groups/${group.group_id}/members/${member.user_id}`,
          { method: "DELETE", expectEmpty: true },
        );
        detailMembers = await loadMembers(group);
        renderDetail(group);
      });
    });
    return [remove];
  }

  function renderDetail(group) {
    detailElement.classList.remove("hidden");
    detailTitle.textContent = group.name;
    roleElement.textContent = group.role === "owner" ? "オーナー" : "メンバー";
    renameInput.value = group.name;
    ownerTools.classList.toggle("hidden", group.role !== "owner");
    removeGroup.textContent = group.role === "owner" ? "グループを削除" : "グループから脱退";

    MinAppGroupManagement.renderMemberList({
      container: membersElement,
      members: detailMembers,
      getLabel: displayLabel,
      getRoleLabel: (member) => member.role === "owner" ? "オーナー" : "メンバー",
      rowClass: "girls-group-member-row",
      actionsClass: "girls-group-member-actions",
      createActions: (member) => makeOwnerMemberActions(group, member),
    });

    const transferable = detailMembers.some((member) => member.role !== "owner");
    transferOwner.disabled = group.role !== "owner" || !transferable || busy;
    inviteCreate.disabled = group.role !== "owner" || busy;
    iconFile.disabled = group.role !== "owner" || busy;
    iconReset.disabled = group.role !== "owner" || busy;
  }

  async function openGroup(groupId) {
    MinAppGroupManagement.validateHostedId(groupId, "Managed group id");
    const group = selection.groups.find((candidate) => candidate.group_id === groupId);
    if (group === undefined) throw new Error("Managed group is no longer available.");
    detailGroupId = groupId;
    inviteCode.textContent = "";
    inviteCopy.classList.add("hidden");
    inviteRevoke.classList.add("hidden");
    setError(null);
    try {
      detailMembers = await loadMembers(group);
      renderDetail(group);
      detailElement.scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (error) {
      handleError(error);
    }
  }

  async function runMutation(action) {
    if (busy) return;
    busy = true;
    setError(null);
    renderGroups();
    const group = activeDetailGroup();
    if (group !== null) renderDetail(group);
    try {
      await action();
    } catch (error) {
      handleError(error);
    } finally {
      busy = false;
      renderGroups();
      const currentDetail = activeDetailGroup();
      if (currentDetail !== null) renderDetail(currentDetail);
    }
  }

  createForm.addEventListener("submit", (event) => {
    event.preventDefault();
    void runMutation(async () => {
      const name = MinAppGroupManagement.validateGroupName(
        createName.value,
        MAX_GROUP_NAME_LENGTH,
      );
      const previousCurrent = selection.selectedId;
      const created = normalizeGroup(
        await portal.request("/hosted/groups", {
          method: "POST",
          jsonBody: { name },
        }),
      );
      if (created.role !== "owner" || created.name !== name) {
        throw new Error("Created group response changed the requested scope.");
      }
      createName.value = "";
      const groups = await portal.reloadGroups();
      await applyGroups(groups);
      if (selection.selectedId !== previousCurrent) {
        throw new Error("Creating a group unexpectedly changed the current group.");
      }
      statusElement.textContent = `「${created.name}」を作りました。いまのグループはそのままです。`;
    });
  });

  joinForm.addEventListener("submit", (event) => {
    event.preventDefault();
    void runMutation(async () => {
      const code = MinAppGroupManagement.normalizeInviteCode(joinCode.value);
      const previousCurrent = selection.selectedId;
      const joined = normalizeGroup(
        await portal.request("/hosted/groups/join", {
          method: "POST",
          jsonBody: { code },
        }),
      );
      joinCode.value = "";
      const groups = await portal.reloadGroups();
      await applyGroups(groups);
      if (selection.selectedId !== previousCurrent) {
        throw new Error("Joining a group unexpectedly changed the current group.");
      }
      statusElement.textContent = `「${joined.name}」に参加しました。いまのグループはそのままです。`;
    });
  });

  renameForm.addEventListener("submit", (event) => {
    event.preventDefault();
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can rename a group.");
      }
      const name = MinAppGroupManagement.validateGroupName(
        renameInput.value,
        MAX_GROUP_NAME_LENGTH,
      );
      const updated = normalizeGroup(
        await portal.request(`/hosted/groups/${group.group_id}`, {
          method: "PATCH",
          jsonBody: { name },
        }),
      );
      if (updated.group_id !== group.group_id || updated.name !== name || updated.role !== "owner") {
        throw new Error("Group rename response changed the requested scope.");
      }
      const groups = await portal.reloadGroups();
      await applyGroups(groups);
      await openGroup(group.group_id);
    });
  });

  inviteCreate.addEventListener("click", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can create an invite.");
      }
      const payload = requirePlainObject(
        await portal.request(`/hosted/groups/${group.group_id}/invite`, {
          method: "POST",
          jsonBody: {},
        }),
        "Hosted invite response",
      );
      const expectedFields = ["code", "expires_at", "group_id", "valid_for_seconds"];
      const actual = Object.keys(payload).sort();
      if (actual.length !== expectedFields.length || actual.some((field, index) => field !== expectedFields[index])) {
        throw new Error("Hosted invite response fields are invalid.");
      }
      if (payload.group_id !== group.group_id) throw new Error("Hosted invite group_id mismatch.");
      const code = MinAppGroupManagement.normalizeInviteCode(requireString(payload.code, "Hosted invite code"));
      if (!Number.isInteger(payload.valid_for_seconds) || payload.valid_for_seconds < 1) {
        throw new Error("Hosted invite valid_for_seconds is invalid.");
      }
      if (Number.isNaN(Date.parse(requireString(payload.expires_at, "Hosted invite expires_at")))) {
        throw new Error("Hosted invite expires_at is invalid.");
      }
      inviteCode.textContent = code;
      inviteCopy.classList.remove("hidden");
      inviteRevoke.classList.remove("hidden");
    });
  });

  inviteCopy.addEventListener("click", async () => {
    const code = inviteCode.textContent;
    if (code === null || code.length === 0) throw new Error("No invite code is available.");
    if (navigator.clipboard === undefined || typeof navigator.clipboard.writeText !== "function") {
      setError("このブラウザでは招待コードをコピーできません。");
      return;
    }
    try {
      await navigator.clipboard.writeText(code);
      statusElement.textContent = "招待コードをコピーしました。";
    } catch (error) {
      handleError(error);
    }
  });

  inviteRevoke.addEventListener("click", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can revoke an invite.");
      }
      if (!window.confirm("現在の招待コードを無効にしますか？")) return;
      await portal.request(`/hosted/groups/${group.group_id}/invite`, {
        method: "DELETE",
        expectEmpty: true,
      });
      inviteCode.textContent = "";
      inviteCopy.classList.add("hidden");
      inviteRevoke.classList.add("hidden");
      statusElement.textContent = "招待コードを無効にしました。";
    });
  });

  iconFile.addEventListener("change", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can change a group icon.");
      }
      if (iconFile.files === null || iconFile.files.length !== 1) {
        throw new Error("グループアイコン画像を1つ選んでください。");
      }
      const file = iconFile.files[0];
      if (file.size < 1 || file.size > MAX_ICON_BYTES) {
        throw new Error("グループアイコンは192KB以下にしてください。");
      }
      const extension = file.name.toLowerCase().split(".").pop();
      const contentType = extension === "png"
        ? "image/png"
        : ["jpg", "jpeg"].includes(extension)
          ? "image/jpeg"
          : extension === "webp"
            ? "image/webp"
            : null;
      if (contentType === null) {
        throw new Error("グループアイコンはPNG・JPEG・WebPから選んでください。");
      }
      const bytes = new Uint8Array(await file.arrayBuffer());
      const payload = requirePlainObject(
        await portal.request(`/hosted/groups/${group.group_id}/icon`, {
          method: "POST",
          headers: { "Content-Type": contentType },
          body: bytes,
        }),
        "Group icon response",
      );
      const expectedFields = ["bytes", "content_type", "group_id", "updated_at"];
      const actual = Object.keys(payload).sort();
      if (actual.length !== expectedFields.length || actual.some((field, index) => field !== expectedFields[index])) {
        throw new Error("Group icon response fields are invalid.");
      }
      if (
        payload.group_id !== group.group_id ||
        payload.content_type !== contentType ||
        payload.bytes !== bytes.length
      ) {
        throw new Error("Group icon response changed the requested scope.");
      }
      requireString(payload.updated_at, "Group icon updated_at");
      iconFile.value = "";
      statusElement.textContent = "グループアイコンを変更しました。";
    });
  });

  iconReset.addEventListener("click", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can reset a group icon.");
      }
      await portal.request(`/hosted/groups/${group.group_id}/icon`, {
        method: "DELETE",
        expectEmpty: true,
      });
      statusElement.textContent = "グループアイコンをデフォルトに戻しました。";
    });
  });

  transferOwner.addEventListener("click", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null || group.role !== "owner") {
        throw new Error("Only the owner can transfer ownership.");
      }
      const candidates = detailMembers.filter((member) => member.role !== "owner");
      if (candidates.length === 0) throw new Error("オーナーにできるほかのメンバーがいません。");
      const menu = candidates
        .map((member, index) => `${index + 1}: ${displayLabel(member)}`)
        .join("\n");
      const raw = window.prompt(`新しいオーナーを番号で選んでください。\n${menu}`);
      if (raw === null) return;
      if (!/^[1-9][0-9]*$/.test(raw)) throw new Error("オーナー候補の番号を入力してください。");
      const index = Number(raw) - 1;
      if (!Number.isSafeInteger(index) || index < 0 || index >= candidates.length) {
        throw new Error("オーナー候補の番号が範囲外です。");
      }
      const nextOwner = candidates[index];
      if (!window.confirm(`「${displayLabel(nextOwner)}」を新しいオーナーにしますか？`)) return;
      const payload = requirePlainObject(
        await portal.request(`/hosted/groups/${group.group_id}/owner`, {
          method: "POST",
          jsonBody: { user_id: nextOwner.user_id },
        }),
        "Ownership transfer response",
      );
      const actual = Object.keys(payload).sort();
      if (
        actual.length !== 2 ||
        actual[0] !== "group_id" ||
        actual[1] !== "owner_user_id" ||
        payload.group_id !== group.group_id ||
        payload.owner_user_id !== nextOwner.user_id
      ) {
        throw new Error("Ownership transfer response changed the requested scope.");
      }
      const groups = await portal.reloadGroups();
      await applyGroups(groups);
      const updated = selection.groups.find((candidate) => candidate.group_id === group.group_id);
      if (updated === undefined || updated.role !== "member") {
        throw new Error("Ownership transfer did not change the current role.");
      }
      await openGroup(group.group_id);
    });
  });

  removeGroup.addEventListener("click", () => {
    void runMutation(async () => {
      const group = activeDetailGroup();
      if (group === null) throw new Error("No group is selected for removal.");
      const owner = group.role === "owner";
      const message = owner
        ? `「${group.name}」を削除します。グループ内のアプリやメンバー情報も削除されます。続けますか？`
        : `「${group.name}」から脱退します。続けますか？`;
      if (!window.confirm(message)) return;
      await portal.request(
        owner
          ? `/hosted/groups/${group.group_id}`
          : `/hosted/groups/${group.group_id}/membership`,
        { method: "DELETE", expectEmpty: true },
      );
      const removedWasCurrent = selection.selectedId === group.group_id;
      detailGroupId = null;
      detailMembers = [];
      detailElement.classList.add("hidden");
      const groups = await portal.reloadGroups();
      await applyGroups(groups);
      if (removedWasCurrent && selection.selectedId !== null) {
        throw new Error("Removing the current group unexpectedly selected another group.");
      }
      statusElement.textContent = owner
        ? `「${group.name}」を削除しました。`
        : `「${group.name}」から脱退しました。`;
    });
  });

  refreshButton.addEventListener("click", () => void reloadGroups());

  globalThis.addEventListener("minapp:girls-groups-changed", () => {
    void applyGroups(portal.groups()).catch(handleError);
  });

  globalThis.MinAppGirlsGroups = Object.freeze({
    currentGroup: () => {
      const group = currentGroup();
      return group === null ? null : { ...group };
    },
    reload: () => reloadGroups(),
  });

  if (portal.groups().length > 0) {
    void applyGroups(portal.groups()).catch(handleError);
  }
})();
