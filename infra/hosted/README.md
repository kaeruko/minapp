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
- current MinApp Web API Lambda and HTTP API Gateway routes needed for the existing group/upload foundation
- public read-only `/tenant-info`
- CloudWatch log groups

The runtime table is provisioned now but is not exposed directly to app JavaScript. A later Runtime/Data API must derive `tenant_id`, `group_id`, `app_id`, and `user_id` server-side from trusted authentication / launch context.

## Self sign-up is deliberately disabled by default

`allow_self_signup = false` is a release gate, not a forgotten setting.

Do not enable it until all of the following exist:

1. hosted account registration API/UI
2. group invite / membership flow
3. rate limits and abuse controls
4. account deletion and recovery policy
5. UGC reporting / blocking appropriate for BtoC use

The existing teacher-created account flow can still be used while the hosted backend is being developed.

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

1. hosted user registration and account deletion
2. group invite / join / leave / owner controls
3. scoped Runtime/Data API backed by the separate runtime table
4. storage quota / request quota accounting per group
5. built-in app installation/fork metadata
6. media/file storage only when the first creative built-ins actually require it

Keeping these steps separate avoids turning the hosted tenant into an unrestricted PaaS before the authorization model is ready.
