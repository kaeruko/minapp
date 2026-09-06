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
