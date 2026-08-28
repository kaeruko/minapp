# Editable app foundation

Tracks #98.

The first reference implementation is a novel Player/Editor pair, but the
platform contract must also support quiz, picture-book, map and user-created
Player/Editor apps without introducing format-specific backend APIs.

## Core model

Do not model an Editor as directly editing a Player.

Use three separate identities:

```text
app_id          executable package installed in a group
content_id      editable/published work
content_format  compatibility contract for Master Data
```

Example:

```text
Novel Player
  app_id = P1
  accepts = [minapp/novel@1]

Novel Editor
  app_id = E1
  edits = [minapp/novel@1]

Novel work
  content_id = C1
  content_format = minapp/novel@1
```

Both executable apps operate on C1 because they understand the same
`content_format`; they do not point at each other.

This avoids overloading the existing Hosted `app_id`, which already identifies
an installed executable app and is the scope for source/publish/runtime behavior.

## Data ownership

### Master Data

The authored work itself:

- `story.json`
- `quiz.json`
- images
- audio
- other format-owned assets

Master Data belongs to `content_id`, not Player `app_id` or Editor `app_id`.

Draft revisions are immutable snapshots. Publishing creates another immutable
version and only then advances the published metadata pointer.

### User Data

Per-user state generated while consuming a published work:

- current scene
- read position
- choices
- flags
- score
- save slots
- per-user settings

User Data belongs to the authenticated user and `content_id`. Child JavaScript
must not choose an arbitrary `user_id`.

### Shared Data

Optional state shared by users of the same content:

- ranking
- shared counters
- class/shared state

Shared Data belongs to `content_id` and its sharing scope. A format that does not
need it should not receive write capability for it.

## Storage boundary

The API contract uses logical names (`Master Data`, `User Data`, `Shared Data`).
Child apps never know bucket names, table names, AWS account IDs or credentials.

Suggested physical layout:

```text
Metadata DynamoDB
  CONTENT#{content_id} / META
    group_id
    owner_user_id
    content_format
    status
    draft_revision
    published_revision
    created_at
    updated_at

Authoring object storage
  authoring/{group_id}/{content_id}/revisions/{revision}/...

Published object storage
  published/{group_id}/{content_id}/versions/{version}/...

Runtime DynamoDB
  CONTENT#{content_id}
    SHARED#STATE#{key}
    USER#{user_id}#STATE#{key}
```

Exact physical keys remain an implementation detail. The important invariant is
that content deletion can find its bounded data without scanning every user.

## Content Format

Formats use an explicit namespaced version string. The first novel format is:

```text
minapp/novel@1
```

Player metadata declares `accepts`; Editor metadata declares `edits`.

A format string is an exact contract. The platform must not silently reinterpret
unknown or newer formats as an older format. Unsupported formats fail before
launching the operation.

A format migration, if added later, is an explicit operation producing a new
Master Data revision. It is not an automatic fallback inside `load` or `save`.

## Authoring capability

An untrusted Editor WebView does not receive Cognito credentials or a generic DB
API. The trusted host creates a short-lived capability scoped server-side to one
editing target.

Conceptually the capability binds:

```text
editor_app_id
content_id
group_id
content_format
allowed_operations
expires_at
```

The Editor cannot override those values in an authoring request.

Initial allowed operations:

```text
load
save
preview
publish_request
```

Whether `publish_request` immediately publishes or enters teacher/review approval
is decided by the trusted platform workflow, not by arbitrary Editor JavaScript.

## JS bridge

Keep the surface narrow:

```js
await minapp.authoring.load()
await minapp.authoring.save({
  expectedRevision: 7,
  data: masterData,
})
await minapp.authoring.preview()
await minapp.authoring.publish()
```

Do not expose generic primitives such as:

```js
minapp.db.query(...)
minapp.s3.put(...)
minapp.authoring.open(otherContentId)
```

The current Hosted Runtime trust boundary remains the model: child JavaScript
calls a bridge, the trusted Flutter/native layer performs the authenticated API
operation, and AWS/Cognito credentials stay outside the child document.

## Save concurrency

Saving uses optimistic concurrency.

```text
Editor A loads revision 7
Editor B loads revision 7

A saves expected_revision=7
  -> creates revision 8

B saves expected_revision=7
  -> 409 revision_conflict
```

The platform does not silently merge, overwrite, retry against revision 8 or
choose a different save path. The Editor must reload and explicitly resolve the
conflict.

## Draft and Published

Draft and Published are separate namespaces.

```text
Published v3   current playable version
Draft r8       current authoring state
```

A normal `save` never mutates Published data.

Publish order:

```text
1. validate current draft revision
2. materialize immutable published version N
3. validate the completed published object/manifest
4. atomically update metadata pointer to version N
```

S3/object storage and DynamoDB cannot be one transaction. Therefore a failure
before step 4 leaves the previous published pointer unchanged. Orphaned immutable
objects can be cleaned later from manifests; the active Published version must
not become partial.

## Preview

Preview uses the same Player implementation as production, but it must not
mutate production User Data or Shared Data.

The Preview session binds:

```text
player_app_id
content_id
draft_revision
content_format
preview_state_namespace
expires_at
```

Initial implementation may choose either:

1. isolated preview User/Shared state namespace; or
2. read-only state during preview.

The novel reference implementation needs stateful preview, so isolated preview
state is the preferred direction.

Preview state is temporary platform data. It is not promoted into Published User
Data when the work is published.

## Runtime API split

Keep the semantic distinction clear in JavaScript:

```js
// shared among users of this content
await minapp.state.get('ranking')

// private to the authenticated user
await minapp.userState.get('progress')
```

Both are scoped by server-created Runtime capability. Neither API accepts
`user_id`, `group_id` or `content_id` from child JavaScript.

For existing static apps that do not have a separate `content_id` yet, current
`app_id`-scoped Runtime behavior remains a compatibility path until those apps
explicitly adopt the editable-content contract. Do not silently reinterpret old
state rows as new content state.

## Creation flow

New work creation is a trusted host/platform operation:

```text
user chooses Novel Editor
  -> trusted host chooses content_format from Editor declaration
  -> backend creates content_id C1
  -> backend creates initial Master Data revision
  -> backend creates authoring capability for E1 + C1
  -> Editor opens C1
```

The Editor does not submit its own arbitrary owner/group/content identifiers.

## Re-edit flow

```text
content C1
  -> user selects Edit
  -> trusted host selects an Editor whose `edits` contains C1.content_format
  -> backend authorizes user/group/content relation
  -> backend creates authoring capability
  -> Editor loads current draft revision of C1
```

Editing C1 updates C1. It does not create a new content record unless the user
explicitly chooses duplicate/fork.

## Player launch

```text
content C1
  -> trusted host selects Player P1 whose `accepts` contains C1.content_format
  -> backend resolves current published version
  -> launch capability binds P1 + C1 + version + user/group
  -> Player receives published Master Data plus scoped Runtime bridge
```

A Player cannot request another `content_id` through the child bridge.

## Deletion

Deletion is app/content-centered and idempotent.

Suggested content deletion order:

```text
1. mark content deleting/deleted so no new launch/authoring session can be minted
2. delete/revoke Runtime and preview state for content_id
3. delete authoring manifests/objects
4. delete published manifests/objects
5. remove/tombstone metadata
```

Existing sessions must re-check deletion/membership as appropriate and stop
working after revocation.

Do not report deletion success while a known required cleanup step failed.
Repeated deletion requests may resume the same explicit cleanup sequence.

## Quotas

The backend enforces explicit limits for at least:

- Master Data file size
- asset file size
- files per content
- total bytes per content revision
- revisions per content
- published versions per content
- User Data value size
- User Data keys per user/content
- Shared Data value/key totals
- authoring save/request rate
- content count per user/group

Limit violations return stable errors. Do not compress, truncate, move to another
storage service or otherwise continue through an implicit fallback.

## First implementation slice

After #99 moves Hosted to the new AWS account:

1. add `content_id` metadata and exact `content_format` validation;
2. add `minapp.userState` while keeping current shared `minapp.state` semantics;
3. add authoring capability/session backend;
4. implement immutable Master Data draft revisions;
5. implement Novel Editor `load/save`;
6. implement Novel Player draft Preview with isolated preview state;
7. implement publish pointer flow;
8. add deletion/quota coverage;
9. document the `minapp/novel@1` format for third-party Player/Editor authors.

The novel implementation is the reference client of these contracts, not a
special backend path.
