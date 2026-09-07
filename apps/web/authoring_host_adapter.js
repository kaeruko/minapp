"use strict";

(function defineMinAppWebAuthoring(root, factory) {
  const api = factory();
  if (typeof module === "object" && module !== null && module.exports) {
    module.exports = api;
  }
  if (root && typeof root === "object") {
    Object.defineProperty(root, "MinAppWebAuthoring", {
      configurable: true,
      value: Object.freeze(api),
    });
  }
})(typeof globalThis === "object" ? globalThis : null, function createMinAppWebAuthoring() {
  const BRIDGE_VERSION = 1;
  const BRIDGE_CHANNEL = "minapp.web";
  const ID_PATTERN = /^[0-9a-f]{32}$/;
  const TOKEN_PATTERN = /^[A-Za-z0-9_-]{32,64}$/;
  const REQUEST_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;
  const STATE_KEY_PATTERN = /^[a-z][a-z0-9_.-]{0,63}$/;
  const CONTENT_FORMAT_PATTERN = /^[a-z0-9][a-z0-9._-]{0,63}\/[a-z0-9][a-z0-9._-]{0,63}@[1-9][0-9]{0,5}$/;
  const EDITOR_PATH_PATTERN = /^\/hosted\/authoring-editor\/[A-Za-z0-9_-]{32,64}\/index\.html$/;
  const PREVIEW_PATH_PATTERN = /^\/hosted\/authoring-preview\/[A-Za-z0-9_-]{32,64}\/index\.html$/;
  const AUTHORING_METHODS = new Set([
    "authoring.load",
    "authoring.save",
    "authoring.preview",
    "authoring.publish",
  ]);
  const RUNTIME_METHODS = new Set([
    "state.get",
    "state.set",
    "state.delete",
    "userState.get",
    "userState.set",
    "userState.delete",
  ]);

  class HostedWebApiError extends Error {
    constructor(status, code, message) {
      super(message);
      this.name = "HostedWebApiError";
      this.status = status;
      this.code = code;
    }
  }

  class WebAuthoringBridgeProtocolError extends Error {
    constructor(code, message, requestId = null) {
      super(message);
      this.name = "WebAuthoringBridgeProtocolError";
      this.code = code;
      this.requestId = requestId;
    }
  }

  function isPlainObject(value) {
    return typeof value === "object" && value !== null && !Array.isArray(value);
  }

  function requirePlainObject(value, label) {
    if (!isPlainObject(value)) throw new Error(`${label} must be an object.`);
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

  function validateId(value, label) {
    if (typeof value !== "string" || !ID_PATTERN.test(value)) {
      throw new Error(`${label} must be a 32-character lowercase hexadecimal id.`);
    }
    return value;
  }

  function validateToken(value, label) {
    if (typeof value !== "string" || !TOKEN_PATTERN.test(value)) {
      throw new Error(`${label} has an invalid token format.`);
    }
    return value;
  }

  function validateContentFormat(value, label) {
    if (typeof value !== "string" || !CONTENT_FORMAT_PATTERN.test(value)) {
      throw new Error(`${label} must be a namespaced versioned content format.`);
    }
    return value;
  }

  function validateApiOrigin(value) {
    if (typeof value !== "string" || value.length === 0 || value !== value.trim()) {
      throw new Error("Hosted API origin is invalid.");
    }
    let url;
    try {
      url = new URL(value);
    } catch (error) {
      throw new Error("Hosted API origin is not a valid URL.", { cause: error });
    }
    if (
      url.protocol !== "https:" ||
      url.username !== "" ||
      url.password !== "" ||
      url.pathname !== "/" ||
      url.search !== "" ||
      url.hash !== ""
    ) {
      throw new Error("Hosted API origin must be an HTTPS origin without path/query/fragment.");
    }
    return url.origin;
  }

  function validateAccessToken(value) {
    if (typeof value !== "string" || value.length === 0) {
      throw new Error("accessToken must be a non-empty string.");
    }
    return value;
  }

  function validateFetch(fetchImpl) {
    if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl must be a function.");
    return fetchImpl;
  }

  function validateResponseContentType(response, context) {
    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new HostedWebApiError(
        response.status,
        "invalid_api_response",
        `${context} returned a non-JSON response (HTTP ${response.status}).`,
      );
    }
  }

  async function decodeJsonResponse(response, context) {
    validateResponseContentType(response, context);
    let payload;
    try {
      payload = await response.json();
    } catch (error) {
      throw new HostedWebApiError(
        response.status,
        "invalid_api_response",
        `${context} returned invalid JSON.`,
      );
    }
    if (!isPlainObject(payload)) {
      throw new HostedWebApiError(
        response.status,
        "invalid_api_response",
        `${context} returned a non-object JSON payload.`,
      );
    }
    if (!response.ok) {
      let errorPayload;
      try {
        errorPayload = requireExactFields(payload, ["error", "message"], `${context} error response`);
      } catch (error) {
        throw new HostedWebApiError(
          response.status,
          "invalid_api_response",
          `${context} error response fields are invalid.`,
        );
      }
      const code = requireString(errorPayload.error, `${context} error code`);
      const message = requireString(errorPayload.message, `${context} error message`);
      throw new HostedWebApiError(response.status, code, message);
    }
    return payload;
  }

  async function jsonRequest({
    apiOrigin,
    fetchImpl,
    method,
    path,
    accessToken = null,
    body = null,
    context,
  }) {
    const origin = validateApiOrigin(apiOrigin);
    validateFetch(fetchImpl);
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Hosted API path must be origin-relative.");
    }
    if (!new Set(["GET", "POST"]).has(method)) {
      throw new TypeError(`Unsupported JSON request method: ${String(method)}`);
    }
    if (method === "GET" && body !== null) {
      throw new TypeError("GET request must not contain a body.");
    }
    const url = new URL(path, `${origin}/`);
    if (url.origin !== origin) throw new Error("Hosted API path escaped the configured origin.");
    const headers = { Accept: "application/json" };
    if (accessToken !== null) headers.Authorization = `Bearer ${validateAccessToken(accessToken)}`;
    const options = {
      method,
      headers,
      cache: "no-store",
      credentials: "omit",
    };
    if (body !== null) {
      if (!isPlainObject(body)) throw new TypeError("JSON request body must be an object.");
      headers["Content-Type"] = "application/json";
      options.body = JSON.stringify(body);
    }
    let response;
    try {
      response = await fetchImpl(url.toString(), options);
    } catch (error) {
      throw new HostedWebApiError(0, "host_adapter_request_failed", String(error));
    }
    return await decodeJsonResponse(response, context);
  }

  async function emptyRequest({ apiOrigin, fetchImpl, method, path, context }) {
    const origin = validateApiOrigin(apiOrigin);
    validateFetch(fetchImpl);
    if (method !== "DELETE") throw new TypeError("Empty request currently supports DELETE only.");
    if (typeof path !== "string" || !path.startsWith("/") || path.startsWith("//")) {
      throw new TypeError("Hosted API path must be origin-relative.");
    }
    const url = new URL(path, `${origin}/`);
    if (url.origin !== origin) throw new Error("Hosted API path escaped the configured origin.");
    let response;
    try {
      response = await fetchImpl(url.toString(), {
        method: "DELETE",
        headers: { Accept: "application/json" },
        cache: "no-store",
        credentials: "omit",
      });
    } catch (error) {
      throw new HostedWebApiError(0, "host_adapter_request_failed", String(error));
    }
    if (response.status === 204) {
      const body = await response.text();
      if (body.length !== 0) {
        throw new HostedWebApiError(204, "invalid_api_response", `${context} returned a body for HTTP 204.`);
      }
      return;
    }
    await decodeJsonResponse(response, context);
    throw new HostedWebApiError(response.status, "invalid_api_response", `${context} returned an unexpected success status.`);
  }

  function validateLaunchPayload(payload, requestedContentId, requestedEditorAppId, apiOrigin) {
    requireExactFields(
      payload,
      [
        "content_path",
        "content_expires_in",
        "runtime_token",
        "runtime_expires_in",
        "authoring_token",
        "authoring_expires_in",
        "content_id",
        "content_format",
        "editor_app_id",
        "allowed_operations",
        "web_bridge_nonce",
      ],
      "Web Authoring launch response",
    );
    const contentId = validateId(payload.content_id, "launch content_id");
    const editorAppId = validateId(payload.editor_app_id, "launch editor_app_id");
    if (contentId !== requestedContentId || editorAppId !== requestedEditorAppId) {
      throw new Error("Web Authoring launch response changed the requested scope.");
    }
    const contentPath = requireString(payload.content_path, "launch content_path");
    if (!EDITOR_PATH_PATTERN.test(contentPath)) {
      throw new Error("Web Authoring launch returned an invalid Editor content path.");
    }
    const allowedOperations = payload.allowed_operations;
    if (!Array.isArray(allowedOperations) ||
        allowedOperations.some((value) => typeof value !== "string" || value.length === 0)) {
      throw new Error("Web Authoring launch allowed_operations is invalid.");
    }
    const requiredOperations = ["load", "save_document", "preview_request", "publish_request"];
    for (const operation of requiredOperations) {
      if (!allowedOperations.includes(operation)) {
        throw new Error(`Web Authoring launch is missing required operation: ${operation}.`);
      }
    }
    const origin = validateApiOrigin(apiOrigin);
    return Object.freeze({
      contentUrl: new URL(contentPath, `${origin}/`).toString(),
      contentPath,
      contentExpiresIn: requirePositiveInteger(payload.content_expires_in, "launch content_expires_in"),
      runtimeToken: validateToken(payload.runtime_token, "launch runtime_token"),
      runtimeExpiresIn: requirePositiveInteger(payload.runtime_expires_in, "launch runtime_expires_in"),
      authoringToken: validateToken(payload.authoring_token, "launch authoring_token"),
      authoringExpiresIn: requirePositiveInteger(payload.authoring_expires_in, "launch authoring_expires_in"),
      contentId,
      contentFormat: validateContentFormat(payload.content_format, "launch content_format"),
      editorAppId,
      allowedOperations: Object.freeze([...allowedOperations]),
      webBridgeNonce: validateToken(payload.web_bridge_nonce, "launch web_bridge_nonce"),
    });
  }

  async function createWebAuthoringLaunch({
    apiOrigin,
    accessToken,
    contentId,
    editorAppId,
    fetchImpl = globalThis.fetch,
  }) {
    validateId(contentId, "contentId");
    validateId(editorAppId, "editorAppId");
    const payload = await jsonRequest({
      apiOrigin,
      fetchImpl,
      method: "POST",
      path: `/hosted/authoring/projects/${contentId}/launch`,
      accessToken,
      body: { editor_app_id: editorAppId, host_adapter: "web" },
      context: "Web Authoring launch",
    });
    return validateLaunchPayload(payload, contentId, editorAppId, apiOrigin);
  }

  async function listAuthoringApps({ apiOrigin, accessToken, groupId, fetchImpl = globalThis.fetch }) {
    validateId(groupId, "groupId");
    const payload = await jsonRequest({
      apiOrigin,
      fetchImpl,
      method: "GET",
      path: `/hosted/authoring/groups/${groupId}/apps`,
      accessToken,
      context: "Authoring app discovery",
    });
    requireExactFields(payload, ["apps"], "Authoring app discovery response");
    if (!Array.isArray(payload.apps)) throw new Error("Authoring app discovery apps must be a list.");
    return Object.freeze(payload.apps.map((rawApp) => {
      const app = requireExactFields(rawApp, ["app_id", "group_id", "title", "edits", "accepts"], "Authoring app");
      const appId = validateId(app.app_id, "Authoring app app_id");
      const returnedGroupId = validateId(app.group_id, "Authoring app group_id");
      if (returnedGroupId !== groupId) throw new Error("Authoring app discovery changed group scope.");
      const title = requireString(app.title, "Authoring app title");
      const validateFormats = (value, label) => {
        if (!Array.isArray(value) || value.some((format) => typeof format !== "string" || !CONTENT_FORMAT_PATTERN.test(format))) {
          throw new Error(`${label} is invalid.`);
        }
        return Object.freeze([...value]);
      };
      return Object.freeze({
        appId,
        groupId: returnedGroupId,
        title,
        edits: validateFormats(app.edits, "Authoring app edits"),
        accepts: validateFormats(app.accepts, "Authoring app accepts"),
      });
    }));
  }

  function playersFor(apps, contentFormat) {
    validateContentFormat(contentFormat, "contentFormat");
    if (!Array.isArray(apps)) throw new TypeError("apps must be a list.");
    return apps.filter((app) => app && Array.isArray(app.accepts) && app.accepts.includes(contentFormat));
  }

  async function createAuthoringPreview({
    apiOrigin,
    accessToken,
    contentId,
    playerAppId,
    expectedRevision,
    fetchImpl = globalThis.fetch,
  }) {
    validateId(contentId, "contentId");
    validateId(playerAppId, "playerAppId");
    requirePositiveInteger(expectedRevision, "expectedRevision");
    const payload = await jsonRequest({
      apiOrigin,
      fetchImpl,
      method: "POST",
      path: `/hosted/authoring/projects/${contentId}/preview`,
      accessToken,
      body: { player_app_id: playerAppId, expected_revision: expectedRevision },
      context: "Authoring preview",
    });
    requireExactFields(
      payload,
      [
        "content_id",
        "content_format",
        "draft_revision",
        "player_app_id",
        "content_path",
        "expires_in",
        "runtime_token",
        "runtime_expires_in",
      ],
      "Authoring preview response",
    );
    if (payload.content_id !== contentId || payload.player_app_id !== playerAppId || payload.draft_revision !== expectedRevision) {
      throw new Error("Authoring preview response changed requested scope or revision.");
    }
    validateContentFormat(payload.content_format, "preview content_format");
    const contentPath = requireString(payload.content_path, "preview content_path");
    if (!PREVIEW_PATH_PATTERN.test(contentPath)) throw new Error("Authoring preview returned an invalid content path.");
    const origin = validateApiOrigin(apiOrigin);
    return Object.freeze({
      contentId,
      contentFormat: payload.content_format,
      draftRevision: expectedRevision,
      playerAppId,
      contentPath,
      contentUrl: new URL(contentPath, `${origin}/`).toString(),
      expiresIn: requirePositiveInteger(payload.expires_in, "preview expires_in"),
      runtimeToken: validateToken(payload.runtime_token, "preview runtime_token"),
      runtimeExpiresIn: requirePositiveInteger(payload.runtime_expires_in, "preview runtime_expires_in"),
    });
  }

  function protocolError(code, message, requestId = null) {
    return new WebAuthoringBridgeProtocolError(code, message, requestId);
  }

  function decodeBridgeRequest(data, expectedNonce) {
    if (!isPlainObject(data)) throw protocolError("invalid_bridge_request", "Web bridge request must be an object.");
    const id = typeof data.id === "string" && REQUEST_ID_PATTERN.test(data.id) ? data.id : null;
    if (data.channel !== BRIDGE_CHANNEL || data.nonce !== expectedNonce) {
      throw protocolError("bridge_scope_mismatch", "Web bridge request scope is invalid.", id);
    }
    if (data.version !== BRIDGE_VERSION) {
      throw protocolError("unsupported_bridge_version", `Web bridge version must be ${BRIDGE_VERSION}.`, id);
    }
    if (data.type !== "request") {
      throw protocolError("invalid_bridge_request", "Web bridge message type must be request.", id);
    }
    if (id === null) throw protocolError("invalid_bridge_request", "Web bridge request id is invalid.");
    if (typeof data.method !== "string" || (!AUTHORING_METHODS.has(data.method) && !RUNTIME_METHODS.has(data.method))) {
      throw protocolError("unsupported_bridge_method", "Web bridge method is not supported.", id);
    }

    const common = ["channel", "nonce", "version", "type", "id", "method"];
    if (RUNTIME_METHODS.has(data.method)) {
      const needsValue = data.method.endsWith(".set");
      const expected = [...common, "key", ...(needsValue ? ["value"] : [])];
      try {
        requireExactFields(data, expected, "Runtime bridge request");
      } catch (error) {
        throw protocolError("invalid_bridge_request", "Runtime bridge request fields are invalid.", id);
      }
      if (typeof data.key !== "string" || !STATE_KEY_PATTERN.test(data.key)) {
        throw protocolError("invalid_state_key", "State key is invalid.", id);
      }
      return Object.freeze({ id, method: data.method, key: data.key, hasValue: needsValue, value: data.value });
    }

    if (data.method === "authoring.load") {
      try {
        requireExactFields(data, common, "Authoring load request");
      } catch (error) {
        throw protocolError("invalid_bridge_request", "Authoring load request fields are invalid.", id);
      }
      return Object.freeze({ id, method: data.method });
    }

    const expected = data.method === "authoring.save"
      ? [...common, "expectedRevision", "data"]
      : [...common, "expectedRevision"];
    try {
      requireExactFields(data, expected, "Authoring bridge request");
    } catch (error) {
      throw protocolError("invalid_bridge_request", "Authoring bridge request fields are invalid.", id);
    }
    if (!Number.isInteger(data.expectedRevision) || data.expectedRevision < 1) {
      throw protocolError("invalid_expected_revision", "expectedRevision must be a positive integer.", id);
    }
    if (data.method === "authoring.save" && !isPlainObject(data.data)) {
      throw protocolError("invalid_master_data", "Authoring save data must be an object.", id);
    }
    return Object.freeze({
      id,
      method: data.method,
      expectedRevision: data.expectedRevision,
      ...(data.method === "authoring.save" ? { data: data.data } : {}),
    });
  }

  function successResponse(nonce, id, result) {
    return {
      channel: BRIDGE_CHANNEL,
      nonce,
      version: BRIDGE_VERSION,
      type: "response",
      id,
      ok: true,
      result,
    };
  }

  function errorResponse(nonce, id, status, code, message) {
    return {
      channel: BRIDGE_CHANNEL,
      nonce,
      version: BRIDGE_VERSION,
      type: "response",
      id,
      ok: false,
      error: { status, code, message },
    };
  }

  function validateFrameSandbox(frame) {
    if (!frame || typeof frame !== "object") throw new TypeError("frame must be an iframe-like object.");
    if (!frame.contentWindow || typeof frame.contentWindow.postMessage !== "function") {
      throw new TypeError("frame.contentWindow must support postMessage.");
    }
    if (!frame.sandbox || typeof frame.sandbox.contains !== "function") {
      throw new TypeError("frame must expose a sandbox token list.");
    }
    if (!frame.sandbox.contains("allow-scripts")) {
      throw new Error("Web Authoring iframe must allow scripts.");
    }
    if (frame.sandbox.contains("allow-same-origin")) {
      throw new Error("Web Authoring iframe must not allow same-origin.");
    }
  }

  class WebAuthoringHostAdapter {
    constructor({
      frame,
      apiOrigin,
      launch,
      previewHandler,
      fetchImpl = globalThis.fetch,
      eventTarget = globalThis,
    }) {
      validateFrameSandbox(frame);
      this.frame = frame;
      this.apiOrigin = validateApiOrigin(apiOrigin);
      this.fetchImpl = validateFetch(fetchImpl);
      this.launch = launch;
      if (!launch || typeof launch !== "object") throw new TypeError("launch must be a Web Authoring launch grant.");
      validateId(launch.contentId, "launch contentId");
      validateId(launch.editorAppId, "launch editorAppId");
      validateToken(launch.runtimeToken, "launch runtimeToken");
      validateToken(launch.authoringToken, "launch authoringToken");
      validateToken(launch.webBridgeNonce, "launch webBridgeNonce");
      if (typeof previewHandler !== "function") throw new TypeError("previewHandler must be a function.");
      this.previewHandler = previewHandler;
      if (!eventTarget || typeof eventTarget.addEventListener !== "function" || typeof eventTarget.removeEventListener !== "function") {
        throw new TypeError("eventTarget must support addEventListener/removeEventListener.");
      }
      this.eventTarget = eventTarget;
      this.inFlight = new Set();
      this.attached = false;
      this.listener = (event) => { void this.handleMessageEvent(event); };
    }

    attach() {
      if (this.attached) throw new Error("Web Authoring Host Adapter is already attached.");
      this.eventTarget.addEventListener("message", this.listener);
      this.attached = true;
    }

    destroy() {
      if (!this.attached) return;
      this.eventTarget.removeEventListener("message", this.listener);
      this.attached = false;
      this.inFlight.clear();
    }

    async handleMessageEvent(event) {
      if (!event || event.source !== this.frame.contentWindow) return false;
      // sandbox="allow-scripts" without allow-same-origin serializes the child
      // origin as "null". Rejecting any other origin makes sandbox relaxation
      // fail closed instead of silently widening trust.
      if (event.origin !== "null") return false;
      const raw = event.data;
      if (!isPlainObject(raw) || raw.channel !== BRIDGE_CHANNEL || raw.nonce !== this.launch.webBridgeNonce) {
        return false;
      }

      let request;
      try {
        request = decodeBridgeRequest(raw, this.launch.webBridgeNonce);
      } catch (error) {
        if (error instanceof WebAuthoringBridgeProtocolError && error.requestId !== null) {
          this.post(errorResponse(
            this.launch.webBridgeNonce,
            error.requestId,
            400,
            error.code,
            error.message,
          ));
        }
        return true;
      }

      if (this.inFlight.has(request.id)) {
        this.post(errorResponse(
          this.launch.webBridgeNonce,
          request.id,
          409,
          "duplicate_request_id",
          "A Web Authoring bridge request with this id is already in flight.",
        ));
        return true;
      }
      this.inFlight.add(request.id);
      try {
        const result = await this.dispatch(request);
        this.post(successResponse(this.launch.webBridgeNonce, request.id, result));
      } catch (error) {
        if (error instanceof HostedWebApiError) {
          this.post(errorResponse(
            this.launch.webBridgeNonce,
            request.id,
            error.status,
            error.code,
            error.message,
          ));
        } else {
          this.post(errorResponse(
            this.launch.webBridgeNonce,
            request.id,
            0,
            "authoring_host_error",
            error instanceof Error ? error.message : String(error),
          ));
        }
      } finally {
        this.inFlight.delete(request.id);
      }
      return true;
    }

    post(message) {
      // The sandboxed child has an opaque origin, so a specific targetOrigin is
      // impossible here. The child validates event.source, the trusted Portal
      // origin, protocol fields, and the per-launch nonce before accepting it.
      this.frame.contentWindow.postMessage(message, "*");
    }

    async dispatch(request) {
      if (request.method === "authoring.preview") {
        return await this.previewHandler(request.expectedRevision);
      }
      if (request.method === "authoring.load") {
        return await jsonRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "GET",
          path: `/hosted/authoring/session/${this.launch.authoringToken}`,
          context: "Authoring load",
        });
      }
      if (request.method === "authoring.save") {
        return await jsonRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "POST",
          path: `/hosted/authoring/session/${this.launch.authoringToken}/document`,
          body: { expected_revision: request.expectedRevision, document: request.data },
          context: "Authoring save",
        });
      }
      if (request.method === "authoring.publish") {
        return await jsonRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "POST",
          path: `/hosted/authoring/session/${this.launch.authoringToken}/publish`,
          body: { expected_revision: request.expectedRevision },
          context: "Authoring publish",
        });
      }

      const runtimeToken = this.launch.runtimeToken;
      const userState = request.method.startsWith("userState.");
      const scope = userState ? "user-state" : "state";
      const encodedKey = encodeURIComponent(request.key);
      if (request.method.endsWith(".get")) {
        const payload = await jsonRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "GET",
          path: `/hosted/runtime/${runtimeToken}/${scope}/${encodedKey}`,
          context: "Runtime state get",
        });
        requireExactFields(payload, ["key", "value", "updated_at"], "Runtime state get response");
        if (payload.key !== request.key) throw new Error("Runtime state response changed the requested key.");
        requireString(payload.updated_at, "Runtime state updated_at");
        return payload.value;
      }
      if (request.method.endsWith(".set")) {
        const payload = await jsonRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "POST",
          path: `/hosted/runtime/${runtimeToken}/${scope}/${encodedKey}`,
          body: { value: request.value },
          context: "Runtime state set",
        });
        requireExactFields(payload, ["key", "value", "updated_at"], "Runtime state set response");
        if (payload.key !== request.key) throw new Error("Runtime state response changed the requested key.");
        requireString(payload.updated_at, "Runtime state updated_at");
        return payload.value;
      }
      if (request.method.endsWith(".delete")) {
        await emptyRequest({
          apiOrigin: this.apiOrigin,
          fetchImpl: this.fetchImpl,
          method: "DELETE",
          path: `/hosted/runtime/${runtimeToken}/${scope}/${encodedKey}`,
          context: "Runtime state delete",
        });
        return null;
      }
      throw new Error("Validated Web Authoring bridge request has an unsupported method.");
    }
  }

  return {
    BRIDGE_VERSION,
    BRIDGE_CHANNEL,
    HostedWebApiError,
    WebAuthoringBridgeProtocolError,
    WebAuthoringHostAdapter,
    createWebAuthoringLaunch,
    listAuthoringApps,
    playersFor,
    createAuthoringPreview,
    decodeBridgeRequest,
    successResponse,
    errorResponse,
    validateApiOrigin,
  };
});
