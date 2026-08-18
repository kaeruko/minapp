"use strict";

const ACCESS_TOKEN_KEY = "minapp_access_token";
const ACCESS_TOKEN_TENANT_KEY = "minapp_access_token_tenant_id";
const TENANT_DESCRIPTOR_KEY = "minapp_tenant_descriptor";
const SUPPORTED_DIRECTORY_SCHEMA_VERSION = 1;
const SUPPORTED_TENANT_API_PROTOCOL_VERSION = 1;
const MAX_DESCRIPTOR_VALID_FOR_SECONDS = 86400;

const portalRouting = globalThis.MinAppPortalRouting;
if (typeof portalRouting !== "object" || portalRouting === null) {
  throw new Error("MinAppPortalRouting must be loaded before app.js.");
}
const { PortalApiError, PortalRouter } = portalRouting;
if (typeof PortalApiError !== "function" || typeof PortalRouter !== "function") {
  throw new Error("MinAppPortalRouting is incomplete.");
}

const portalRouter = new PortalRouter({
  fetchImpl: window.fetch.bind(window),
  sessionStorage,
  localStorage,
});

function requiredElement(id) {
  const element = document.getElementById(id);
  if (!(element instanceof HTMLElement)) {
    throw new Error(`Required element #${id} was not found.`);
  }
  return element;
}

const apiStatus = requiredElement("api-status");
const classroomPanel = requiredElement("classroom-panel");
const classroomForm = requiredElement("classroom-form");
const classroomCodeInput = requiredElement("classroom-code");
const classroomError = requiredElement("classroom-error");
const classroomContext = requiredElement("classroom-context");
const classroomName = requiredElement("classroom-name");
const classroomChangeButton = requiredElement("classroom-change-button");
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

if (!(classroomForm instanceof HTMLFormElement)) throw new Error("#classroom-form must be a form.");
if (!(classroomCodeInput instanceof HTMLInputElement)) throw new Error("#classroom-code must be an input.");
if (!(classroomChangeButton instanceof HTMLButtonElement)) throw new Error("#classroom-change-button must be a button.");

let webMode = null;
let currentTenant = null;
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

function isLocalDevelopmentOrigin() {
  return (
    window.location.protocol === "http:" &&
    ["localhost", "127.0.0.1", "[::1]"].includes(window.location.hostname)
  );
}

function isDirectBrowserMode() {
  return webMode === "portal";
}

function usesClassroomRouting() {
  return webMode === "portal" || webMode === "federated";
}

function convertPortalApiError(error) {
  if (error instanceof PortalApiError) {
    return new ApiError(error.status, error.error, error.message);
  }
  return error;
}

async function jsonRequest(url, options = {}) {
  const headers = new Headers(options.headers ?? {});
  headers.set("Accept", "application/json");
  if (options.body !== undefined) {
    headers.set("Content-Type", "application/json");
  }

  const response = await fetch(url, {
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

async function loadWebMode() {
  const payload = await jsonRequest("/web-config");
  if (Object.keys(payload).length !== 1 || !["local", "fixed", "federated"].includes(payload.mode)) {
    throw new Error("Web configuration response is invalid.");
  }
  return payload.mode;
}

async function loadRuntimeMode() {
  if (isLocalDevelopmentOrigin()) {
    return loadWebMode();
  }
  if (window.location.protocol !== "https:") {
    throw new Error("Production Web portal must be served over HTTPS.");
  }
  webMode = "portal";
  await portalRouter.loadPortalConfig();
  return "portal";
}

function requireExactFields(payload, expectedFields, label) {
  const actual = Object.keys(payload).sort();
  const expected = [...expectedFields].sort();
  if (actual.length !== expected.length || actual.some((name, index) => name !== expected[index])) {
    throw new Error(`${label} response schema is invalid.`);
  }
}

function validateTenantId(value) {
  if (typeof value !== "string" || !/^[0-9a-f]{32}$/.test(value)) {
    throw new Error("tenant_id is invalid.");
  }
  return value;
}

function validateTenantDescriptor(payload) {
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error("Directory descriptor must be an object.");
  }
  requireExactFields(
    payload,
    ["schema_version", "tenant_id", "display_name", "api_base_url", "api_protocol_version", "config_revision", "valid_for_seconds"],
    "Directory descriptor",
  );

  if (payload.schema_version !== SUPPORTED_DIRECTORY_SCHEMA_VERSION) {
    throw new Error(`未対応のDirectory schema_versionです: ${payload.schema_version}`);
  }
  const tenantId = validateTenantId(payload.tenant_id);
  if (typeof payload.display_name !== "string" || payload.display_name.trim() !== payload.display_name || payload.display_name.length < 1 || payload.display_name.length > 120 || /[\u0000-\u001f]/.test(payload.display_name)) {
    throw new Error("Directory display_name is invalid.");
  }
  if (typeof payload.api_base_url !== "string") {
    throw new Error("Directory api_base_url is invalid.");
  }
  const apiBaseUrl = new URL(payload.api_base_url);
  if (apiBaseUrl.protocol !== "https:" || apiBaseUrl.username !== "" || apiBaseUrl.password !== "" || apiBaseUrl.search !== "" || apiBaseUrl.hash !== "" || !["", "/"].includes(apiBaseUrl.pathname)) {
    throw new Error("Directory api_base_url is invalid.");
  }
  if (payload.api_protocol_version !== SUPPORTED_TENANT_API_PROTOCOL_VERSION) {
    throw new Error(`未対応のtenant api_protocol_versionです: ${payload.api_protocol_version}`);
  }
  if (!Number.isInteger(payload.config_revision) || payload.config_revision < 1) {
    throw new Error("Directory config_revision is invalid.");
  }
  if (!Number.isInteger(payload.valid_for_seconds) || payload.valid_for_seconds < 1 || payload.valid_for_seconds > MAX_DESCRIPTOR_VALID_FOR_SECONDS) {
    throw new Error("Directory valid_for_seconds is invalid.");
  }

  return {
    schema_version: payload.schema_version,
    tenant_id: tenantId,
    display_name: payload.display_name,
    api_base_url: apiBaseUrl.origin,
    api_protocol_version: payload.api_protocol_version,
    config_revision: payload.config_revision,
    valid_for_seconds: payload.valid_for_seconds,
  };
}

function showTenantDescriptor(descriptor) {
  currentTenant = descriptor;
  classroomName.textContent = descriptor.display_name;
  show(classroomContext);
  hide(classroomPanel);
}

function saveTenantDescriptor(descriptor) {
  showTenantDescriptor(descriptor);
  sessionStorage.setItem(TENANT_DESCRIPTOR_KEY, JSON.stringify(descriptor));
}

function removeTenantDescriptor() {
  sessionStorage.removeItem(TENANT_DESCRIPTOR_KEY);
  currentTenant = null;
  classroomName.textContent = "";
  hide(classroomContext);
}

function restoredTenantId() {
  const raw = sessionStorage.getItem(TENANT_DESCRIPTOR_KEY);
  if (raw === null) return null;
  try {
    return validateTenantDescriptor(JSON.parse(raw)).tenant_id;
  } catch (error) {
    console.error(error);
    sessionStorage.removeItem(TENANT_DESCRIPTOR_KEY);
    return null;
  }
}

async function resolveClassroom(code) {
  const payload = await jsonRequest("/directory/v1/classrooms/resolve", {
    method: "POST",
    body: { code },
  });
  return validateTenantDescriptor(payload);
}

async function selectTenantRouting(tenantId) {
  const payload = await jsonRequest("/federation/select", {
    method: "POST",
    body: { tenant_id: validateTenantId(tenantId) },
  });
  return validateTenantDescriptor(payload);
}

async function clearTenantRouting() {
  await jsonRequest("/federation/clear", { method: "POST", body: {} });
}

async function verifyTenantEndpoint(descriptor) {
  const payload = await apiRequest("/tenant-info");
  requireExactFields(payload, ["service", "tenant_id", "api_protocol_version", "environment"], "tenant-info");
  if (payload.service !== "minapp-tenant-api") throw new Error("tenant-info service mismatch.");
  if (validateTenantId(payload.tenant_id) !== descriptor.tenant_id) throw new Error("tenant-info tenant_id mismatch.");
  if (payload.api_protocol_version !== descriptor.api_protocol_version) throw new Error("tenant-info api_protocol_version mismatch.");
  if (typeof payload.environment !== "string" || payload.environment.length === 0) throw new Error("tenant-info environment is invalid.");
}

async function apiRequest(path, options = {}) {
  if (typeof path !== "string" || !path.startsWith("/")) {
    throw new TypeError("API path must start with /.");
  }

  if (isDirectBrowserMode()) {
    const directOptions = { ...options };
    if (Object.prototype.hasOwnProperty.call(directOptions, "body")) {
      directOptions.jsonBody = directOptions.body;
      delete directOptions.body;
    }
    try {
      return await portalRouter.tenantApiRequest(path, directOptions);
    } catch (error) {
      throw convertPortalApiError(error);
    }
  }

  const headers = new Headers(options.headers ?? {});
  if (options.authenticated === true) {
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new ApiError(401, "unauthorized", "ログインが必要です。");
    }
    if (webMode === "federated") {
      const tokenTenantId = sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY);
      if (currentTenant === null || tokenTenantId !== currentTenant.tenant_id) {
        sessionStorage.removeItem(ACCESS_TOKEN_KEY);
        sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
        throw new ApiError(401, "tenant_session_mismatch", "教室が変更されたため、もう一度ログインしてください。");
      }
    }
    headers.set("Authorization", `Bearer ${token}`);
  }
  return jsonRequest(`/api${path}`, { ...options, headers });
}

async function binaryApiRequest(path, file, contentType) {
  if (!(file instanceof Blob)) throw new TypeError("Binary API body must be a Blob.");
  if (typeof contentType !== "string" || contentType.length === 0) throw new TypeError("contentType must be a non-empty string.");

  if (isDirectBrowserMode()) {
    try {
      return await portalRouter.tenantApiRequest(path, {
        method: "POST",
        authenticated: true,
        headers: { "Content-Type": contentType },
        body: file,
      });
    } catch (error) {
      throw convertPortalApiError(error);
    }
  }

  const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
  if (token === null || token.length === 0) {
    throw new ApiError(401, "unauthorized", "ログインが必要です。");
  }
  if (webMode === "federated") {
    const tokenTenantId = sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY);
    if (currentTenant === null || tokenTenantId !== currentTenant.tenant_id) {
      sessionStorage.removeItem(ACCESS_TOKEN_KEY);
      sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
      throw new ApiError(401, "tenant_session_mismatch", "教室が変更されたため、もう一度ログインしてください。");
    }
  }

  const response = await fetch(`/api${path}`, {
    method: "POST",
    headers: {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
      "Content-Type": contentType,
    },
    body: file,
    cache: "no-store",
  });
  const contentTypeHeader = response.headers.get("content-type");
  if (contentTypeHeader === null || !contentTypeHeader.toLowerCase().startsWith("application/json")) {
    throw new Error(`API returned non-JSON response (HTTP ${response.status}).`);
  }
  const payload = await response.json();
  if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
    throw new Error("API returned an unexpected JSON payload.");
  }
  if (!response.ok) {
    throw new ApiError(
      response.status,
      typeof payload.error === "string" ? payload.error : "api_error",
      typeof payload.message === "string" ? payload.message : `HTTP ${response.status}`,
    );
  }
  return payload;
}

function resetTenantTransientPreview() {
  const frame = document.getElementById("preview-frame");
  if (frame instanceof HTMLIFrameElement) frame.removeAttribute("src");
  const panel = document.getElementById("preview-panel");
  if (panel instanceof HTMLElement) hide(panel);
}

async function checkHealth() {
  if (usesClassroomRouting() && currentTenant === null) {
    apiStatus.textContent = "教室を選んでください";
    apiStatus.className = "status";
    return;
  }
  try {
    const payload = await apiRequest("/health");
    if (payload.status !== "ok" || payload.service !== "minapp-api") {
      throw new Error("Health endpoint returned an unexpected payload.");
    }
    const prefix = currentTenant === null ? "" : `${currentTenant.display_name} · `;
    apiStatus.textContent = `${prefix}API接続OK · ${payload.version}`;
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
  if (isDirectBrowserMode()) {
    portalRouter.storeAccessToken(accessToken);
  } else {
    sessionStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
    if (webMode === "federated") {
      if (currentTenant === null) throw new Error("Cannot authenticate without a selected classroom.");
      sessionStorage.setItem(ACCESS_TOKEN_TENANT_KEY, currentTenant.tenant_id);
    } else {
      sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
    }
  }
  pendingPasswordChallenge = null;
  loginPasswordInput.value = "";
  newPasswordInput.value = "";
  newPasswordConfirmInput.value = "";
}

function clearAuthentication() {
  if (isDirectBrowserMode()) {
    portalRouter.clearAuthentication();
  } else {
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
  }
  pendingPasswordChallenge = null;
  currentUser = null;
  currentGroups = [];
  hide(dashboard);
  hide(teacherPanel);
  hide(passwordPanel);
  hide(logoutButton);
  hide(credentialResult);

  if (usesClassroomRouting() && currentTenant === null) {
    hide(loginPanel);
    show(classroomPanel);
    hide(classroomContext);
    return;
  }

  hide(classroomPanel);
  show(loginPanel);
  if (currentTenant !== null) {
    classroomName.textContent = currentTenant.display_name;
    show(classroomContext);
  }
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

classroomForm.addEventListener("submit", async (event) => {
  event.preventDefault();
  setError(classroomError, null);
  const code = classroomCodeInput.value.trim();
  if (code.length === 0) {
    setError(classroomError, "教室コードを入力してください。");
    return;
  }

  const submitButton = classroomForm.querySelector("button[type='submit']");
  if (!(submitButton instanceof HTMLButtonElement)) throw new Error("Classroom submit button was not found.");
  submitButton.disabled = true;
  try {
    if (isDirectBrowserMode()) {
      const selected = await portalRouter.selectClassroom(code, { resetTransientState: resetTenantTransientPreview });
      showTenantDescriptor(selected);
    } else {
      sessionStorage.removeItem(ACCESS_TOKEN_KEY);
      sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
      removeTenantDescriptor();
      const resolved = await resolveClassroom(code);
      const selected = await selectTenantRouting(resolved.tenant_id);
      if (selected.tenant_id !== resolved.tenant_id) {
        throw new Error("Directory returned a different tenant_id during selection.");
      }
      currentTenant = selected;
      await verifyTenantEndpoint(selected);
      saveTenantDescriptor(selected);
    }
    classroomCodeInput.value = "";
    clearAuthentication();
    await checkHealth();
    loginIdInput.focus();
  } catch (error) {
    console.error(error);
    if (isDirectBrowserMode()) portalRouter.clearAuthentication();
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
    removeTenantDescriptor();
    if (!isDirectBrowserMode()) {
      try {
        await clearTenantRouting();
      } catch (clearError) {
        console.error(clearError);
      }
    }
    clearAuthentication();
    setError(classroomError, apiErrorMessage(convertPortalApiError(error)));
  } finally {
    submitButton.disabled = false;
  }
});

classroomChangeButton.addEventListener("click", async () => {
  const hasLoginState = sessionStorage.getItem(ACCESS_TOKEN_KEY) !== null || pendingPasswordChallenge !== null;
  if (hasLoginState && !window.confirm("教室を変更するとログアウトします。変更しますか？")) return;

  if (isDirectBrowserMode()) {
    try {
      await portalRouter.clearForClassroomChange({ resetTransientState: resetTenantTransientPreview });
    } catch (error) {
      console.error(error);
      setError(classroomError, apiErrorMessage(error));
      return;
    }
    pendingPasswordChallenge = null;
    removeTenantDescriptor();
    clearAuthentication();
    window.location.reload();
    return;
  }

  sessionStorage.removeItem(ACCESS_TOKEN_KEY);
  sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
  sessionStorage.removeItem(TENANT_DESCRIPTOR_KEY);
  pendingPasswordChallenge = null;
  try {
    await clearTenantRouting();
  } catch (error) {
    console.error(error);
  }
  window.location.reload();
});

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

async function initializeFederatedTenant() {
  const tenantId = restoredTenantId();
  if (tenantId === null) {
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
    removeTenantDescriptor();
    clearAuthentication();
    await checkHealth();
    return false;
  }

  try {
    const descriptor = await selectTenantRouting(tenantId);
    currentTenant = descriptor;
    await verifyTenantEndpoint(descriptor);
    saveTenantDescriptor(descriptor);
    return true;
  } catch (error) {
    console.error(error);
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
    removeTenantDescriptor();
    try {
      await clearTenantRouting();
    } catch (clearError) {
      console.error(clearError);
    }
    clearAuthentication();
    setError(classroomError, "保存していた教室情報を確認できませんでした。教室コードをもう一度入力してください。");
    await checkHealth();
    return false;
  }
}

async function initializePortalTenant() {
  try {
    const restored = await portalRouter.restoreCachedTenant();
    if (restored === null) {
      removeTenantDescriptor();
      clearAuthentication();
      await checkHealth();
      return false;
    }
    showTenantDescriptor(restored);
    return true;
  } catch (error) {
    console.error(error);
    portalRouter.clearAuthentication();
    removeTenantDescriptor();
    clearAuthentication();
    setError(classroomError, "保存していた教室情報を確認できませんでした。教室コードをもう一度入力してください。");
    await checkHealth();
    return false;
  }
}

async function initialize() {
  webMode = await loadRuntimeMode();

  if (webMode === "portal") {
    if (!(await initializePortalTenant())) return;
  } else if (webMode === "federated") {
    if (!(await initializeFederatedTenant())) return;
  } else {
    hide(classroomPanel);
    hide(classroomContext);
  }

  await checkHealth();
  const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
  if (token === null || token.length === 0) {
    clearAuthentication();
    return;
  }
  if (usesClassroomRouting()) {
    if (currentTenant === null || sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY) !== currentTenant.tenant_id) {
      clearAuthentication();
      setError(loginError, "教室が変更されたため、もう一度ログインしてください。");
      return;
    }
  }
  await loadDashboard();
}

initialize().catch((error) => {
  console.error(error);
  sessionStorage.removeItem(ACCESS_TOKEN_KEY);
  sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
  removeTenantDescriptor();
  clearAuthentication();
  setError(usesClassroomRouting() ? classroomError : loginError, apiErrorMessage(convertPortalApiError(error)));
});
