"use strict";

(function installGirlsAuthoringPortal() {
  const portalApi = globalThis.MinAppHostedAuthoringPortal;
  if (!portalApi || typeof portalApi.HostedAuthoringPortalController !== "function") {
    throw new Error("Girls Authoring portal requires hosted_authoring_portal.js.");
  }
  if (!globalThis.MinAppWebAuthoring) {
    throw new Error("Girls Authoring portal requires authoring_host_adapter.js.");
  }

  const ACCESS_TOKEN_KEY = "minapp_girls_portal_access_token";
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

  function validateApiOrigin(value) {
    return globalThis.MinAppWebAuthoring.validateApiOrigin(value);
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

  const shell = requiredElement("girls-upload-panel");
  const authoringPanel = requiredElement("girls-view-authoring");
  const logoutButton = requiredElement("girls-logout");
  const sourceGroupSelect = requiredElement("girls-upload-group");

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
    editorFrame: requiredElement("girls-authoring-editor-frame"),
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
  controller.bind();

  function authoringViewIsVisible() {
    return !authoringPanel.classList.contains("girls-view-hidden") &&
      !shell.classList.contains("hidden");
  }

  for (const button of document.querySelectorAll(
    "[data-girls-view='authoring'], [data-girls-open-view='authoring']",
  )) {
    if (!(button instanceof HTMLButtonElement)) {
      throw new Error("Girls Authoring navigation control must be a button.");
    }
    button.addEventListener("click", () => { void controller.activate(); });
  }

  new MutationObserver(() => {
    if (shell.classList.contains("hidden")) controller.destroy();
  }).observe(shell, {
    attributes: true,
    attributeFilter: ["class"],
  });

  new MutationObserver(() => {
    if (authoringViewIsVisible()) void controller.activate();
  }).observe(authoringPanel, {
    attributes: true,
    attributeFilter: ["class"],
  });

  globalThis.MinAppGirlsAuthoringPortal = Object.freeze({
    activate: () => controller.activate(),
    destroy: () => controller.destroy(),
  });
})();
