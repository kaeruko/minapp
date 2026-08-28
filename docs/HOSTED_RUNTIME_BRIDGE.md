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

For Flutter, the Runtime token is retained only in Dart/native state (`HostedBridgeSession`). It is not appended to the content URL, injected into the DOM, written to `localStorage`, or included in the bootstrap JavaScript. Child code talks to a `JavaScriptChannel`; Dart performs the Runtime HTTP request.

The content capability remains in the content URL because it is required to fetch the published static files. Navigation is restricted to HTTPS, the same origin, and the same `/hosted/content/<current-token>/` path prefix. `file:`, `javascript:`, a different host/token, user-info URLs, and path traversal are rejected.

The existing dedicated/school `AppWebViewPage` and `/launch/{token}/...` navigation contract are unchanged. Hosted apps use the separate `HostedAppWebViewPage`.

## JavaScript API v1

After bridge injection, child code receives:

```js
minapp.version === 1

await minapp.state.get("chapter")
await minapp.state.set("chapter", { page: 3 })
await minapp.state.delete("chapter")
```

All three methods return a `Promise`. `get()` and `set()` resolve to the state value. `delete()` resolves to `null`.

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

Expected backend errors include `state_not_found`, `runtime_session_not_found`, `runtime_request_limit_reached`, `runtime_value_too_large`, `runtime_storage_limit_reached`, and current-membership rejection. The bridge does not rewrite those codes or retry through another path.

Bridge request envelopes are versioned and strict. Unknown methods, unknown/missing fields, invalid state keys, and duplicate in-flight request IDs are rejected instead of being interpreted permissively.

## Lifecycle and expiry

`HostedAppWebViewPage` injects the bootstrap after every allowed `onPageFinished`, so a normal reload or same-app relative navigation recreates `window.minapp`. The native `HostedBridgeSession` remains scoped to the launch's one user/group/app Runtime token.

A Runtime session lasts 10 minutes. The bridge deliberately does **not** auto-refresh or silently retry. Once the backend returns `runtime_session_not_found`, the child Promise rejects with that exact error. A trusted host may explicitly create a new launch session and reopen/rebind the app in a higher-level flow, but that is a separate operation and still requires valid Cognito authentication plus current membership.

Removing a member or deleting the app takes effect on the next existing Runtime request because the Runtime backend re-checks membership and app/group association for every operation. A previously injected bridge therefore does not preserve access after removal.

## Test fixture

`apps/mobile/test/fixtures/hosted_runtime_bridge.html` waits for `minappready`, performs `set -> get -> delete`, validates the returned value, and surfaces the Promise error fields on failure.
