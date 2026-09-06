"use strict";

(function attachSingleHtmlZip(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.MinAppSingleHtmlZip = api;
})(typeof globalThis === "object" ? globalThis : this, function buildSingleHtmlZipApi() {
  const INDEX_FILENAME = "index.html";
  const ZIP_UTF8_FLAG = 0x0800;
  const ZIP_STORE_METHOD = 0;
  const DOS_TIME_MIDNIGHT = 0x0000;
  const DOS_DATE_1980_01_01 = 0x0021;

  function requireTextEncoder() {
    if (typeof TextEncoder !== "function") {
      throw new Error("TextEncoder is required to build a ZIP archive.");
    }
    return new TextEncoder();
  }

  function writeUint16(view, offset, value) {
    view.setUint16(offset, value, true);
  }

  function writeUint32(view, offset, value) {
    view.setUint32(offset, value >>> 0, true);
  }

  function crc32(bytes) {
    if (!(bytes instanceof Uint8Array)) {
      throw new TypeError("crc32 input must be a Uint8Array.");
    }
    let crc = 0xffffffff;
    for (const byte of bytes) {
      crc ^= byte;
      for (let bit = 0; bit < 8; bit += 1) {
        const mask = -(crc & 1);
        crc = (crc >>> 1) ^ (0xedb88320 & mask);
      }
    }
    return (crc ^ 0xffffffff) >>> 0;
  }

  function buildSingleHtmlZip(htmlText) {
    if (typeof htmlText !== "string") {
      throw new TypeError("htmlText must be a string.");
    }
    if (htmlText.length === 0) {
      throw new Error("htmlText must not be empty.");
    }

    const encoder = requireTextEncoder();
    const filenameBytes = encoder.encode(INDEX_FILENAME);
    const htmlBytes = encoder.encode(htmlText);
    if (htmlBytes.length === 0) {
      throw new Error("Encoded HTML must not be empty.");
    }
    if (htmlBytes.length > 0xffffffff) {
      throw new RangeError("HTML is too large for the supported ZIP format.");
    }

    const checksum = crc32(htmlBytes);
    const localHeaderLength = 30 + filenameBytes.length;
    const centralHeaderLength = 46 + filenameBytes.length;
    const centralDirectoryOffset = localHeaderLength + htmlBytes.length;
    const centralDirectorySize = centralHeaderLength;
    const totalLength = centralDirectoryOffset + centralDirectorySize + 22;
    if (!Number.isSafeInteger(totalLength) || totalLength > 0xffffffff) {
      throw new RangeError("ZIP output is too large for the supported ZIP format.");
    }

    const output = new Uint8Array(totalLength);
    const view = new DataView(output.buffer);

    let offset = 0;
    writeUint32(view, offset, 0x04034b50); offset += 4;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, ZIP_UTF8_FLAG); offset += 2;
    writeUint16(view, offset, ZIP_STORE_METHOD); offset += 2;
    writeUint16(view, offset, DOS_TIME_MIDNIGHT); offset += 2;
    writeUint16(view, offset, DOS_DATE_1980_01_01); offset += 2;
    writeUint32(view, offset, checksum); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint16(view, offset, filenameBytes.length); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    output.set(filenameBytes, offset); offset += filenameBytes.length;
    output.set(htmlBytes, offset); offset += htmlBytes.length;

    if (offset !== centralDirectoryOffset) {
      throw new Error("ZIP local record length mismatch.");
    }

    writeUint32(view, offset, 0x02014b50); offset += 4;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, 20); offset += 2;
    writeUint16(view, offset, ZIP_UTF8_FLAG); offset += 2;
    writeUint16(view, offset, ZIP_STORE_METHOD); offset += 2;
    writeUint16(view, offset, DOS_TIME_MIDNIGHT); offset += 2;
    writeUint16(view, offset, DOS_DATE_1980_01_01); offset += 2;
    writeUint32(view, offset, checksum); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint32(view, offset, htmlBytes.length); offset += 4;
    writeUint16(view, offset, filenameBytes.length); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint32(view, offset, 0); offset += 4;
    writeUint32(view, offset, 0); offset += 4;
    output.set(filenameBytes, offset); offset += filenameBytes.length;

    writeUint32(view, offset, 0x06054b50); offset += 4;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 0); offset += 2;
    writeUint16(view, offset, 1); offset += 2;
    writeUint16(view, offset, 1); offset += 2;
    writeUint32(view, offset, centralDirectorySize); offset += 4;
    writeUint32(view, offset, centralDirectoryOffset); offset += 4;
    writeUint16(view, offset, 0); offset += 2;

    if (offset !== output.length) {
      throw new Error("ZIP output length mismatch.");
    }
    return output;
  }

  return Object.freeze({
    INDEX_FILENAME,
    buildSingleHtmlZip,
  });
});

(function attachGirlsGroupApps() {
  if (typeof document === "undefined") return;

  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const CONFIG_PATH = "/girls-config.json";
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const PUBLISHED_CONTENT_PATH_PATTERN = /^\/hosted\/content\/[A-Za-z0-9_-]{32,128}\/index\.html$/;

  function requireElement(id, ctor = HTMLElement) {
    const element = document.getElementById(id);
    if (!(element instanceof ctor)) throw new Error(`#${id} has an unexpected type.`);
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

  function setError(element, error) {
    if (error === null) {
      element.textContent = "";
      element.classList.add("hidden");
      return;
    }
    element.textContent = error instanceof Error ? error.message : String(error);
    element.classList.remove("hidden");
  }

  async function init() {
    const shell = requireElement("girls-upload-panel");
    const nav = requireElement("girls-shell-nav");
    const shellTitle = requireElement("girls-shell-title");
    const menuButton = requireElement("girls-shell-menu", HTMLButtonElement);
    const existingAppsPanel = requireElement("girls-view-apps");
    const existingPreviewClose = requireElement("girls-preview-close", HTMLButtonElement);

    if (document.getElementById("girls-group-apps-nav") !== null) {
      throw new Error("Girls group apps navigation was initialized more than once.");
    }

    const settingsButton = nav.querySelector('[data-girls-view="settings"]');
    if (!(settingsButton instanceof HTMLButtonElement)) {
      throw new Error("Girls settings navigation item was not found.");
    }

    const navButton = document.createElement("button");
    navButton.id = "girls-group-apps-nav";
    navButton.className = "portal-shell-nav-item";
    navButton.type = "button";
    navButton.dataset.girlsView = "group-apps";
    navButton.innerHTML = '<span class="portal-shell-nav-icon" aria-hidden="true">▦</span><span>グループのアプリ</span>';
    settingsButton.before(navButton);

    const panel = document.createElement("section");
    panel.id = "girls-view-group-apps";
    panel.className = "girls-view-panel girls-view-hidden";
    panel.dataset.girlsPanel = "group-apps";
    panel.innerHTML = `
      <section class="girls-dashboard-card">
        <div class="girls-section-heading girls-apps-heading">
          <div><p class="girls-step">GROUP APPS</p><h2>グループのアプリ</h2></div>
          <button id="girls-group-apps-refresh" class="girls-secondary" type="button">更新</button>
        </div>
        <p class="girls-muted">グループのみんなに公開されているアプリを表示します。</p>
        <label class="girls-form">
          グループ
          <select id="girls-group-apps-select"></select>
        </label>
        <p id="girls-group-apps-status" class="girls-muted" role="status">グループを読み込むとここに表示されます。</p>
        <div id="girls-group-apps-list" class="girls-app-grid" aria-live="polite"></div>
        <p id="girls-group-apps-error" class="girls-message girls-message-error hidden" role="alert"></p>
      </section>
      <section id="girls-group-preview-panel" class="girls-dashboard-card girls-preview-card hidden" aria-labelledby="girls-group-preview-title">
        <div class="girls-section-heading girls-preview-heading">
          <div><p class="girls-step">公開版プレビュー</p><h2 id="girls-group-preview-title">アプリを確認</h2></div>
          <button id="girls-group-preview-close" class="girls-secondary" type="button">閉じる</button>
        </div>
        <p class="girls-muted">グループのみんなが使う公開版を表示しています。</p>
        <div class="girls-preview-frame-wrap">
          <iframe id="girls-group-preview-frame" title="公開中アプリのプレビュー" sandbox="allow-scripts" referrerpolicy="no-referrer"></iframe>
        </div>
        <p id="girls-group-preview-error" class="girls-message girls-message-error hidden" role="alert"></p>
      </section>
    `;
    existingAppsPanel.after(panel);

    const groupSelect = requireElement("girls-group-apps-select", HTMLSelectElement);
    const refreshButton = requireElement("girls-group-apps-refresh", HTMLButtonElement);
    const status = requireElement("girls-group-apps-status");
    const list = requireElement("girls-group-apps-list");
    const error = requireElement("girls-group-apps-error");
    const previewPanel = requireElement("girls-group-preview-panel");
    const previewTitle = requireElement("girls-group-preview-title");
    const previewClose = requireElement("girls-group-preview-close", HTMLButtonElement);
    const previewFrame = requireElement("girls-group-preview-frame", HTMLIFrameElement);
    const previewError = requireElement("girls-group-preview-error");

    let apiBaseUrl = null;
    let groups = [];
    let loadGeneration = 0;
    let previewGeneration = 0;

    function closePreview() {
      previewGeneration += 1;
      previewFrame.removeAttribute("src");
      previewTitle.textContent = "アプリを確認";
      setError(previewError, null);
      previewPanel.classList.add("hidden");
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
      const contentType = response.headers.get("content-type");
      if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
        throw new Error("Girls config returned a non-JSON response.");
      }
      const payload = requirePlainObject(await response.json(), "Girls config response");
      if (payload.schema_version !== 1) {
        throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
      }
      const rawBase = requireString(payload.hosted_api_base_url, "Girls API base URL");
      if (rawBase !== rawBase.trim()) throw new Error("Girls API base URL contains surrounding whitespace.");
      const parsed = new URL(rawBase);
      if (parsed.protocol !== "https:" || parsed.username !== "" || parsed.password !== "" ||
          parsed.pathname !== "/" || parsed.search !== "" || parsed.hash !== "") {
        throw new Error("Girls API base URL must be an HTTPS origin.");
      }
      apiBaseUrl = parsed.origin;
      return apiBaseUrl;
    }

    async function authenticatedFetch(path, init = {}) {
      if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
        throw new TypeError("Girls group apps path must be origin-relative.");
      }
      const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
      if (token === null || token.length === 0) {
        throw new Error("ログイン情報がありません。もう一度ログインしてください。");
      }
      const baseUrl = await getApiBaseUrl();
      const url = new URL(path, `${baseUrl}/`);
      if (url.origin !== baseUrl) throw new Error("Girls group apps path escaped the configured origin.");
      const headers = new Headers(init.headers ?? {});
      headers.set("Authorization", `Bearer ${token}`);
      const response = await fetch(url.toString(), {
        ...init,
        headers,
        cache: "no-store",
        credentials: "omit",
      });
      return response;
    }

    async function jsonRequest(path, method = "GET") {
      if (method !== "GET" && method !== "POST") {
        throw new TypeError(`Unsupported Girls group apps method: ${String(method)}`);
      }
      const headers = { Accept: "application/json" };
      const init = { method, headers };
      if (method === "POST") {
        headers["Content-Type"] = "application/json";
        init.body = "{}";
      }
      const response = await authenticatedFetch(path, init);
      const contentType = response.headers.get("content-type");
      if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
        throw new Error(`Girls API returned a non-JSON response (HTTP ${response.status}).`);
      }
      const payload = requirePlainObject(await response.json(), "Girls API response");
      if (!response.ok) {
        const message = typeof payload.message === "string" && payload.message.length > 0
          ? payload.message
          : `HTTP ${response.status}`;
        throw new Error(message);
      }
      return payload;
    }

    async function loadGroups() {
      const payload = await jsonRequest("/hosted/groups");
      if (!Array.isArray(payload.groups)) throw new Error("Hosted groups response has no groups list.");
      groups = payload.groups.map((rawGroup) => {
        const group = requirePlainObject(rawGroup, "Hosted group");
        const groupId = requireString(group.group_id, "Hosted group_id");
        if (!ID_PATTERN.test(groupId)) throw new Error("Hosted group has an invalid group_id.");
        const name = requireString(group.name, "Hosted group name");
        if (group.role !== "owner" && group.role !== "member") throw new Error("Hosted group has an invalid role.");
        if (group.status !== "active") throw new Error("Hosted group is not active.");
        return { groupId, name, role: group.role };
      });

      const previousValue = groupSelect.value;
      groupSelect.replaceChildren();
      for (const group of groups) {
        const option = document.createElement("option");
        option.value = group.groupId;
        option.textContent = group.name;
        groupSelect.append(option);
      }
      if (groups.some((group) => group.groupId === previousValue)) groupSelect.value = previousValue;
      groupSelect.disabled = groups.length === 0;
    }

    function validateApps(payload, group) {
      if (!Array.isArray(payload.apps)) throw new Error("Hosted apps response has no apps list.");
      return payload.apps.map((rawApp) => {
        const app = requirePlainObject(rawApp, "Hosted app");
        const appId = requireString(app.app_id, "Hosted app_id");
        if (!ID_PATTERN.test(appId)) throw new Error("Hosted app has an invalid app_id.");
        if (app.group_id !== group.groupId) throw new Error("Hosted app group_id mismatch.");
        const title = requireString(app.title, "Hosted app title");
        const createdAt = requireString(app.created_at, "Hosted app created_at");
        const date = new Date(createdAt);
        if (Number.isNaN(date.getTime())) throw new Error("Hosted app created_at is invalid.");
        const publishedVersion = app.published_version;
        if (publishedVersion !== null && publishedVersion !== undefined &&
            (!Number.isInteger(publishedVersion) || publishedVersion < 1)) {
          throw new Error("Hosted app has an invalid published_version.");
        }
        return { appId, title, createdAt, publishedVersion };
      });
    }

    async function openPublishedPreview(group, app, button) {
      if (!(button instanceof HTMLButtonElement)) throw new TypeError("Preview trigger must be a button.");
      const generation = ++previewGeneration;
      closePreview();
      previewGeneration = generation;
      previewTitle.textContent = `${app.title}を確認`;
      previewPanel.classList.remove("hidden");
      button.disabled = true;
      const originalLabel = button.textContent;
      button.textContent = "読み込み中…";
      try {
        const payload = await jsonRequest(
          `/hosted/groups/${group.groupId}/apps/${app.appId}/published-session`,
          "POST",
        );
        if (generation !== previewGeneration) return;
        const contentPath = requireString(payload.content_path, "Published preview content_path");
        if (!PUBLISHED_CONTENT_PATH_PATTERN.test(contentPath)) {
          throw new Error("Published preview returned an invalid content path.");
        }
        const baseUrl = await getApiBaseUrl();
        if (generation !== previewGeneration) return;
        const url = new URL(contentPath, `${baseUrl}/`);
        if (url.origin !== baseUrl) throw new Error("Published preview URL escaped the configured origin.");
        previewFrame.src = url.toString();
        previewPanel.scrollIntoView({ behavior: "smooth", block: "start" });
      } catch (caught) {
        if (generation === previewGeneration) {
          previewFrame.removeAttribute("src");
          setError(previewError, caught);
        }
      } finally {
        button.disabled = false;
        button.textContent = originalLabel;
      }
    }

    async function downloadSourceZip(group, app, button) {
      if (group.role !== "owner") throw new Error("ZIP download requires the group owner role.");
      if (!(button instanceof HTMLButtonElement)) throw new TypeError("ZIP download trigger must be a button.");
      button.disabled = true;
      const originalLabel = button.textContent;
      button.textContent = "DL中…";
      setError(error, null);
      try {
        const response = await authenticatedFetch(
          `/hosted/groups/${group.groupId}/apps/${app.appId}/source`,
          { method: "GET", headers: { Accept: "application/zip" } },
        );
        if (!response.ok) {
          const contentType = response.headers.get("content-type");
          if (contentType !== null && contentType.toLowerCase().startsWith("application/json")) {
            const payload = requirePlainObject(await response.json(), "ZIP download error response");
            const message = typeof payload.message === "string" && payload.message.length > 0
              ? payload.message
              : `HTTP ${response.status}`;
            throw new Error(message);
          }
          throw new Error(`ZIP download failed: HTTP ${response.status}`);
        }
        const contentType = response.headers.get("content-type");
        if (contentType === null || contentType.split(";", 1)[0].trim().toLowerCase() !== "application/zip") {
          throw new Error("ZIP download returned an unexpected content type.");
        }
        const blob = await response.blob();
        if (blob.size === 0) throw new Error("ZIP download returned an empty file.");
        const objectUrl = URL.createObjectURL(blob);
        try {
          const anchor = document.createElement("a");
          anchor.href = objectUrl;
          anchor.download = `minapp-${app.appId}.zip`;
          document.body.append(anchor);
          anchor.click();
          anchor.remove();
        } finally {
          URL.revokeObjectURL(objectUrl);
        }
      } catch (caught) {
        setError(error, caught);
      } finally {
        button.disabled = false;
        button.textContent = originalLabel;
      }
    }

    function renderApps(group, apps) {
      list.replaceChildren();
      const published = apps
        .filter((app) => Number.isInteger(app.publishedVersion) && app.publishedVersion >= 1)
        .sort((left, right) => Date.parse(right.createdAt) - Date.parse(left.createdAt));

      for (const app of published) {
        const card = document.createElement("article");
        card.className = "girls-app-card";

        const media = document.createElement("div");
        media.className = "girls-app-card-media";
        const image = document.createElement("img");
        image.className = "girls-app-card-thumbnail";
        image.src = "/girls-assets/no_image.svg";
        image.alt = "";
        image.dataset.thumbnailState = "no-image";
        media.append(image);

        const body = document.createElement("div");
        body.className = "girls-app-card-body";
        const heading = document.createElement("div");
        heading.className = "girls-app-card-heading";
        const title = document.createElement("h3");
        title.textContent = app.title;
        heading.append(title);

        const groupName = document.createElement("p");
        groupName.textContent = group.name;

        const meta = document.createElement("div");
        meta.className = "girls-app-card-meta";
        const publishedChip = document.createElement("span");
        publishedChip.className = "girls-app-chip girls-app-chip-published";
        publishedChip.textContent = `公開中 v${app.publishedVersion}`;
        const dateChip = document.createElement("span");
        dateChip.className = "girls-app-chip";
        dateChip.textContent = new Date(app.createdAt).toLocaleDateString("ja-JP");
        meta.append(publishedChip, dateChip);

        const actions = document.createElement("div");
        actions.className = "girls-app-card-actions";
        const previewButton = document.createElement("button");
        previewButton.className = "girls-secondary";
        previewButton.type = "button";
        previewButton.textContent = "プレビュー";
        previewButton.addEventListener("click", () => void openPublishedPreview(group, app, previewButton));
        actions.append(previewButton);

        if (group.role === "owner") {
          const downloadButton = document.createElement("button");
          downloadButton.className = "girls-secondary";
          downloadButton.type = "button";
          downloadButton.textContent = "ZIPをDL";
          downloadButton.addEventListener("click", () => void downloadSourceZip(group, app, downloadButton));
          actions.append(downloadButton);
        }

        body.append(heading, groupName, meta, actions);
        card.append(media, body);
        list.append(card);
      }

      status.textContent = published.length === 0
        ? "このグループには公開中のアプリがありません。"
        : `${published.length}個の公開中アプリがあります。`;
    }

    async function loadSelectedGroupApps() {
      const generation = ++loadGeneration;
      closePreview();
      setError(error, null);
      refreshButton.disabled = true;
      status.textContent = "グループのアプリを読み込み中…";
      list.replaceChildren();
      try {
        await loadGroups();
        if (generation !== loadGeneration) return;
        if (groups.length === 0) {
          status.textContent = "参加中のグループがありません。";
          return;
        }
        const group = groups.find((candidate) => candidate.groupId === groupSelect.value);
        if (group === undefined) throw new Error("選択中のグループが見つかりません。");
        const payload = await jsonRequest(`/hosted/groups/${group.groupId}/apps`);
        if (generation !== loadGeneration) return;
        renderApps(group, validateApps(payload, group));
      } catch (caught) {
        if (generation !== loadGeneration) return;
        status.textContent = "グループのアプリを読み込めませんでした。";
        setError(error, caught);
      } finally {
        if (generation === loadGeneration) refreshButton.disabled = false;
      }
    }

    function showGroupAppsView() {
      existingPreviewClose.click();
      for (const view of document.querySelectorAll("[data-girls-panel]")) {
        if (!(view instanceof HTMLElement)) throw new Error("Girls view panel must be an element.");
        view.classList.toggle("girls-view-hidden", view !== panel);
      }
      for (const button of nav.querySelectorAll("[data-girls-view]")) {
        if (!(button instanceof HTMLButtonElement)) throw new Error("Girls navigation item must be a button.");
        const active = button === navButton;
        button.classList.toggle("portal-shell-nav-item-active", active);
        if (active) button.setAttribute("aria-current", "page");
        else button.removeAttribute("aria-current");
      }
      shellTitle.textContent = "グループのアプリ";
      shell.classList.remove("portal-shell-nav-open");
      menuButton.setAttribute("aria-expanded", "false");
      void loadSelectedGroupApps();
    }

    navButton.addEventListener("click", showGroupAppsView);
    refreshButton.addEventListener("click", () => void loadSelectedGroupApps());
    groupSelect.addEventListener("change", () => void loadSelectedGroupApps());
    previewClose.addEventListener("click", closePreview);
  }

  document.addEventListener("DOMContentLoaded", () => {
    void init().catch((error) => {
      console.error("Girls group apps initialization failed", error);
      const fatal = document.getElementById("girls-fatal");
      if (fatal instanceof HTMLElement) {
        fatal.textContent = error instanceof Error ? error.message : String(error);
        fatal.classList.remove("hidden");
      }
    });
  }, { once: true });
})();
