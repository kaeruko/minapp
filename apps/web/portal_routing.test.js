"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  ACCESS_TOKEN_KEY,
  ACCESS_TOKEN_TENANT_KEY,
  ROUTING_CACHE_KEY,
  PortalApiError,
  PortalRouter,
  validatePortalConfig,
  validateTenantDescriptor,
} = require("./portal_routing.js");

const TENANT_A = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
const TENANT_B = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";
const DIRECTORY_ORIGIN = "https://directory.example.com";
const TENANT_A_ORIGIN = "https://tenant-a.example.com";

class MemoryStorage {
  constructor(entries = {}) {
    this.values = new Map(Object.entries(entries));
  }

  getItem(key) {
    return this.values.has(key) ? this.values.get(key) : null;
  }

  setItem(key, value) {
    this.values.set(String(key), String(value));
  }

  removeItem(key) {
    this.values.delete(key);
  }
}

function jsonResponse(payload, { status = 200 } = {}) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8" },
  });
}

function descriptor(overrides = {}) {
  return {
    schema_version: 1,
    tenant_id: TENANT_A,
    display_name: "教室A",
    api_base_url: TENANT_A_ORIGIN,
    api_protocol_version: 1,
    config_revision: 7,
    valid_for_seconds: 300,
    ...overrides,
  };
}

function tenantInfo(overrides = {}) {
  return {
    service: "minapp-tenant-api",
    tenant_id: TENANT_A,
    api_protocol_version: 1,
    environment: "dev-a",
    ...overrides,
  };
}

function createRouter(fetchImpl, { now = 1_000_000, sessionStorage, localStorage } = {}) {
  const router = new PortalRouter({
    fetchImpl,
    sessionStorage: sessionStorage ?? new MemoryStorage(),
    localStorage: localStorage ?? new MemoryStorage(),
    now: () => now,
  });
  router.setPortalConfig({ schema_version: 1, directory_api_base_url: DIRECTORY_ORIGIN });
  return router;
}

test("portal config parser is exact and fail-closed", () => {
  assert.deepEqual(validatePortalConfig({ schema_version: 1, directory_api_base_url: DIRECTORY_ORIGIN }), {
    schema_version: 1,
    directory_api_base_url: DIRECTORY_ORIGIN,
  });
  assert.throws(
    () => validatePortalConfig({ schema_version: 1, directory_api_base_url: DIRECTORY_ORIGIN, extra: true }),
    /schema is invalid/,
  );
  assert.throws(
    () => validatePortalConfig({ schema_version: 2, directory_api_base_url: DIRECTORY_ORIGIN }),
    /Unsupported portal config schema_version/,
  );
  assert.throws(
    () => validatePortalConfig({ schema_version: 1, directory_api_base_url: "http://directory.example.com" }),
    /must use HTTPS/,
  );
  assert.throws(
    () => validatePortalConfig({ schema_version: 1, directory_api_base_url: "https://localhost" }),
    /public DNS name/,
  );
  assert.throws(
    () => validatePortalConfig({ schema_version: 1, directory_api_base_url: "https://127.0.0.1" }),
    /IP literals/,
  );
});

test("tenant descriptor parser rejects unknown fields and unsafe endpoints", () => {
  assert.equal(validateTenantDescriptor(descriptor()).api_base_url, TENANT_A_ORIGIN);
  assert.throws(() => validateTenantDescriptor(descriptor({ extra: true })), /schema is invalid/);
  assert.throws(() => validateTenantDescriptor(descriptor({ display_name: " 教室A" })), /display_name is invalid/);
  assert.throws(() => validateTenantDescriptor(descriptor({ api_base_url: "https://tenant-a.example.com/path" })), /must use HTTPS/);
  assert.throws(() => validateTenantDescriptor(descriptor({ tenant_id: TENANT_A.toUpperCase() })), /tenant_id/);
});

test("selectClassroom resolves through Directory then verifies tenant directly", async () => {
  const calls = [];
  const router = createRouter(async (url, options) => {
    calls.push({ url, options });
    if (url === `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`) return jsonResponse(descriptor());
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    throw new Error(`Unexpected URL: ${url}`);
  });

  const route = await router.selectClassroom("7K2M-4Q9P-W6TX");
  assert.equal(route.tenant_id, TENANT_A);
  assert.equal(router.currentTenant.tenant_id, TENANT_A);
  assert.equal(router.requestsEnabled, true);
  assert.deepEqual(calls.map((call) => call.url), [
    `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`,
    `${TENANT_A_ORIGIN}/tenant-info`,
  ]);
  assert.deepEqual(JSON.parse(calls[0].options.body), { code: "7K2M-4Q9P-W6TX" });
  assert.equal(calls[0].options.credentials, "omit");
  assert.equal(calls[1].options.credentials, "omit");
  assert.equal(JSON.parse(router.localStorage.getItem(ROUTING_CACHE_KEY)).tenant_id, TENANT_A);
});

test("tenantApiRequest cannot escape the verified tenant origin", async () => {
  let fetchCount = 0;
  const router = createRouter(async (url) => {
    fetchCount += 1;
    if (url === `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`) return jsonResponse(descriptor());
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    if (url === `${TENANT_A_ORIGIN}/health`) return jsonResponse({ status: "ok" });
    throw new Error(`Unexpected URL: ${url}`);
  });
  await router.selectClassroom("ROOM-A");
  const beforeRequests = fetchCount;

  await assert.rejects(() => router.tenantApiRequest("https://evil.example.com/steal"), /relative path/);
  await assert.rejects(() => router.tenantApiRequest("//evil.example.com/steal"), /relative path/);
  await assert.rejects(() => router.tenantApiRequest("/ok\\evil"), /relative path/);
  await assert.rejects(() => router.tenantApiRequest("/health#fragment"), /fragment/);
  assert.equal(fetchCount, beforeRequests);

  assert.deepEqual(await router.tenantApiRequest("/health"), { status: "ok" });
});

test("authenticated tenant request binds the access token to the selected tenant", async () => {
  const sessionStorage = new MemoryStorage();
  let authorization = null;
  const router = createRouter(async (url, options) => {
    if (url === `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`) return jsonResponse(descriptor());
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    if (url === `${TENANT_A_ORIGIN}/me`) {
      authorization = options.headers.get("Authorization");
      return jsonResponse({ user: { login_id: "student-1" } });
    }
    throw new Error(`Unexpected URL: ${url}`);
  }, { sessionStorage });

  await router.selectClassroom("ROOM-A");
  router.storeAccessToken("secret-token-a");
  await router.tenantApiRequest("/me", { authenticated: true });
  assert.equal(authorization, "Bearer secret-token-a");

  sessionStorage.setItem(ACCESS_TOKEN_TENANT_KEY, TENANT_B);
  await assert.rejects(
    () => router.tenantApiRequest("/me", { authenticated: true }),
    (error) => error instanceof PortalApiError && error.status === 401 && error.error === "tenant_session_mismatch",
  );
  assert.equal(sessionStorage.getItem(ACCESS_TOKEN_KEY), null);
  assert.equal(sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY), null);
});

test("classroom change blocks requests and clears auth before transient state and route cache", async () => {
  const sessionStorage = new MemoryStorage();
  const localStorage = new MemoryStorage();
  const router = createRouter(async (url) => {
    if (url === `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`) return jsonResponse(descriptor());
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    throw new Error(`Unexpected URL: ${url}`);
  }, { sessionStorage, localStorage });

  await router.selectClassroom("ROOM-A");
  router.storeAccessToken("secret-token-a");
  assert.notEqual(localStorage.getItem(ROUTING_CACHE_KEY), null);

  let callbackObserved = false;
  await router.clearForClassroomChange({
    resetTransientState: () => {
      callbackObserved = true;
      assert.equal(router.requestsEnabled, false);
      assert.equal(sessionStorage.getItem(ACCESS_TOKEN_KEY), null);
      assert.equal(sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY), null);
      assert.notEqual(localStorage.getItem(ROUTING_CACHE_KEY), null);
    },
  });

  assert.equal(callbackObserved, true);
  assert.equal(localStorage.getItem(ROUTING_CACHE_KEY), null);
  assert.equal(router.currentTenant, null);
  await assert.rejects(() => router.tenantApiRequest("/me"), /blocked until a tenant endpoint is verified/);
});

test("tenant 401 clears the stored authentication session", async () => {
  const sessionStorage = new MemoryStorage();
  const router = createRouter(async (url) => {
    if (url === `${DIRECTORY_ORIGIN}/v1/classrooms/resolve`) return jsonResponse(descriptor());
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    if (url === `${TENANT_A_ORIGIN}/me`) return jsonResponse({ error: "unauthorized", message: "expired" }, { status: 401 });
    throw new Error(`Unexpected URL: ${url}`);
  }, { sessionStorage });

  await router.selectClassroom("ROOM-A");
  router.storeAccessToken("secret-token-a");
  await assert.rejects(() => router.tenantApiRequest("/me", { authenticated: true }), (error) => error instanceof PortalApiError && error.status === 401);
  assert.equal(sessionStorage.getItem(ACCESS_TOKEN_KEY), null);
  assert.equal(sessionStorage.getItem(ACCESS_TOKEN_TENANT_KEY), null);
});

test("unexpired cached route is re-verified without Directory refresh", async () => {
  const localStorage = new MemoryStorage({
    [ROUTING_CACHE_KEY]: JSON.stringify({
      tenant_id: TENANT_A,
      display_name: "教室A",
      api_base_url: TENANT_A_ORIGIN,
      api_protocol_version: 1,
      config_revision: 7,
      verified_at: 900_000,
      expires_at: 1_100_000,
    }),
  });
  const calls = [];
  const router = createRouter(async (url) => {
    calls.push(url);
    if (url === `${TENANT_A_ORIGIN}/tenant-info`) return jsonResponse(tenantInfo());
    throw new Error(`Unexpected URL: ${url}`);
  }, { now: 1_000_000, localStorage });

  const restored = await router.restoreCachedTenant();
  assert.equal(restored.tenant_id, TENANT_A);
  assert.deepEqual(calls, [`${TENANT_A_ORIGIN}/tenant-info`]);
});

test("expired cached route requires Directory refresh and rejects revision rollback", async () => {
  const localStorage = new MemoryStorage({
    [ROUTING_CACHE_KEY]: JSON.stringify({
      tenant_id: TENANT_A,
      display_name: "教室A",
      api_base_url: TENANT_A_ORIGIN,
      api_protocol_version: 1,
      config_revision: 8,
      verified_at: 800_000,
      expires_at: 900_000,
    }),
  });
  const router = createRouter(async (url) => {
    if (url === `${DIRECTORY_ORIGIN}/v1/tenants/${TENANT_A}`) return jsonResponse(descriptor({ config_revision: 7 }));
    throw new Error(`Unexpected URL: ${url}`);
  }, { now: 1_000_000, localStorage });

  await assert.rejects(() => router.restoreCachedTenant(), /config_revision moved backwards/);
  assert.equal(router.currentTenant, null);
  assert.equal(router.requestsEnabled, false);
});
