"use strict";

(function attachPortalRouting(root, factory) {
  const api = factory();
  if (typeof module === "object" && module.exports) {
    module.exports = api;
  }
  root.MinAppPortalRouting = api;
})(typeof globalThis === "object" ? globalThis : this, function buildPortalRouting() {
  const PORTAL_CONFIG_PATH = "/portal-config.json";
  const PORTAL_CONFIG_SCHEMA_VERSION = 1;
  const DIRECTORY_SCHEMA_VERSION = 1;
  const TENANT_API_PROTOCOL_VERSION = 1;
  const MAX_DESCRIPTOR_VALID_FOR_SECONDS = 86400;
  const ACCESS_TOKEN_KEY = "minapp_access_token";
  const ACCESS_TOKEN_TENANT_KEY = "minapp_access_token_tenant_id";
  const ROUTING_CACHE_KEY = "minapp_verified_tenant_route_v1";

  class PortalApiError extends Error {
    constructor(status, error, message) {
      super(message);
      this.name = "PortalApiError";
      this.status = status;
      this.error = error;
    }
  }

  function requirePlainObject(value, label) {
    if (typeof value !== "object" || value === null || Array.isArray(value)) {
      throw new TypeError(`${label} must be an object.`);
    }
    return value;
  }

  function requireExactFields(value, expectedFields, label) {
    requirePlainObject(value, label);
    const actual = Object.keys(value).sort();
    const expected = [...expectedFields].sort();
    if (actual.length !== expected.length || actual.some((name, index) => name !== expected[index])) {
      throw new Error(`${label} schema is invalid.`);
    }
  }

  function validateTenantId(value) {
    if (typeof value !== "string" || !/^[0-9a-f]{32}$/.test(value)) {
      throw new Error("tenant_id must be exactly 32 lowercase hexadecimal characters.");
    }
    return value;
  }

  function validateDisplayName(value) {
    if (
      typeof value !== "string" ||
      value.length < 1 ||
      value.length > 120 ||
      value.trim() !== value ||
      /[\u0000-\u001f]/.test(value)
    ) {
      throw new Error("display_name is invalid.");
    }
    return value;
  }

  function validatePublicHttpsBaseUrl(value, label = "base URL") {
    if (typeof value !== "string" || value.length === 0) {
      throw new TypeError(`${label} must be a non-empty string.`);
    }
    if (/[^\x00-\x7f]/.test(value)) {
      throw new Error(`${label} host must be ASCII.`);
    }

    let url;
    try {
      url = new URL(value);
    } catch (error) {
      throw new Error(`${label} is not a valid absolute URL.`, { cause: error });
    }

    if (
      url.protocol !== "https:" ||
      url.username !== "" ||
      url.password !== "" ||
      url.search !== "" ||
      url.hash !== "" ||
      !["", "/"].includes(url.pathname) ||
      url.port !== ""
    ) {
      throw new Error(`${label} must use HTTPS on the default port with no path, credentials, query, or fragment.`);
    }

    let host = url.hostname.toLowerCase();
    if (host.endsWith(".")) host = host.slice(0, -1);
    if (host.length === 0 || host.length > 253) {
      throw new Error(`${label} host is invalid.`);
    }
    if (/^\[.*\]$/.test(host) || host.includes(":") || /^\d{1,3}(?:\.\d{1,3}){3}$/.test(host)) {
      throw new Error(`${label} IP literals are not allowed.`);
    }
    if (
      host === "localhost" ||
      host.endsWith(".localhost") ||
      host.endsWith(".local") ||
      host.endsWith(".internal") ||
      host.endsWith(".lan") ||
      host.endsWith(".home") ||
      !host.includes(".")
    ) {
      throw new Error(`${label} host must be a public DNS name.`);
    }

    const labelPattern = /^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$/;
    for (const hostLabel of host.split(".")) {
      if (!labelPattern.test(hostLabel)) {
        throw new Error(`${label} host is malformed.`);
      }
    }
    return `https://${host}`;
  }

  function validatePortalConfig(payload) {
    requireExactFields(payload, ["schema_version", "directory_api_base_url"], "portal-config.json");
    if (payload.schema_version !== PORTAL_CONFIG_SCHEMA_VERSION) {
      throw new Error(`Unsupported portal config schema_version: ${payload.schema_version}`);
    }
    return Object.freeze({
      schema_version: payload.schema_version,
      directory_api_base_url: validatePublicHttpsBaseUrl(payload.directory_api_base_url, "directory_api_base_url"),
    });
  }

  function validateTenantDescriptor(payload) {
    requireExactFields(
      payload,
      ["schema_version", "tenant_id", "display_name", "api_base_url", "api_protocol_version", "config_revision", "valid_for_seconds"],
      "Directory descriptor",
    );
    if (payload.schema_version !== DIRECTORY_SCHEMA_VERSION) {
      throw new Error(`Unsupported Directory schema_version: ${payload.schema_version}`);
    }
    if (payload.api_protocol_version !== TENANT_API_PROTOCOL_VERSION) {
      throw new Error(`Unsupported tenant api_protocol_version: ${payload.api_protocol_version}`);
    }
    if (!Number.isInteger(payload.config_revision) || payload.config_revision < 1) {
      throw new Error("config_revision must be a positive integer.");
    }
    if (
      !Number.isInteger(payload.valid_for_seconds) ||
      payload.valid_for_seconds < 1 ||
      payload.valid_for_seconds > MAX_DESCRIPTOR_VALID_FOR_SECONDS
    ) {
      throw new Error("valid_for_seconds is outside the supported range.");
    }

    return Object.freeze({
      schema_version: payload.schema_version,
      tenant_id: validateTenantId(payload.tenant_id),
      display_name: validateDisplayName(payload.display_name),
      api_base_url: validatePublicHttpsBaseUrl(payload.api_base_url, "api_base_url"),
      api_protocol_version: payload.api_protocol_version,
      config_revision: payload.config_revision,
      valid_for_seconds: payload.valid_for_seconds,
    });
  }

  function routeFromDescriptor(descriptor) {
    return Object.freeze({
      tenant_id: descriptor.tenant_id,
      display_name: descriptor.display_name,
      api_base_url: descriptor.api_base_url,
      api_protocol_version: descriptor.api_protocol_version,
      config_revision: descriptor.config_revision,
    });
  }

  function validateRoutingCache(payload) {
    requireExactFields(
      payload,
      ["tenant_id", "display_name", "api_base_url", "api_protocol_version", "config_revision", "verified_at", "expires_at"],
      "routing cache",
    );
    if (payload.api_protocol_version !== TENANT_API_PROTOCOL_VERSION) {
      throw new Error(`Unsupported cached tenant api_protocol_version: ${payload.api_protocol_version}`);
    }
    if (!Number.isInteger(payload.config_revision) || payload.config_revision < 1) {
      throw new Error("Cached config_revision must be a positive integer.");
    }
    if (!Number.isInteger(payload.verified_at) || payload.verified_at < 0) {
      throw new Error("Cached verified_at is invalid.");
    }
    if (!Number.isInteger(payload.expires_at) || payload.expires_at <= payload.verified_at) {
      throw new Error("Cached expires_at is invalid.");
    }

    return Object.freeze({
      tenant_id: validateTenantId(payload.tenant_id),
      display_name: validateDisplayName(payload.display_name),
      api_base_url: validatePublicHttpsBaseUrl(payload.api_base_url, "cached api_base_url"),
      api_protocol_version: payload.api_protocol_version,
      config_revision: payload.config_revision,
      verified_at: payload.verified_at,
      expires_at: payload.expires_at,
    });
  }

  function validateNow(now) {
    if (!Number.isInteger(now) || now < 0) throw new TypeError("now() must return a non-negative integer timestamp in milliseconds.");
    return now;
  }

  function validateRelativeApiPath(path) {
    if (typeof path !== "string" || path.length === 0 || !path.startsWith("/") || path.startsWith("//") || path.includes("\\")) {
      throw new TypeError("Tenant API path must be a single-origin relative path starting with exactly one /.");
    }
    const hashIndex = path.indexOf("#");
    if (hashIndex !== -1) throw new TypeError("Tenant API path must not contain a fragment.");
    return path;
  }

  async function decodeJsonResponse(response) {
    if (response.status === 204) {
      if (!response.ok) throw new PortalApiError(response.status, "http_error", `HTTP ${response.status}`);
      return null;
    }
    const contentType = response.headers.get("content-type");
    if (contentType === null || !contentType.toLowerCase().startsWith("application/json")) {
      throw new Error(`API returned a non-JSON response (HTTP ${response.status}).`);
    }
    const payload = await response.json();
    if (typeof payload !== "object" || payload === null || Array.isArray(payload)) {
      throw new Error("API returned an unexpected JSON payload.");
    }
    if (!response.ok) {
      const error = typeof payload.error === "string" ? payload.error : "api_error";
      const message = typeof payload.message === "string" ? payload.message : `API request failed with HTTP ${response.status}.`;
      throw new PortalApiError(response.status, error, message);
    }
    return payload;
  }

  function validateRequestOptions(options) {
    requirePlainObject(options, "request options");
    const allowed = new Set(["method", "headers", "body", "jsonBody", "authenticated", "signal"]);
    for (const name of Object.keys(options)) {
      if (!allowed.has(name)) throw new TypeError(`Unsupported request option: ${name}`);
    }
    if (options.body !== undefined && options.jsonBody !== undefined) {
      throw new TypeError("Request must not contain both body and jsonBody.");
    }
  }

  class PortalRouter {
    constructor({ fetchImpl, sessionStorage, localStorage, now = Date.now } = {}) {
      if (typeof fetchImpl !== "function") throw new TypeError("fetchImpl is required.");
      if (sessionStorage === null || typeof sessionStorage !== "object") throw new TypeError("sessionStorage is required.");
      if (localStorage === null || typeof localStorage !== "object") throw new TypeError("localStorage is required.");
      if (typeof now !== "function") throw new TypeError("now must be a function.");
      for (const [name, storage] of [["sessionStorage", sessionStorage], ["localStorage", localStorage]]) {
        for (const method of ["getItem", "setItem", "removeItem"]) {
          if (typeof storage[method] !== "function") throw new TypeError(`${name}.${method} is required.`);
        }
      }

      this.fetchImpl = fetchImpl;
      this.sessionStorage = sessionStorage;
      this.localStorage = localStorage;
      this.now = now;
      this.portalConfig = null;
      this.currentTenant = null;
      this.requestsEnabled = false;
    }

    async loadPortalConfig() {
      const response = await this.fetchImpl(PORTAL_CONFIG_PATH, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        credentials: "same-origin",
      });
      const payload = await decodeJsonResponse(response);
      this.portalConfig = validatePortalConfig(payload);
      return this.portalConfig;
    }

    setPortalConfig(payload) {
      this.portalConfig = validatePortalConfig(payload);
      return this.portalConfig;
    }

    requirePortalConfig() {
      if (this.portalConfig === null) throw new Error("Portal configuration is not loaded.");
      return this.portalConfig;
    }

    clearAuthentication() {
      this.sessionStorage.removeItem(ACCESS_TOKEN_KEY);
      this.sessionStorage.removeItem(ACCESS_TOKEN_TENANT_KEY);
    }

    storeAccessToken(accessToken) {
      if (!this.requestsEnabled || this.currentTenant === null) {
        throw new Error("Cannot store an access token before a tenant endpoint is verified.");
      }
      if (typeof accessToken !== "string" || accessToken.length === 0) {
        throw new TypeError("accessToken must be a non-empty string.");
      }
      this.clearAuthentication();
      this.sessionStorage.setItem(ACCESS_TOKEN_TENANT_KEY, this.currentTenant.tenant_id);
      this.sessionStorage.setItem(ACCESS_TOKEN_KEY, accessToken);
    }

    loadRoutingCache() {
      const raw = this.localStorage.getItem(ROUTING_CACHE_KEY);
      if (raw === null) return null;
      let decoded;
      try {
        decoded = JSON.parse(raw);
      } catch (error) {
        this.localStorage.removeItem(ROUTING_CACHE_KEY);
        throw new Error("Routing cache contains invalid JSON.", { cause: error });
      }
      try {
        return validateRoutingCache(decoded);
      } catch (error) {
        this.localStorage.removeItem(ROUTING_CACHE_KEY);
        throw error;
      }
    }

    saveVerifiedDescriptor(descriptor) {
      const now = validateNow(this.now());
      const expiresAt = now + descriptor.valid_for_seconds * 1000;
      if (!Number.isSafeInteger(expiresAt)) throw new Error("Routing cache expiry exceeds the supported timestamp range.");
      const route = routeFromDescriptor(descriptor);
      const record = Object.freeze({
        ...route,
        verified_at: now,
        expires_at: expiresAt,
      });
      this.localStorage.setItem(ROUTING_CACHE_KEY, JSON.stringify(record));
      this.currentTenant = route;
      this.requestsEnabled = true;
      return route;
    }

    async clearForClassroomChange({ resetTransientState } = {}) {
      if (resetTransientState !== undefined && typeof resetTransientState !== "function") {
        throw new TypeError("resetTransientState must be a function when provided.");
      }
      this.requestsEnabled = false;
      this.clearAuthentication();

      let resetError = null;
      if (resetTransientState !== undefined) {
        try {
          await resetTransientState();
        } catch (error) {
          resetError = error;
        }
      }

      this.localStorage.removeItem(ROUTING_CACHE_KEY);
      this.currentTenant = null;
      if (resetError !== null) throw resetError;
    }

    async resolveClassroom(classroomCode) {
      const config = this.requirePortalConfig();
      if (typeof classroomCode !== "string" || classroomCode.length < 1 || classroomCode.length > 64) {
        throw new TypeError("classroomCode must be a non-empty string of at most 64 characters.");
      }
      const response = await this.fetchImpl(`${config.directory_api_base_url}/v1/classrooms/resolve`, {
        method: "POST",
        headers: { Accept: "application/json", "Content-Type": "application/json" },
        body: JSON.stringify({ code: classroomCode }),
        cache: "no-store",
        credentials: "omit",
      });
      return validateTenantDescriptor(await decodeJsonResponse(response));
    }

    async refreshTenant(tenantId) {
      const config = this.requirePortalConfig();
      const validatedTenantId = validateTenantId(tenantId);
      const response = await this.fetchImpl(`${config.directory_api_base_url}/v1/tenants/${validatedTenantId}`, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        credentials: "omit",
      });
      const descriptor = validateTenantDescriptor(await decodeJsonResponse(response));
      if (descriptor.tenant_id !== validatedTenantId) {
        throw new Error("Directory returned a different tenant_id during refresh.");
      }
      return descriptor;
    }

    async verifyTenantEndpoint(descriptorOrRoute) {
      const route = descriptorOrRoute.valid_for_seconds === undefined
        ? validateRoutingCache({
            ...descriptorOrRoute,
            verified_at: 0,
            expires_at: 1,
          })
        : routeFromDescriptor(validateTenantDescriptor(descriptorOrRoute));
      const response = await this.fetchImpl(`${route.api_base_url}/tenant-info`, {
        method: "GET",
        headers: { Accept: "application/json" },
        cache: "no-store",
        credentials: "omit",
      });
      const payload = await decodeJsonResponse(response);
      requireExactFields(payload, ["service", "tenant_id", "api_protocol_version", "environment"], "tenant-info");
      if (payload.service !== "minapp-tenant-api") throw new Error("tenant-info service mismatch.");
      if (validateTenantId(payload.tenant_id) !== route.tenant_id) throw new Error("tenant-info tenant_id mismatch.");
      if (payload.api_protocol_version !== route.api_protocol_version) throw new Error("tenant-info api_protocol_version mismatch.");
      if (typeof payload.environment !== "string" || payload.environment.length === 0) throw new Error("tenant-info environment is invalid.");
      return route;
    }

    async selectClassroom(classroomCode, { resetTransientState } = {}) {
      await this.clearForClassroomChange({ resetTransientState });
      const descriptor = await this.resolveClassroom(classroomCode);
      await this.verifyTenantEndpoint(descriptor);
      return this.saveVerifiedDescriptor(descriptor);
    }

    async restoreCachedTenant() {
      this.requestsEnabled = false;
      this.clearAuthentication();
      this.currentTenant = null;

      const cached = this.loadRoutingCache();
      if (cached === null) return null;
      const now = validateNow(this.now());

      if (cached.expires_at <= now) {
        const refreshed = await this.refreshTenant(cached.tenant_id);
        if (refreshed.config_revision < cached.config_revision) {
          throw new Error("Directory config_revision moved backwards.");
        }
        await this.verifyTenantEndpoint(refreshed);
        return this.saveVerifiedDescriptor(refreshed);
      }

      await this.verifyTenantEndpoint(cached);
      this.currentTenant = Object.freeze({
        tenant_id: cached.tenant_id,
        display_name: cached.display_name,
        api_base_url: cached.api_base_url,
        api_protocol_version: cached.api_protocol_version,
        config_revision: cached.config_revision,
      });
      this.requestsEnabled = true;
      return this.currentTenant;
    }

    async tenantApiRequest(path, options = {}) {
      if (!this.requestsEnabled || this.currentTenant === null) {
        throw new Error("Tenant API requests are blocked until a tenant endpoint is verified.");
      }
      validateRequestOptions(options);
      const relativePath = validateRelativeApiPath(path);
      const url = new URL(relativePath, `${this.currentTenant.api_base_url}/`);
      if (url.origin !== this.currentTenant.api_base_url || url.hash !== "") {
        throw new TypeError("Tenant API path escaped the selected tenant origin.");
      }

      const method = options.method ?? "GET";
      if (typeof method !== "string" || !["GET", "POST", "PUT", "PATCH", "DELETE"].includes(method)) {
        throw new TypeError(`Unsupported HTTP method: ${method}`);
      }
      if (method === "GET" && (options.body !== undefined || options.jsonBody !== undefined)) {
        throw new TypeError("GET tenant request must not contain a body.");
      }

      const headers = new Headers(options.headers ?? {});
      if (headers.has("Authorization")) {
        throw new TypeError("Authorization header is managed by tenantApiRequest and must not be supplied by callers.");
      }
      headers.set("Accept", "application/json");

      let body = options.body;
      if (options.jsonBody !== undefined) {
        headers.set("Content-Type", "application/json");
        body = JSON.stringify(options.jsonBody);
      }

      if (options.authenticated === true) {
        const token = this.sessionStorage.getItem(ACCESS_TOKEN_KEY);
        const tokenTenantId = this.sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY);
        if (token === null || token.length === 0) {
          this.clearAuthentication();
          throw new PortalApiError(401, "unauthorized", "ログインが必要です。");
        }
        if (tokenTenantId !== this.currentTenant.tenant_id) {
          this.clearAuthentication();
          throw new PortalApiError(401, "tenant_session_mismatch", "教室が変更されたため、もう一度ログインしてください。");
        }
        headers.set("Authorization", `Bearer ${token}`);
      }

      try {
        const response = await this.fetchImpl(url.toString(), {
          method,
          headers,
          body,
          cache: "no-store",
          credentials: "omit",
          signal: options.signal,
        });
        return await decodeJsonResponse(response);
      } catch (error) {
        if (error instanceof PortalApiError && error.status === 401) this.clearAuthentication();
        throw error;
      }
    }
  }

  return Object.freeze({
    ACCESS_TOKEN_KEY,
    ACCESS_TOKEN_TENANT_KEY,
    ROUTING_CACHE_KEY,
    PortalApiError,
    PortalRouter,
    validatePortalConfig,
    validatePublicHttpsBaseUrl,
    validateRoutingCache,
    validateTenantDescriptor,
    validateTenantId,
  });
});
