# Hosted MinApp tenant foundation

This stack is the shared BtoC foundation for MinApp.

It is intentionally separate from `infra/terraform`, which remains the dedicated tenant stack for schools and organizations.

## Boundary

- `tenant` = infrastructure / data-management boundary
- `group` = human sharing boundary

The hosted environment uses one MinApp-owned tenant and stores many user-created groups inside it. Creating a group must not create a new Cognito User Pool, Lambda, DynamoDB table, or S3 bucket.

```text
MinApp hosted tenant
  ├─ group A
  ├─ group B
  ├─ group C
  └─ group D
```

Dedicated school tenants continue to use the existing Phase 6 design.

## Resources created

- one Cognito User Pool and app client
- one DynamoDB metadata table for users/groups/memberships/apps/runtime-session metadata
- one separate DynamoDB runtime table for built-in/user-app state
- one private S3 upload bucket
- one private S3 published bucket
- current MinApp Web API Lambda and HTTP API Gateway foundation
- Hosted platform Lambda for registration, group lifecycle, built-in catalog and scoped Runtime state
- a dedicated least-privilege IAM role for the Hosted platform Lambda
- public read-only `/tenant-info`
- CloudWatch log groups

App JavaScript never receives AWS credentials or a Cognito access token.

## Registration and recovery

Keep native Cognito self-sign-up disabled. Hosted users register through MinApp's `POST /hosted/register` endpoint. The Lambda validates the request and provisions the Cognito account itself.

Registration returns a recovery code once. Only its SHA-256 hash is stored. Because Hosted registration does not require email or phone, this recovery code is the MVP password-recovery credential and the UI must clearly ask the user to save it.

A successful password recovery automatically rotates the recovery code and returns the replacement. An authenticated user can also rotate it manually. Old recovery codes stop working immediately.

Stored account fields remain intentionally small:

- generated internal user ID
- login ID
- Cognito subject
- role `user`
- account status
- recovery-code hash

Email address, phone number, real name, birthday, and school are not required by this foundation.

Account deletion fails closed while the user owns a group. The owner must either transfer ownership or delete the group first. For a deletable account, membership rows are removed and the account is put into a non-active `deleting` state before Cognito deletion; this prevents an existing JWT from continuing to use the account if later cleanup fails.

## Hosted group model

Global Hosted users have role `user`. A user's permissions inside a group live in Membership records:

- `owner` — group administrator
- `member` — invited participant

MVP hard guards:

- maximum 20 groups per user
- maximum 20 active members per group
- one current invite code per group
- invite lifetime: 7 days
- creating a new invite immediately invalidates the previous code
- owner cannot silently leave a group
- ownership can only be transferred to an existing active member
- group deletion is refused while app records still exist

## Built-in catalog, install and fork

Hosted has a server-side built-in template registry. The first registry entries mirror the two existing Flutter built-ins:

- `shiba-game`
- `shiba-goshujin`

A built-in is a versioned template definition, not a new AWS deployment. Installing a template creates normal App metadata inside the target group and records its provenance:

```text
builtin template
  builtin_id
  version
  asset_path
       │
       ▼ install
App
  source_kind = builtin
  builtin_id
  builtin_version
  editable = false
       │
       ▼ fork
App
  source_kind = fork
  parent_app_id
  builtin_id
  builtin_version
  editable = true
```

Installing/forking never creates a new Lambda, table, bucket or User Pool. Only the group owner can install, fork or delete apps; active members can list/use them.

The fork implemented here establishes identity/provenance and an editable app record. Copying/editing actual source files and connecting AI-generated source uploads is a later layer; do not treat `editable = true` as arbitrary server-code execution.

Initial app guard:

- maximum 20 app records per group, including forks
- the same built-in template can only be installed once directly in a group; users can create separate forks
- deleting an app also deletes its bounded Runtime key/value state

## Scoped Runtime state and quotas

The first Runtime/Data API is intentionally small: per-app JSON key/value state.

Flow:

```text
Authenticated MinApp client
  POST /hosted/groups/{group_id}/apps/{app_id}/runtime-session
        │
        │ server verifies current group membership and app -> group relation
        ▼
10-minute opaque runtime token
        │
        ▼
/hosted/runtime/{token}/state/{key}
        │
        ├─ GET
        ├─ POST {"value": ...}
        └─ DELETE
        │
        ▼
separate runtime DynamoDB table
```

The runtime token is not a Cognito token. The server derives `group_id`, `app_id`, and `user_id` from the session record and re-checks current Membership plus app/group association on every state request. Removing a member therefore revokes an already-issued runtime token immediately.

Initial Runtime hard guards:

- session lifetime: 10 minutes
- maximum 300 state operations per Runtime session; the counter is incremented with an atomic DynamoDB conditional update
- state key: lowercase identifier, up to 64 characters
- maximum 64 state keys per app
- one JSON value: maximum 16 KiB
- total JSON value storage: maximum 256 KiB per app
- no arbitrary DynamoDB access
- no arbitrary collection/table names
- no external API proxy yet

The API Gateway also applies the Hosted stack's platform-wide default throttle of 25 requests/second with a burst of 50. The per-session Runtime budget is separate from that infrastructure throttle.

Runtime session records include a future TTL timestamp, but DynamoDB TTL cleanup is not yet enabled on the metadata table. Expired sessions are rejected by application logic regardless; enabling automatic physical cleanup is still a deployment follow-up.

## Hosted routes

```text
GET    /hosted/health                                      public
GET    /hosted/builtins                                    public
POST   /hosted/register                                    public
POST   /hosted/recover                                     public

GET    /hosted/me                                          authenticated
GET    /hosted/account/email                               authenticated
POST   /hosted/account/email                               authenticated; send confirmation code
POST   /hosted/account/email/verify                        authenticated; confirm code
POST   /hosted/recovery-code                               authenticated
DELETE /hosted/account                                     authenticated

GET    /hosted/groups                                      authenticated
POST   /hosted/groups                                      authenticated
POST   /hosted/groups/join                                 authenticated
GET    /hosted/groups/{group_id}/members                   authenticated member
POST   /hosted/groups/{group_id}/invite                    owner
DELETE /hosted/groups/{group_id}/invite                    owner
POST   /hosted/groups/{group_id}/owner                     owner; transfer ownership
DELETE /hosted/groups/{group_id}                           owner
DELETE /hosted/groups/{group_id}/membership                member leaves self
DELETE /hosted/groups/{group_id}/members/{user_id}         owner removes member

GET    /hosted/groups/{group_id}/apps                      authenticated member
POST   /hosted/groups/{group_id}/apps/install              owner
POST   /hosted/groups/{group_id}/apps/{app_id}/fork        owner
DELETE /hosted/groups/{group_id}/apps/{app_id}             owner
POST   /hosted/groups/{group_id}/apps/{app_id}/runtime-session authenticated member

GET    /hosted/runtime/{token}/state/{key}                 scoped runtime token
POST   /hosted/runtime/{token}/state/{key}                 scoped runtime token
DELETE /hosted/runtime/{token}/state/{key}                 scoped runtime token
```

Login continues to use the existing `POST /auth/login` endpoint on the same Hosted API Gateway. Hosted clients call `/hosted/me` rather than the dedicated-school `/me` endpoint after login.

## Deploy safety

The stack requires `expected_account_id`. Terraform fails before creating resources when the active AWS credentials point at a different account.

The hosted tenant ID is immutable and must be a server-issued 32-character lowercase hexadecimal ID. Do not reuse a school tenant ID.

The Lambda execution roles are deliberately separated:

```text
api                  -> general API role
hosted_identity_api  -> dedicated Hosted identity/platform role
tenant_info          -> read-only tenant-info role
```

The Hosted identity/platform role is limited to the metadata table, Runtime table, Hosted Cognito user pool, and abuse-control table. It has no S3 access. DynamoDB transactions require the item-level `PutItem`, `UpdateItem`, and `DeleteItem` actions in addition to `TransactWriteItems`, so all six table actions in the Hosted application policy are intentional.

After applying a reviewed plan with zero destroys, run the IAM-specific smoke test. It verifies the deployed role and exact policy resources, creates a generated temporary account, exercises the one-user Runtime flow and rate limits, and removes the temporary account, group, app, and state data.

```powershell
./scripts/smoke-test-hosted-iam.ps1 `
  -HostedApiBaseUrl $hostedApiBaseUrl `
  -ExpectedTenantId $hostedTenantId `
  -ExpectedAccountId $expectedAccountId `
  -AwsRegion $awsRegion `
  -AwsProfile $awsProfile `
  -IdentityRoleName $identityRoleName `
  -IdentityFunctionName $identityFunctionName `
  -DataTableName $dataTableName `
  -RuntimeTableName $runtimeTableName `
  -UserPoolId $userPoolId
```

## First-time setup

Copy the examples locally. The real files are ignored by Git.

```powershell
Copy-Item infra\hosted\terraform.tfvars.example infra\hosted\terraform.tfvars
Copy-Item infra\hosted\backend.hcl.example infra\hosted\backend.hcl
```

Edit both files before running Terraform. In particular, replace:

- `hosted_tenant_id`
- `expected_account_id`
- remote-state bucket name

Then initialize and validate:

```powershell
terraform -chdir=infra/hosted init -backend-config=backend.hcl
terraform -chdir=infra/hosted fmt -check
terraform -chdir=infra/hosted validate
terraform -chdir=infra/hosted plan -out=tfplan
```

Review the plan before apply. Do not automatically apply a plan created with an unexpected account, region, tenant ID, or environment.

## Next steps before the first creative built-in

1. registration/recovery rate limiting and terms/privacy acceptance
2. automatic TTL cleanup for runtime-session metadata
3. connect actual app launch to the scoped Runtime token
4. add source-file/version metadata for editable forks and AI-generated HTML/CSS/JS uploads
5. add media/file storage when the first novel/profile built-ins require images
6. deploy the Hosted stack and exercise registration -> group -> invite -> install -> Runtime end-to-end
7. build the first creative built-in (novel/profile/setting archive)

This stack deliberately remains a constrained application platform, not an unrestricted PaaS.
