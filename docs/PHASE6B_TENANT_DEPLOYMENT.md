# Phase 6B: tenant identity / isolated AWS deployment

Phase 6B turns the existing MinApp AWS stack into a tenant-scoped deployment that can be installed independently in each customer-owned AWS account.

## Security boundary

- one production tenant is deployed into one customer AWS account unless an explicit exception is designed
- `tenant_id` is a 32-character lowercase hexadecimal identifier and is not an AWS account ID
- `tenant_id` is immutable after the first apply; Terraform refuses a replacement of the identity guard
- every taggable AWS resource receives the `TenantId` default tag
- tenant Lambdas receive `TENANT_ID` and `API_PROTOCOL_VERSION`
- `GET /tenant-info` is public and returns routing identity only; it returns no Cognito IDs, AWS account ID, credentials, users, or application data
- no tenant-to-tenant IAM trust is created
- MinApp support does not require customer root credentials or a stored long-lived access key

## Required local files

Copy the examples and edit them for exactly one tenant:

```powershell
Copy-Item infra\terraform\terraform.tfvars.example infra\terraform\terraform.tfvars
Copy-Item infra\terraform\backend.hcl.example infra\terraform\backend.hcl
```

Both local files are gitignored.

`terraform.tfvars` must contain the server-issued tenant ID. During development before Phase 6A exists, a test tenant ID may be generated once with:

```powershell
$tenantId = [guid]::NewGuid().ToString("N")
$tenantId
```

Do not regenerate it for an existing tenant.

## Verify the target AWS account before touching state

Use an explicit temporary CLI/SSO session. Never ask a customer for root credentials or store their long-lived access key.

```powershell
.\scripts\verify-aws-deploy-target.ps1 `
  -ExpectedAccountId "123456789012" `
  -Profile "customer-school"
```

The script prints the caller ARN and fails if the current credentials point at another account.

Run this check before state bootstrap, `terraform plan`, and `terraform apply`.

## Bootstrap customer-owned remote state

The state bucket belongs to the same customer AWS account as the tenant resources. The bucket name below is an example; S3 bucket names are global, so choose an available deterministic name.

```powershell
$profile = "customer-school"
$region = "ap-northeast-1"
$stateBucket = "minapp-terraform-state-123456789012-ap-northeast-1"

aws s3api create-bucket `
  --bucket $stateBucket `
  --region $region `
  --create-bucket-configuration LocationConstraint=$region `
  --profile $profile

aws s3api put-bucket-versioning `
  --bucket $stateBucket `
  --versioning-configuration Status=Enabled `
  --profile $profile

aws s3api put-bucket-encryption `
  --bucket $stateBucket `
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' `
  --profile $profile

aws s3api put-public-access-block `
  --bucket $stateBucket `
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
  --profile $profile
```

Set `infra/terraform/backend.hcl` to a tenant-specific key, for example:

```hcl
bucket       = "minapp-terraform-state-123456789012-ap-northeast-1"
key          = "tenants/2d8860f2b45b4eaa9b8f97b935f55f50/terraform.tfstate"
region       = "ap-northeast-1"
encrypt      = true
use_lockfile = true
```

Never use one state key for multiple tenants.

## Existing local-state development environment

Phase 6B adds an S3 backend. Before the first Phase 6B plan, migrate the existing local state instead of starting with an empty remote state.

After verifying the AWS account and preparing `backend.hcl`:

```powershell
terraform -chdir=infra/terraform init -migrate-state -backend-config=backend.hcl
```

Read the migration prompt carefully and confirm only when the source state is the intended tenant. Keep a protected backup of the old local state until the migration and post-deploy verification are complete.

For a brand-new tenant:

```powershell
terraform -chdir=infra/terraform init -backend-config=backend.hcl
```

## Plan and apply

```powershell
.\scripts\verify-aws-deploy-target.ps1 `
  -ExpectedAccountId "123456789012" `
  -Profile "customer-school"

$env:AWS_PROFILE = "customer-school"
terraform -chdir=infra/terraform plan -out=tfplan
```

Review the plan. An existing tenant should not unexpectedly destroy Cognito, DynamoDB, S3, Lambda, or API Gateway resources merely because Phase 6B is being enabled.

Then:

```powershell
terraform -chdir=infra/terraform apply tfplan
```

## Verify tenant identity after apply

```powershell
$tenantId = terraform -chdir=infra/terraform output -raw tenant_id
$apiBaseUrl = terraform -chdir=infra/terraform output -raw api_base_url

.\scripts\verify-tenant-deployment.ps1 `
  -ExpectedTenantId $tenantId `
  -ApiBaseUrl $apiBaseUrl `
  -ExpectedEnvironment "dev" `
  -ExpectedProtocolVersion 1
```

Expected public response shape:

```json
{
  "service": "minapp-tenant-api",
  "tenant_id": "2d8860f2b45b4eaa9b8f97b935f55f50",
  "api_protocol_version": 1,
  "environment": "dev"
}
```

Only after this check succeeds should Phase 6A register or activate the endpoint in the central Directory.

## Operational rules

- never edit `tenant_id` to repurpose an existing deployment for another customer
- never copy one tenant's Terraform state into another tenant
- never send tenant A credentials or state to tenant B
- store the customer-owned state bucket and tenant ID in the handover record
- endpoint replacement is allowed, but `/tenant-info` must continue to report the same tenant ID for a migration of the same tenant
- a future persistent support role must be separately designed and reviewed; it is not part of Phase 6B
