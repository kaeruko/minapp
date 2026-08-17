"use strict";

const ACCESS_TOKEN_KEY = "minapp_access_token";

function requiredElement(id) {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLElement)) {
    throw new Error(`Required element #${id} was not found.`);
  }
  return element;
}

const apiStatus = requiredElement("api-status");
const loginPanel = requiredElement("login-panel");
const loginForm = requiredElement("login-form");
const loginIdInput = requiredElement("login-id");
const loginPasswordInput = requiredElement("login-password");
const loginError = requiredElement("login-error");
const passwordPanel = requiredElement("password-panel");
const passwordForm = requiredElement("password-form");
const newPasswordInput = requiredElement("new-password");
const newPasswordConfirmInput = requiredElement("new-password-confirm");
const passwordError = requiredElement("password-error");
const dashboard = requiredElement("dashboard");
const logoutButton = requiredElement("logout-button");
const accountLabel = requiredElement("account-label");
const groupList = requiredElement("group-list");
const noGroups = requiredElement("no-groups");
const teacherPanel = requiredElement("teacher-panel");
const createGroupForm = requiredElement("create-group-form");
const groupNameInput = requiredElement("group-name");
const createGroupError = requiredElement("create-group-error");
const createStudentForm = requiredElement("create-student-form");
const studentGroupSelect = requiredElement("student-group");
const createStudentError = requiredElement("create-student-error");
const credentialResult = requiredElement("credential-result");
const issuedLoginId = requiredElement("issued-login-id");
const issuedPassword = requiredElement("issued-password");
const membersGroupSelect = requiredElement("members-group");
const membersList = requiredElement("members-list");
const membersError = requiredElement("members-error");

let pendingPasswordChallenge = null;
let currentUser = null;
let currentGroups = [];

function show(element) {
  element.classList.remove("hidden");
}

function hide(element) {
  element.classList.add("hidden");
}

function setError(element, message) {
  if (message === null) {
    element.textContent = "";
    hide(element);
    return;
  }
  element.textContent = message;
  show(element);
}

class ApiError extends Error {
  constructor(status, error, message) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.error = error;
  }
}

function apiErrorMessage(error) {
  if (error instanceof ApiError) {
    return error.message;
  }
  if (error instanceof Error) {
    return `通信に失敗しました: ${error.message}`;
  }
  return "予期しないエラーが発生しました。";
}

async function apiRequest(path, options = {}) {
  if (typeof path !== "string" || !path.startsWith("/")) {
    throw new TypeError("API path must start with /.");
  }

  const headers = new Headers(options.headers ?? {});
  headers.set("Accept", "application/json");
  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
  }
  if (options.authenticated === true) {
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new ApiError(401, "unauthorized", "ログインが必要です。");
    }
    headers.set("Authorization", `Bearer ${token}`);
  }

  const response = await fetch(`/api${path}`, {
    method: options.method ?? "GET",
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
    cache: "no-store",
  });

  if (response.status === 204) {
    if (!response.ok) {
      throw new ApiError(response.status, "http_error", `HTTP ${response.status}`);
    }
    return null;
  }

  const contentType = response.headers.get("content-type");
  if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
    throw new Error(`API returned non-JSON response (HTTP ${response.status}).`);
  }

  const payload = await response.json();
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error("API returned an unexpected JSON payload.");
  }
  if (!response.ok) {
    const error = typeof payload.error === "string" ? payload.error : "api_error";
    const message = typeof payload.message === "string" ? payload.message : `API request failed with HTTP ${response.status}.`;
    throw new ApiError(response.status, error, message);
  }
  return payload;
}

async function checkHealth() {
  try {
    const payload = await apiRequest("/health");
    if (payload.status !== "ok" || payload.service !== "minapp-api") {
      throw new Error("Health endpoint returned an unexpected payload.");
    }
    apiStatus.textContent = `API接続OK · ${payload.version}`;
    apiStatus.className = "status status-ok";
  } catch (error) {
    console.error(error);
    apiStatus.textContent = "API接続エラー";
    apiStatus.className = "status status-error";
  }
}

function setAuthenticated(accessToken) {
  if (typeof accessToken !== "string" || accessToken.length === 0) {
    throw new TypeError("accessToken must be a non-empty string.");
  }
  sessionStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
  pendingPasswordChallenge = null;
  loginPasswordInput.value = "";
  newPasswordInput.value = "";
  newPasswordConfirmInput.value = "";
}

function clearAuthentication() {
  sessionStorage.removeItem(ACCESS_TOKEN_KEY);
  pendingPasswordChallenge = null;
  currentUser = null;
  currentGroups = [];
  hide(dashboard);
  hide(teacherPanel);
  hide(passwordPanel);
  hide(logoutButton);
  show(loginPanel);
  hide(credentialResult);
}

function showCredential(loginId, temporaryPassword) {
  if (typeof loginId !== "string" || loginId.length === 0 || typeof temporaryPassword !== "string" || temporaryPassword.length === 0) {
    throw new Error("Credential response is missing ID or temporary password.");
  }
  issuedLoginId.textContent = loginId;
  issuedPassword.textContent = temporaryPassword;
  show(credentialResult);
}

function validateAuthenticatedResponse(payload) {
  if (payload.state === "new_password_required") {
    if (typeof payload.login_id !== "string" || typeof payload.session !== "string" || payload.login_id.length === 0 || payload.session.length === 0) {
      throw new Error("Password challenge response is incomplete.");
    }
    return "challenge";
  }
  if (payload.state === "authenticated") {
    if (typeof payload.access_token !== "string" || payload.access_token.length === 0) {
      throw new Error("Authentication response has no access token.");
    }
    return "authenticated";
  }
  throw new Error("Authentication response has an unsupported state.");
}

loginForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError(loginError, null);
  try {
    const payload = await apiRequest("/auth/login", {
      method: "POST",
      body: { login_id: loginIdInput.value, password: loginPasswordInput.value },
    });
    const state = validateAuthenticatedResponse(payload);
    if (state === "challenge") {
      pendingPasswordChallenge = { loginId: payload.login_id, session: payload.session };
      loginPasswordInput.value = "";
      hide(loginPanel);
      show(passwordPanel);
      newPasswordInput.focus();
      return;
    }
    setAuthenticated(payload.access_token);
    await loadDashboard();
  } catch (error) {
    setError(loginError, apiErrorMessage(error));
  }
});

passwordForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError(passwordError, null);
  if (pendingPasswordChallenge === null) {
    setError(passwordError, "初回パスワード変更の情報がありません。もう一度ログインしてください。");
    return;
  }
  if (newPasswordInput.value !== newPasswordConfirmInput.value) {
    setError(passwordError, "確認用パスワードが一致しません。");
    return;
  }
  try {
    const payload = await apiRequest("/auth/change-password", {
      method: "POST",
      body: {
        login_id: pendingPasswordChallenge.loginId,
        new_password: newPasswordInput.value,
        session: pendingPasswordChallenge.session,
      },
    });
    if (validateAuthenticatedResponse(payload) !== "authenticated") {
      throw new Error("Password change returned another challenge unexpectedly.");
    }
    setAuthenticated(payload.access_token);
    await loadDashboard();
  } catch (error) {
    setError(passwordError, apiErrorMessage(error));
  }
});

logoutButton.addEventListener("click", () => {
  clearAuthentication();
  loginIdInput.focus();
});

function validateMe(payload) {
  if (typeof payload.user !== "object" || payload.user === null || Array.isArray(payload.user)) {
    throw new Error("/me response has no user object.");
  }
  if (!Array.isArray(payload.groups)) {
    throw new Error("/me response has no groups array.");
  }
  if (typeof payload.user.login_id !== "string" || !["teacher", "student"].includes(payload.user.role)) {
    throw new Error("/me response contains an invalid user.");
  }
  for (const group of payload.groups) {
    if (typeof group !== "object" || group === null || typeof group.group_id !== "string" || typeof group.name !== "string" || !["teacher", "student"].includes(group.role)) {
      throw new Error("/me response contains an invalid group.");
    }
  }
}

async function loadDashboard() {
  try {
    const payload = await apiRequest("/me", { authenticated: true });
    validateMe(payload);
    currentUser = payload.user;
    currentGroups = payload.groups;
    hide(loginPanel);
    hide(passwordPanel);
    show(dashboard);
    show(logoutButton);
    accountLabel.textContent = `${currentUser.login_id} · ${currentUser.role === "teacher" ? "先生" : "生徒"}`;
    renderGroups();
    if (currentUser.role === "teacher") {
      show(teacherPanel);
      renderTeacherGroupSelects();
      await loadMembersForSelectedGroup();
    } else {
      hide(teacherPanel);
    }
  } catch (error) {
    clearAuthentication();
    if (error instanceof ApiError && error.status === 401) {
      setError(loginError, "ログインの有効期限が切れました。もう一度ログインしてください。");
      return;
    }
    setError(loginError, apiErrorMessage(error));
  }
}

function renderGroups() {
  groupList.replaceChildren();
  if (currentGroups.length === 0) {
    show(noGroups);
    return;
  }
  hide(noGroups);
  for (const group of currentGroups) {
    const card = document.createElement("article");
    card.className = "group-card";
    const title = document.createElement("h3");
    title.textContent = group.name;
    const role = document.createElement("span");
    role.className = "role-badge";
    role.textContent = group.role === "teacher" ? "先生" : "生徒";
    card.append(title, role);
    groupList.append(card);
  }
}

function setSelectOptions(select, groups) {
  select.replaceChildren();
  for (const group of groups) {
    const option = document.createElement("option");
    option.value = group.group_id;
    option.textContent = group.name;
    select.append(option);
  }
  select.disabled = groups.length === 0;
}

function teacherGroups() {
  return currentGroups.filter((group) => group.role === "teacher" && group.status === "active");
}

function renderTeacherGroupSelects() {
  const groups = teacherGroups();
  const previousStudentGroup = studentGroupSelect.value;
  const previousMembersGroup = membersGroupSelect.value;
  setSelectOptions(studentGroupSelect, groups);
  setSelectOptions(membersGroupSelect, groups);
  if (groups.some((group) => group.group_id === previousStudentGroup)) studentGroupSelect.value = previousStudentGroup;
  if (groups.some((group) => group.group_id === previousMembersGroup)) membersGroupSelect.value = previousMembersGroup;
  const studentButton = createStudentForm.querySelector("button[type='submit']");
  if (!(studentButton instanceof HTMLButtonElement)) throw new Error("Create student submit button was not found.");
  studentButton.disabled = groups.length === 0;
}

createGroupForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError(createGroupError, null);
  try {
    await apiRequest("/groups", { method: "POST", authenticated: true, body: { name: groupNameInput.value } });
    groupNameInput.value = "";
    hide(credentialResult);
    await loadDashboard();
  } catch (error) {
    setError(createGroupError, apiErrorMessage(error));
  }
});

createStudentForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError(createStudentError, null);
  const groupId = studentGroupSelect.value;
  if (groupId.length === 0) {
    setError(createStudentError, "生徒を追加するグループを選んでください。");
    return;
  }
  try {
    const payload = await apiRequest(`/groups/${groupId}/students`, { method: "POST", authenticated: true, body: {} });
    showCredential(payload.login_id, payload.temporary_password);
    membersGroupSelect.value = groupId;
    await loadMembersForSelectedGroup();
  } catch (error) {
    setError(createStudentError, apiErrorMessage(error));
  }
});

membersGroupSelect.addEventListener("change", () => {
  loadMembersForSelectedGroup().catch((error) => setError(membersError, apiErrorMessage(error)));
});

async function loadMembersForSelectedGroup() {
  setError(membersError, null);
  membersList.replaceChildren();
  const groupId = membersGroupSelect.value;
  if (groupId.length === 0) return;
  const payload = await apiRequest(`/groups/${groupId}/members`, { authenticated: true });
  if (!Array.isArray(payload.members)) throw new Error("Members response has no members array.");
  for (const member of payload.members) renderMember(groupId, member);
}

function renderMember(groupId, member) {
  if (typeof member !== "object" || member === null || typeof member.user_id !== "string" || typeof member.login_id !== "string" || !["teacher", "student"].includes(member.role)) {
    throw new Error("Members response contains an invalid member.");
  }
  const row = document.createElement("article");
  row.className = "member-row";
  const main = document.createElement("div");
  main.className = "member-main";
  const id = document.createElement("p");
  id.className = "member-id";
  id.textContent = member.login_id;
  const meta = document.createElement("p");
  meta.className = "member-meta";
  meta.textContent = member.role === "teacher" ? "先生" : "生徒";
  main.append(id, meta);
  row.append(main);

  if (member.role === "student") {
    const actions = document.createElement("div");
    actions.className = "member-actions";
    const resetButton = document.createElement("button");
    resetButton.className = "button button-quiet button-small";
    resetButton.type = "button";
    resetButton.textContent = "仮パスワード再発行";
    resetButton.addEventListener("click", async () => {
      setError(membersError, null);
      try {
        const payload = await apiRequest(`/users/${member.user_id}/reset-password`, { method: "POST", authenticated: true, body: {} });
        showCredential(payload.login_id, payload.temporary_password);
      } catch (error) {
        setError(membersError, apiErrorMessage(error));
      }
    });

    const removeButton = document.createElement("button");
    removeButton.className = "button button-danger button-small";
    removeButton.type = "button";
    removeButton.textContent = "所属解除";
    removeButton.addEventListener("click", async () => {
      if (!window.confirm(`${member.login_id} をこのグループから外しますか？`)) return;
      setError(membersError, null);
      try {
        await apiRequest(`/groups/${groupId}/members/${member.user_id}`, { method: "DELETE", authenticated: true });
        await loadMembersForSelectedGroup();
      } catch (error) {
        setError(membersError, apiErrorMessage(error));
      }
    });
    actions.append(resetButton, removeButton);
    row.append(actions);
  }
  membersList.append(row);
}

async function initialize() {
  await checkHealth();
  const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
  if (token === null || token.length === 0) {
    clearAuthentication();
    return;
  }
  await loadDashboard();
}

initialize().catch((error) => {
  console.error(error);
  clearAuthentication();
  setError(loginError, apiErrorMessage(error));
});
