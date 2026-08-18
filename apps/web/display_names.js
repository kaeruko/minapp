"use strict";

if (
  typeof apiRequest !== "function" ||
  typeof loadDashboard !== "function" ||
  typeof teacherPortalRefreshGroupData !== "function" ||
  typeof teacherPortalRenderMembers !== "function" ||
  typeof teacherPortalUpdateIdentity !== "function"
) {
  throw new Error("Display-name UI requires the base and teacher dashboard scripts.");
}

const displayNameState = {
  selfName: null,
  groupProfiles: new Map(),
};

function displayNameValidate(value) {
  if (typeof value !== "string") throw new TypeError("表示名は文字列で入力してください。");
  if (value.length < 1 || value.length > 40) throw new Error("名前は1〜40文字で入力してください。");
  if (value !== value.trim()) throw new Error("名前の前後に空白は入れないでください。");
  if (/[\u0000-\u001f\u007f]/.test(value)) throw new Error("名前に制御文字は使えません。");
  return value;
}

function displayNameValidateProfile(payload) {
  if (
    typeof payload !== "object" || payload === null || Array.isArray(payload) ||
    typeof payload.user_id !== "string" || payload.user_id.length === 0 ||
    typeof payload.login_id !== "string" || payload.login_id.length === 0 ||
    !["teacher", "student"].includes(payload.role) ||
    !(payload.display_name === null || typeof payload.display_name === "string")
  ) {
    throw new Error("表示名APIのレスポンスが不正です。");
  }
  if (typeof payload.display_name === "string") displayNameValidate(payload.display_name);
  return payload;
}

const displayNameStudentForm = document.createElement("form");
displayNameStudentForm.id = "display-name-student-form";
displayNameStudentForm.className = "display-name-card hidden";
displayNameStudentForm.innerHTML = `
  <div>
    <p class="display-name-kicker">表示名</p>
    <h3>みんなに表示する名前</h3>
    <p>アプリの作成者名として表示されます。ログインIDは変わりません。</p>
  </div>
  <div class="display-name-form-row">
    <input id="display-name-student-input" maxlength="40" autocomplete="name" placeholder="例：山田 太郎" required />
    <button class="button button-small" type="submit">名前を保存</button>
  </div>
  <p id="display-name-student-message" class="display-name-message hidden" role="status"></p>
`;
const displayNameStudentInput = displayNameStudentForm.querySelector("#display-name-student-input");
const displayNameStudentMessage = displayNameStudentForm.querySelector("#display-name-student-message");
if (!(displayNameStudentInput instanceof HTMLInputElement)) throw new Error("Student display-name input is missing.");
if (!(displayNameStudentMessage instanceof HTMLElement)) throw new Error("Student display-name message is missing.");
const displayNameAccountPanel = dashboard.querySelector(".panel");
if (!(displayNameAccountPanel instanceof HTMLElement)) throw new Error("Account panel was not found.");
displayNameAccountPanel.append(displayNameStudentForm);

const displayNameTeacherSettingsCard = teacherPortalRoot.querySelector(".teacher-settings-card");
if (!(displayNameTeacherSettingsCard instanceof HTMLElement)) throw new Error("Teacher settings card was not found.");
const displayNameTeacherForm = document.createElement("form");
displayNameTeacherForm.id = "display-name-teacher-form";
displayNameTeacherForm.className = "teacher-display-name-form";
displayNameTeacherForm.innerHTML = `
  <div>
    <p class="teacher-kicker">表示名</p>
    <h3>先生の名前</h3>
    <p>管理画面には「○○先生」と表示されます。ログインIDはそのままです。</p>
  </div>
  <div class="teacher-display-name-row">
    <input id="display-name-teacher-input" maxlength="40" autocomplete="name" placeholder="例：横田" required />
    <button class="teacher-primary-button" type="submit">名前を保存</button>
  </div>
  <p id="display-name-teacher-message" class="teacher-inline-error hidden" role="status"></p>
`;
displayNameTeacherSettingsCard.append(displayNameTeacherForm);
const displayNameTeacherInput = displayNameTeacherForm.querySelector("#display-name-teacher-input");
const displayNameTeacherMessage = displayNameTeacherForm.querySelector("#display-name-teacher-message");
if (!(displayNameTeacherInput instanceof HTMLInputElement)) throw new Error("Teacher display-name input is missing.");
if (!(displayNameTeacherMessage instanceof HTMLElement)) throw new Error("Teacher display-name message is missing.");

function displayNameSetMessage(element, message, isError = false) {
  element.textContent = message ?? "";
  element.classList.toggle("hidden", message === null);
  element.classList.toggle("display-name-message-error", isError);
  element.classList.toggle("display-name-message-ok", !isError && message !== null);
}

function displayNameApplySelf() {
  if (currentUser === null) return;
  const label = displayNameState.selfName ?? currentUser.login_id;
  accountLabel.textContent = `${label} · ${currentUser.role === "teacher" ? "先生" : "生徒"}`;
  if (currentUser.role === "student") {
    displayNameStudentInput.value = displayNameState.selfName ?? "";
    show(displayNameStudentForm);
    hide(displayNameTeacherForm);
  } else {
    hide(displayNameStudentForm);
    show(displayNameTeacherForm);
    displayNameTeacherInput.value = displayNameState.selfName ?? "";
  }
}

function displayNameApplyTeacherIdentity() {
  if (currentUser === null || currentUser.role !== "teacher" || displayNameState.selfName === null) return;
  const name = displayNameState.selfName;
  teacherPortalWelcomeTitle.textContent = `${name}先生、こんにちは！`;
  teacherPortalAccountName.textContent = `${name}先生`;
  teacherPortalAccountAvatar.textContent = name.slice(0, 1);
}

async function displayNameLoadSelf() {
  if (currentUser === null) return;
  const profile = displayNameValidateProfile(
    await apiRequest("/me/display-name", { authenticated: true }),
  );
  if (profile.user_id !== currentUser.user_id || profile.login_id !== currentUser.login_id || profile.role !== currentUser.role) {
    throw new Error("表示名APIとログイン中ユーザーが一致しません。");
  }
  displayNameState.selfName = profile.display_name;
  displayNameApplySelf();
  displayNameApplyTeacherIdentity();
}

function displayNameDecorateTeacherState(profiles) {
  displayNameState.groupProfiles = new Map();
  for (const raw of profiles) {
    const profile = displayNameValidateProfile(raw);
    if (displayNameState.groupProfiles.has(profile.user_id)) {
      throw new Error("表示名一覧に同じユーザーが重複しています。");
    }
    displayNameState.groupProfiles.set(profile.user_id, profile);
  }

  for (const app of [...teacherPortalState.reviewApps, ...teacherPortalState.publishedApps]) {
    const profile = displayNameState.groupProfiles.get(app.owner_user_id);
    if (profile === undefined) throw new Error("アプリ作成者がクラスのメンバー一覧に存在しません。");
    app.owner_account_login_id = app.owner_login_id;
    app.owner_display_name = profile.display_name;
    if (profile.display_name !== null) app.owner_login_id = profile.display_name;
  }

  for (const member of teacherPortalState.members) {
    const profile = displayNameState.groupProfiles.get(member.user_id);
    if (profile === undefined) throw new Error("メンバーの表示名情報が見つかりません。");
    member.account_login_id = member.login_id;
    member.display_name = profile.display_name;
    if (profile.display_name !== null) member.login_id = profile.display_name;
  }
}

async function displayNameLoadTeacherGroup() {
  const group = teacherPortalActiveGroup();
  if (group === null) {
    displayNameState.groupProfiles = new Map();
    return;
  }
  const payload = await apiRequest(`/groups/${group.group_id}/display-names`, { authenticated: true });
  if (typeof payload !== "object" || payload === null || !Array.isArray(payload.members)) {
    throw new Error("クラスの表示名一覧レスポンスが不正です。");
  }
  displayNameDecorateTeacherState(payload.members);
  teacherPortalRenderReviewApps();
  teacherPortalRenderPublishedApps();
  teacherPortalRenderMembers();
}

const displayNameOriginalUpdateIdentity = teacherPortalUpdateIdentity;
teacherPortalUpdateIdentity = function displayNameUpdateIdentity() {
  displayNameOriginalUpdateIdentity();
  displayNameApplyTeacherIdentity();
};

const displayNameOriginalRenderMembers = teacherPortalRenderMembers;
teacherPortalRenderMembers = function displayNameRenderMembers() {
  displayNameOriginalRenderMembers();
  const rows = Array.from(teacherPortalMembersList.querySelectorAll(".teacher-member-row"));
  if (rows.length !== teacherPortalState.members.length) {
    throw new Error("メンバー表示とメンバーデータの件数が一致しません。");
  }
  rows.forEach((row, index) => {
    if (!(row instanceof HTMLElement)) throw new Error("Member row is not an HTMLElement.");
    const member = teacherPortalState.members[index];
    const identity = row.firstElementChild;
    if (!(identity instanceof HTMLElement)) throw new Error("Member identity is missing.");
    const meta = identity.querySelector("span");
    if (!(meta instanceof HTMLElement)) throw new Error("Member role label is missing.");
    const accountLoginId = typeof member.account_login_id === "string" ? member.account_login_id : member.login_id;
    meta.textContent = `${member.role === "teacher" ? "先生" : "生徒"}${member.display_name ? ` · ID: ${accountLoginId}` : ""}`;

    if (member.role !== "student") return;
    const actions = row.lastElementChild;
    if (!(actions instanceof HTMLElement) || actions === identity) throw new Error("Student action area is missing.");
    const editButton = document.createElement("button");
    editButton.type = "button";
    editButton.className = "teacher-secondary-button teacher-small-button teacher-name-button";
    editButton.textContent = member.display_name ? "名前を変更" : "名前を設定";
    editButton.addEventListener("click", async () => {
      const proposed = window.prompt(`${accountLoginId} の名前を入力してください。`, member.display_name ?? "");
      if (proposed === null) return;
      try {
        const displayName = displayNameValidate(proposed);
        editButton.disabled = true;
        await apiRequest(`/users/${member.user_id}/display-name`, {
          method: "PATCH",
          authenticated: true,
          body: { display_name: displayName },
        });
        await teacherPortalRefreshGroupData();
      } catch (error) {
        teacherPortalHandleError(error);
      } finally {
        editButton.disabled = false;
      }
    });
    actions.prepend(editButton);
  });
};

const displayNameOriginalRefreshGroupData = teacherPortalRefreshGroupData;
teacherPortalRefreshGroupData = async function displayNameRefreshGroupData() {
  await displayNameOriginalRefreshGroupData();
  await displayNameLoadTeacherGroup();
};

async function displayNameSaveSelf(input, messageElement) {
  const displayName = displayNameValidate(input.value);
  const button = input.closest("form")?.querySelector("button[type='submit']");
  if (!(button instanceof HTMLButtonElement)) throw new Error("Display-name submit button was not found.");
  button.disabled = true;
  displayNameSetMessage(messageElement, null);
  try {
    const profile = displayNameValidateProfile(
      await apiRequest("/me/display-name", {
        method: "PATCH",
        authenticated: true,
        body: { display_name: displayName },
      }),
    );
    displayNameState.selfName = profile.display_name;
    displayNameApplySelf();
    displayNameApplyTeacherIdentity();
    if (currentUser?.role === "teacher") await teacherPortalRefreshGroupData();
    displayNameSetMessage(messageElement, "名前を保存しました。", false);
  } catch (error) {
    displayNameSetMessage(messageElement, apiErrorMessage(error), true);
  } finally {
    button.disabled = false;
  }
}

displayNameStudentForm.addEventListener("submit", (event) => {
  event.preventDefault();
  displayNameSaveSelf(displayNameStudentInput, displayNameStudentMessage).catch((error) => {
    displayNameSetMessage(displayNameStudentMessage, apiErrorMessage(error), true);
  });
});

displayNameTeacherForm.addEventListener("submit", (event) => {
  event.preventDefault();
  displayNameSaveSelf(displayNameTeacherInput, displayNameTeacherMessage).catch((error) => {
    displayNameSetMessage(displayNameTeacherMessage, apiErrorMessage(error), true);
  });
});

const displayNameOriginalLoadDashboard = loadDashboard;
loadDashboard = async function displayNameLoadDashboard() {
  await displayNameOriginalLoadDashboard();
  if (currentUser !== null) await displayNameLoadSelf();
};
