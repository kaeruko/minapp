"use strict";

(function initGirlsFooter() {
  const CONFIG_PATH = "/girls-config.json";

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

    return url.origin;
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
      const message = typeof payload.message === "string" && payload.message.length > 0
        ? payload.message
        : `HTTP ${response.status}`;
      throw new Error(`${label} failed: ${message}`);
    }
    return payload;
  }

  async function loadPrivacy() {
    const configResponse = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    const config = await decodeJsonResponse(configResponse, "Girls config");
    if (config.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(config.schema_version)}`);
    }

    const apiBaseUrl = validateApiBaseUrl(config.hosted_api_base_url);
    const legalResponse = await fetch(`${apiBaseUrl}/hosted/legal`, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "omit",
    });
    const legal = await decodeJsonResponse(legalResponse, "Girls legal documents");
    const privacy = requirePlainObject(legal.privacy, "Girls legal privacy");

    return {
      title: requireString(privacy.title, "Girls legal privacy title"),
      body: requireString(privacy.body, "Girls legal privacy body"),
    };
  }

  const privacyButton = requiredElement("girls-footer-privacy");
  const dialog = requiredElement("girls-privacy-dialog");
  const closeButton = requiredElement("girls-privacy-close");
  const title = requiredElement("girls-privacy-title");
  const status = requiredElement("girls-privacy-status");
  const body = requiredElement("girls-privacy-body");

  if (!(privacyButton instanceof HTMLButtonElement)) throw new Error("#girls-footer-privacy must be a button.");
  if (!(dialog instanceof HTMLDialogElement)) throw new Error("#girls-privacy-dialog must be a dialog.");
  if (!(closeButton instanceof HTMLButtonElement)) throw new Error("#girls-privacy-close must be a button.");

  closeButton.addEventListener("click", () => dialog.close());

  privacyButton.addEventListener("click", async () => {
    title.textContent = "プライバシーポリシー";
    status.textContent = "読み込んでいます…";
    status.classList.remove("hidden", "girls-privacy-error");
    body.textContent = "";
    body.classList.add("hidden");

    if (!dialog.open) dialog.showModal();

    privacyButton.disabled = true;
    try {
      const privacy = await loadPrivacy();
      title.textContent = privacy.title;
      body.textContent = privacy.body;
      status.classList.add("hidden");
      body.classList.remove("hidden");
    } catch (error) {
      status.textContent = error instanceof Error ? error.message : String(error);
      status.classList.add("girls-privacy-error");
      status.classList.remove("hidden");
      body.classList.add("hidden");
    } finally {
      privacyButton.disabled = false;
    }
  });
})();

(function initGirlsAppManagementActions() {
  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const CONFIG_PATH = "/girls-config.json";
  const NO_IMAGE_URL = "/girls-assets/no_image.svg";
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const DATE_LABEL_PATTERN = /^\d{4}\/\d{1,2}\/\d{1,2}$/;

  const appList = document.getElementById("girls-app-list");
  const appsStatus = document.getElementById("girls-apps-status");
  const appsError = document.getElementById("girls-apps-error");
  const appsRefresh = document.getElementById("girls-apps-refresh");
  const logoutButton = document.getElementById("girls-logout");
  const previewPanel = document.getElementById("girls-preview-panel");
  const previewClose = document.getElementById("girls-preview-close");

  for (const [value, label, ctor] of [
    [appList, "#girls-app-list", HTMLElement],
    [appsStatus, "#girls-apps-status", HTMLElement],
    [appsError, "#girls-apps-error", HTMLElement],
    [appsRefresh, "#girls-apps-refresh", HTMLButtonElement],
    [logoutButton, "#girls-logout", HTMLButtonElement],
    [previewPanel, "#girls-preview-panel", HTMLElement],
    [previewClose, "#girls-preview-close", HTMLButtonElement],
  ]) {
    if (!(value instanceof ctor)) throw new Error(`${label} has an unexpected type.`);
  }

  let apiBaseUrl = null;
  let decorateScheduled = false;
  let decorateGeneration = 0;

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

  function optionalThumbnailUrl(value, label) {
    if (value === undefined || value === null) return null;
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error(`${label} must be null or a non-empty URL string.`);
    }

    let url;
    try {
      url = new URL(value, globalThis.location.origin);
    } catch (error) {
      throw new Error(`${label} is not a valid URL.`, { cause: error });
    }

    const isSameOrigin = url.origin === globalThis.location.origin;
    if (!isSameOrigin && url.protocol !== "https:") {
      throw new Error(`${label} must be same-origin or HTTPS.`);
    }
    return url.toString();
  }

  function setError(message) {
    if (message === null) {
      appsError.textContent = "";
      appsError.classList.add("hidden");
      return;
    }
    appsError.textContent = message;
    appsError.classList.remove("hidden");
  }

  function errorMessage(error) {
    return error instanceof Error && error.message.length > 0 ? error.message : String(error);
  }

  function validateApiBaseUrl(value) {
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error("girls-config hosted_api_base_url is invalid.");
    }
    const url = new URL(value);
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

  async function getApiBaseUrl() {
    if (apiBaseUrl !== null) return apiBaseUrl;
    const response = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    if (!response.ok) throw new Error(`Girls config request failed: HTTP ${response.status}`);
    const payload = requirePlainObject(await response.json(), "Girls config response");
    if (payload.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
    }
    apiBaseUrl = validateApiBaseUrl(payload.hosted_api_base_url);
    return apiBaseUrl;
  }

  async function apiRequest(path, options = {}) {
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Girls app management path must be origin-relative.");
    }
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new Error("ログイン情報がありません。もう一度ログインしてください。");
    }
    const baseUrl = await getApiBaseUrl();
    const url = new URL(path, `${baseUrl}/`);
    if (url.origin !== baseUrl) throw new Error("Girls app management path escaped the configured origin.");

    const headers = new Headers({
      Accept: "application/json",
      Authorization: `Bearer ${token}`,
    });
    let body;
    if (options.jsonBody !== undefined) {
      headers.set("Content-Type", "application/json");
      body = JSON.stringify(options.jsonBody);
    }
    const response = await fetch(url.toString(), {
      method: options.method ?? "GET",
      headers,
      body,
      cache: "no-store",
      credentials: "omit",
    });

    if (response.status === 401) {
      logoutButton.click();
      throw new Error("ログインの有効期限が切れました。もう一度ログインしてください。");
    }
    if (response.status === 204) return null;

    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new Error(`Girls app management returned a non-JSON response (HTTP ${response.status}).`);
    }
    const payload = requirePlainObject(await response.json(), "Girls app management response");
    if (!response.ok) {
      const message = typeof payload.message === "string" && payload.message.length > 0
        ? payload.message
        : `HTTP ${response.status}`;
      throw new Error(message);
    }
    return payload;
  }

  async function loadAppMetadata() {
    const managedPayload = await apiRequest("/hosted/my/apps");
    const keys = Object.keys(managedPayload);
    if (keys.length !== 1 || keys[0] !== "apps" || !Array.isArray(managedPayload.apps)) {
      throw new Error("Managed Girls apps response has invalid fields.");
    }
    const allowedFields = new Set([
      "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
      "builtin_id", "builtin_asset_path", "parent_app_id", "source_sha256",
      "source_updated_at", "published_sha256", "published_at", "deletion_state",
      "builtin_version", "source_revision", "published_version", "editable",
      "visibility", "stats", "group_name",
    ]);
    const apps = [];
    const managedById = new Map();
    for (const rawManaged of managedPayload.apps) {
      const managed = requirePlainObject(rawManaged, "Managed Girls app");
      const actual = Object.keys(managed);
      for (const field of [
        "app_id", "group_id", "owner_user_id", "title", "source_kind", "created_at",
        "editable", "visibility", "stats", "group_name",
      ]) {
        if (!actual.includes(field)) throw new Error(`Managed Girls app is missing field: ${field}`);
      }
      for (const field of actual) {
        if (!allowedFields.has(field)) throw new Error(`Managed Girls app contained unexpected field: ${field}`);
      }
      if (!ID_PATTERN.test(managed.app_id)) throw new Error("Managed Girls app has an invalid app_id.");
      if (!ID_PATTERN.test(managed.group_id)) throw new Error("Managed Girls app has an invalid group_id.");
      if (!ID_PATTERN.test(managed.owner_user_id)) throw new Error("Managed Girls app has an invalid owner_user_id.");
      if (managed.visibility !== "visible" && managed.visibility !== "hidden") {
        throw new Error("Managed Girls app has an invalid visibility state.");
      }
      if (typeof managed.editable !== "boolean") throw new Error("Managed Girls app has invalid editable.");
      const title = requireString(managed.title, "Managed Girls app title");
      const groupName = requireString(managed.group_name, "Managed Girls app group_name");
      const createdAt = requireString(managed.created_at, "Managed Girls app created_at");
      const parsedDate = new Date(createdAt);
      if (Number.isNaN(parsedDate.getTime())) throw new Error("Managed Girls app created_at is invalid.");
      requirePlainObject(managed.stats, "Managed Girls app stats");
      const app = {
        appId: managed.app_id,
        groupId: managed.group_id,
        ownerUserId: managed.owner_user_id,
        groupName,
        title,
        dateLabel: parsedDate.toLocaleDateString("ja-JP"),
        thumbnailUrl: optionalThumbnailUrl(managed.thumbnail_url, "Managed Girls app thumbnail_url"),
      };
      apps.push(app);
      managedById.set(managed.app_id, {
        appId: managed.app_id,
        visibility: managed.visibility,
        thumbnailUrl: app.thumbnailUrl,
      });
    }
    return { apps, managedById };
  }

  function cardIdentity(card) {
    const title = card.querySelector("h3");
    const group = card.querySelector("p");
    const chips = [...card.querySelectorAll(".girls-app-card-meta .girls-app-chip")];
    const date = chips.find((chip) => DATE_LABEL_PATTERN.test(chip.textContent?.trim() ?? ""));
    if (!(title instanceof HTMLElement) || !(group instanceof HTMLElement) || !(date instanceof HTMLElement)) {
      throw new Error("Girls app card is missing title, group, or date metadata.");
    }
    return {
      title: title.textContent?.trim() ?? "",
      groupName: group.textContent?.trim() ?? "",
      dateLabel: date.textContent?.trim() ?? "",
    };
  }

  function setVisibilityChip(card, hidden) {
    const meta = card.querySelector(".girls-app-card-meta");
    if (!(meta instanceof HTMLElement)) throw new Error("Girls app card metadata row was not found.");
    const existing = meta.querySelector(".girls-app-hidden-chip");
    if (!hidden) {
      existing?.remove();
      return;
    }
    const chip = existing ?? document.createElement("span");
    chip.className = "girls-app-chip girls-app-hidden-chip";
    chip.textContent = "非表示";
    if (existing === null) meta.append(chip);
  }

  function createThumbnail(app) {
    const media = document.createElement("div");
    media.className = "girls-app-card-media";

    const image = document.createElement("img");
    image.className = "girls-app-card-thumbnail";
    image.loading = "lazy";
    image.decoding = "async";
    image.referrerPolicy = "no-referrer";

    const hasThumbnail = app.thumbnailUrl !== null;
    image.src = hasThumbnail ? app.thumbnailUrl : NO_IMAGE_URL;
    image.alt = hasThumbnail ? `${app.title}のサムネイル` : "";
    image.dataset.thumbnailState = hasThumbnail ? "custom" : "no-image";

    let fallbackApplied = !hasThumbnail;
    image.addEventListener("error", () => {
      if (fallbackApplied) {
        console.error(`No Image asset failed to load for app ${app.appId}.`);
        return;
      }
      fallbackApplied = true;
      console.error(`Thumbnail failed to load for app ${app.appId}; showing No Image.`);
      image.src = NO_IMAGE_URL;
      image.alt = "";
      image.dataset.thumbnailState = "no-image";
    });

    media.append(image);
    return media;
  }

  function installCardLayout(card, app) {
    if (card.querySelector(":scope > .girls-app-card-body") !== null) {
      throw new Error("Girls app card layout was already installed.");
    }
    const body = document.createElement("div");
    body.className = "girls-app-card-body";
    while (card.firstChild !== null) body.append(card.firstChild);
    card.append(createThumbnail(app), body);
  }

  async function toggleVisibility(app, managed, button, card) {
    const hide = managed.visibility !== "hidden";
    button.disabled = true;
    setError(null);
    try {
      const payload = await apiRequest(`/hosted/my/apps/${app.appId}/visibility`, {
        method: "POST",
        jsonBody: { hidden: hide },
      });
      if (payload.app_id !== app.appId) throw new Error("Visibility response app_id mismatch.");
      if (payload.visibility !== "visible" && payload.visibility !== "hidden") {
        throw new Error("Visibility response has an invalid state.");
      }
      managed.visibility = payload.visibility;
      const hidden = managed.visibility === "hidden";
      button.textContent = hidden ? "再表示" : "非表示";
      button.setAttribute("aria-pressed", String(hidden));
      setVisibilityChip(card, hidden);
      appsStatus.textContent = hidden
        ? `「${app.title}」を非表示にしました。`
        : `「${app.title}」を再表示しました。`;
    } catch (error) {
      setError(`表示設定を変更できませんでした: ${errorMessage(error)}`);
    } finally {
      button.disabled = false;
    }
  }

  async function deleteApp(app, button) {
    const confirmed = globalThis.confirm(`「${app.title}」を削除しますか？\nこの操作は取り消せません。`);
    if (!confirmed) return;
    button.disabled = true;
    setError(null);
    try {
      const payload = await apiRequest(`/hosted/groups/${app.groupId}/apps/${app.appId}`, {
        method: "DELETE",
      });
      if (payload !== null) throw new Error("Delete response must be empty.");
      if (!previewPanel.classList.contains("hidden")) previewClose.click();
      appsStatus.textContent = `「${app.title}」を削除しました。`;
      appsRefresh.click();
    } catch (error) {
      setError(`アプリを削除できませんでした: ${errorMessage(error)}`);
      button.disabled = false;
    }
  }

  function decorateCard(card, app, managed) {
    card.dataset.girlsAppId = app.appId;
    const heading = card.querySelector(".girls-app-card-heading");
    const previewButton = card.querySelector(".girls-app-preview-button");
    if (!(heading instanceof HTMLElement) || !(previewButton instanceof HTMLButtonElement)) {
      throw new Error("Girls app card action area was not found.");
    }

    const actions = document.createElement("div");
    actions.className = "girls-app-card-actions";
    previewButton.remove();
    actions.append(previewButton);

    if (managed !== undefined) {
      const visibilityButton = document.createElement("button");
      visibilityButton.className = "girls-secondary girls-app-visibility-button";
      visibilityButton.type = "button";
      const hidden = managed.visibility === "hidden";
      visibilityButton.textContent = hidden ? "再表示" : "非表示";
      visibilityButton.setAttribute("aria-pressed", String(hidden));
      visibilityButton.addEventListener("click", () => void toggleVisibility(app, managed, visibilityButton, card));
      actions.append(visibilityButton);
      setVisibilityChip(card, hidden);
    }

    const deleteButton = document.createElement("button");
    deleteButton.className = "girls-secondary girls-app-delete-button";
    deleteButton.type = "button";
    deleteButton.textContent = "削除";
    deleteButton.addEventListener("click", () => void deleteApp(app, deleteButton));
    actions.append(deleteButton);
    card.append(actions);

    const thumbnailUrl = app.thumbnailUrl ?? managed?.thumbnailUrl ?? null;
    installCardLayout(card, { ...app, thumbnailUrl });
  }

  async function decorateCards() {
    const cards = [...appList.children].filter((child) => child instanceof HTMLElement && child.classList.contains("girls-app-card"));
    if (cards.length === 0) return;
    if (cards.every((card) => ID_PATTERN.test(card.dataset.girlsAppId ?? ""))) return;

    const generation = ++decorateGeneration;
    try {
      const { apps, managedById } = await loadAppMetadata();
      if (generation !== decorateGeneration) return;
      const used = new Set();

      for (const card of cards) {
        const existingId = card.dataset.girlsAppId ?? "";
        if (ID_PATTERN.test(existingId)) {
          used.add(existingId);
          continue;
        }

        const identity = cardIdentity(card);
        const matches = apps.filter((app) =>
          !used.has(app.appId) &&
          app.title === identity.title &&
          app.groupName === identity.groupName &&
          app.dateLabel === identity.dateLabel
        );
        if (matches.length !== 1) {
          throw new Error(`「${identity.title}」の管理対象を一意に特定できませんでした。`);
        }
        const app = matches[0];
        used.add(app.appId);
        decorateCard(card, app, managedById.get(app.appId));
      }
    } catch (error) {
      if (generation === decorateGeneration) {
        setError(`アプリ管理ボタンを表示できませんでした: ${errorMessage(error)}`);
      }
    }
  }

  function scheduleDecorate() {
    if (decorateScheduled) return;
    decorateScheduled = true;
    queueMicrotask(() => {
      decorateScheduled = false;
      void decorateCards();
    });
  }

  new MutationObserver(scheduleDecorate).observe(appList, { childList: true });
  appsRefresh.addEventListener("click", () => {
    decorateGeneration += 1;
  });
  scheduleDecorate();
})();

(function initGirlsThumbnailEditor() {
  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const CONFIG_PATH = "/girls-config.json";
  const NO_IMAGE_URL = "/girls-assets/no_image.svg";
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const ACCEPTED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"]);
  const MAX_STORED_BYTES = 192 * 1024;
  const MAX_INPUT_BYTES = 12 * 1024 * 1024;

  const appList = document.getElementById("girls-app-list");
  const logoutButton = document.getElementById("girls-logout");
  if (!(appList instanceof HTMLElement)) throw new Error("#girls-app-list has an unexpected type.");
  if (!(logoutButton instanceof HTMLButtonElement)) throw new Error("#girls-logout has an unexpected type.");

  const style = document.createElement("style");
  style.textContent = `
    .girls-app-thumbnail-editor {
      display: grid;
      gap: 6px;
      margin-top: 8px;
    }
    .girls-app-thumbnail-picker,
    .girls-app-thumbnail-save {
      display: grid;
      width: 100%;
      min-height: 30px;
      place-items: center;
      padding: 5px 8px;
      border: 1px solid #d8b9df;
      border-radius: 999px;
      background: #fff9fd;
      color: #765a8e;
      font: inherit;
      font-size: 0.66rem;
      font-weight: 800;
      line-height: 1.2;
      text-align: center;
      cursor: pointer;
    }
    .girls-app-thumbnail-picker:hover,
    .girls-app-thumbnail-picker:focus-within,
    .girls-app-thumbnail-save:hover:not(:disabled),
    .girls-app-thumbnail-save:focus-visible:not(:disabled) {
      border-color: #bc93c9;
      background: #f9effb;
      outline: none;
    }
    .girls-app-thumbnail-picker input {
      position: absolute;
      width: 1px;
      height: 1px;
      overflow: hidden;
      clip: rect(0 0 0 0);
      clip-path: inset(50%);
      white-space: nowrap;
    }
    .girls-app-thumbnail-save:disabled {
      cursor: default;
      opacity: 0.46;
    }
    .girls-app-thumbnail-status {
      min-height: 1.3em;
      margin: 0;
      color: #8e7482;
      font-size: 0.58rem;
      font-weight: 700;
      line-height: 1.3;
      text-align: center;
    }
    .girls-app-thumbnail-status[data-state="error"] {
      color: #aa4d63;
    }
    .girls-app-thumbnail-status[data-state="success"] {
      color: #4d7c58;
    }
    @media (max-width: 560px) {
      .girls-app-thumbnail-editor {
        grid-template-columns: minmax(0, 1fr) minmax(90px, 0.35fr);
        align-items: center;
      }
      .girls-app-thumbnail-status {
        grid-column: 1 / -1;
        text-align: left;
      }
    }
  `;
  document.head.append(style);

  let apiBaseUrl = null;
  let decorateScheduled = false;
  const objectUrls = new Map();
  const cardState = new WeakMap();

  function errorMessage(error) {
    return error instanceof Error && error.message.length > 0 ? error.message : String(error);
  }

  function validateApiBaseUrl(value) {
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error("girls-config hosted_api_base_url is invalid.");
    }
    const url = new URL(value);
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

  async function getApiBaseUrl() {
    if (apiBaseUrl !== null) return apiBaseUrl;
    const response = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    if (!response.ok) throw new Error(`Girls config request failed: HTTP ${response.status}`);
    const payload = await response.json();
    if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
      throw new Error("Girls config response must be an object.");
    }
    if (payload.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
    }
    apiBaseUrl = validateApiBaseUrl(payload.hosted_api_base_url);
    return apiBaseUrl;
  }

  async function authenticatedFetch(path, options = {}) {
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Girls thumbnail path must be origin-relative.");
    }
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new Error("ログイン情報がありません。もう一度ログインしてください。");
    }
    const baseUrl = await getApiBaseUrl();
    const url = new URL(path, `${baseUrl}/`);
    if (url.origin !== baseUrl) throw new Error("Girls thumbnail path escaped the configured origin.");

    const headers = new Headers(options.headers ?? {});
    headers.set("Authorization", `Bearer ${token}`);
    const response = await fetch(url.toString(), {
      method: options.method ?? "GET",
      headers,
      body: options.body,
      cache: "no-store",
      credentials: "omit",
    });
    if (response.status === 401) {
      logoutButton.click();
      throw new Error("ログインの有効期限が切れました。もう一度ログインしてください。");
    }
    return response;
  }

  async function responseError(response) {
    const contentType = response.headers.get("content-type") ?? "";
    if (contentType.toLowerCase().startsWith("application/json")) {
      const payload = await response.json();
      if (typeof payload === "object" && payload !== null && !Array.isArray(payload)) {
        if (typeof payload.message === "string" && payload.message.length > 0) return payload.message;
      }
    }
    return `HTTP ${response.status}`;
  }

  function setStatus(element, message, state = "idle") {
    element.textContent = message;
    element.dataset.state = state;
  }

  function releaseObjectUrl(appId) {
    const previous = objectUrls.get(appId);
    if (previous !== undefined) {
      URL.revokeObjectURL(previous);
      objectUrls.delete(appId);
    }
  }

  function setNoImage(appId, image) {
    releaseObjectUrl(appId);
    image.src = NO_IMAGE_URL;
    image.alt = "";
    image.dataset.thumbnailState = "no-image";
  }

  function setBlobImage(appId, image, blob, alt, state) {
    releaseObjectUrl(appId);
    const url = URL.createObjectURL(blob);
    objectUrls.set(appId, url);
    image.src = url;
    image.alt = alt;
    image.dataset.thumbnailState = state;
  }

  async function loadSavedThumbnail(appId, image) {
    const response = await authenticatedFetch(`/hosted/my/apps/${appId}/thumbnail`, {
      headers: { Accept: "image/avif,image/webp,image/png,image/jpeg,*/*;q=0.8" },
    });
    if (response.status === 404) {
      setNoImage(appId, image);
      return false;
    }
    if (!response.ok) throw new Error(await responseError(response));

    const contentType = (response.headers.get("content-type") ?? "").split(";", 1)[0].trim().toLowerCase();
    if (!ACCEPTED_TYPES.has(contentType)) {
      throw new Error(`サムネイルAPIが未対応の形式を返しました: ${contentType || "不明"}`);
    }
    const blob = await response.blob();
    if (blob.size === 0 || blob.size > MAX_STORED_BYTES) {
      throw new Error("保存済みサムネイルのサイズが不正です。");
    }
    setBlobImage(appId, image, blob, "アプリのサムネイル", "custom");
    return true;
  }

  async function decodeImage(file) {
    const url = URL.createObjectURL(file);
    try {
      const image = new Image();
      image.decoding = "async";
      const loaded = new Promise((resolve, reject) => {
        image.addEventListener("load", resolve, { once: true });
        image.addEventListener("error", () => reject(new Error("画像を読み込めませんでした。")), { once: true });
      });
      image.src = url;
      await loaded;
      if (image.naturalWidth < 1 || image.naturalHeight < 1) {
        throw new Error("画像のサイズを確認できませんでした。");
      }
      return image;
    } finally {
      URL.revokeObjectURL(url);
    }
  }

  function canvasToBlob(canvas, contentType, quality) {
    return new Promise((resolve, reject) => {
      canvas.toBlob((blob) => {
        if (!(blob instanceof Blob)) {
          reject(new Error("サムネイル画像を圧縮できませんでした。"));
          return;
        }
        resolve(blob);
      }, contentType, quality);
    });
  }

  async function prepareThumbnail(file) {
    if (!(file instanceof File)) throw new TypeError("Thumbnail selection must be a File.");
    if (!ACCEPTED_TYPES.has(file.type)) {
      throw new Error("JPEG・PNG・WebPの画像を選んでください。");
    }
    if (file.size < 1 || file.size > MAX_INPUT_BYTES) {
      throw new Error("元画像は12MB以下にしてください。");
    }

    const source = await decodeImage(file);
    const attempts = [
      { width: 640, height: 480, qualities: [0.86, 0.76, 0.66, 0.56] },
      { width: 480, height: 360, qualities: [0.76, 0.64, 0.52] },
      { width: 360, height: 270, qualities: [0.64, 0.5] },
    ];

    for (const attempt of attempts) {
      const canvas = document.createElement("canvas");
      canvas.width = attempt.width;
      canvas.height = attempt.height;
      const context = canvas.getContext("2d", { alpha: false });
      if (context === null) throw new Error("画像処理用のCanvasを作成できませんでした。");
      context.fillStyle = "#fffafd";
      context.fillRect(0, 0, canvas.width, canvas.height);

      const scale = Math.max(canvas.width / source.naturalWidth, canvas.height / source.naturalHeight);
      const drawWidth = source.naturalWidth * scale;
      const drawHeight = source.naturalHeight * scale;
      const dx = (canvas.width - drawWidth) / 2;
      const dy = (canvas.height - drawHeight) / 2;
      context.drawImage(source, dx, dy, drawWidth, drawHeight);

      for (const quality of attempt.qualities) {
        let blob = await canvasToBlob(canvas, "image/webp", quality);
        if (!ACCEPTED_TYPES.has(blob.type)) {
          blob = await canvasToBlob(canvas, "image/jpeg", quality);
        }
        if (ACCEPTED_TYPES.has(blob.type) && blob.size > 0 && blob.size <= MAX_STORED_BYTES) {
          return blob;
        }
      }
    }
    throw new Error("画像を192KB以下に圧縮できませんでした。別の画像を選んでください。");
  }

  function installEditor(card) {
    if (card.dataset.girlsThumbnailEditor === "ready") return;
    const appId = card.dataset.girlsAppId ?? "";
    if (!ID_PATTERN.test(appId)) return;
    const media = card.querySelector(".girls-app-card-media");
    const image = card.querySelector(".girls-app-card-thumbnail");
    const title = card.querySelector("h3")?.textContent?.trim() ?? "アプリ";
    if (!(media instanceof HTMLElement) || !(image instanceof HTMLImageElement)) return;

    card.dataset.girlsThumbnailEditor = "ready";
    const editor = document.createElement("div");
    editor.className = "girls-app-thumbnail-editor";

    const picker = document.createElement("label");
    picker.className = "girls-app-thumbnail-picker";
    picker.textContent = "画像を選ぶ";
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "image/jpeg,image/png,image/webp";
    picker.append(input);

    const save = document.createElement("button");
    save.className = "girls-app-thumbnail-save";
    save.type = "button";
    save.textContent = "保存";
    save.disabled = true;

    const status = document.createElement("p");
    status.className = "girls-app-thumbnail-status";
    status.setAttribute("role", "status");

    editor.append(picker, save, status);
    media.append(editor);

    const state = { prepared: null, generation: 0 };
    cardState.set(card, state);

    void loadSavedThumbnail(appId, image).catch((error) => {
      setNoImage(appId, image);
      setStatus(status, `画像を読み込めません: ${errorMessage(error)}`, "error");
    });

    input.addEventListener("change", () => {
      const file = input.files?.[0];
      state.generation += 1;
      const generation = state.generation;
      state.prepared = null;
      save.disabled = true;
      if (file === undefined) {
        setStatus(status, "");
        return;
      }

      input.disabled = true;
      setStatus(status, "画像を準備中…");
      void prepareThumbnail(file)
        .then((blob) => {
          if (state.generation !== generation) return;
          state.prepared = blob;
          setBlobImage(appId, image, blob, `${title}の保存前サムネイル`, "pending");
          save.disabled = false;
          setStatus(status, `保存前 ${Math.ceil(blob.size / 1024)}KB`);
        })
        .catch((error) => {
          if (state.generation !== generation) return;
          state.prepared = null;
          save.disabled = true;
          setStatus(status, errorMessage(error), "error");
        })
        .finally(() => {
          if (state.generation === generation) input.disabled = false;
        });
    });

    save.addEventListener("click", () => {
      const blob = state.prepared;
      if (!(blob instanceof Blob)) {
        setStatus(status, "先に画像を選んでください。", "error");
        return;
      }
      if (!ACCEPTED_TYPES.has(blob.type) || blob.size < 1 || blob.size > MAX_STORED_BYTES) {
        throw new Error("Prepared thumbnail has an invalid type or size.");
      }

      save.disabled = true;
      input.disabled = true;
      setStatus(status, "保存中…");
      void authenticatedFetch(`/hosted/my/apps/${appId}/thumbnail`, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": blob.type,
        },
        body: blob,
      })
        .then(async (response) => {
          if (!response.ok) throw new Error(await responseError(response));
          const contentType = response.headers.get("content-type") ?? "";
          if (!contentType.toLowerCase().startsWith("application/json")) {
            throw new Error("サムネイル保存APIがJSONを返しませんでした。");
          }
          const payload = await response.json();
          if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
            throw new Error("サムネイル保存APIの応答が不正です。");
          }
          if (
            payload.app_id !== appId ||
            payload.content_type !== blob.type ||
            payload.bytes !== blob.size ||
            typeof payload.updated_at !== "string" ||
            payload.updated_at.length === 0
          ) {
            throw new Error("サムネイル保存APIの応答内容が一致しません。");
          }
          state.prepared = null;
          input.value = "";
          await loadSavedThumbnail(appId, image);
          setStatus(status, "保存しました ♡", "success");
        })
        .catch((error) => {
          save.disabled = false;
          setStatus(status, `保存できませんでした: ${errorMessage(error)}`, "error");
        })
        .finally(() => {
          input.disabled = false;
        });
    });
  }

  function decorateCards() {
    for (const card of appList.querySelectorAll(".girls-app-card[data-girls-app-id]")) {
      if (card instanceof HTMLElement) installEditor(card);
    }
  }

  function scheduleDecorate() {
    if (decorateScheduled) return;
    decorateScheduled = true;
    queueMicrotask(() => {
      decorateScheduled = false;
      decorateCards();
    });
  }

  new MutationObserver(scheduleDecorate).observe(appList, { childList: true, subtree: true });
  globalThis.addEventListener("beforeunload", () => {
    for (const url of objectUrls.values()) URL.revokeObjectURL(url);
    objectUrls.clear();
  });
  scheduleDecorate();
})();
