"use strict";

(function initGirlsPortal() {
  const routing = globalThis.MinAppPortalRouting;
  const zipApi = globalThis.MinAppSingleHtmlZip;
  if (routing === undefined || typeof routing.PortalRouter !== "function") {
    throw new Error("Girls portal requires portal_routing.js.");
  }
  if (zipApi === undefined || typeof zipApi.buildSingleHtmlZip !== "function") {
    throw new Error("Girls portal requires single_html_zip.js.");
  }

  const MAX_UPLOAD_BYTES = 2 * 1024 * 1024;
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const LOGIN_ID_PATTERN = /^[a-z0-9][a-z0-9-]{2,31}$/;

  function requiredElement(id) {
    const element = document.getElementById(id);
    if (element === null) throw new Error(`#${id} was not found.`);
    return element;
  }

  const fatal = requiredElement("girls-fatal");
  const classroomPanel = requiredElement("girls-classroom-panel");
  const classroomForm = requiredElement("girls-classroom-form");
  const classroomCode = requiredElement("girls-classroom-code");
  const classroomError = requiredElement("girls-classroom-error");
  const loginPanel = requiredElement("girls-login-panel");
  const loginForm = requiredElement("girls-login-form");
  const loginId = requiredElement("girls-login-id");
  const loginPassword = requiredElement("girls-login-password");
  const loginTenant = requiredElement("girls-login-tenant");
  const loginError = requiredElement("girls-login-error");
  const changeClassroom = requiredElement("girls-change-classroom");
  const passwordPanel = requiredElement("girls-password-panel");
  const passwordForm = requiredElement("girls-password-form");
  const newPassword = requiredElement("girls-new-password");
  const newPasswordConfirm = requiredElement("girls-new-password-confirm");
  const passwordError = requiredElement("girls-password-error");
  const uploadPanel = requiredElement("girls-upload-panel");
  const workspaceTenant = requiredElement("girls-workspace-tenant");
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

  if (!(classroomForm instanceof HTMLFormElement)) throw new Error("#girls-classroom-form must be a form.");
  if (!(loginForm instanceof HTMLFormElement)) throw new Error("#girls-login-form must be a form.");
  if (!(passwordForm instanceof HTMLFormElement)) throw new Error("#girls-password-form must be a form.");
  if (!(uploadForm instanceof HTMLFormElement)) throw new Error("#girls-upload-form must be a form.");
  if (!(uploadGroup instanceof HTMLSelectElement)) throw new Error("#girls-upload-group must be a select.");
  if (!(sourceFile instanceof HTMLInputElement)) throw new Error("#girls-source-file must be an input.");
  if (!(sourceCode instanceof HTMLTextAreaElement)) throw new Error("#girls-source-code must be a textarea.");
  if (!(uploadSubmit instanceof HTMLButtonElement)) throw new Error("#girls-upload-submit must be a button.");

  const router = new routing.PortalRouter({
    fetchImpl: (...args) => globalThis.fetch(...args),
    sessionStorage: globalThis.sessionStorage,
    localStorage: globalThis.localStorage,
  });

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
    for (const candidate of [classroomPanel, loginPanel, passwordPanel, uploadPanel]) {
      candidate.classList.toggle("hidden", candidate !== panel);
    }
  }

  function errorMessage(error) {
    if (error instanceof routing.PortalApiError) return error.message;
    if (error instanceof Error && error.message.length > 0) return error.message;
    return String(error);
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

  function validateLoginId(value) {
    if (typeof value !== "string" || value !== value.trim() || !LOGIN_ID_PATTERN.test(value)) {
      throw new Error("IDは半角英小文字・数字・ハイフンで入力してください。");
    }
    return value;
  }

  function validateAuthenticatedResponse(payload) {
    requirePlainObject(payload, "Authentication response");
    if (payload.state === "new_password_required") {
      requireString(payload.login_id, "login_id");
      requireString(payload.session, "session");
      return {
        kind: "challenge",
        loginId: payload.login_id,
        session: payload.session,
      };
    }
    if (payload.state !== "authenticated") {
      throw new Error(`Unsupported authentication state: ${String(payload.state)}`);
    }
    const token = requireString(payload.access_token, "access_token");
    if (payload.token_type !== "Bearer") {
      throw new Error("Authentication token_type must be Bearer.");
    }
    if (!Number.isInteger(payload.expires_in) || payload.expires_in <= 0) {
      throw new Error("Authentication expires_in is invalid.");
    }
    return { kind: "authenticated", token };
  }

  function setTenant(route) {
    requirePlainObject(route, "Tenant route");
    loginTenant.textContent = requireString(route.display_name, "tenant display_name");
    workspaceTenant.textContent = route.display_name;
  }

  async function loadOwnerGroups() {
    const payload = await router.tenantApiRequest("/hosted/groups", { authenticated: true });
    requirePlainObject(payload, "Hosted groups response");
    if (Object.keys(payload).length !== 1 || !Array.isArray(payload.groups)) {
      throw new Error("Hosted groups response schema is invalid.");
    }

    const owners = [];
    for (const rawGroup of payload.groups) {
      const group = requirePlainObject(rawGroup, "Hosted group");
      const allowedFields = new Set(["group_id", "name", "role", "status", "visibility"]);
      for (const field of Object.keys(group)) {
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
    if (typeof token !== "string" || token.length === 0) throw new TypeError("token must be non-empty.");
    currentLoginId = validateLoginId(authenticatedLoginId);
    router.storeAccessToken(token);
    await loadOwnerGroups();
    const tenant = router.currentTenant;
    if (tenant === null) throw new Error("Tenant disappeared after login.");
    setTenant(tenant);
    setOnlyPanel(uploadPanel);
  }

  async function handleAuthPayload(payload, attemptedLoginId) {
    const result = validateAuthenticatedResponse(payload);
    if (result.kind === "challenge") {
      pendingPasswordChallenge = {
        loginId: validateLoginId(result.loginId),
        session: result.session,
      };
      newPassword.value = "";
      newPasswordConfirm.value = "";
      setMessage(passwordError, null);
      setOnlyPanel(passwordPanel);
      return;
    }
    pendingPasswordChallenge = null;
    await enterWorkspace(result.token, attemptedLoginId);
  }

  async function showLoginForTenant(route) {
    setTenant(route);
    loginPassword.value = "";
    setMessage(loginError, null);
    setOnlyPanel(loginPanel);
  }

  classroomForm.addEventListener("submit", async (event) => {
    event.preventDefault();
    setMessage(classroomError, null);
    const code = classroomCode.value;
    if (code.length === 0 || code !== code.trim()) {
      setMessage(classroomError, "教室コードは前後に空白を入れず入力してください。");
      return;
    }
    const button = classroomForm.querySelector("button[type='submit']");
    if (!(button instanceof HTMLButtonElement)) throw new Error("Classroom submit button was not found.");
    button.disabled = true;
    try {
      const route = await router.selectClassroom(code);
      await showLoginForTenant(route);
    } catch (error) {
      setMessage(classroomError, errorMessage(error));
    } finally {
      button.disabled = false;
    }
  });

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
      const payload = await router.tenantApiRequest("/auth/login", {
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
      const payload = await router.tenantApiRequest("/auth/change-password", {
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

  changeClassroom.addEventListener("click", async () => {
    await router.clearForClassroomChange();
    pendingPasswordChallenge = null;
    currentLoginId = null;
    classroomCode.value = "";
    setMessage(classroomError, null);
    setOnlyPanel(classroomPanel);
  });

  logoutButton.addEventListener("click", () => {
    router.clearAuthentication();
    pendingPasswordChallenge = null;
    currentLoginId = null;
    const tenant = router.currentTenant;
    if (tenant === null) throw new Error("Cannot log out without a selected tenant.");
    void showLoginForTenant(tenant);
  });

  copyPrompt.addEventListener("click", async () => {
    setMessage(copyResult, null);
    if (navigator.clipboard === undefined || typeof navigator.clipboard.writeText !== "function") {
      setMessage(uploadError, "このブラウザではクリップボードへコピーできません。文章を長押ししてコピーしてください。");
      return;
    }
    try {
      await navigator.clipboard.writeText(aiPrompt.textContent);
      setMessage(copyResult, "コピーしたよ♡ AIにそのまま貼ってね。 ");
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
    if (typeof html !== "string" || html.length === 0) {
      throw new Error("HTMLコードが空です。");
    }
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
      const created = await router.tenantApiRequest(`/hosted/groups/${groupId}/apps/upload?${params.toString()}`, {
        method: "POST",
        headers: { "Content-Type": "application/zip" },
        body: zipBytes,
        authenticated: true,
      });
      requirePlainObject(created, "Hosted app upload response");
      if (!ID_PATTERN.test(created.app_id)) throw new Error("Uploaded app_id is invalid.");
      if (created.group_id !== groupId) throw new Error("Uploaded app group_id mismatch.");
      createdAppId = created.app_id;

      const published = await router.tenantApiRequest(`/hosted/groups/${groupId}/apps/${createdAppId}/publish`, {
        method: "POST",
        jsonBody: { revision: 1 },
        authenticated: true,
      });
      requirePlainObject(published, "Hosted publish response");
      if (!Number.isInteger(published.published_version) || published.published_version < 1 || published.source_revision !== 1) {
        throw new Error("Publish response has invalid version information.");
      }

      appTitle.value = "";
      sourceFile.value = "";
      sourceCode.value = "";
      setMessage(uploadResult, `「${title}」をアップロードして公開したよ♡ Girlsアプリに戻って更新すると表示されます。`);
    } catch (error) {
      const prefix = createdAppId === null
        ? ""
        : `アプリは下書きとして作成されました（app_id=${createdAppId}）が、公開に失敗しました。\n`;
      setMessage(uploadError, `${prefix}${errorMessage(error)}`);
    } finally {
      uploadSubmit.disabled = uploadGroup.disabled;
    }
  });

  async function bootstrap() {
    await router.loadPortalConfig();
    const route = await router.restoreCachedTenant();
    if (route === null) {
      setOnlyPanel(classroomPanel);
      return;
    }
    await showLoginForTenant(route);
  }

  bootstrap().catch((error) => {
    setOnlyPanel(null);
    setMessage(fatal, `ポータルを開始できませんでした: ${errorMessage(error)}`);
  });
})();
