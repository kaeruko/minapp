# Phase 6A: onboard an already-deployed tenant

Phase 6A normally creates the Directory tenant record first and then deploys the tenant AWS stack with the returned immutable `tenant_id`.

Development environments may already have a Phase 6B tenant deployed before the central Directory exists. Do not replace that tenant's immutable ID just to fit the normal onboarding order. Use the explicit existing-tenant path instead.

## 1. Deploy the Directory stack

`scripts/deploy-directory.ps1` bootstraps the Directory remote-state bucket, writes the gitignored `infra/directory/terraform.tfvars` and `infra/directory/backend.hcl`, initializes Terraform, and creates a fail-fast plan.

The script always verifies the expected AWS account first. It refuses to apply a plan containing delete actions.

Plan only:

```powershell
.\scripts\deploy-directory.ps1 `
  -ExpectedAccountId "123456789012" `
  -Profile "minapp-operator" `
  -Region "us-west-2"
```

After reviewing the plan, apply the saved plan:

```powershell
.\scripts\deploy-directory.ps1 `
  -ExpectedAccountId "123456789012" `
  -Profile "minapp-operator" `
  -Region "us-west-2" `
  -Apply
```

Get the Directory outputs:

```powershell
$directoryApi = terraform -chdir="infra/directory" output -raw directory_api_base_url
$directoryTable = terraform -chdir="infra/directory" output -raw directory_table_name
```

## 2. Read the existing tenant identity

Use the tenant stack outputs; do not generate a replacement ID.

```powershell
$tenantId = terraform -chdir="infra/terraform" output -raw tenant_id
$tenantApi = terraform -chdir="infra/terraform" output -raw api_base_url
```

Confirm the tenant endpoint before writing Directory data:

```powershell
.\scripts\verify-tenant-deployment.ps1 `
  -ExpectedTenantId $tenantId `
  -ApiBaseUrl $tenantApi `
  -ExpectedEnvironment "dev" `
  -ExpectedProtocolVersion 1
```

## 3. Register the existing tenant

The operator CLI provides an explicit `register-existing` command. It requires the existing immutable ID and tenant API URL, validates the URL, calls `/tenant-info`, and writes nothing if identity verification fails.

It creates the Directory record in `pending` state and generates a new classroom code server-side. Only the normalized code hash is stored; the raw code is printed once.

```powershell
python tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile minapp-operator `
  --region us-west-2 `
  tenant register-existing `
  --tenant-id $tenantId `
  --display-name "Existing Programming School" `
  --api-base-url $tenantApi
```

Keep the printed classroom code for the enrollment E2E. If it is lost, rotate it instead of trying to recover it.

## 4. Activate

Activation verifies `/tenant-info` again before changing the record to `active`.

```powershell
python tools/minapp_directory.py `
  --table-name $directoryTable `
  --profile minapp-operator `
  --region us-west-2 `
  tenant activate `
  --tenant-id $tenantId
```

## 5. Verify the public Directory API

Resolve the printed classroom code:

```powershell
$body = @{ code = "<printed-classroom-code>" } | ConvertTo-Json -Compress
Invoke-RestMethod `
  -Method Post `
  -Uri "$directoryApi/v1/classrooms/resolve" `
  -ContentType "application/json" `
  -Body $body
```

The returned descriptor must contain the existing `tenant_id`, the same tenant `api_base_url`, API protocol version `1`, and a positive `config_revision`/`valid_for_seconds`.

Then verify configured-client refresh:

```powershell
Invoke-RestMethod `
  -Method Get `
  -Uri "$directoryApi/v1/tenants/$tenantId"
```

There is no fuzzy lookup or fallback. A failed identity check, duplicate tenant/code, unsupported schema/protocol, or inactive tenant fails explicitly.
