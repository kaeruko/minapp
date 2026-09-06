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
  const uploadGroup = document.getElementById("girls-upload-group");
  const logoutButton = document.getElementById("girls-logout");
  const previewPanel = document.getElementById("girls-preview-panel");
  const previewClose = document.getElementById("girls-preview-close");

  for (const [value, label, ctor] of [
    [appList, "#girls-app-list", HTMLElement],
    [appsStatus, "#girls-apps-status", HTMLElement],
    [appsError, "#girls-apps-error", HTMLElement],
    [appsRefresh, "#girls-apps-refresh", HTMLButtonElement],
    [uploadGroup, "#girls-upload-group", HTMLSelectElement],
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

  function ownerGroups() {
    return [...uploadGroup.options].map((option) => {
      if (!ID_PATTERN.test(option.value)) {
        throw new Error("Girls portal contains an invalid owner group id.");
      }
      const name = option.textContent === null ? "" : option.textContent.trim();
      if (name.length === 0) throw new Error("Girls portal contains an owner group without a name.");
      return { groupId: option.value, name };
    });
  }

  async function loadAppMetadata() {
    const groups = ownerGroups();
    const [managedPayload, groupResults] = await Promise.all([
      apiRequest("/hosted/my/apps"),
      Promise.all(groups.map(async (group) => {
        const payload = await apiRequest(`/hosted/groups/${group.groupId}/apps`);
        if (!Array.isArray(payload.apps)) {
          throw new Error(`Hosted apps response for ${group.name} has no apps list.`);
        }
        return payload.apps.map((rawApp) => {
          const app = requirePlainObject(rawApp, "Hosted app");
          if (!ID_PATTERN.test(app.app_id)) throw new Error("Hosted app has an invalid app_id.");
          if (app.group_id !== group.groupId) throw new Error("Hosted app group_id mismatch.");
          const title = requireString(app.title, "Hosted app title");
          const createdAt = requireString(app.created_at, "Hosted app created_at");
          const parsedDate = new Date(createdAt);
          if (Number.isNaN(parsedDate.getTime())) throw new Error("Hosted app created_at is invalid.");
          return {
            appId: app.app_id,
            groupId: group.groupId,
            groupName: group.name,
            title,
            dateLabel: parsedDate.toLocaleDateString("ja-JP"),
            thumbnailUrl: optionalThumbnailUrl(app.thumbnail_url, "Hosted app thumbnail_url"),
          };
        });
      })),
    ]);

    if (!Array.isArray(managedPayload.apps)) {
      throw new Error("Managed Girls apps response has no apps list.");
    }
    const managedById = new Map();
    for (const rawManaged of managedPayload.apps) {
      const managed = requirePlainObject(rawManaged, "Managed Girls app");
      if (!ID_PATTERN.test(managed.app_id)) throw new Error("Managed Girls app has an invalid app_id.");
      if (managed.visibility !== "visible" && managed.visibility !== "hidden") {
        throw new Error("Managed Girls app has an invalid visibility state.");
      }
      managedById.set(managed.app_id, {
        appId: managed.app_id,
        visibility: managed.visibility,
        thumbnailUrl: optionalThumbnailUrl(managed.thumbnail_url, "Managed Girls app thumbnail_url"),
      });
    }

    return { apps: groupResults.flat(), managedById };
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
