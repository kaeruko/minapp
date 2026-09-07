# Hosted Runtime JS bridge

Issue #87 adds one launch operation that mints the two capabilities a Hosted app needs without giving the child app a Cognito or AWS credential.

## Launch contract

Authenticated parents/native clients call:

```http
POST /hosted/groups/{group_id}/apps/{app_id}/launch-session
Authorization: Bearer <Cognito access token>
Content-Type: application/json

{}
```

The backend validates the authenticated user, current active membership, app/group association, deletion state, and the existence of a published version before writing anything. It then creates the published-content session and Runtime session in one DynamoDB transaction. A failed transaction is an all-or-nothing failure; there is no sequential fallback and no partial capability to clean up.

The response is exactly:

```json
{
  "content_path": "/hosted/content/<content-capability>/index.html",
  "content_expires_in": 600,
  "runtime_token": "<runtime-capability>",
  "runtime_expires_in": 600,
  "published_version": 1
}
```

`published-session` and `runtime-session` remain available for compatibility.

## Trust boundary

The Cognito access token is used only by the trusted Flutter/client layer to create the launch. The untrusted child HTML/JavaScript receives neither Cognito access/refresh/ID tokens nor AWS access key, secret key, or session token.

For Flutter, the Runtime token is retained only in Dart/native state (`HostedBridgeSession` / `HostedApiClient`). It is not appended to the content URL, injected into the DOM, written to `localStorage`, or included in the bootstrap JavaScript. Child code talks to a `JavaScriptChannel`; Dart performs the Runtime HTTP request. The trusted client also retains the launch's Cognito access token, `group_id`, and `app_id` in memory only for bounded Runtime re-session. Child code cannot choose or rewrite that scope.

The content capability remains in the content URL because it is required to fetch the published static files. Navigation is restricted to HTTPS, the same origin, and the same `/hosted/content/<current-token>/` path prefix. `file:`, `javascript:`, a different host/token, user-info URLs, and path traversal are rejected.

The existing dedicated/school `AppWebViewPage` and `/launch/{token}/...` navigation contract are unchanged. Hosted apps use the separate `HostedAppWebViewPage`.

## JavaScript API v1

After bridge injection, child code receives:

```js
minapp.version === 1

await minapp.state.get("chapter")
await minapp.state.set("chapter", { page: 3 })
await minapp.state.delete("chapter")

await minapp.userState.get("progress")
await minapp.userState.set("progress", { scene: "scene_014" })
await minapp.userState.delete("progress")
```

`minapp.state` is shared for the Runtime app scope. `minapp.userState` is private to the authenticated Runtime user; child code never supplies a `user_id`.

The Flutter Runtime transport contract requires both scopes. There is no optional private-state transport, compatibility adapter, or fallback from `userState` to shared `state`. A transport that cannot provide both contracts is not a valid Hosted Runtime transport.

Shared state and private state use separate explicit quotas. Shared state is bounded per app; private state is bounded per authenticated user and app. A private quota failure stays a private-state error and never writes the value into shared state. The backend does not compress, truncate, move, or reinterpret the value to make the request succeed.

All methods return a `Promise`. `get()` and `set()` resolve to the state value. `delete()` resolves to `null`.

A backend failure rejects with `MinAppError`. The error preserves the backend contract:

```js
try {
  await minapp.state.get("chapter")
} catch (error) {
  console.log(error.status)  // HTTP status
  console.log(error.code)    // e.g. runtime_session_not_found
  console.log(error.message)
}
```

Expected backend errors include `state_not_found`, `runtime_session_not_found`, `runtime_request_limit_reached`, `runtime_value_too_large`, `runtime_storage_limit_reached`, `runtime_user_key_limit_reached`, `runtime_user_storage_limit_reached`, and current-membership rejection. Other than the exact Runtime-expiry recovery described below, the bridge/client does not rewrite error codes, retry through another path, or substitute shared state for user state.

Bridge request envelopes are versioned and strict. Unknown methods, unknown/missing fields, invalid state keys, and duplicate in-flight request IDs are rejected instead of being interpreted permissively.

## Lifecycle and Runtime expiry

`HostedAppWebViewPage` injects the bootstrap after every allowed `onPageFinished`, so a normal reload or same-app relative navigation recreates `window.minapp`. The native `HostedBridgeSession` remains scoped to the launch's one user/group/app Runtime capability.

A Runtime session lasts 10 minutes. For a Runtime token that was created by the same `HostedApiClient.createLaunch` instance, the trusted host handles exactly one recoverable condition: HTTP 404 with code `runtime_session_not_found`.

On that exact error, the client:

1. keeps the child request and original launch scope unchanged;
2. creates one replacement launch session using the trusted host's original Cognito access token, `group_id`, and `app_id`;
3. replaces only the native Runtime token for that scope; and
4. retries the same state/userState operation once.

Concurrent requests that observe the same expired token share the same in-flight replacement launch. A successful replacement therefore does not fan out into multiple launch-session writes.

There is no second automatic refresh for the retried operation. Any other backend error is returned without refresh. A Runtime token that was not registered through this client's `createLaunch` path also keeps the old fail-fast behavior and returns `runtime_session_not_found` directly.

If replacement launch creation itself fails, the client throws `HostedRuntimeRefreshException`, which retains both the original expiry `ApiException` and the replacement-launch error plus its stack trace. It does not try a different credential, storage scope, API, or shared-state fallback.

This recovery changes only the native Runtime capability. It does not silently replace the page's published-content URL/capability; published-content expiry is a separate lifecycle concern.

Removing a member or deleting the app takes effect on the next existing Runtime request because the Runtime backend re-checks membership and app/group association for every operation. Those errors are not treated as session expiry and are never refreshed away.

## Test fixture

`apps/mobile/test/fixtures/hosted_runtime_bridge.html` waits for `minappready`, performs `set -> get -> delete`, validates the returned value, and surfaces the Promise error fields on failure.

`apps/mobile/test/hosted_runtime_refresh_test.dart` covers one bounded replacement launch, reuse of the replacement Runtime token, no second refresh on retry failure, and preservation of both errors when replacement launch creation fails.
