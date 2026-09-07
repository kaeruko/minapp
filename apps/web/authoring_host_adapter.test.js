"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const {
  HostedWebApiError,
  WebAuthoringBridgeProtocolError,
  WebAuthoringHostAdapter,
  createWebAuthoringLaunch,
  decodeBridgeRequest,
} = require("./authoring_host_adapter.js");

const CONTENT_ID = "3".repeat(32);
const EDITOR_ID = "4".repeat(32);
const RUNTIME_TOKEN = "r".repeat(43);
const AUTHORING_TOKEN = "a".repeat(43);
const NONCE = "n".repeat(43);
const API_ORIGIN = "https://hosted.example.test";

function jsonResponse(status, payload) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: {
      get(name) {
        return name.toLowerCase() === "content-type" ? "application/json; charset=utf-8" : null;
      },
    },
    async json() { return payload; },
    async text() { return JSON.stringify(payload); },
  };
}

function emptyResponse(status = 204) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: { get() { return null; } },
    async text() { return ""; },
    async json() { throw new Error("no json"); },
  };
}

function launchPayload() {
  return {
    content_path: `/hosted/authoring-editor/${"c".repeat(43)}/index.html`,
    content_expires_in: 600,
    runtime_token: RUNTIME_TOKEN,
    runtime_expires_in: 900,
    authoring_token: AUTHORING_TOKEN,
    authoring_expires_in: 600,
    content_id: CONTENT_ID,
    content_format: "example/quiz@1",
    editor_app_id: EDITOR_ID,
    allowed_operations: ["load", "save_document", "preview_request", "publish_request"],
    web_bridge_nonce: NONCE,
  };
}

function launchGrant() {
  return {
    contentUrl: `${API_ORIGIN}/hosted/authoring-editor/${"c".repeat(43)}/index.html`,
    contentPath: `/hosted/authoring-editor/${"c".repeat(43)}/index.html`,
    contentExpiresIn: 600,
    runtimeToken: RUNTIME_TOKEN,
    runtimeExpiresIn: 900,
    authoringToken: AUTHORING_TOKEN,
    authoringExpiresIn: 600,
    contentId: CONTENT_ID,
    contentFormat: "example/quiz@1",
    editorAppId: EDITOR_ID,
    allowedOperations: Object.freeze(["load", "save_document", "preview_request", "publish_request"]),
    webBridgeNonce: NONCE,
  };
}

function request(method, extra = {}, id = "req1") {
  return {
    channel: "minapp.web",
    nonce: NONCE,
    version: 1,
    type: "request",
    id,
    method,
    ...extra,
  };
}

function fakeFrame() {
  const messages = [];
  const contentWindow = {
    postMessage(message, targetOrigin) {
      messages.push({ message, targetOrigin });
    },
  };
  return {
    messages,
    frame: {
      contentWindow,
      sandbox: {
        contains(token) { return token === "allow-scripts"; },
      },
    },
  };
}

function fakeEventTarget() {
  const listeners = new Set();
  return {
    listeners,
    addEventListener(type, listener) {
      assert.equal(type, "message");
      listeners.add(listener);
    },
    removeEventListener(type, listener) {
      assert.equal(type, "message");
      listeners.delete(listener);
    },
  };
}

test("Web launch is explicit and keeps JWT in the trusted parent request", async () => {
  const calls = [];
  const grant = await createWebAuthoringLaunch({
    apiOrigin: API_ORIGIN,
    accessToken: "jwt-owner",
    contentId: CONTENT_ID,
    editorAppId: EDITOR_ID,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(201, launchPayload());
    },
  });

  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${API_ORIGIN}/hosted/authoring/projects/${CONTENT_ID}/launch`);
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.headers.Authorization, "Bearer jwt-owner");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    editor_app_id: EDITOR_ID,
    host_adapter: "web",
  });
  assert.equal(grant.webBridgeNonce, NONCE);
  assert.equal(grant.authoringToken, AUTHORING_TOKEN);
  assert.equal(grant.runtimeToken, RUNTIME_TOKEN);
});

test("Preview request cannot smuggle content_id or player_app_id through the bridge", () => {
  assert.throws(
    () => decodeBridgeRequest(
      request("authoring.preview", {
        expectedRevision: 2,
        content_id: "9".repeat(32),
        player_app_id: "8".repeat(32),
      }),
      NONCE,
    ),
    (error) => error instanceof WebAuthoringBridgeProtocolError &&
      error.code === "invalid_bridge_request" && error.requestId === "req1",
  );
});

test("Adapter ignores wrong window, non-opaque origin, and wrong nonce", async () => {
  const { frame, messages } = fakeFrame();
  const target = fakeEventTarget();
  const adapter = new WebAuthoringHostAdapter({
    frame,
    apiOrigin: API_ORIGIN,
    launch: launchGrant(),
    previewHandler: async () => null,
    fetchImpl: async () => { throw new Error("must not fetch"); },
    eventTarget: target,
  });

  assert.equal(await adapter.handleMessageEvent({
    source: {},
    origin: "null",
    data: request("authoring.load"),
  }), false);
  assert.equal(await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: API_ORIGIN,
    data: request("authoring.load"),
  }), false);
  assert.equal(await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: "null",
    data: { ...request("authoring.load"), nonce: "x".repeat(43) },
  }), false);
  assert.equal(messages.length, 0);
});

test("Authoring load uses only the scoped session token and returns to the exact iframe", async () => {
  const { frame, messages } = fakeFrame();
  const target = fakeEventTarget();
  const calls = [];
  const adapter = new WebAuthoringHostAdapter({
    frame,
    apiOrigin: API_ORIGIN,
    launch: launchGrant(),
    previewHandler: async () => null,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200, {
        content_id: CONTENT_ID,
        group_id: "2".repeat(32),
        content_format: "example/quiz@1",
        status: "draft",
        draft_revision: 3,
        assets: [],
        created_at: "2026-09-07T00:00:00Z",
        updated_at: "2026-09-07T00:00:00Z",
        document: { questions: [] },
      });
    },
    eventTarget: target,
  });

  const handled = await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: "null",
    data: request("authoring.load"),
  });
  assert.equal(handled, true);
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, `${API_ORIGIN}/hosted/authoring/session/${AUTHORING_TOKEN}`);
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.equal(messages.length, 1);
  assert.equal(messages[0].targetOrigin, "*");
  assert.equal(messages[0].message.ok, true);
  assert.equal(messages[0].message.id, "req1");
  assert.deepEqual(messages[0].message.result.document, { questions: [] });
});

test("Backend Authoring error status/code/message are preserved", async () => {
  const { frame, messages } = fakeFrame();
  const target = fakeEventTarget();
  const adapter = new WebAuthoringHostAdapter({
    frame,
    apiOrigin: API_ORIGIN,
    launch: launchGrant(),
    previewHandler: async () => null,
    fetchImpl: async () => jsonResponse(409, {
      error: "revision_conflict",
      message: "Expected revision no longer matches.",
    }),
    eventTarget: target,
  });

  await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: "null",
    data: request("authoring.save", {
      expectedRevision: 2,
      data: { questions: [{ id: "q1" }] },
    }),
  });
  assert.equal(messages.length, 1);
  assert.deepEqual(messages[0].message.error, {
    status: 409,
    code: "revision_conflict",
    message: "Expected revision no longer matches.",
  });
});

test("Preview callback receives revision only and its result is bridged back", async () => {
  const { frame, messages } = fakeFrame();
  const target = fakeEventTarget();
  const seen = [];
  const adapter = new WebAuthoringHostAdapter({
    frame,
    apiOrigin: API_ORIGIN,
    launch: launchGrant(),
    previewHandler: async (expectedRevision) => {
      seen.push(expectedRevision);
      return { content_format: "example/quiz@1", draft_revision: expectedRevision, player_app_id: "5".repeat(32) };
    },
    fetchImpl: async () => { throw new Error("preview handler owns preview API"); },
    eventTarget: target,
  });

  await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: "null",
    data: request("authoring.preview", { expectedRevision: 7 }),
  });
  assert.deepEqual(seen, [7]);
  assert.equal(messages[0].message.ok, true);
  assert.equal(messages[0].message.result.draft_revision, 7);
});

test("Private userState uses only the Runtime capability path", async () => {
  const { frame, messages } = fakeFrame();
  const target = fakeEventTarget();
  const calls = [];
  const adapter = new WebAuthoringHostAdapter({
    frame,
    apiOrigin: API_ORIGIN,
    launch: launchGrant(),
    previewHandler: async () => null,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200, { key: "slot.one", value: { scene: 2 }, updated_at: "2026-09-07T00:00:00Z" });
    },
    eventTarget: target,
  });

  await adapter.handleMessageEvent({
    source: frame.contentWindow,
    origin: "null",
    data: request("userState.get", { key: "slot.one" }),
  });
  assert.equal(calls[0].url, `${API_ORIGIN}/hosted/runtime/${RUNTIME_TOKEN}/user-state/slot.one`);
  assert.equal(calls[0].options.headers.Authorization, undefined);
  assert.deepEqual(messages[0].message.result, { scene: 2 });
});

test("Adapter rejects allow-same-origin because origin must stay opaque", () => {
  const contentWindow = { postMessage() {} };
  assert.throws(
    () => new WebAuthoringHostAdapter({
      frame: {
        contentWindow,
        sandbox: { contains(token) { return token === "allow-scripts" || token === "allow-same-origin"; } },
      },
      apiOrigin: API_ORIGIN,
      launch: launchGrant(),
      previewHandler: async () => null,
      fetchImpl: async () => emptyResponse(),
      eventTarget: fakeEventTarget(),
    }),
    /must not allow same-origin/,
  );
});

test("API error type retains status code and code", () => {
  const error = new HostedWebApiError(403, "forbidden", "no");
  assert.equal(error.status, 403);
  assert.equal(error.code, "forbidden");
});
