"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");

const webAuthoring = require("./authoring_host_adapter.js");
const portal = require("./hosted_authoring_portal.js");

const API_ORIGIN = "https://hosted.example.test";
const GROUP_ID = "2".repeat(32);
const CONTENT_ID = "3".repeat(32);
const EDITOR_ID = "4".repeat(32);
const PLAYER_ID = "5".repeat(32);
const FORMAT = "example/quiz@1";

function jsonResponse(status, payload) {
  return {
    status,
    ok: status >= 200 && status < 300,
    headers: {
      get(name) {
        return name.toLowerCase() === "content-type"
          ? "application/json; charset=utf-8"
          : null;
      },
    },
    async json() { return payload; },
  };
}

function projectPayload(overrides = {}) {
  return {
    content_id: CONTENT_ID,
    group_id: GROUP_ID,
    content_format: FORMAT,
    status: "draft",
    draft_revision: 7,
    assets: [],
    created_at: "2026-09-08T00:00:00Z",
    updated_at: "2026-09-08T01:00:00Z",
    ...overrides,
  };
}

test("editorChoices exposes each exact edits contract and excludes player-only apps", () => {
  const choices = portal.editorChoices([
    {
      appId: EDITOR_ID,
      title: "Quiz Editor",
      edits: [FORMAT, "example/book@1"],
      accepts: [],
    },
    {
      appId: PLAYER_ID,
      title: "Quiz Player",
      edits: [],
      accepts: [FORMAT],
    },
  ]);

  assert.deepEqual(
    choices.map((choice) => ({
      appId: choice.appId,
      title: choice.title,
      contentFormat: choice.contentFormat,
    })),
    [
      { appId: EDITOR_ID, title: "Quiz Editor", contentFormat: "example/book@1" },
      { appId: EDITOR_ID, title: "Quiz Editor", contentFormat: FORMAT },
    ],
  );
});

test("listProjects keeps JWT in trusted parent and validates exact group/format scope", async () => {
  const calls = [];
  const projects = await portal.listProjects({
    apiOrigin: API_ORIGIN,
    accessToken: "jwt-owner",
    groupId: GROUP_ID,
    contentFormat: FORMAT,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(200, { projects: [projectPayload()] });
    },
  });

  assert.equal(calls.length, 1);
  assert.equal(
    calls[0].url,
    `${API_ORIGIN}/hosted/authoring/groups/${GROUP_ID}/projects?content_format=example%2Fquiz%401`,
  );
  assert.equal(calls[0].options.method, "GET");
  assert.equal(calls[0].options.headers.Authorization, "Bearer jwt-owner");
  assert.equal(projects.length, 1);
  assert.equal(projects[0].contentId, CONTENT_ID);
  assert.equal(projects[0].contentFormat, FORMAT);
  assert.equal(projects[0].draftRevision, 7);
});

test("listProjects rejects a response that changes requested content format", async () => {
  await assert.rejects(
    () => portal.listProjects({
      apiOrigin: API_ORIGIN,
      accessToken: "jwt-owner",
      groupId: GROUP_ID,
      contentFormat: FORMAT,
      fetchImpl: async () => jsonResponse(200, {
        projects: [projectPayload({ content_format: "example/book@1" })],
      }),
    }),
    /changed the requested scope/,
  );
});

test("createProject sends exact empty document and requires revision one", async () => {
  const calls = [];
  const project = await portal.createProject({
    apiOrigin: API_ORIGIN,
    accessToken: "jwt-owner",
    groupId: GROUP_ID,
    contentFormat: FORMAT,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      return jsonResponse(201, projectPayload({ draft_revision: 1 }));
    },
  });

  assert.equal(calls[0].url, `${API_ORIGIN}/hosted/authoring/projects`);
  assert.equal(calls[0].options.method, "POST");
  assert.equal(calls[0].options.headers.Authorization, "Bearer jwt-owner");
  assert.deepEqual(JSON.parse(calls[0].options.body), {
    group_id: GROUP_ID,
    content_format: FORMAT,
    document: {},
  });
  assert.equal(project.draftRevision, 1);
});

test("backend Authoring status/code/message are preserved by portal requests", async () => {
  await assert.rejects(
    () => portal.listProjects({
      apiOrigin: API_ORIGIN,
      accessToken: "jwt-owner",
      groupId: GROUP_ID,
      contentFormat: FORMAT,
      fetchImpl: async () => jsonResponse(409, {
        error: "revision_conflict",
        message: "Expected revision no longer matches.",
      }),
    }),
    (error) => error instanceof webAuthoring.HostedWebApiError &&
      error.status === 409 &&
      error.code === "revision_conflict" &&
      error.message === "Expected revision no longer matches.",
  );
});

test("Girls production route installs Web Authoring without weakening iframe sandbox", () => {
  const html = fs.readFileSync(path.join(__dirname, "girls.html"), "utf8");
  const adapterIndex = html.indexOf('<script src="/authoring_host_adapter.js" defer></script>');
  const portalIndex = html.indexOf('<script src="/hosted_authoring_portal.js" defer></script>');
  const girlsPortalIndex = html.indexOf('<script src="/girls_authoring_portal.js" defer></script>');
  assert.ok(adapterIndex >= 0);
  assert.ok(portalIndex > adapterIndex);
  assert.ok(girlsPortalIndex > portalIndex);

  assert.match(html, /id="girls-authoring-nav"[^>]*data-girls-authoring-open/);
  assert.doesNotMatch(html, /data-girls-view="authoring"/);
  assert.match(
    html,
    /id="girls-authoring-editor-frame"[^>]*sandbox="allow-scripts"[^>]*referrerpolicy="no-referrer"/,
  );
  assert.match(
    html,
    /id="girls-authoring-preview-frame"[^>]*sandbox="allow-scripts"[^>]*referrerpolicy="no-referrer"/,
  );
  assert.doesNotMatch(html, /girls-authoring-(?:editor|preview)-frame[^>]*allow-same-origin/);
});

test("Girls integration never passes content/player selectors through child bridge", () => {
  const source = fs.readFileSync(path.join(__dirname, "girls_authoring_portal.js"), "utf8");
  assert.match(source, /HostedAuthoringPortalController/);
  assert.doesNotMatch(source, /postMessage\s*\(/);
  assert.doesNotMatch(source, /webBridgeNonce/);
  assert.doesNotMatch(source, /authoringToken/);
  assert.doesNotMatch(source, /runtimeToken/);
});
