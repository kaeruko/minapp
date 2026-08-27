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
- one DynamoDB metadata table for users/groups/memberships/apps
- one separate DynamoDB runtime table reserved for built-in/user-app state
- one private S3 upload bucket
- one private S3 published bucket
- current MinApp Web API Lambda and HTTP API Gateway foundation
- Hosted identity/group Lambda for registration and invite flows
- public read-only `/tenant-info`
- CloudWatch log groups

The runtime table is provisioned now but is not exposed directly to app JavaScript. A later Runtime/Data API must derive `tenant_id`, `group_id`, `app_id`, and `user_id` server-side from trusted authentication / launch context.

## Registration does not enable native Cognito self-sign-up

Keep `allow_self_signup = false`.

Hosted users register through MinApp's public `POST /hosted/register` endpoint. The Lambda validates the request and provisions the Cognito account with a permanent password. This keeps the registration boundary inside MinApp so later age gates, terms acceptance, per-source rate limits, abuse controls, or other registration policy can be added without exposing Cognito SignUp directly.

Registration currently stores only:

- generated internal user ID
- login ID
- Cognito subject
- role `user`
- active status

Email address, phone number, real name, birthday, and school are not required by this foundation.

Do not consider public Hosted launch ready until account deletion/recovery and the BtoC moderation/privacy requirements are implemented.

## Hosted group model

Global Hosted users have role `user`. A user's permissions inside a group live in Membership records:

- `owner` — created the group and can rotate/revoke invites or remove members
- `member` — joined using an invite and can leave voluntarily

MVP hard guards:

- maximum 20 groups per user
- maximum 20 active members per group
- one current invite code per group
- invite lifetime: 7 days
- creating a new invite immediately invalidates the previous code
- owner cannot silently leave a group; ownership transfer/group deletion must be designed explicitly later

Hosted routes:

```text
POST   /hosted/register                         public
GET    /hosted/health                           public
GET    /hosted/me                               authenticated
GET    /hosted/groups                           authenticated
POST   /hosted/groups                           authenticated
POST   /hosted/groups/join                      authenticated
GET    /hosted/groups/{group_id}/members        authenticated member
POST   /hosted/groups/{group_id}/invite         owner
DELETE /hosted/groups/{group_id}/invite         owner
DELETE /hosted/groups/{group_id}/membership     member leaves self
DELETE /hosted/groups/{group_id}/members/{id}   owner removes member
```

Login continues to use the existing `POST /auth/login` endpoint on the same Hosted API Gateway. Hosted clients should call `/hosted/me` rather than the dedicated-school `/me` endpoint after login.

## Deploy safety

The stack requires `expected_account_id`. Terraform fails before creating resources when the active AWS credentials point at a different account.

The hosted tenant ID is immutable and must be a server-issued 32-character lowercase hexadecimal ID. Do not reuse a school tenant ID.

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

## Next infrastructure/backend steps

This foundation intentionally stops before built-in apps.

Next work should add, in order:

1. account deletion / recovery and registration abuse controls
2. group ownership transfer / group deletion
3. scoped Runtime/Data API backed by the separate runtime table
4. storage quota / request quota accounting per group
5. built-in app installation/fork metadata
6. media/file storage only when the first creative built-ins actually require it

Keeping these steps separate avoids turning the hosted tenant into an unrestricted PaaS before the authorization model is ready.
