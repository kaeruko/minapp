# Phase 6D: onboarding package and multi-tenant E2E

Phase 6D turns the Phase 6 architecture into a repeatable installation/support procedure and proves isolation with two independently deployed tenants.

This document is an operator runbook. It does not replace customer-specific security review or contracts.

## 1. Completion criteria

Phase 6D is complete only after all of the following are true:

- tenant A and tenant B have different immutable `tenant_id` values
- each production-like tenant has its own customer-owned AWS account, Cognito, DynamoDB, S3, Lambda and API Gateway
- each tenant has its own remote Terraform state key owned by that tenant account
- both tenants are registered in the central Directory with different classroom codes
- a teacher and a student can complete Login -> Catalog -> Launch in both tenants
- all multi-tenant E2E scenarios in section 12 are recorded as passed
- the onboarding record, classroom handout and handover checklist are complete

A second `tenant_id` deployed into the same AWS resources does not count as an isolation test.

## 2. Credentials and regions

Keep Directory/operator credentials separate from customer tenant credentials.

Example variables:

```powershell
$directoryProfile = "minapp-admin"
$directoryRegion = "us-west-2"

$tenantProfile = "customer-school-a"
$tenantLoginRegion = "us-east-1"
$tenantRegion = "us-west-2"
$expectedTenantAccountId = "123456789012"
```

If `aws login` needs a different region from the resource region, use that region only for authentication:

```powershell
aws login --profile $tenantProfile --region $tenantLoginRegion
```

Terraform, Cognito, DynamoDB, Lambda, API Gateway and S3 remain in `$tenantRegion`.

Do not request or store a customer root credential or long-lived access key.

## 3. Create the pending Directory tenant

Run this with the central Directory operator profile, not the customer profile.

```powershell
$directoryTable = terraform -chdir=infra/directory output -raw directory_table_name

$createRaw = py -3.12 tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile $directoryProfile `
  --region $directoryRegion `
  tenant create `
  --display-name "Example School A"

if ($LASTEXITCODE -ne 0) {
    throw "Directory tenant create failed"
}

$created = $createRaw | ConvertFrom-Json
$tenantId = [string]$created.tenant_id
$classroomCode = [string]$created.classroom_code

if ($tenantId -notmatch '^[0-9a-f]{32}$') {
    throw "Directory returned an invalid tenant_id"
}
if ([string]::IsNullOrWhiteSpace($classroomCode)) {
    throw "Directory did not return a classroom code"
}
```

The raw classroom code is an onboarding handoff value. Directory stores only its hash and cannot redisplay it later. Store the code in the approved handoff location immediately. Do not commit it to Git.

The `tenant_id` is immutable. Never regenerate it for the same tenant.

## 4. Verify the customer AWS account before state or resources

Run before state bootstrap, `terraform init`, `terraform plan`, and `terraform apply`:

```powershell
.\scripts\verify-aws-deploy-target.ps1 `
  -ExpectedAccountId $expectedTenantAccountId `
  -Profile $tenantProfile
```

Stop immediately if the account does not match.

## 5. Bootstrap customer-owned remote state

Follow `docs/PHASE6B_TENANT_DEPLOYMENT.md` and create the state bucket in the same customer account as the tenant resources.

Use a tenant-specific state key:

```text
tenants/<tenant_id>/terraform.tfstate
```

Never reuse a state key between tenants and never copy tenant A state into tenant B.

The required local files are gitignored:

```text
infra/terraform/terraform.tfvars
infra/terraform/backend.hcl
```

Example `terraform.tfvars`:

```hcl
aws_region  = "us-west-2"
environment = "dev"
tenant_id   = "<immutable tenant_id>"
```

Before continuing, read the file back and verify that the tenant ID is the one returned by Directory.

## 6. Plan, record, review, then apply the exact plan

Verify the account again, then initialize the intended remote backend and create a named plan:

```powershell
.\scripts\verify-aws-deploy-target.ps1 `
  -ExpectedAccountId $expectedTenantAccountId `
  -Profile $tenantProfile

$previousProfile = $env:AWS_PROFILE
try {
    $env:AWS_PROFILE = $tenantProfile

    terraform -chdir=infra/terraform init -reconfigure -backend-config=backend.hcl
    if ($LASTEXITCODE -ne 0) { throw "terraform init failed" }

    $planName = "tfplan-$tenantId"
    terraform -chdir=infra/terraform plan -out=$planName
    if ($LASTEXITCODE -ne 0) { throw "terraform plan failed" }
}
finally {
    if ($null -eq $previousProfile) {
        Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
    }
    else {
        $env:AWS_PROFILE = $previousProfile
    }
}
```

Review the plan before apply. For a brand-new tenant, unexplained update/delete actions indicate the wrong backend or configuration and must stop onboarding.

Record the plan filename and SHA-256 in the private onboarding record:

```powershell
$planPath = "infra\terraform\$planName"
$planHash = (Get-FileHash $planPath -Algorithm SHA256).Hash
$planHash
```

Do not commit the binary plan. Terraform plans may contain sensitive data.

Immediately before apply, verify the AWS account again and verify that the reviewed plan hash has not changed. Apply that exact binary plan rather than running a new implicit plan:

```powershell
.\scripts\verify-aws-deploy-target.ps1 `
  -ExpectedAccountId $expectedTenantAccountId `
  -Profile $tenantProfile

$currentHash = (Get-FileHash $planPath -Algorithm SHA256).Hash
if ($currentHash -ne $planHash) {
    throw "Reviewed Terraform plan changed; refusing apply"
}

$previousProfile = $env:AWS_PROFILE
try {
    $env:AWS_PROFILE = $tenantProfile
    terraform -chdir=infra/terraform apply $planName
    if ($LASTEXITCODE -ne 0) { throw "terraform apply failed" }
}
finally {
    if ($null -eq $previousProfile) {
        Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
    }
    else {
        $env:AWS_PROFILE = $previousProfile
    }
}
```

## 7. Verify tenant identity before Directory activation

Read outputs and verify `/tenant-info`:

```powershell
$deployedTenantId = terraform -chdir=infra/terraform output -raw tenant_id
$tenantApi = terraform -chdir=infra/terraform output -raw api_base_url

if ($deployedTenantId -ne $tenantId) {
    throw "Terraform tenant_id does not match Directory tenant_id"
}

.\scripts\verify-tenant-deployment.ps1 `
  -ExpectedTenantId $tenantId `
  -ApiBaseUrl $tenantApi `
  -ExpectedEnvironment "dev" `
  -ExpectedProtocolVersion 1
```

Do not register or activate an endpoint that fails this check.

## 8. Attach and activate the endpoint in Directory

With the central Directory operator profile:

```powershell
py -3.12 tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile $directoryProfile `
  --region $directoryRegion `
  tenant update-endpoint `
  --tenant-id $tenantId `
  --api-base-url $tenantApi

if ($LASTEXITCODE -ne 0) { throw "Directory endpoint update failed" }

py -3.12 tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile $directoryProfile `
  --region $directoryRegion `
  tenant activate `
  --tenant-id $tenantId

if ($LASTEXITCODE -ne 0) { throw "Directory tenant activation failed" }
```

Then verify both public Directory paths:

```text
POST /v1/classrooms/resolve
GET  /v1/tenants/{tenant_id}
```

Both must return the expected tenant ID and API URL.

## 9. Bootstrap the first teacher

Use the customer tenant profile. Authentication and resource regions are deliberately separated by the tool.

```powershell
$userPoolId = terraform -chdir=infra/terraform output -raw cognito_user_pool_id
$tableName = terraform -chdir=infra/terraform output -raw data_table_name

py -3.12 tools/bootstrap_teacher.py `
  --user-pool-id $userPoolId `
  --table-name $tableName `
  --login-id teacher-admin `
  --profile $tenantProfile `
  --region $tenantRegion

if ($LASTEXITCODE -ne 0) { throw "Teacher bootstrap failed" }
```

The temporary password is displayed only once. Deliver it through the approved credential channel and require the teacher to complete the first-login password change.

The teacher then creates a group and student ID in the Web portal.

## 10. Classroom handoff

Use `docs/templates/CLASSROOM_HANDOFF.md`.

Handoff may contain:

- classroom display name
- classroom code
- official join link when an official join domain is configured
- student/teacher usage instructions

Do not put AWS credentials, Cognito IDs, `tenant_id`, internal state bucket details, access tokens or tenant API URLs into the classroom handout.

## 11. Federated smoke test

Prerequisites:

- student has completed first-login password change
- exactly one intended approved test app title is known
- the classroom code and expected immutable tenant identity are known

Run:

```powershell
.\scripts\smoke-test-federated-tenant.ps1 `
  -DirectoryApiBaseUrl $directoryApi `
  -ClassroomCode $classroomCode `
  -ExpectedTenantId $tenantId `
  -ExpectedTenantApiBaseUrl $tenantApi `
  -LoginId "student-example" `
  -ExpectedAppTitle "tenant-a-smoke"
```

The script prompts for the password without putting it in PowerShell command history and verifies:

```text
Directory resolve
 -> exact tenant descriptor
 -> /tenant-info identity
 -> login
 -> approved mobile catalog
 -> exact app title
 -> launch grant
 -> launch HTML fetch
```

It never prints the password, access token or classroom code.

## 12. Two-tenant E2E matrix

Record date, operator, tenant IDs, AWS account IDs, app version/commit and pass/fail evidence for every scenario.

### 12.1 Code isolation

- code A resolves tenant A only
- code B resolves tenant B only
- A code must never return B API URL or tenant ID

### 12.2 Explicit classroom switch

On one Android device:

1. configure A
2. login as student A
3. confirm only A catalog
4. use `教室を変更`
5. configure B
6. login as student B
7. confirm only B catalog

Confirm that no A WebView/local/session state appears in B.

### 12.3 Same login ID in both tenants

Create the same textual login ID in both tenants with different credentials. Each credential must authenticate only in its own tenant. Identity linkage across tenants is forbidden.

### 12.4 Same app title in both tenants

Publish an app with the same title in A and B but visibly different content. Each mobile catalog and launch must return only the local tenant version.

### 12.5 Token isolation

Capture an A access token only in the controlled test harness. Send it to a protected B endpoint and require rejection. Production mobile code must never route an A token to B during normal switching.

Never put captured tokens in issue comments, CI logs or onboarding records.

### 12.6 Endpoint rotation

Deploy or expose a replacement endpoint that reports the same immutable tenant ID. Verify it first, then run `tenant update-endpoint`. Confirm `config_revision` increases and an expired/config-refreshing client picks up the new endpoint.

A replacement endpoint reporting a different tenant ID must be rejected.

### 12.7 Classroom-code rotation

Run:

```powershell
py -3.12 tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile $directoryProfile `
  --region $directoryRegion `
  tenant rotate-code `
  --tenant-id $tenantId
```

Record the new code in the approved handoff location. Confirm:

- old code no longer works for new enrollment
- new code works
- an already configured device continues refresh by immutable `tenant_id`

### 12.8 Directory outage on first setup

With no cached descriptor, make Directory unreachable in a controlled test environment. Enrollment must fail closed; the app must not accept a manually supplied tenant URL or guess another classroom.

### 12.9 Directory outage with valid cache

Configure a tenant, then make Directory unreachable while the verified descriptor TTL is still valid. Existing classroom Login/Catalog should remain available using the specified valid-cache behavior.

### 12.10 Expired cache plus Directory outage

Use a controlled test build/store fixture with an expired descriptor. Directory refresh failure must block Login explicitly. No silent use of expired endpoint data.

### 12.11 `/tenant-info` mismatch

Point a controlled Directory fixture at an endpoint reporting a different tenant ID or protocol. Mobile must block Login and must not persist the descriptor.

### 12.12 Tenant failure isolation

Disable or remove tenant A only in a controlled environment. Tenant B Directory resolve, Login, Catalog and Launch must remain operational.

## 13. Directory outage support semantics

- first setup always needs Directory
- valid verified descriptor cache may be used until its explicit expiry
- expired cache requires Directory refresh
- expired cache plus Directory outage fails explicitly
- Directory `inactive` is a routing/onboarding state, not a complete tenant security shutdown

Support must never tell a customer that `tenant deactivate` alone guarantees all tenant data access has stopped.

## 14. Operational changes

### Endpoint update

1. deploy replacement endpoint in the same tenant account
2. verify `/tenant-info` reports the same immutable tenant ID
3. update Directory endpoint
4. verify Directory descriptor and revision
5. smoke test Login/Catalog/Launch

### Classroom-code rotation

Use `tenant rotate-code`. The new raw code is a one-time handoff value. Do not log or commit it.

### Directory deactivate

Use `tenant deactivate` to stop new resolve/refresh routing. This does not revoke already cached routes or credentials.

### Hard tenant suspension

There is currently no single automated hard-disable command in this repository. A real security suspension must also disable the tenant-side service/credentials according to an approved incident procedure. Do not invent or silently perform destructive AWS actions.

## 15. Customer handover

Use `docs/templates/TENANT_HANDOVER_CHECKLIST.md` and record at minimum:

- customer AWS account ID
- tenant ID
- resource region
- Terraform state bucket and state key
- current API base URL
- Directory display name and config revision
- code handoff date, but not the raw classroom code in general-purpose tickets
- teacher bootstrap completion
- smoke test result
- ownership of billing, state and resources
- whether a support role exists; default is none

## 16. Evidence handling

Safe to record:

- tenant ID
- AWS account ID
- resource region
- API base URL
- config revision
- app title used for smoke test
- pass/fail and timestamps
- Terraform plan SHA-256

Do not record in GitHub issues, CI logs or shared runbooks:

- passwords
- Cognito access/refresh tokens
- AWS session credentials
- long-lived access keys
- raw classroom code unless the approved handoff system is explicitly the destination
- Terraform binary plan/state contents
- child app private data
