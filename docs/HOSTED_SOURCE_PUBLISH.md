# Hosted fork source and publishing

Hosted BtoC fork apps use validated static ZIP archives. The mobile files under
`apps/mobile/assets/builtin` remain the built-in source of truth; Terraform
packages them and stores versioned, read-only templates under
`hosted/templates/...` in the private uploads bucket.

## Source and publish model

- Installing a built-in stores catalog metadata only. Built-ins are not editable.
- Forking copies the parent built-in template or the current draft of another
  fork into immutable source revision `1`.
- Each source update is a new immutable object under
  `hosted/drafts/{group}/{app}/revisions/{revision}/source.zip`.
- Updates require the current `revision`. A stale revision returns HTTP `409`.
- ZIP validation reuses the Phase 2 path, size, file-count, extension, CRC,
  symlink, encryption, and root `index.html` checks.
- Publishing copies the selected current draft to a new immutable object under
  `hosted/published/{group}/{app}/versions/{version}/source.zip`.
  Later draft edits cannot change an existing published version.
- Source and published versions are capped at 20 each per app. DynamoDB keeps an
  exact-key manifest for every object.
- Deletion first blocks further writes, then deletes only manifest-recorded S3
  keys and exact S3 version IDs plus Runtime rows. It physically removes the
  versioned objects without requiring `s3:ListBucket` or `s3:ListBucketVersions`.

## API

The owner-only source operations are:

- `GET /hosted/groups/{group_id}/apps/{app_id}/source`
- `POST /hosted/groups/{group_id}/apps/{app_id}/source?revision={current}` with
  a base64-transported `application/zip` body
- `POST /hosted/groups/{group_id}/apps/{app_id}/publish` with
  `{ "revision": current }`

Any active group member can create a ten-minute published-content session with:

- `POST /hosted/groups/{group_id}/apps/{app_id}/published-session`

The returned `content_path` is fetched without a Cognito token. It is an opaque,
short-lived, content-only capability; the child document receives no Cognito
JWT or AWS credential. Every file request rechecks current membership and app
existence before reading the immutable published ZIP. Responses use restrictive
CSP and related browser security headers.

## IAM boundary

The Hosted identity Lambda can read the two exact built-in template objects and
can get/put/delete only the `hosted/drafts/*` and `hosted/published/*` prefixes.
It has no S3 bucket-list or wildcard action. Buckets remain private with public
access blocked.

## AWS smoke

After applying the saved Hosted Terraform plan, run:

```powershell
./scripts/smoke-test-hosted-source-publish.ps1 `
  -HostedApiBaseUrl https://example.execute-api.us-west-2.amazonaws.com `
  -ExpectedTenantId 00000000000000000000000000000000
```

The script creates two temporary accounts, exercises copy/edit/stale
protection/publish/member delivery/immutability/deletion, and removes the apps,
group, memberships, and accounts in a `finally` cleanup path.
