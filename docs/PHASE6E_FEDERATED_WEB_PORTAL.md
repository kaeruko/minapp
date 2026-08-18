# Phase 6E design: operator-hosted federated Web portal

## 1. Status

This document is a design proposal for the production Web portal used by students and teachers.

The proposed canonical URL is:

```text
https://minapp.cloxs.jp
```

Phase 6A-6D established the central Directory and independently owned tenant AWS stacks. Phase 6E extends the same isolation model to the PC Web portal without turning the operator AWS account into a credential or application-data proxy.

This document does not mean the production portal infrastructure or direct-browser API mode has already been deployed.

## 2. Goals

The production Web portal must provide one stable URL for every classroom while preserving tenant isolation.

Required properties:

- students and teachers use the same ID/password on Android and Web
- the operator hosts one common Web portal, not one portal per tenant
- classroom code selects the tenant through the existing central Directory
- after tenant resolution and verification, login and application operations go directly from the browser to that tenant AWS account
- student/teacher passwords, Cognito access tokens, ZIP contents and application data do not pass through the operator Web hosting layer during normal operation
- the operator Directory remains routing metadata only
- no user-entered API URL and no silent fallback are allowed
- tenant identity is verified with `/tenant-info` before login
- switching classrooms clears authentication and tenant-specific browser state
- failures are explicit and fail closed

## 3. Decision summary

Adopt the following production shape:

```text
                          Operator AWS
                  ┌────────────────────────┐
                  │ minapp.cloxs.jp        │
Browser ─────────▶│ CloudFront + private S3│
                  │ static HTML/CSS/JS     │
                  └───────────┬────────────┘
                              │
                              │ classroom code only
                              ▼
                  ┌────────────────────────┐
                  │ MinApp Directory       │
                  │ routing metadata only  │
                  └───────────┬────────────┘
                              │
                       tenant descriptor
                              │
               browser verifies /tenant-info
                              │
          ┌───────────────────┼───────────────────┐
          ▼                   ▼                   ▼
   Tenant A AWS         Tenant B AWS        Tenant C AWS
   API/Cognito          API/Cognito         API/Cognito
   DynamoDB/S3          DynamoDB/S3         DynamoDB/S3
          ▲                   ▲                   ▲
          └──────── browser talks directly ──────┘
```

The operator-hosted portal is a static trusted UI and classroom router. It is not a production reverse proxy for tenant APIs.

The existing `tools/dev_server.py` federation proxy remains useful for local development and tests, but it is not the target production data path.

## 4. Ownership boundary

### Operator AWS owns

- `minapp.cloxs.jp` static Web assets
- CloudFront distribution
- private S3 portal bucket
- TLS certificate / DNS integration required for the portal hostname
- central Directory
- portal deployment configuration

### Tenant AWS owns

- Cognito User Pool
- tenant API Gateway / Lambda
- control-plane DynamoDB
- upload/published S3 buckets
- student and teacher identities
- access-token validation
- application ZIPs and published contents
- future runtime application data

### Operator AWS must not persist

- student or teacher password
- Cognito access token
- refresh token
- temporary password
- application ZIP body
- child application data

The Directory necessarily receives a classroom code during `POST /v1/classrooms/resolve`, but it continues to store only the normalized-code hash mapping defined by Phase 6.

## 5. Why not use the current Web proxy in production

The current federated development server accepts browser requests under `/api/...` and forwards them server-side to the selected tenant API.

That is convenient for local development because the browser sees one origin, but a production deployment of the same pattern would make tenant login requests and access tokens transit the operator Web server.

Phase 6E changes the production browser flow to:

```text
browser
  ├─> minapp.cloxs.jp       static assets only
  ├─> Directory             classroom resolution only
  └─> selected tenant API   login / app operations directly
```

This preserves the tenant ownership boundary more cleanly.

## 6. Portal bootstrap configuration

The portal loads a small same-origin configuration file, for example:

```text
/portal-config.json
```

Example schema:

```json
{
  "schema_version": 1,
  "directory_api_base_url": "https://example.execute-api.us-west-2.amazonaws.com"
}
```

Rules:

- configuration is public metadata, not a secret
- unknown fields are rejected
- unsupported `schema_version` is rejected
- `directory_api_base_url` uses the same strict public-HTTPS validation rules as the Android client
- no tenant API URL is stored in the static configuration
- if configuration is missing or malformed, classroom selection and login remain disabled
- there is no fallback to localhost, a compiled tenant URL or a user-entered URL

## 7. First classroom setup flow

```text
1. Browser loads https://minapp.cloxs.jp
2. Portal loads and validates /portal-config.json
3. User enters classroom code
4. Browser POSTs code directly to the configured Directory
5. Portal strictly validates the returned descriptor
6. Browser GETs {api_base_url}/tenant-info directly
7. Portal requires exact tenant_id and protocol match
8. Only then does the login form become active
```

The classroom code must not be put in a normal GET URL or query string.

Directory response fields remain the Phase 6 descriptor:

```text
schema_version
tenant_id
display_name
api_base_url
api_protocol_version
config_revision
valid_for_seconds
```

The portal must reject unknown or missing fields instead of guessing a compatible shape.

## 8. Browser routing cache

To make Web behavior consistent with Android, the portal may cache only verified routing metadata.

Allowed cached values:

```text
tenant_id
display_name
api_base_url
api_protocol_version
config_revision
verified_at
expires_at
```

Recommended storage: `localStorage`, because these values are non-secret routing metadata and retaining the selected classroom is useful on a PC.

Rules:

- never store raw classroom code
- validate every cached field when loading it
- a valid, unexpired descriptor may be used during a short Directory outage
- even when using cached routing, `/tenant-info` must still match before login begins
- an expired descriptor requires Directory refresh
- expired descriptor + Directory failure blocks login explicitly
- `config_revision` moving backwards is rejected
- changing classroom clears the cached descriptor before a new classroom is accepted

## 9. Authentication flow

After tenant verification:

```text
Browser
  │ POST {tenant-api}/auth/login
  │ ID + password
  ▼
Tenant API
  │ Cognito authentication inside tenant AWS
  ▼
Browser receives tenant access token
```

The operator static portal and central Directory are not on this request path.

The same account credentials are used by Android and Web. There is no separate "developer account".

For the MVP, keep the existing Web session behavior:

- access token may be held in `sessionStorage`
- never store the access token in `localStorage`
- never put it in URL/query/fragment
- never write it to console logs
- logout clears it
- classroom change clears it before clearing the tenant descriptor
- no refresh token is introduced merely to support the portal

A later hardening phase may move the access token to memory-only storage if the usability trade-off is acceptable.

## 10. Tenant API requests

All authenticated Web API calls are made directly to the selected, verified tenant origin.

The Web client should have one central request helper such as conceptually:

```text
tenantApiRequest(relativePath, options)
```

Requirements:

- only relative API paths are accepted by application code
- the base origin comes only from the validated tenant descriptor
- arbitrary absolute URLs are rejected
- the Authorization header is attached only to the selected tenant origin
- a tenant change invalidates the request client before the new tenant is configured
- 401 clears the Web authentication session

This reduces the chance of accidentally sending an A token to B.

## 11. ZIP upload

The current MVP uploads a ZIP of at most 2 MiB through the tenant API.

In Phase 6E the request becomes:

```text
Browser -> selected tenant API -> tenant Lambda/S3
```

It no longer needs to pass through `/api` on the operator Web server.

This is sufficient for the current MVP limit and preserves the current backend validation path.

A later large-file design may switch to a tenant-issued presigned S3 upload URL. If that is added, the upload URL must be tenant-issued after authorization and the tenant upload bucket must use an exact portal-origin CORS policy.

## 12. Preview and review

Preview authorization remains tenant-owned.

Flow:

```text
Browser -> tenant preview API
        <- short-lived preview URL
Browser -> sandboxed iframe using preview URL
```

Existing child-app isolation remains required:

- `sandbox="allow-scripts"`
- `Referrer-Policy: no-referrer`
- no parent Cognito token in preview URL
- preview response CSP blocks external communication and form submission
- child application DOM is never inserted into the parent portal DOM

The preview iframe must be removed or reset when the classroom changes.

## 13. CORS requirements

Direct browser-to-AWS communication requires explicit CORS. CORS is a browser boundary, not an authentication mechanism; all existing server-side authorization remains mandatory.

### Directory API

Allow exactly the production portal origin:

```text
https://minapp.cloxs.jp
```

Required methods are limited to the Directory public read/resolve routes, including preflight handling.

Do not use `Access-Control-Allow-Origin: *` for production merely for convenience.

### Tenant API

Every tenant stack receives an explicit portal origin configuration in Terraform.

Production allowed origin:

```text
https://minapp.cloxs.jp
```

Allow only required methods and headers, including:

```text
Authorization
Content-Type
```

Do not enable credentialed browser cookies for the tenant API. Authentication remains bearer-token based.

Local development origins must be configured separately and must not silently appear in production configuration.

## 14. Portal Content Security Policy

The portal is trusted code and must not load third-party scripts.

The production CloudFront response headers should include at minimum:

- Content Security Policy
- HSTS
- `X-Content-Type-Options: nosniff`
- `Referrer-Policy: no-referrer`
- framing protection for the portal itself

The difficult CSP part is that tenant API origins are dynamic.

Initial production approach:

- maintain an explicit allow-list of active tenant API origins in portal infrastructure configuration
- allow Directory + currently active tenant API origins in `connect-src`
- allow required tenant preview origins in `frame-src`
- adding or rotating a tenant endpoint updates this egress allow-list as part of onboarding/endpoint-rotation procedure

Directory remains the routing source of truth. The CSP list is an additional browser egress guard, not a replacement for descriptor validation.

Future simplification:

- give tenant APIs controlled custom hostnames under a dedicated operator-owned suffix such as `*.api.minapp.cloxs.jp`
- narrow CSP to that suffix

Custom tenant API domains are not required to launch the first production portal.

## 15. Static hosting design

Create a separate operator-owned Terraform stack, for example:

```text
infra/portal/
```

Recommended resources:

```text
private S3 bucket
  ↓ OAC
CloudFront
  ↓
https://minapp.cloxs.jp
```

Properties:

- S3 public access block enabled
- no public S3 website endpoint
- CloudFront Origin Access Control for S3
- HTTPS only; HTTP redirects to HTTPS
- portal response security headers managed as infrastructure
- `index.html` and `portal-config.json` use short/no-cache behavior
- fingerprinted static assets may use long cache lifetimes later
- no Lambda@Edge or reverse-proxy Lambda is required for the MVP

The portal Terraform state is operator-owned and separate from each tenant's Terraform state.

`cloxs.jp` DNS does not need to be moved to Route 53 solely for this design. The current authoritative DNS provider may point `minapp.cloxs.jp` at CloudFront. If the zone is already in Route 53, an alias record may be managed in the portal stack.

## 16. Logging and privacy

### CloudFront / static portal logs

Static hosting requests contain no login password or bearer token by design.

Do not encode classroom code, password or token into portal URLs, so normal CloudFront request logs cannot contain them.

### Directory logs

Do not log request bodies containing classroom code.

### Tenant API logs

Do not log:

- Authorization headers
- passwords
- temporary passwords
- access tokens
- ZIP body content

Existing redaction/fail-fast rules remain in force.

## 17. Classroom switch

`教室を変更` on Web must be a security boundary, not only a UI navigation action.

Required order:

```text
1. stop new tenant requests
2. clear access token / pending-login session
3. remove preview iframe and transient app state
4. clear selected tenant routing cache
5. return to classroom-code entry
6. resolve and verify the new tenant from scratch
```

No A token may be reused or sent after B selection begins.

## 18. Failure behavior

The portal never guesses a route.

Required behavior:

| Situation | Result |
| --- | --- |
| portal config missing/invalid | block classroom setup |
| first setup + Directory unavailable | explicit failure |
| invalid classroom code | explicit failure |
| descriptor schema invalid | reject |
| tenant API URL invalid | reject |
| `/tenant-info` tenant mismatch | block login |
| valid cached descriptor + short Directory outage | allow cached route only after tenant identity check |
| expired cache + Directory outage | block login |
| tenant API unavailable | report tenant-specific failure |
| CORS/preflight failure | report configuration failure; no fallback |
| unknown protocol/schema | require portal/app update |

## 19. Current-code migration

The existing Web UI already contains student upload, review and federated classroom-selection behavior. Phase 6E should reuse it instead of creating a second portal application.

Required implementation refactor:

1. keep `apps/web/` as the single Web UI
2. add production portal configuration loading
3. move Directory browser calls from `/directory/...` proxy paths to the configured Directory origin
4. replace `/api/...` proxy calls with direct selected-tenant requests
5. replace the production dependency on `/federation/select` and the server-side tenant cookie with browser-side verified routing state
6. keep `tools/dev_server.py` for local modes and compatibility tests
7. add exact CORS configuration to Directory Terraform
8. add exact CORS configuration to tenant Terraform
9. add `infra/portal/` for S3/CloudFront/domain infrastructure
10. deploy the static portal and set Android `MINAPP_CREATOR_PORTAL_BASE_URL=https://minapp.cloxs.jp`

The migration must not introduce a mode that accepts an arbitrary tenant API URL from the user.

## 20. Testing requirements

### Unit / static tests

- strict `portal-config.json` parser
- strict tenant descriptor parser
- routing-cache validation and expiry
- no absolute URL accepted by tenant request helper
- classroom switch clears auth before route change
- invalid/missing portal configuration fails closed

### Infrastructure tests

- portal S3 bucket is private
- CloudFront uses HTTPS
- Directory CORS contains the exact portal origin
- tenant CORS contains the exact portal origin
- production CORS does not contain wildcard origin
- production CORS does not contain localhost development origin

### Two-tenant browser E2E

Use isolated tenant A and B and verify:

1. classroom A login reaches only A API
2. classroom B login reaches only B API
3. switching A -> B clears A token/session state
4. same login ID in A/B remains independent
5. same app title in A/B does not mix
6. ZIP upload request goes directly to the selected tenant origin
7. preview URL is tenant-owned and sandboxed
8. browser network log contains no password/token request to the operator static portal
9. A failure does not prevent B from working when Directory and portal remain healthy
10. tenant-info mismatch blocks login before credentials are sent

A browser network capture for this test must not be committed to Git if it contains credentials or tokens.

## 21. Deployment sequence

Recommended rollout:

```text
1. merge the Phase 6E direct-browser implementation
2. deploy Directory CORS update
3. deploy tenant A CORS update
4. deploy tenant B CORS update
5. create operator portal infrastructure
6. publish apps/web to private portal S3
7. verify https://minapp.cloxs.jp
8. run two-tenant Web E2E
9. build Android with MINAPP_CREATOR_PORTAL_BASE_URL=https://minapp.cloxs.jp
10. verify Android menu -> browser portal -> same classroom ID/password flow
```

Roll out one infrastructure boundary at a time and review Terraform plans before apply.

## 22. Out of scope for Phase 6E MVP

- automatic Android-to-Web SSO
- sharing an Android access token with the browser
- separate developer credentials
- public child-app hosting
- PWA/service worker installation
- central storage of tenant credentials
- operator-side reverse proxy for login/app APIs
- arbitrary external API URLs
- moving all `cloxs.jp` DNS management to AWS
- custom tenant API domains, unless chosen as a later CSP-hardening step

## 23. Final responsibility model

The intended product boundary is:

```text
Operator responsibility
  minapp.cloxs.jp UI + Directory + routing integrity

Tenant responsibility boundary
  identity + API + database + ZIP + published app contents

Browser
  uses the operator portal to discover a verified tenant,
  then talks directly to that tenant for authenticated work
```

This keeps a single, simple Web address for children and teachers while preserving the Phase 6 principle that each classroom's real application environment belongs to that classroom AWS account.
