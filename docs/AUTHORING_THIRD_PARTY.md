# Third-party Authoring Editor / Player contract

Tracks #161. This document describes the Hosted v1 contract implemented by the platform. Format-specific schema belongs to the Editor/Player author, not to the Host.

## Identities

Keep these identities separate:

```text
app_id          executable Editor / Player / published MinApp
content_id      one editable work
content_format  exact compatibility contract
```

For example:

```text
Alice Quiz Editor
  app_id = E1
  edits = [example/quiz@1]

Alice Quiz Player
  app_id = P1
  accepts = [example/quiz@1]

Bob's quiz
  content_id = C1
  content_format = example/quiz@1
```

Bob may use Alice's published Editor without receiving permission to download or update Alice's editable source. Editor use and Editor source management are separate permissions.

## 1. Upload and publish the executable app

A third-party Editor or Player starts as a normal editable Hosted app. Upload its ZIP through the normal app upload flow, then register its Authoring contract and publish the app through the normal app publish flow.

Only the app owner may register or change the Authoring contract. Merely being the group owner does not grant another member's app source-management rights.

An unpublished or hidden third-party app is not returned by Authoring discovery and cannot be launched as an Editor or Player.

## 2. Register the Authoring contract

Authenticated request:

```http
POST /hosted/authoring/groups/{group_id}/apps/{app_id}/contract
Content-Type: application/json
Authorization: Bearer <trusted-host-user-token>
```

Editor example:

```json
{
  "edits": ["example/quiz@1"],
  "accepts": [],
  "master_data_element_id": null
}
```

Player example:

```json
{
  "edits": [],
  "accepts": ["example/quiz@1"],
  "master_data_element_id": "quiz-data"
}
```

The platform validates every format as an exact namespaced/versioned value. Duplicate, malformed, or unversioned formats fail explicitly. A Player contract requires a valid `master_data_element_id`; an Editor-only contract must use `null`.

There is no Novel/Quiz/builtin-ID special case in discovery or resolution.

## 3. Minimal Editor

An Editor ZIP must contain `index.html`. The Editor is ordinary untrusted web content and receives the Runtime/Authoring bridges, not Cognito JWT, AWS credentials, bucket names, table names, or arbitrary `content_id` access.

Minimal outline:

```html
<!doctype html>
<meta charset="utf-8">
<button id="save">Save</button>
<script>
window.addEventListener('minappready', async () => {
  const project = await minapp.authoring.load();

  // Only exactly {} is a new-project initialization target.
  let masterData = project.document;
  if (Object.keys(masterData).length === 0) {
    masterData = {
      schema_version: 1,
      content_format: 'example/quiz@1',
      questions: []
    };
  }

  document.querySelector('#save').addEventListener('click', async () => {
    await minapp.authoring.save(masterData, {
      expectedRevision: project.draft_revision,
    });
  });
});
</script>
```

The important initialization rule is independent of the UI code: only the exact empty object supplied for a new Project may be initialized. Missing, malformed, or incompatible data must not be treated as a new empty Project.

Save uses optimistic concurrency:

```js
const loaded = await minapp.authoring.load();
await minapp.authoring.save(updatedDocument, {
  expectedRevision: loaded.draft_revision,
});
```

A stale revision returns the original revision-conflict error. The platform does not fetch the newest revision and retry, merge automatically, or switch storage paths.

## 4. Minimal Player

A Player ZIP also requires `index.html`. It must contain exactly one declared JSON injection element matching `master_data_element_id`:

```html
<!doctype html>
<meta charset="utf-8">
<div id="quiz"></div>
<script id="quiz-data" type="application/json">{}</script>
<script>
const data = JSON.parse(document.getElementById('quiz-data').textContent);
// Render data according to example/quiz@1.
</script>
```

Before Preview or Publish, the platform verifies that the injection target exists exactly once and is `type="application/json"`. Authoring document JSON is encoded and script-termination characters are escaped before injection.

Project asset paths must not collide with Player source paths. A collision fails; the platform does not rename or drop either file.

## 5. New Project and Editor launch

The trusted Host creates a new work as:

```json
{
  "group_id": "...",
  "content_format": "example/quiz@1",
  "document": {}
}
```

The Host treats `document` as opaque. The selected Editor initializes `{}` according to its own schema and saves the first format-specific revision.

Editor launch verifies:

- the user still owns the target `content_id` and is an active group member;
- the selected app declares the exact `content_format` in `edits`;
- the third-party Editor is visible and has a normal published version;
- the executable source is the immutable source revision referenced by that published version.

A later unpublished Editor draft is never served to another user. A live Editor session continues to serve the immutable source version pinned when that session started; it does not silently switch to a later publication.

## 6. Preview and Player selection

The Host resolves Players only by exact `content_format` / `accepts`. If multiple compatible Players exist, the user must choose explicitly; the first result is not selected implicitly.

Creating Preview validates the selected Player and records the exact immutable Player source used for that Preview. Preview uses the current Draft revision and an isolated preview Runtime namespace, so it does not mutate production `minapp.state` or `minapp.userState`.

The explicit Preview selection is also the Player selection used by the subsequent v1 Publish. Publish without a recorded compatible Player selection fails with `authoring_player_not_selected`; the platform does not pick a candidate automatically.

If a Player is republished after Preview, the recorded immutable Player revision stays pinned for the work's subsequent Publish. The platform revalidates that the Player remains available and compatible but does not silently substitute its newer source.

## 7. Publish as a normal MinApp

Authoring Publish materializes one immutable ZIP containing:

```text
pinned Player source
+ canonical Master Data injected into index.html
+ Authoring assets
```

The completed ZIP is read back and verified before metadata pointers move. Only then are the Authoring published pointer and normal Hosted app pointer committed.

The first Publish creates one `published_app_id` for the work. Later edits and republishes retain the same `content_id` and the same `published_app_id`; only the immutable published version advances.

The Publish response includes:

```json
{
  "content_id": "...",
  "group_id": "...",
  "content_format": "example/quiz@1",
  "published_version": 1,
  "source_revision": 2,
  "published_app_id": "...",
  "player_app_id": "...",
  "player_source_version": 1,
  "assets": [],
  "published_at": "..."
}
```

The published work appears in the normal group app list and is launched through the same normal published-content/Runtime path as other Hosted apps.

A Player update does not mutate an already published work. Applying another Player publication requires an explicit Preview selection and work republish.

## 8. Security and fail-fast requirements

Never expose these to Editor or Player JavaScript:

- Cognito JWT;
- AWS credentials;
- bucket/table names;
- arbitrary user/group/content selectors;
- Editor source-management rights merely because the Editor can be used.

Do not silently recover by changing format, Player, Editor, revision, API, backend, storage location, or source version. Preserve the original platform error and stop.

## 9. Host Adapter support in this slice

The implemented interactive Authoring Host Adapter in this slice is Flutter `HostedAppWebViewPage.authoring`. It injects the scoped Runtime and Authoring bridges into the Editor WebView while the trusted Flutter layer retains authentication credentials.

Preview selection is currently Host-driven from `HostedAuthoringProjectsPage`; the Editor JavaScript bridge in this slice exposes `load`, `save`, and `publish`. The broader #161 contract still tracks exposing Host-driven Preview as `minapp.authoring.preview(...)`.

A Web Portal iframe Authoring Host Adapter is not implemented by this slice. Unsupported hosts must not silently fall back to Flutter-specific assumptions, another backend, or direct credential access. Web Portal support remains tracked by #161.

Project-level Authoring deletion is also outside this slice: asset deletion exists, but idempotent deletion of a whole `content_id` and all Draft/Published artifacts remains tracked by #161.

## Reference test

`backend/tests/test_hosted_third_party_authoring_roundtrip.py` exercises `example/quiz@1` through the real Hosted metadata/object-storage backends used by the tests:

```text
Alice uploads Editor + Player
-> Alice registers exact contracts
-> Alice publishes both apps
-> Bob discovers them
-> Bob creates {}
-> Bob launches Alice's Editor
-> Editor capability loads and saves Bob's work
-> Bob Previews with Alice's Player
-> Bob Publishes to a normal Hosted app
-> normal published app launches
-> Bob re-edits
-> Bob republishes to the same published_app_id
```

The same test also verifies that Alice's later unpublished Editor draft is not exposed to Bob and that Bob cannot manage Alice's Editor source.
