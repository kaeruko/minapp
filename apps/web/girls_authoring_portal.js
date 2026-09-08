"use strict";

(function installGirlsAuthoringPortal() {
  const portalApi = globalThis.MinAppHostedAuthoringPortal;
  if (!portalApi || typeof portalApi.HostedAuthoringPortalController !== "function") {
    throw new Error("Girls Authoring portal requires hosted_authoring_portal.js.");
  }
  const authoringApi = globalThis.MinAppWebAuthoring;
  if (!authoringApi) {
    throw new Error("Girls Authoring portal requires authoring_host_adapter.js.");
  }

  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
  const CONFIG_PATH = "/girls-config.json";
  const NOVEL_CONTENT_FORMAT = "minapp/novel@1";
  const NOVEL_PLAYER_BUILTIN_ID = "novel-starter";
  const HOSTED_ID_PATTERN = /^[0-9a-f]{32}$/;
  const RECOVERY_CHANNEL = "minapp.novel-editor.recovery";
  const RECOVERY_VERSION = 1;
  const RECOVERY_REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
  const RECOVERY_STORAGE_PREFIX = "minapp_novel_editor_recovery_v1:";
  const RECOVERY_MAX_CHARS = 1500000;
  const RENEWABLE_SESSION_ERRORS = new Set([
    "authoring_session_not_found",
    "authoring_request_limit_reached",
    "runtime_session_not_found",
    "runtime_request_limit_reached",
  ]);
  let activeRecoveryContentId = null;

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

  function requireNonEmptyString(value, label) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error(`${label} must be a non-empty string.`);
    }
    return value;
  }

  function validateHostedId(value, label) {
    if (typeof value !== "string" || !HOSTED_ID_PATTERN.test(value)) {
      throw new Error(`${label} must be a 32-character lowercase hexadecimal id.`);
    }
    return value;
  }

  function validateApiOrigin(value) {
    return authoringApi.validateApiOrigin(value);
  }

  function requireExactFields(value, expected, label) {
    const object = requirePlainObject(value, label);
    const actual = Object.keys(object).sort();
    const wanted = [...expected].sort();
    if (actual.length !== wanted.length || actual.some((name, index) => name !== wanted[index])) {
      throw new Error(`${label} fields are invalid.`);
    }
    return object;
  }

  function recoveryStorageKey(contentId) {
    return `${RECOVERY_STORAGE_PREFIX}${validateHostedId(contentId, "Recovery content id")}`;
  }

  function recoverySuccess(id, result) {
    return {
      channel: RECOVERY_CHANNEL,
      version: RECOVERY_VERSION,
      type: "response",
      id,
      ok: true,
      result,
    };
  }

  function recoveryFailure(id, code, message) {
    return {
      channel: RECOVERY_CHANNEL,
      version: RECOVERY_VERSION,
      type: "response",
      id,
      ok: false,
      error: { code, message },
    };
  }

  function validateStoredRecovery(raw, contentId) {
    const value = requireExactFields(
      raw,
      ["contentId", "expectedRevision", "document", "savedAt"],
      "Stored recovery backup",
    );
    if (validateHostedId(value.contentId, "Stored recovery content id") !== contentId) {
      throw new Error("Stored recovery backup changed content scope.");
    }
    if (!Number.isInteger(value.expectedRevision) || value.expectedRevision < 1) {
      throw new Error("Stored recovery expectedRevision is invalid.");
    }
    requirePlainObject(value.document, "Stored recovery document");
    requireNonEmptyString(value.savedAt, "Stored recovery savedAt");
    return value;
  }

  function installAuthoringSessionRenewal() {
    const prototype = authoringApi.WebAuthoringHostAdapter.prototype;
    if (prototype.__girlsSessionRenewalInstalled === true) return;
    const originalDispatch = prototype.dispatch;
    if (typeof originalDispatch !== "function") {
      throw new Error("Web Authoring Host Adapter dispatch is unavailable.");
    }
    prototype.dispatch = async function dispatchWithRenewal(request) {
      try {
        return await originalDispatch.call(this, request);
      } catch (error) {
        if (!(error instanceof authoringApi.HostedWebApiError) ||
            !RENEWABLE_SESSION_ERRORS.has(error.code)) {
          throw error;
        }
        const renewed = await authoringApi.createWebAuthoringLaunch({
          apiOrigin: this.apiOrigin,
          accessToken: getAccessToken(),
          contentId: this.launch.contentId,
          editorAppId: this.launch.editorAppId,
          fetchImpl: this.fetchImpl,
        });
        if (renewed.contentFormat !== this.launch.contentFormat) {
          throw new Error("Renewed Authoring session changed content format.");
        }
        this.launch = Object.freeze({
          ...this.launch,
          runtimeToken: renewed.runtimeToken,
          runtimeExpiresIn: renewed.runtimeExpiresIn,
          authoringToken: renewed.authoringToken,
          authoringExpiresIn: renewed.authoringExpiresIn,
        });
        return await originalDispatch.call(this, request);
      }
    };
    Object.defineProperty(prototype, "__girlsSessionRenewalInstalled", {
      configurable: false,
      enumerable: false,
      value: true,
    });
  }

  let hostedApiOrigin = null;
  async function getApiOrigin() {
    if (hostedApiOrigin !== null) return hostedApiOrigin;
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
    const fields = Object.keys(payload).sort();
    if (fields.length !== 2 || fields[0] !== "hosted_api_base_url" || fields[1] !== "schema_version") {
      throw new Error("Girls config fields are invalid.");
    }
    if (payload.schema_version !== 1) {
      throw new Error(`Unsupported Girls config schema_version: ${String(payload.schema_version)}`);
    }
    hostedApiOrigin = validateApiOrigin(payload.hosted_api_base_url);
    return hostedApiOrigin;
  }

  function getAccessToken() {
    const token = sessionStorage.getItem(ACCESS_TOKEN_KEY);
    if (token === null || token.length === 0) {
      throw new Error("ログイン情報がありません。もう一度ログインしてください。");
    }
    return token;
  }

  async function installNovelPlayer({ apiOrigin, accessToken, groupId }) {
    const origin = validateApiOrigin(apiOrigin);
    requireNonEmptyString(accessToken, "Hosted access token");
    const normalizedGroupId = validateHostedId(groupId, "Novel Player group id");
    const url = new URL(`/hosted/groups/${normalizedGroupId}/apps/install`, `${origin}/`);
    if (url.origin !== origin) {
      throw new Error("Novel Player install path escaped the configured Hosted origin.");
    }

    let response;
    try {
      response = await fetch(url.toString(), {
        method: "POST",
        headers: {
          Accept: "application/json",
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ builtin_id: NOVEL_PLAYER_BUILTIN_ID }),
        cache: "no-store",
        credentials: "omit",
      });
    } catch (error) {
      throw new authoringApi.HostedWebApiError(
        0,
        "host_adapter_request_failed",
        error instanceof Error ? error.message : String(error),
      );
    }

    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new authoringApi.HostedWebApiError(
        response.status,
        "invalid_api_response",
        `Novel Player install returned a non-JSON response (HTTP ${response.status}).`,
      );
    }

    let payload;
    try {
      payload = requirePlainObject(await response.json(), "Novel Player install response");
    } catch (error) {
      throw new authoringApi.HostedWebApiError(
        response.status,
        "invalid_api_response",
        error instanceof Error ? error.message : String(error),
      );
    }

    if (!response.ok) {
      const fields = Object.keys(payload).sort();
      if (fields.length !== 2 || fields[0] !== "error" || fields[1] !== "message") {
        throw new authoringApi.HostedWebApiError(
          response.status,
          "invalid_api_response",
          "Novel Player install error response fields are invalid.",
        );
      }
      throw new authoringApi.HostedWebApiError(
        response.status,
        requireNonEmptyString(payload.error, "Novel Player install error code"),
        requireNonEmptyString(payload.message, "Novel Player install error message"),
      );
    }

    const appId = validateHostedId(payload.app_id, "Novel Player app_id");
    const returnedGroupId = validateHostedId(payload.group_id, "Novel Player group_id");
    if (returnedGroupId !== normalizedGroupId ||
        payload.source_kind !== "builtin" ||
        payload.builtin_id !== NOVEL_PLAYER_BUILTIN_ID) {
      throw new authoringApi.HostedWebApiError(
        response.status,
        "invalid_api_response",
        "Novel Player install response changed the requested app scope.",
      );
    }
    return Object.freeze({ appId, groupId: returnedGroupId });
  }

  const shell = requiredElement("girls-upload-panel");
  const shellTitle = requiredElement("girls-shell-title");
  const shellMenu = requiredElement("girls-shell-menu");
  const authoringPanel = requiredElement("girls-view-authoring");
  const authoringNav = requiredElement("girls-authoring-nav");
  const logoutButton = requiredElement("girls-logout");
  const sourceGroupSelect = requiredElement("girls-upload-group");
  const editorFrame = requiredElement("girls-authoring-editor-frame");

  if (!(shell instanceof HTMLElement)) throw new Error("#girls-upload-panel must be an element.");
  if (!(shellTitle instanceof HTMLElement)) throw new Error("#girls-shell-title must be an element.");
  if (!(shellMenu instanceof HTMLButtonElement)) throw new Error("#girls-shell-menu must be a button.");
  if (!(authoringPanel instanceof HTMLElement)) throw new Error("#girls-view-authoring must be an element.");
  if (!(authoringNav instanceof HTMLButtonElement)) throw new Error("#girls-authoring-nav must be a button.");
  if (!(logoutButton instanceof HTMLButtonElement)) throw new Error("#girls-logout must be a button.");
  if (!(sourceGroupSelect instanceof HTMLSelectElement)) throw new Error("#girls-upload-group must be a select.");
  if (!(editorFrame instanceof HTMLIFrameElement)) throw new Error("#girls-authoring-editor-frame must be an iframe.");

  installAuthoringSessionRenewal();

  const controller = new portalApi.HostedAuthoringPortalController({
    sourceGroupSelect,
    groupSelect: requiredElement("girls-authoring-group"),
    editorSelect: requiredElement("girls-authoring-editor"),
    refreshButton: requiredElement("girls-authoring-refresh"),
    createButton: requiredElement("girls-authoring-create"),
    statusElement: requiredElement("girls-authoring-status"),
    errorElement: requiredElement("girls-authoring-error"),
    projectList: requiredElement("girls-authoring-projects"),
    editorDialog: requiredElement("girls-authoring-editor-dialog"),
    editorTitle: requiredElement("girls-authoring-editor-title"),
    editorFrame,
    editorCloseButton: requiredElement("girls-authoring-editor-close"),
    playerDialog: requiredElement("girls-authoring-player-dialog"),
    playerOptions: requiredElement("girls-authoring-player-options"),
    playerCancelButton: requiredElement("girls-authoring-player-cancel"),
    previewDialog: requiredElement("girls-authoring-preview-dialog"),
    previewTitle: requiredElement("girls-authoring-preview-title"),
    previewFrame: requiredElement("girls-authoring-preview-frame"),
    previewCloseButton: requiredElement("girls-authoring-preview-close"),
    getApiOrigin,
    getAccessToken,
    onUnauthorized: () => logoutButton.click(),
  });

  const openEditor = controller.openEditor.bind(controller);
  controller.openEditor = async (contentId, options = {}) => {
    const normalizedContentId = validateHostedId(contentId, "Recovery active content id");
    activeRecoveryContentId = normalizedContentId;
    try {
      return await openEditor(normalizedContentId, options);
    } catch (error) {
      if (!controller.editorDialog.open) activeRecoveryContentId = null;
      throw error;
    }
  };

  const closeEditor = controller.closeEditor.bind(controller);
  controller.closeEditor = async () => {
    try {
      return await closeEditor();
    } finally {
      activeRecoveryContentId = null;
    }
  };

  window.addEventListener("message", (event) => {
    if (event.source !== editorFrame.contentWindow || event.origin !== "null") return;
    const raw = event.data;
    if (typeof raw !== "object" || raw === null || Array.isArray(raw) ||
        raw.channel !== RECOVERY_CHANNEL || raw.version !== RECOVERY_VERSION ||
        raw.type !== "request") {
      return;
    }
    const id = typeof raw.id === "string" && RECOVERY_REQUEST_ID_PATTERN.test(raw.id)
      ? raw.id
      : null;
    if (id === null) return;
    try {
      const common = ["channel", "version", "type", "id", "method", "contentId"];
      const expected = raw.method === "save"
        ? [...common, "expectedRevision", "document"]
        : common;
      requireExactFields(raw, expected, "Novel recovery request");
      if (!new Set(["load", "save", "clear"]).has(raw.method)) {
        throw new Error("Novel recovery method is unsupported.");
      }
      const contentId = validateHostedId(raw.contentId, "Novel recovery content id");
      if (activeRecoveryContentId === null || contentId !== activeRecoveryContentId) {
        throw new Error("Novel recovery request does not match the active Editor content.");
      }
      const key = recoveryStorageKey(contentId);
      let result = null;
      if (raw.method === "load") {
        const stored = localStorage.getItem(key);
        result = stored === null ? null : validateStoredRecovery(JSON.parse(stored), contentId);
      } else if (raw.method === "clear") {
        localStorage.removeItem(key);
      } else {
        if (!Number.isInteger(raw.expectedRevision) || raw.expectedRevision < 1) {
          throw new Error("Novel recovery expectedRevision is invalid.");
        }
        const document = requirePlainObject(raw.document, "Novel recovery document");
        const stored = JSON.stringify({
          contentId,
          expectedRevision: raw.expectedRevision,
          document,
          savedAt: new Date().toISOString(),
        });
        if (stored.length > RECOVERY_MAX_CHARS) {
          throw new Error("Novel recovery backup is too large for local storage.");
        }
        localStorage.setItem(key, stored);
      }
      editorFrame.contentWindow.postMessage(recoverySuccess(id, result), "*");
    } catch (error) {
      editorFrame.contentWindow.postMessage(
        recoveryFailure(
          id,
          "recovery_store_error",
          error instanceof Error ? error.message : String(error),
        ),
        "*",
      );
    }
  });

  const previewFromEditor = controller.previewFromEditor.bind(controller);
  controller.previewFromEditor = async (request) => {
    const context = requirePlainObject(request, "Girls Authoring preview request");
    if (context.contentFormat === NOVEL_CONTENT_FORMAT) {
      const apps = await authoringApi.listAuthoringApps({
        apiOrigin: context.apiOrigin,
        accessToken: context.accessToken,
        groupId: context.groupId,
        fetchImpl: fetch,
      });
      const players = authoringApi.playersFor(apps, NOVEL_CONTENT_FORMAT);
      if (players.length === 0) {
        await installNovelPlayer({
          apiOrigin: context.apiOrigin,
          accessToken: context.accessToken,
          groupId: context.groupId,
        });
      }
    }
    return await previewFromEditor(request);
  };

  controller.bind();

  function clearAuthoringNavigation() {
    authoringNav.classList.remove("portal-shell-nav-item-active");
    authoringNav.removeAttribute("aria-current");
    authoringPanel.classList.add("girls-view-hidden");
  }

  function closeNavigation() {
    shell.classList.remove("portal-shell-nav-open");
    shellMenu.setAttribute("aria-expanded", "false");
  }

  async function openAuthoringView() {
    if (shell.classList.contains("hidden")) {
      throw new Error("Girls Authoring view requires an authenticated portal session.");
    }
    for (const panel of document.querySelectorAll("[data-girls-panel]")) {
      if (!(panel instanceof HTMLElement)) throw new Error("Girls view panel must be an element.");
      panel.classList.add("girls-view-hidden");
    }
    for (const button of document.querySelectorAll("[data-girls-view]")) {
      if (!(button instanceof HTMLButtonElement)) throw new Error("Girls navigation item must be a button.");
      button.classList.remove("portal-shell-nav-item-active");
      button.removeAttribute("aria-current");
    }
    authoringPanel.classList.remove("girls-view-hidden");
    authoringNav.classList.add("portal-shell-nav-item-active");
    authoringNav.setAttribute("aria-current", "page");
    shellTitle.textContent = "作品を作る";
    closeNavigation();
    await controller.activate();
  }

  for (const button of document.querySelectorAll("[data-girls-authoring-open]")) {
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error("Girls Authoring navigation control must be a button.");
    }
    button.addEventListener("click", () => {
      void openAuthoringView().catch((error) => {
        console.error(error);
      });
    });
  }

  for (const button of document.querySelectorAll("[data-girls-view]")) {
    if (!(button instanceof HTMLButtonElement)) throw new Error("Girls navigation item must be a button.");
    button.addEventListener("click", () => {
      if (!authoringPanel.classList.contains("girls-view-hidden")) {
        controller.destroy();
      }
      clearAuthoringNavigation();
    });
  }

  new MutationObserver(() => {
    if (shell.classList.contains("hidden")) {
      controller.destroy();
      clearAuthoringNavigation();
    }
  }).observe(shell, {
    attributes: true,
    attributeFilter: ["class"],
  });

  globalThis.MinAppGirlsAuthoringPortal = Object.freeze({
    activate: openAuthoringView,
    destroy() {
      controller.destroy();
      clearAuthoringNavigation();
    },
  });
})();
