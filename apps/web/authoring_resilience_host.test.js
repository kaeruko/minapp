"use strict";

const assert = require("node:assert/strict");
const test = require("node:test");

const resilience = require("./authoring_resilience_host.js");

function fakeFrame() {
  const messages = [];
  const contentWindow = {
    postMessage(message, targetOrigin) {
      messages.push({ message, targetOrigin });
    },
  };
  return {
    frame: {
      contentWindow,
      sandbox: {
        contains(token) {
          return token === "allow-scripts";
        },
      },
    },
    messages,
  };
}

function fakeEventTarget() {
  let listener = null;
  return {
    addEventListener(type, callback) {
      assert.equal(type, "message");
      assert.equal(listener, null);
      listener = callback;
    },
    removeEventListener(type, callback) {
      assert.equal(type, "message");
      assert.equal(callback, listener);
      listener = null;
    },
    emit(event) {
      assert.notEqual(listener, null);
      listener(event);
    },
  };
}

function fakeStorage() {
  const values = new Map();
  return {
    getItem(key) {
      return values.has(key) ? values.get(key) : null;
    },
    setItem(key, value) {
      values.set(key, value);
    },
    removeItem(key) {
      values.delete(key);
    },
    values,
  };
}

const CONTENT_ID = "a".repeat(32);

function recoveryRequest(id, method, extra = {}) {
  return {
    channel: resilience.RECOVERY_CHANNEL,
    version: resilience.RECOVERY_VERSION,
    type: "request",
    id,
    method,
    contentId: CONTENT_ID,
    ...extra,
  };
}

test("Novel recovery host stores and reloads only the active content scope", () => {
  const { frame, messages } = fakeFrame();
  const eventTarget = fakeEventTarget();
  const storage = fakeStorage();
  const host = new resilience.NovelRecoveryHost({
    frame,
    storage,
    getActiveContentId: () => CONTENT_ID,
    eventTarget,
  });
  host.attach();

  const document = { content_format: "minapp/novel@1", title: "途中" };
  eventTarget.emit({
    source: frame.contentWindow,
    origin: "null",
    data: recoveryRequest("1", "save", { expectedRevision: 7, document }),
  });
  assert.equal(messages.at(-1).message.ok, true);
  assert.equal(storage.values.size, 1);

  eventTarget.emit({
    source: frame.contentWindow,
    origin: "null",
    data: recoveryRequest("2", "load"),
  });
  const loaded = messages.at(-1).message.result;
  assert.equal(loaded.contentId, CONTENT_ID);
  assert.equal(loaded.expectedRevision, 7);
  assert.deepEqual(loaded.document, document);

  host.destroy();
});

test("Novel recovery host fails closed when child content scope does not match", () => {
  const { frame, messages } = fakeFrame();
  const eventTarget = fakeEventTarget();
  const host = new resilience.NovelRecoveryHost({
    frame,
    storage: fakeStorage(),
    getActiveContentId: () => "b".repeat(32),
    eventTarget,
  });
  host.attach();

  eventTarget.emit({
    source: frame.contentWindow,
    origin: "null",
    data: recoveryRequest("3", "load"),
  });
  assert.equal(messages.length, 1);
  assert.equal(messages[0].message.ok, false);
  assert.equal(messages[0].message.error.code, "recovery_store_error");
  assert.match(messages[0].message.error.message, /active Editor content/);
});

test("session renewal replaces capabilities and retries exactly once", async () => {
  class HostedWebApiError extends Error {
    constructor(status, code, message) {
      super(message);
      this.status = status;
      this.code = code;
    }
  }

  let dispatchCalls = 0;
  class FakeAdapter {
    async dispatch(request) {
      dispatchCalls += 1;
      if (dispatchCalls === 1) {
        throw new HostedWebApiError(404, "authoring_session_not_found", "expired");
      }
      return { request, token: this.launch.authoringToken };
    }
  }

  let renewalCalls = 0;
  const authoringApi = {
    WebAuthoringHostAdapter: FakeAdapter,
    HostedWebApiError,
    async createWebAuthoringLaunch() {
      renewalCalls += 1;
      return {
        contentId: CONTENT_ID,
        editorAppId: "c".repeat(32),
        contentFormat: "minapp/novel@1",
        runtimeToken: "r".repeat(32),
        runtimeExpiresIn: 86400,
        authoringToken: "n".repeat(32),
        authoringExpiresIn: 86400,
      };
    },
  };

  resilience.installSessionRenewal({
    authoringApi,
    getAccessToken: () => "access-token",
  });

  const adapter = new FakeAdapter();
  adapter.apiOrigin = "https://hosted.example.test";
  adapter.fetchImpl = async () => { throw new Error("unused"); };
  adapter.launch = {
    contentId: CONTENT_ID,
    editorAppId: "c".repeat(32),
    contentFormat: "minapp/novel@1",
    runtimeToken: "x".repeat(32),
    runtimeExpiresIn: 600,
    authoringToken: "y".repeat(32),
    authoringExpiresIn: 600,
    webBridgeNonce: "z".repeat(32),
  };

  const result = await adapter.dispatch({ method: "authoring.load" });
  assert.equal(dispatchCalls, 2);
  assert.equal(renewalCalls, 1);
  assert.equal(result.token, "n".repeat(32));
  assert.equal(adapter.launch.webBridgeNonce, "z".repeat(32));
});
