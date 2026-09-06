"use strict";

(function initLegalDocumentPage() {
  const CONFIG_PATH = "/girls-config.json";
  const body = document.body;
  const documentKey = body.dataset.legalDocument;

  if (documentKey !== "privacy" && documentKey !== "terms") {
    throw new Error("body[data-legal-document] must be either privacy or terms.");
  }

  const title = document.getElementById("legal-title");
  const meta = document.getElementById("legal-meta");
  const status = document.getElementById("legal-status");
  const content = document.getElementById("legal-content");

  if (!(title instanceof HTMLElement)) throw new Error("#legal-title was not found.");
  if (!(meta instanceof HTMLElement)) throw new Error("#legal-meta was not found.");
  if (!(status instanceof HTMLElement)) throw new Error("#legal-status was not found.");
  if (!(content instanceof HTMLElement)) throw new Error("#legal-content was not found.");

  function requireObject(value, label) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new Error(`${label} must be an object.`);
    }
    return value;
  }

  function requireString(value, label) {
    if (typeof value !== "string" || value.trim().length === 0) {
      throw new Error(`${label} must be a non-empty string.`);
    }
    return value;
  }

  function validateApiOrigin(value) {
    const raw = requireString(value, "hosted_api_base_url");
    if (raw !== raw.trim()) throw new Error("hosted_api_base_url must not contain surrounding whitespace.");

    let url;
    try {
      url = new URL(raw);
    } catch (error) {
      throw new Error("hosted_api_base_url is not a valid URL.", { cause: error });
    }

    if (
      url.protocol !== "https:" ||
      url.username !== "" ||
      url.password !== "" ||
      url.pathname !== "/" ||
      url.search !== "" ||
      url.hash !== ""
    ) {
      throw new Error("hosted_api_base_url must be an HTTPS origin without path, credentials, query, or fragment.");
    }

    return url.origin;
  }

  async function readJson(response, label) {
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

    requireObject(payload, `${label} response`);
    if (!response.ok) {
      const message = typeof payload.message === "string" && payload.message.length > 0
        ? payload.message
        : `HTTP ${response.status}`;
      throw new Error(`${label} failed: ${message}`);
    }
    return payload;
  }

  async function load() {
    const configResponse = await fetch(CONFIG_PATH, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "same-origin",
    });
    const config = await readJson(configResponse, "Hosted config");
    if (config.schema_version !== 1) {
      throw new Error(`Unsupported hosted config schema_version: ${String(config.schema_version)}`);
    }

    const apiOrigin = validateApiOrigin(config.hosted_api_base_url);
    const legalResponse = await fetch(`${apiOrigin}/hosted/legal`, {
      method: "GET",
      headers: { Accept: "application/json" },
      cache: "no-store",
      credentials: "omit",
    });
    const legal = await readJson(legalResponse, "Hosted legal documents");
    const selected = requireObject(legal[documentKey], `legal.${documentKey}`);
    const effectiveDate = requireString(legal.effective_date, "legal.effective_date");
    const selectedTitle = requireString(selected.title, `legal.${documentKey}.title`);
    const selectedBody = requireString(selected.body, `legal.${documentKey}.body`);
    const selectedVersion = requireString(selected.version, `legal.${documentKey}.version`);

    title.textContent = selectedTitle;
    document.title = `${selectedTitle} | みんアプ`;
    meta.textContent = `発効日: ${effectiveDate} / version: ${selectedVersion}`;
    content.textContent = selectedBody;
    status.hidden = true;
    content.hidden = false;
  }

  load().catch((error) => {
    console.error("Failed to load legal document.", error);
    status.textContent = "法的文書を読み込めませんでした。時間をおいて再読み込みしてください。";
    status.classList.add("error");
    content.hidden = true;
  });
})();
