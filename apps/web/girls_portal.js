"use strict";

(function initGirlsPortal() {
  const zipApi = globalThis.MinAppSingleHtmlZip;
  if (zipApi === undefined || typeof zipApi.buildSingleHtmlZip !== "function") {
    throw new Error("Girls portal requires single_html_zip.js.");
  }

  const CONFIG_PATH = "/girls-config.json";
  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const LOGIN_ID_KEY = "minapp_girls_portal_login_id";
  const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const LOGIN_ID_PATTERN = /^[a-z0-9][a-z0-9-]{2,31}$/;

  class GirlsApiError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = "GirlsApiError";
      this.status = status;
      this.code = code;
    }
  }

  function requiredElement(id) {
    const element = document.getElementById(id);
    if (element === null) throw new Error(`#${id} was not found.`);
    return element;
  }

  const fatal = requiredElement("girls-fatal");
  const loginPanel = requiredElement("girls-login-panel");
  const loginForm = requiredElement("girls-login-form");
  const loginId = requiredElement("girls-login-id");
  const loginPassword = requiredElement("girls-login-password");
  const loginError = requiredElement("girls-login-error");
  const passwordPanel = requiredElement("girls-password-panel");
  const passwordForm = requiredElement("girls-password-form");
  const newPassword = requiredElement("girls-new-password");
  const newPasswordConfirm = requiredElement("girls-new-password-confirm");
  const passwordError = requiredElement("girls-password-error");
  const uploadPanel = requiredElement("girls-upload-panel");
  const logoutButton = requiredElement("girls-logout");
  const copyPrompt = requiredElement("girls-copy-prompt");
  const aiPrompt = requiredElement("girls-ai-prompt");
  const copyResult = requiredElement("girls-copy-result");
  const uploadForm = requiredElement("girls-upload-form");
  const uploadGroup = requiredElement("girls-upload-group");
  const appTitle = requiredElement("girls-app-title");
  const sourceFile = requiredElement("girls-source-file");
  const sourceCode = requiredElement("girls-source-code");
  const uploadSubmit = requiredElement("girls-upload-submit");
  const uploadError = requiredElement("girls-upload-error");
  const uploadResult = requiredElement("girls-upload-result");

  if (!(loginForm instanceof HTMLFormElement)) throw new Error("#girls-login-form must be a form.");
  if (!(passwordForm instanceof HTMLFormElement)) throw new Error("#girls-password-form must be a form.");
  if (!(uploadForm instanceof HTMLFormElement)) throw new Error("#girls-upload-form must be a form.");
  if (!(uploadGroup instanceof HTMLSelectElement)) throw new Error("#girls-upload-group must be a select.");
  if (!(sourceFile instanceof HTMLInputElement)) throw new Error("#girls-source-file must be an input.");
  if (!(sourceCode instanceof HTMLTextAreaElement)) throw new Error("#girls-source-code must be a textarea.");
  if (!(uploadSubmit instanceof HTMLButtonElement)) throw new Error("#girls-upload-submit must be a button.");

  let apiBaseUrl = null;
  let pendingPasswordChallenge = null;
  let currentLoginId = null;

  function hide(element) {
    element.classList.add("hidden");
  }

  function show(element) {
    element.classList.remove("hidden");
  }

  function setMessage(element, message) {
    if (message === null) {
      element.textContent = "";
      hide(element);
      return;
    }
    if (typeof message !== "string" || message.length === 0) {
      throw new TypeError("message must be null or a non-empty string.");
    }
    element.textContent = message;
    show(element);
  }

  function setOnlyPanel(panel) {
    for (const candidate of [loginPanel, passwordPanel, uploadPanel]) {
      candidate.classList.toggle("hidden", candidate !== panel);
    }
  }

  function errorMessage(error) {
    if (error instanceof Error && error.message.length > 0) return error.message;
    return String(error);
  }

  function requirePlainObject(value, label) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new Error(`${label} must be an object.`);
    }
    return value;
  }

  function requireExactFields(value, expected, label) {
    const object = requirePlainObject(value, label);
    const actual = Object.keys(object).sort();
    const sortedExpected = [...expected].sort();
    if (actual.length !== sortedExpected.length || actual.some((name, index) => name !== sortedExpected[index])) {
      throw new Error(`${label} fields are invalid.`);
    }
    return object;
  }

  function requireString(value, label) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${label} must be a non-empty string.`);
    }
    return value;
  }

  function validateApiBaseUrl(value) {
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error("girls-config hosted_api_base_url is invalid.");
    }
    let url;
    try {
      url = new URL(value);
    } catch (error) {
      throw new Error("girls-config hosted_api_base_url is not a valid URL.", { cause: error });
    }
    if (
      url.protocol !== "https:" ||
      url.username !== "" ||
      url.password !== "" ||
      url.pathname !== "/" ||
      url.search !== "" ||
      url.hash !== ""
    ) {
      throw new Error("girls-config hosted_api_base_url must be an HTTPS origin without path, credentials, query, or fragment.");
    }
    const hostname = url.hostname.toLowerCase();
    if (hostname === "localhost" || hostname.endsWith(".localhost") || hostname === "127.0.0.1" || hostname === "::1") {
      throw new Error("girls-config hosted_api_base_url must be public.");
    }
    return url.origin;
  }

  function clearAuthentication() {
    sessionStorage.removeItem(ACCESS_TOKEN_KEY);
    sessionStorage.removeItem(LOGIN_ID_KEY);
    currentLoginId = null;
  }

  function storeAuthentication(token, authenticatedLoginId) {
    requireString(token, "access token");
    const normalizedLoginId = validateLoginId(authenticatedLoginId);
    clearAuthentication();
    sessionStorage.setItem(ACCESS_TOKEN_KEY, token);
    sessionStorage.setItem(LOGIN_ID_KEY, normalizedLoginId);
    currentLoginId = normalizedLoginId;
  }

  async function decodeJsonResponse(response, label) {
    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new Error(`${label} returned a non-JSON response (HTTP ${response.status}).`);
    }
    let payload;
    try {
      payload = await response.json();
    } catch (error) {
      throw new Error(`${label} returned invalid JSON.`, { cause: error });
    }
    requirePlainObject(payload, `${label} response`);
    if (!response.ok) {
      const code = typeof payload.error === "string" && payload.error.length > 0 ? payload.error : null;
      const message = typeof payload.message === "string" && payload.message.length > 0 ? payload.message : null;
      if (response.status === 401 && code === null && message !== null) {
        const fields = Object.keys(payload);
        if (fields.length !== 1 || fields[0] !== "message") {
          throw new Error(`${label} 401 response fields are invalid.`);
        }
        throw new GirlsApiError(401, "unauthorized", message);
      }
      if (code === null || message === null) {
        throw new Error(`${label} error response is missing error or message.`);
      }
      throw new GirlsApiError(response.status, code, message);
    }
    return payload;
  }

  async function loadConfig() {
    const response = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    const payload = await decodeJsonResponse(response, "Girls config");
    requireExactFields(payload, ["schema_version", "hosted_api_base_url"], "Girls config");
    if (payload.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
    }
    apiBaseUrl = validateApiBaseUrl(payload.hosted_api_base_url);
  }

  async function apiRequest(path, options = {}) {
    if (apiBaseUrl === null) throw new Error("Girls API configuration is not loaded.");
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Girls API path must be an origin-relative path.");
    }
    const url = new URL(path, `${apiBaseUrl}/`);
    if (url.origin !== apiBaseUrl || url.hash !== "") {
      throw new TypeError("Girls API path escaped the configured API origin.");
    }

    const method = options.method ?? "GET";
    if (!["GET", "POST"].includes(method)) throw new TypeError(`Unsupported Girls API method: ${method}`);
    if (options.body !== undefined && options.jsonBody !== undefined) {
      throw new TypeError("Girls API request cannot contain both body and jsonBody.");
    }
    if (method === "GET" && (options.body !== undefined || options.jsonBody !== undefined)) {
      throw new TypeError("GET Girls API request must not contain a body.");
    }

    const headers = new Headers(options.headers ?? {});
    if (headers.has("Authorization")) {
      throw new TypeError("Authorization header is managed by Girls portal.");
    }
    headers.set("Accept", "application/json");

    let body = options.body;
    if (options.jsonBody !== undefined) {
      headers.set("Content-Type", "application/json");
      body = JSON.stringify(options.jsonBody);
    }
    if (options.authenticated === true) {
      const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
      if (token === null || token.length === 0) {
        clearAuthentication();
        throw new GirlsApiError(401, "unauthorized", "ログインが必要です。");
      }
      headers.set("Authorization", `Bearer ${token}`);
    }

    let response;
    try {
      response = await fetch(url.toString(), {
        method,
        headers,
        body,
        cache: "no-store",
        credentials: "omit",
      });
    } catch (error) {
      throw new Error("Girls APIとの通信に失敗しました。", { cause: error });
    }

    try {
      return await decodeJsonResponse(response, "Girls API");
    } catch (error) {
      if (error instanceof GirlsApiError && error.status === 401) clearAuthentication();
      throw error;
    }
  }

  function validateLoginId(value) {
    if (typeof value !== "string" || value !== value.trim() || !LOGIN_ID_PATTERN.test(value)) {
      throw new Error("IDは半角英小文字・数字・ハイフンで入力してください。");
    }
    return value;
  }

  function validateAuthenticatedResponse(payload) {
    requirePlainObject(payload, "Authentication response");
    if (payload.state === "new_password_required") {
      requireExactFields(payload, ["state", "login_id", "session"], "Password challenge");
      return {
        kind: "challenge",
        loginId: validateLoginId(requireString(payload.login_id, "login_id")),
        session: requireString(payload.session, "session"),
      };
    }
    const allowedFields = new Set(["state", "access_token", "token_type", "expires_in", "refresh_token"]);
    const actualFields = Object.keys(payload);
    for (const field of ["state", "access_token", "token_type", "expires_in"]) {
      if (!actualFields.includes(field)) throw new Error(`Authentication response is missing field: ${field}`);
    }
    for (const field of actualFields) {
      if (!allowedFields.has(field)) throw new Error(`Authentication response contained unexpected field: ${field}`);
    }
    if (payload.state !== "authenticated") {
      throw new Error(`Unsupported authentication state: ${String(payload.state)}`);
    }
    if (payload.token_type !== "Bearer") throw new Error("Authentication token_type must be Bearer.");
    if (!Number.isInteger(payload.expires_in) || payload.expires_in <= 0) {
      throw new Error("Authentication expires_in is invalid.");
    }
    if (payload.refresh_token !== undefined) requireString(payload.refresh_token, "refresh_token");
    return {
      kind: "authenticated",
      token: requireString(payload.access_token, "access_token"),
    };
  }

  async function loadOwnerGroups() {
    const payload = await apiRequest("/hosted/groups", { authenticated: true });
    requireExactFields(payload, ["groups"], "Hosted groups response");
    if (!Array.isArray(payload.groups)) throw new Error("Hosted groups response has no groups list.");

    const owners = [];
    for (const rawGroup of payload.groups) {
      const group = requirePlainObject(rawGroup, "Hosted group");
      const allowedFields = new Set(["group_id", "name", "role", "status", "visibility"]);
      const actual = Object.keys(group);
      for (const field of ["group_id", "name", "role", "status"]) {
        if (!actual.includes(field)) throw new Error(`Hosted group is missing field: ${field}`);
      }
      for (const field of actual) {
        if (!allowedFields.has(field)) throw new Error(`Hosted group contained unexpected field: ${field}`);
      }
      if (!ID_PATTERN.test(group.group_id)) throw new Error("Hosted group_id is invalid.");
      requireString(group.name, "Hosted group name");
      if (!["owner", "member"].includes(group.role)) throw new Error(`Unsupported hosted group role: ${String(group.role)}`);
      if (group.status !== "active") throw new Error(`Unsupported hosted group status: ${String(group.status)}`);
      if (group.role === "owner") owners.push(group);
    }

    uploadGroup.replaceChildren();
    for (const group of owners) {
      const option = document.createElement("option");
      option.value = group.group_id;
      option.textContent = group.name;
      uploadGroup.append(option);
    }
    uploadGroup.disabled = owners.length === 0;
    uploadSubmit.disabled = owners.length === 0;
    if (owners.length === 0) {
      setMessage(uploadError, "アプリを追加するには、自分がオーナーのグループが必要です。Girlsアプリで先にグループを作ってください。");
    } else {
      setMessage(uploadError, null);
    }
  }

  async function enterWorkspace(token, authenticatedLoginId) {
    storeAuthentication(token, authenticatedLoginId);
    try {
      await loadOwnerGroups();
    } catch (error) {
      if (error instanceof GirlsApiError && error.status === 401) {
        clearAuthentication();
      }
      throw error;
    }
    setOnlyPanel(uploadPanel);
  }

  async function handleAuthPayload(payload, attemptedLoginId) {
    const result = validateAuthenticatedResponse(payload);
    if (result.kind === "challenge") {
      pendingPasswordChallenge = { loginId: result.loginId, session: result.session };
      newPassword.value = "";
      newPasswordConfirm.value = "";
      setMessage(passwordError, null);
      setOnlyPanel(passwordPanel);
      return;
    }
    pendingPasswordChallenge = null;
    await enterWorkspace(result.token, attemptedLoginId);
  }

  loginForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage(loginError, null);
    let normalizedLoginId;
    try {
      normalizedLoginId = validateLoginId(loginId.value);
    } catch (error) {
      setMessage(loginError, errorMessage(error));
      return;
    }
    const password = loginPassword.value;
    if (password.length < 1 || password.length > 128) {
      setMessage(loginError, "パスワードを入力してください。");
      return;
    }
    const button = loginForm.querySelector("button[type='submit']");
    if (!(button instanceof HTMLButtonElement)) throw new Error("Login submit button was not found.");
    button.disabled = true;
    try {
      const payload = await apiRequest("/auth/login", {
        method: "POST",
        jsonBody: { login_id: normalizedLoginId, password },
      });
      await handleAuthPayload(payload, normalizedLoginId);
      loginPassword.value = "";
    } catch (error) {
      setMessage(loginError, errorMessage(error));
    } finally {
      button.disabled = false;
    }
  });

  passwordForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage(passwordError, null);
    if (pendingPasswordChallenge === null) {
      setMessage(passwordError, "初回ログイン情報がありません。もう一度ログインしてください。");
      return;
    }
    const password = newPassword.value;
    if (password.length < 6 || password.length > 128) {
      setMessage(passwordError, "新しいパスワードは6〜128文字で入力してください。");
      return;
    }
    if (password !== newPasswordConfirm.value) {
      setMessage(passwordError, "新しいパスワードが一致しません。");
      return;
    }
    const button = passwordForm.querySelector("button[type='submit']");
    if (!(button instanceof HTMLButtonElement)) throw new Error("Password submit button was not found.");
    button.disabled = true;
    try {
      const challenge = pendingPasswordChallenge;
      const payload = await apiRequest("/auth/change-password", {
        method: "POST",
        jsonBody: {
          login_id: challenge.loginId,
          new_password: password,
          session: challenge.session,
        },
      });
      await handleAuthPayload(payload, challenge.loginId);
    } catch (error) {
      setMessage(passwordError, errorMessage(error));
    } finally {
      button.disabled = false;
    }
  });

  logoutButton.addEventListener("click", () => {
    clearAuthentication();
    pendingPasswordChallenge = null;
    loginPassword.value = "";
    setMessage(loginError, null);
    setOnlyPanel(loginPanel);
  });

  copyPrompt.addEventListener("click", async () => {
    setMessage(copyResult, null);
    setMessage(uploadError, null);
    if (navigator.clipboard === undefined || typeof navigator.clipboard.writeText !== "function") {
      setMessage(uploadError, "このブラウザではクリップボードへコピーできません。文章を長押ししてコピーしてください。");
      return;
    }
    try {
      await navigator.clipboard.writeText(aiPrompt.textContent);
      setMessage(copyResult, "コピーしたよ♡ AIにそのまま貼ってね。");
    } catch (error) {
      setMessage(uploadError, `コピーできませんでした: ${errorMessage(error)}`);
    }
  });

  function validateTitle(value) {
    if (typeof value !== "string" || value.length < 1 || value.length > 80 || value !== value.trim()) {
      throw new Error("アプリ名は前後に空白を入れず、1〜80文字で入力してください。");
    }
    if ([...value].some((char) => char.charCodeAt(0) < 0x20 || char.charCodeAt(0) === 0x7f)) {
      throw new Error("アプリ名に使用できない制御文字が含まれています。");
    }
    return value;
  }

  function validateHtml(html) {
    if (typeof html !== "string" || html.length === 0) throw new Error("HTMLコードが空です。");
    if (!/<html(?:\s|>)/i.test(html)) {
      throw new Error("HTMLコードに <html> 要素が見つかりません。AIには完成したHTML全体を出してもらってください。");
    }
    return html;
  }

  async function buildUploadBytes() {
    if (sourceFile.files === null) throw new Error("File input is unavailable.");
    if (sourceFile.files.length > 1) throw new Error("ファイルは1つだけ選んでください。");
    const file = sourceFile.files.length === 1 ? sourceFile.files[0] : null;
    const pastedHtml = sourceCode.value;
    const hasPaste = pastedHtml.length > 0;
    if (file !== null && hasPaste) {
      throw new Error("ファイル選択とHTML貼り付けを同時には使えません。どちらか片方にしてください。");
    }
    if (file === null && !hasPaste) {
      throw new Error("HTML / ZIPファイルを選ぶか、AIが出したHTMLコードを貼ってください。");
    }

    if (file !== null) {
      if (file.size <= 0) throw new Error("空のファイルはアップロードできません。");
      const lowerName = file.name.toLowerCase();
      if (lowerName.endsWith(".zip")) {
        if (file.size > MAX_UPLOAD_BYTES) throw new Error("ZIPは2MB以下にしてください。");
        return new Uint8Array(await file.arrayBuffer());
      }
      if (!lowerName.endsWith(".html") && !lowerName.endsWith(".htm")) {
        throw new Error("対応ファイルは .html / .htm / .zip だけです。");
      }
      const html = validateHtml(await file.text());
      const bytes = zipApi.buildSingleHtmlZip(html);
      if (bytes.length > MAX_UPLOAD_BYTES) throw new Error("HTMLをみんアプ用ZIPにすると2MBを超えます。");
      return bytes;
    }

    const html = validateHtml(pastedHtml);
    const bytes = zipApi.buildSingleHtmlZip(html);
    if (bytes.length > MAX_UPLOAD_BYTES) throw new Error("貼り付けたHTMLをみんアプ用ZIPにすると2MBを超えます。");
    return bytes;
  }

  function validateCreatedApp(payload, expectedGroupId) {
    const app = requirePlainObject(payload, "Hosted app upload response");
    const allowed = new Set([
      "app_id", "group_id", "title", "source_kind", "created_at", "builtin_id", "builtin_asset_path",
      "parent_app_id", "source_sha256", "source_updated_at", "published_sha256", "published_at",
      "deletion_state", "builtin_version", "source_revision", "published_version", "editable",
    ]);
    for (const field of Object.keys(app)) {
      if (!allowed.has(field)) throw new Error(`Hosted app upload response contained unexpected field: ${field}`);
    }
    for (const field of ["app_id", "group_id", "title", "source_kind", "created_at"]) {
      if (!(field in app)) throw new Error(`Hosted app upload response is missing field: ${field}`);
    }
    if (!ID_PATTERN.test(app.app_id)) throw new Error("Uploaded app_id is invalid.");
    if (app.group_id !== expectedGroupId) throw new Error("Uploaded app group_id mismatch.");
    if (app.source_kind !== "upload") throw new Error("Uploaded app source_kind mismatch.");
    if (app.source_revision !== 1) throw new Error("Uploaded app source_revision must be 1.");
    return app;
  }

  function validatePublishResponse(payload, expectedAppId, expectedGroupId) {
    const published = requireExactFields(
      payload,
      ["app_id", "group_id", "published_version", "source_revision", "sha256", "files", "published_at"],
      "Hosted publish response",
    );
    if (published.app_id !== expectedAppId) throw new Error("Published app_id mismatch.");
    if (published.group_id !== expectedGroupId) throw new Error("Published app group_id mismatch.");
    if (!Number.isInteger(published.published_version) || published.published_version < 1) {
      throw new Error("Publish response has invalid published_version.");
    }
    if (published.source_revision !== 1) throw new Error("Publish response source_revision mismatch.");
    if (typeof published.sha256 !== "string" || !/^[0-9a-f]{64}$/.test(published.sha256)) {
      throw new Error("Publish response sha256 is invalid.");
    }
    if (!Array.isArray(published.files) || !published.files.includes("index.html")) {
      throw new Error("Publish response does not contain index.html.");
    }
    requireString(published.published_at, "published_at");
    return published;
  }

  uploadForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage(uploadError, null);
    setMessage(uploadResult, null);
    if (currentLoginId === null) {
      setMessage(uploadError, "ログイン状態を確認できません。もう一度ログインしてください。");
      return;
    }

    const groupId = uploadGroup.value;
    if (!ID_PATTERN.test(groupId)) {
      setMessage(uploadError, "追加先グループを選んでください。");
      return;
    }

    let title;
    let zipBytes;
    try {
      title = validateTitle(appTitle.value);
      zipBytes = await buildUploadBytes();
    } catch (error) {
      setMessage(uploadError, errorMessage(error));
      return;
    }

    uploadSubmit.disabled = true;
    let createdAppId = null;
    try {
      const params = new URLSearchParams({ title });
      const created = await apiRequest(`/hosted/groups/${groupId}/apps/upload?${params.toString()}`, {
        method: "POST",
        headers: { "Content-Type": "application/zip" },
        body: zipBytes,
        authenticated: true,
      });
      const app = validateCreatedApp(created, groupId);
      createdAppId = app.app_id;

      const published = await apiRequest(`/hosted/groups/${groupId}/apps/${createdAppId}/publish`, {
        method: "POST",
        jsonBody: { revision: 1 },
        authenticated: true,
      });
      validatePublishResponse(published, createdAppId, groupId);

      appTitle.value = "";
      sourceFile.value = "";
      sourceCode.value = "";
      setMessage(uploadResult, `「${title}」をアップロードして公開したよ♡ Girlsアプリに戻って更新すると表示されます。`);
    } catch (error) {
      const prefix = createdAppId === null
        ? ""
        : `アプリは下書きとして作成されました（app_id=${createdAppId}）が、公開に失敗しました。\n`;
      setMessage(uploadError, `${prefix}${errorMessage(error)}`);
      if (error instanceof GirlsApiError && error.status === 401) {
        setOnlyPanel(loginPanel);
      }
    } finally {
      uploadSubmit.disabled = uploadGroup.disabled;
    }
  });

  async function bootstrap() {
    await loadConfig();
    const storedToken = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    const storedLoginId = sessionStorage.getItem(LOGIN_ID_KEY);
    if (storedToken === null && storedLoginId === null) {
      setOnlyPanel(loginPanel);
      return;
    }
    if (storedToken === null || storedLoginId === null) {
      clearAuthentication();
      throw new Error("Girls portal session storage is incomplete.");
    }
    currentLoginId = validateLoginId(storedLoginId);
    try {
      await loadOwnerGroups();
      setOnlyPanel(uploadPanel);
    } catch (error) {
      if (error instanceof GirlsApiError && error.status === 401) {
        clearAuthentication();
        setOnlyPanel(loginPanel);
        return;
      }
      throw error;
    }
  }

  bootstrap().catch((error) => {
    setOnlyPanel(null);
    setMessage(fatal, `ポータルを開始できませんでした: ${errorMessage(error)}`);
  });
})();
