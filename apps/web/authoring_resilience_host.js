"use strict";

(function defineAuthoringResilienceHost(root, factory) {
  const api = factory();
  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  }
  if (root && typeof root === "object") {
    Object.defineProperty(root, "MinAppAuthoringResilienceHost", {
      configurable: true,
      value: Object.freeze(api),
    });
  }
})(typeof globalThis === "object" ? globalThis : null, function createAuthoringResilienceHost() {
  const RECOVERY_CHANNEL = "minapp.novel-editor.recovery";
  const RECOVERY_VERSION = 1;
  const RECOVERY_REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
  const HOSTED_ID_PATTERN = /^[0-9a-f]{32}$/;
  const RECOVERY_STORAGE_PREFIX = "minapp_novel_editor_recovery_v1:";
  const DEFAULT_RECOVERY_MAX_CHARS = 1500000;
  const RENEWABLE_SESSION_ERRORS = new Set([
    "authoring_session_not_found",
    "authoring_request_limit_reached",
    "runtime_session_not_found",
    "runtime_request_limit_reached",
  ]);

  function requirePlainObject(value, label) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new Error(`${label} must be an object.`);
    }
    return value;
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

  function installSessionRenewal({ authoringApi, getAccessToken }) {
    if (!authoringApi || typeof authoringApi !== "object") {
      throw new TypeError("authoringApi is required.");
    }
    if (typeof authoringApi.WebAuthoringHostAdapter !== "function" ||
        typeof authoringApi.HostedWebApiError !== "function" ||
        typeof authoringApi.createWebAuthoringLaunch !== "function") {
      throw new TypeError("authoringApi does not expose the required Web Authoring surface.");
    }
    if (typeof getAccessToken !== "function") {
      throw new TypeError("getAccessToken must be a function.");
    }

    const prototype = authoringApi.WebAuthoringHostAdapter.prototype;
    if (prototype.__authoringSessionRenewalInstalled === true) return false;
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
        if (renewed.contentId !== this.launch.contentId ||
            renewed.editorAppId !== this.launch.editorAppId ||
            renewed.contentFormat !== this.launch.contentFormat) {
          throw new Error("Renewed Authoring session changed Editor scope.");
        }

        // Keep the current child frame and its original bridge nonce. Only the
        // short-lived capabilities are replaced, then the original operation is
        // retried exactly once. A second failure is surfaced unchanged.
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

    Object.defineProperty(prototype, "__authoringSessionRenewalInstalled", {
      configurable: false,
      enumerable: false,
      value: true,
    });
    return true;
  }

  class NovelRecoveryHost {
    constructor({
      frame,
      storage,
      getActiveContentId,
      eventTarget = globalThis,
      maxChars = DEFAULT_RECOVERY_MAX_CHARS,
    }) {
      if (!frame || typeof frame !== "object" ||
          !frame.contentWindow || typeof frame.contentWindow.postMessage !== "function") {
        throw new TypeError("frame must be an iframe-like object with contentWindow.postMessage.");
      }
      if (!frame.sandbox || typeof frame.sandbox.contains !== "function" ||
          !frame.sandbox.contains("allow-scripts") || frame.sandbox.contains("allow-same-origin")) {
        throw new Error("Novel recovery frame must use the opaque allow-scripts sandbox.");
      }
      if (!storage || typeof storage.getItem !== "function" ||
          typeof storage.setItem !== "function" || typeof storage.removeItem !== "function") {
        throw new TypeError("storage must provide getItem/setItem/removeItem.");
      }
      if (typeof getActiveContentId !== "function") {
        throw new TypeError("getActiveContentId must be a function.");
      }
      if (!eventTarget || typeof eventTarget.addEventListener !== "function" ||
          typeof eventTarget.removeEventListener !== "function") {
        throw new TypeError("eventTarget must support addEventListener/removeEventListener.");
      }
      if (!Number.isInteger(maxChars) || maxChars < 1) {
        throw new TypeError("maxChars must be a positive integer.");
      }
      this.frame = frame;
      this.storage = storage;
      this.getActiveContentId = getActiveContentId;
      this.eventTarget = eventTarget;
      this.maxChars = maxChars;
      this.attached = false;
      this.listener = (event) => { this.handleMessageEvent(event); };
    }

    attach() {
      if (this.attached) throw new Error("Novel recovery host is already attached.");
      this.eventTarget.addEventListener("message", this.listener);
      this.attached = true;
    }

    destroy() {
      if (!this.attached) return;
      this.eventTarget.removeEventListener("message", this.listener);
      this.attached = false;
    }

    storageKey(contentId) {
      return `${RECOVERY_STORAGE_PREFIX}${validateHostedId(contentId, "Recovery content id")}`;
    }

    postSuccess(id, result) {
      this.frame.contentWindow.postMessage({
        channel: RECOVERY_CHANNEL,
        version: RECOVERY_VERSION,
        type: "response",
        id,
        ok: true,
        result,
      }, "*");
    }

    postFailure(id, error) {
      this.frame.contentWindow.postMessage({
        channel: RECOVERY_CHANNEL,
        version: RECOVERY_VERSION,
        type: "response",
        id,
        ok: false,
        error: {
          code: "recovery_store_error",
          message: error instanceof Error ? error.message : String(error),
        },
      }, "*");
    }

    handleMessageEvent(event) {
      if (!event || event.source !== this.frame.contentWindow || event.origin !== "null") return false;
      const raw = event.data;
      if (typeof raw !== "object" || raw === null || Array.isArray(raw) ||
          raw.channel !== RECOVERY_CHANNEL || raw.version !== RECOVERY_VERSION ||
          raw.type !== "request") {
        return false;
      }
      const id = typeof raw.id === "string" && RECOVERY_REQUEST_ID_PATTERN.test(raw.id)
        ? raw.id
        : null;
      if (id === null) return true;

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
        const activeContentId = this.getActiveContentId();
        if (activeContentId === null ||
            validateHostedId(activeContentId, "Active recovery content id") !== contentId) {
          throw new Error("Novel recovery request does not match the active Editor content.");
        }

        const key = this.storageKey(contentId);
        let result = null;
        if (raw.method === "load") {
          const stored = this.storage.getItem(key);
          result = stored === null
            ? null
            : validateStoredRecovery(JSON.parse(stored), contentId);
        } else if (raw.method === "clear") {
          this.storage.removeItem(key);
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
          if (stored.length > this.maxChars) {
            throw new Error("Novel recovery backup is too large for local storage.");
          }
          this.storage.setItem(key, stored);
        }
        this.postSuccess(id, result);
      } catch (error) {
        this.postFailure(id, error);
      }
      return true;
    }
  }

  return Object.freeze({
    RECOVERY_CHANNEL,
    RECOVERY_VERSION,
    RENEWABLE_SESSION_ERRORS,
    validateStoredRecovery,
    installSessionRenewal,
    NovelRecoveryHost,
  });
});
