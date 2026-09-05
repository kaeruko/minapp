"use strict";

(function initGirlsPortalShell() {
  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const LOGIN_ID_KEY = "minapp_girls_portal_login_id";
  const CONFIG_PATH = "/girls-config.json";
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const PREVIEW_CONTENT_PATH_PATTERN = /^\/hosted\/preview\/[A-Za-z0-9_-]{32,128}\/index\.html$/;
  const VIEW_TITLES = Object.freeze({
    home: "ホーム",
    add: "アプリを追加",
    apps: "自分のアプリ",
    settings: "設定",
  });

  function requiredElement(id) {
    const element = document.getElementById(id);
    if (element === null) throw new Error(`#${id} was not found.`);
    return element;
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

  function requirePositiveInteger(value, label) {
    if (!Number.isInteger(value) || value < 1) {
      throw new Error(`${label} must be a positive integer.`);
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

  function setMessage(element, message) {
    if (message === null) {
      element.textContent = "";
      element.classList.add("hidden");
      return;
    }
    if (typeof message !== "string" || message.length === 0) {
      throw new TypeError("message must be null or a non-empty string.");
    }
    element.textContent = message;
    element.classList.remove("hidden");
  }

  function errorMessage(error) {
    if (error instanceof Error && error.message.length > 0) return error.message;
    return String(error);
  }

  const shell = requiredElement("girls-upload-panel");
  const nav = requiredElement("girls-shell-nav");
  const shellMenu = requiredElement("girls-shell-menu");
  const shellScrim = requiredElement("girls-shell-scrim");
  const shellTitle = requiredElement("girls-shell-title");
  const shellAvatar = requiredElement("girls-shell-avatar");
  const shellAccountName = requiredElement("girls-shell-account-name");
  const shellGroupName = requiredElement("girls-shell-group-name");
  const uploadGroup = requiredElement("girls-upload-group");
  const homeGroupSummary = requiredElement("girls-home-group-summary");
  const settingsLoginId = requiredElement("girls-settings-login-id");
  const settingsGroups = requiredElement("girls-settings-groups");
  const logoutButton = requiredElement("girls-logout");
  const settingsLogout = requiredElement("girls-settings-logout");
  const appsRefresh = requiredElement("girls-apps-refresh");
  const appsStatus = requiredElement("girls-apps-status");
  const appsError = requiredElement("girls-apps-error");
  const appList = requiredElement("girls-app-list");
  const previewPanel = requiredElement("girls-preview-panel");
  const previewTitle = requiredElement("girls-preview-title");
  const previewClose = requiredElement("girls-preview-close");
  const previewFrame = requiredElement("girls-preview-frame");
  const previewError = requiredElement("girls-preview-error");

  if (!(shell instanceof HTMLElement)) throw new Error("#girls-upload-panel must be an element.");
  if (!(nav instanceof HTMLElement)) throw new Error("#girls-shell-nav must be an element.");
  if (!(shellMenu instanceof HTMLButtonElement)) throw new Error("#girls-shell-menu must be a button.");
  if (!(shellScrim instanceof HTMLElement)) throw new Error("#girls-shell-scrim must be an element.");
  if (!(uploadGroup instanceof HTMLSelectElement)) throw new Error("#girls-upload-group must be a select.");
  if (!(logoutButton instanceof HTMLButtonElement)) throw new Error("#girls-logout must be a button.");
  if (!(settingsLogout instanceof HTMLButtonElement)) throw new Error("#girls-settings-logout must be a button.");
  if (!(appsRefresh instanceof HTMLButtonElement)) throw new Error("#girls-apps-refresh must be a button.");
  if (!(previewPanel instanceof HTMLElement)) throw new Error("#girls-preview-panel must be an element.");
  if (!(previewClose instanceof HTMLButtonElement)) throw new Error("#girls-preview-close must be a button.");
  if (!(previewFrame instanceof HTMLIFrameElement)) throw new Error("#girls-preview-frame must be an iframe.");

  let currentView = "home";
  let hostedApiBaseUrl = null;
  let appsLoadGeneration = 0;
  let previewGeneration = 0;
  let lastAuthenticated = null;

  function closeNavigation() {
    shell.classList.remove("portal-shell-nav-open");
    shellMenu.setAttribute("aria-expanded", "false");
  }

  function toggleNavigation() {
    const open = !shell.classList.contains("portal-shell-nav-open");
    shell.classList.toggle("portal-shell-nav-open", open);
    shellMenu.setAttribute("aria-expanded", String(open));
  }

  function closePreview() {
    previewGeneration += 1;
    previewFrame.removeAttribute("src");
    previewTitle.textContent = "アプリを確認";
    setMessage(previewError, null);
    previewPanel.classList.add("hidden");
  }

  function ownerGroups() {
    return [...uploadGroup.options].map((option) => {
      if (!ID_PATTERN.test(option.value)) {
        throw new Error("Girls portal received an invalid owner group id.");
      }
      if (option.textContent === null || option.textContent.trim().length === 0) {
        throw new Error("Girls portal received an owner group without a name.");
      }
      return { groupId: option.value, name: option.textContent.trim() };
    });
  }

  function syncGroupLabels() {
    const groups = ownerGroups();
    if (groups.length === 0) {
      shellGroupName.textContent = "グループなし";
      homeGroupSummary.textContent = "追加できるグループがありません";
      settingsGroups.textContent = "なし";
      return;
    }

    const selected = uploadGroup.selectedOptions[0];
    const selectedName = selected === undefined || selected.textContent === null
      ? groups[0].name
      : selected.textContent.trim();
    shellGroupName.textContent = selectedName;
    homeGroupSummary.textContent = groups.length === 1
      ? groups[0].name
      : `${selectedName} ほか${groups.length - 1}グループ`;
    settingsGroups.textContent = groups.map((group) => group.name).join(" / ");
  }

  function syncIdentity() {
    const loginId = sessionStorage.getItem(LOGIN_ID_KEY);
    if (loginId === null || loginId.length === 0) {
      shellAccountName.textContent = "Girls";
      settingsLoginId.textContent = "ログイン情報なし";
      shellAvatar.textContent = "♡";
      return;
    }
    shellAccountName.textContent = loginId;
    settingsLoginId.textContent = loginId;
    shellAvatar.textContent = loginId.slice(0, 1).toUpperCase() || "♡";
  }

  function syncAuthenticationChrome() {
    const authenticated = !shell.classList.contains("hidden");
    if (authenticated === lastAuthenticated) return;
    lastAuthenticated = authenticated;
    document.body.classList.toggle("girls-authenticated", authenticated);
    if (!authenticated) {
      closeNavigation();
      closePreview();
      return;
    }
    syncIdentity();
    syncGroupLabels();
    setView(currentView, { refreshApps: false });
  }

  function setView(view, options = {}) {
    if (!Object.hasOwn(VIEW_TITLES, view)) {
      throw new Error(`Unsupported Girls portal view: ${String(view)}`);
    }
    currentView = view;
    shellTitle.textContent = VIEW_TITLES[view];

    for (const panel of document.querySelectorAll("[data-girls-panel]")) {
      if (!(panel instanceof HTMLElement)) throw new Error("Girls view panel must be an element.");
      panel.classList.toggle("girls-view-hidden", panel.dataset.girlsPanel !== view);
    }
    for (const button of nav.querySelectorAll("[data-girls-view]")) {
      if (!(button instanceof HTMLButtonElement)) throw new Error("Girls navigation item must be a button.");
      const active = button.dataset.girlsView === view;
      button.classList.toggle("portal-shell-nav-item-active", active);
      if (active) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    }
    closeNavigation();
    if (view !== "apps") closePreview();

    if (view === "apps" && options.refreshApps !== false) {
      void loadMyApps();
    }
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
      throw new Error("girls-config hosted_api_base_url must be an HTTPS origin.");
    }
    return url.origin;
  }

  async function loadHostedApiBaseUrl() {
    if (hostedApiBaseUrl !== null) return hostedApiBaseUrl;
    const response = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    if (!response.ok) throw new Error(`Girls config request failed: HTTP ${response.status}`);
    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new Error("Girls config returned a non-JSON response.");
    }
    const payload = requirePlainObject(await response.json(), "Girls config response");
    const keys = Object.keys(payload).sort();
    if (keys.length !== 2 || keys[0] !== "hosted_api_base_url" || keys[1] !== "schema_version") {
      throw new Error("Girls config fields are invalid.");
    }
    if (payload.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
    }
    hostedApiBaseUrl = validateApiBaseUrl(payload.hosted_api_base_url);
    return hostedApiBaseUrl;
  }

  async function decodeHostedJsonResponse(response) {
    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new Error(`Girls API returned a non-JSON response (HTTP ${response.status}).`);
    }
    const payload = requirePlainObject(await response.json(), "Girls API response");
    if (!response.ok) {
      const message = typeof payload.message === "string" && payload.message.length > 0
        ? payload.message
        : `Girls API request failed: HTTP ${response.status}`;
      const error = new Error(message);
      error.status = response.status;
      throw error;
    }
    return payload;
  }

  async function hostedRequest(path, method) {
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new Error("ログイン情報がありません。もう一度ログインしてください。");
    }
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Girls API path must be origin-relative.");
    }
    if (method !== "GET" && method !== "POST") {
      throw new TypeError(`Unsupported Girls API method: ${String(method)}`);
    }
    const baseUrl = await loadHostedApiBaseUrl();
    const url = new URL(path, `${baseUrl}/`);
    if (url.origin !== baseUrl) throw new Error("Girls API path escaped the configured origin.");

    const headers = {
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    };
    const options = {
      method,
      headers,
      cache: "no-store",
      credentials: "omit",
    };
    if (method === "POST") {
      headers["Content-Type"] = "application/json";
      options.body = "{}";
    }
    const response = await fetch(url.toString(), options);
    return await decodeHostedJsonResponse(response);
  }

  async function hostedGet(path) {
    return await hostedRequest(path, "GET");
  }

  async function hostedPostEmpty(path) {
    return await hostedRequest(path, "POST");
  }

  function validateGroupAppsPayload(payload, group) {
    const keys = Object.keys(payload);
    if (keys.length !== 1 || keys[0] !== "apps") {
      throw new Error(`Hosted apps response for ${group.name} has invalid fields.`);
    }
    if (!Array.isArray(payload.apps)) {
      throw new Error(`Hosted apps response for ${group.name} has no apps list.`);
    }
    return payload.apps.map((rawApp) => {
      const app = requirePlainObject(rawApp, "Hosted app");
      for (const field of ["app_id", "group_id", "title", "source_kind", "created_at"]) {
        if (!(field in app)) throw new Error(`Hosted app is missing field: ${field}`);
      }
      if (!ID_PATTERN.test(app.app_id)) throw new Error("Hosted app has an invalid app_id.");
      if (app.group_id !== group.groupId) throw new Error("Hosted app group_id mismatch.");
      requireString(app.title, "Hosted app title");
      requireString(app.created_at, "Hosted app created_at");
      const publishedVersion = app.published_version;
      if (publishedVersion !== null && publishedVersion !== undefined &&
          (!Number.isInteger(publishedVersion) || publishedVersion < 1)) {
        throw new Error("Hosted app has an invalid published_version.");
      }
      return {
        appId: app.app_id,
        groupId: group.groupId,
        title: app.title,
        groupName: group.name,
        createdAt: app.created_at,
        published: Number.isInteger(publishedVersion) && publishedVersion >= 1,
      };
    });
  }

  async function openPreview(app, triggerButton) {
    if (!ID_PATTERN.test(app.appId) || !ID_PATTERN.test(app.groupId)) {
      throw new Error("Girls preview received an invalid app or group id.");
    }
    if (!(triggerButton instanceof HTMLButtonElement)) {
      throw new TypeError("Girls preview trigger must be a button.");
    }

    const generation = ++previewGeneration;
    setMessage(previewError, null);
    previewTitle.textContent = `${app.title}を確認`;
    previewFrame.removeAttribute("src");
    previewPanel.classList.remove("hidden");
    triggerButton.disabled = true;
    const originalLabel = triggerButton.textContent;
    triggerButton.textContent = "読み込み中…";

    try {
      const payload = await hostedPostEmpty(`/hosted/my/apps/${app.appId}/preview-session`);
      if (generation !== previewGeneration) return;
      requireExactFields(
        payload,
        ["app_id", "group_id", "source_revision", "content_path", "expires_in"],
        "Draft preview session response",
      );
      if (requireString(payload.app_id, "preview app_id") !== app.appId) {
        throw new Error("Preview session returned a different app_id.");
      }
      if (requireString(payload.group_id, "preview group_id") !== app.groupId) {
        throw new Error("Preview session returned a different group_id.");
      }
      requirePositiveInteger(payload.source_revision, "preview source_revision");
      requirePositiveInteger(payload.expires_in, "preview expires_in");
      const contentPath = requireString(payload.content_path, "preview content_path");
      if (!PREVIEW_CONTENT_PATH_PATTERN.test(contentPath)) {
        throw new Error("Preview session returned an invalid content path.");
      }
      const baseUrl = await loadHostedApiBaseUrl();
      if (generation !== previewGeneration) return;
      const previewUrl = new URL(contentPath, `${baseUrl}/`);
      if (previewUrl.origin !== baseUrl) {
        throw new Error("Preview URL escaped the configured Girls API origin.");
      }
      previewFrame.src = previewUrl.toString();
      previewPanel.scrollIntoView({ behavior: "smooth", block: "start" });
    } catch (error) {
      if (generation !== previewGeneration) return;
      previewFrame.removeAttribute("src");
      setMessage(previewError, errorMessage(error));
      if (error instanceof Error && error.status === 401) {
        logoutButton.click();
      }
    } finally {
      triggerButton.disabled = false;
      triggerButton.textContent = originalLabel;
    }
  }

  function renderApps(apps) {
    appList.replaceChildren();
    for (const app of apps) {
      const card = document.createElement("article");
      card.className = "girls-app-card";

      const heading = document.createElement("div");
      heading.className = "girls-app-card-heading";
      const title = document.createElement("h3");
      title.textContent = app.title;
      const previewButton = document.createElement("button");
      previewButton.className = "girls-secondary girls-app-preview-button";
      previewButton.type = "button";
      previewButton.textContent = "プレビュー";
      previewButton.addEventListener("click", () => void openPreview(app, previewButton));
      heading.append(title, previewButton);

      const group = document.createElement("p");
      group.textContent = app.groupName;

      const meta = document.createElement("div");
      meta.className = "girls-app-card-meta";
      const status = document.createElement("span");
      status.className = `girls-app-chip ${app.published ? "girls-app-chip-published" : "girls-app-chip-draft"}`;
      status.textContent = app.published ? "公開中" : "下書き";
      const date = document.createElement("span");
      date.className = "girls-app-chip";
      const parsedDate = new Date(app.createdAt);
      if (Number.isNaN(parsedDate.getTime())) throw new Error("Hosted app created_at is invalid.");
      date.textContent = parsedDate.toLocaleDateString("ja-JP");
      meta.append(status, date);

      card.append(heading, group, meta);
      appList.append(card);
    }
  }

  async function loadMyApps() {
    const generation = ++appsLoadGeneration;
    closePreview();
    setMessage(appsError, null);
    appsRefresh.disabled = true;
    appsStatus.textContent = "アプリを読み込み中…";
    appList.replaceChildren();

    try {
      const groups = ownerGroups();
      if (groups.length === 0) {
        appsStatus.textContent = "自分がオーナーのグループがまだありません。Girlsアプリでグループを作ってね。";
        return;
      }
      const results = await Promise.all(groups.map(async (group) => {
        const payload = await hostedGet(`/hosted/groups/${group.groupId}/apps`);
        return validateGroupAppsPayload(payload, group);
      }));
      if (generation !== appsLoadGeneration) return;
      const apps = results.flat();
      apps.sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));
      renderApps(apps);
      appsStatus.textContent = apps.length === 0
        ? "まだ追加したアプリはありません。"
        : `${apps.length}個のアプリがあります。`;
    } catch (error) {
      if (generation !== appsLoadGeneration) return;
      setMessage(appsError, errorMessage(error));
      appsStatus.textContent = "アプリを読み込めませんでした。";
      if (error instanceof Error && error.status === 401) {
        logoutButton.click();
      }
    } finally {
      if (generation === appsLoadGeneration) appsRefresh.disabled = false;
    }
  }

  for (const button of nav.querySelectorAll("[data-girls-view]")) {
    if (!(button instanceof HTMLButtonElement)) throw new Error("Girls navigation item must be a button.");
    button.addEventListener("click", () => setView(button.dataset.girlsView));
  }
  for (const button of document.querySelectorAll("[data-girls-open-view]")) {
    if (!(button instanceof HTMLButtonElement)) throw new Error("Girls quick navigation item must be a button.");
    button.addEventListener("click", () => setView(button.dataset.girlsOpenView));
  }

  shellMenu.addEventListener("click", toggleNavigation);
  shellScrim.addEventListener("click", closeNavigation);
  uploadGroup.addEventListener("change", syncGroupLabels);
  settingsLogout.addEventListener("click", () => logoutButton.click());
  appsRefresh.addEventListener("click", () => void loadMyApps());
  previewClose.addEventListener("click", closePreview);

  new MutationObserver(syncGroupLabels).observe(uploadGroup, { childList: true });
  new MutationObserver(syncAuthenticationChrome).observe(shell, {
    attributes: true,
    attributeFilter: ["class"],
  });

  setView("home", { refreshApps: false });
  syncAuthenticationChrome();
})();