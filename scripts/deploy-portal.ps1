param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^https://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$')]
    [string]$DirectoryApiBaseUrl,

    [Parameter(Mandatory = $true)]
    [string[]]$TenantApiOrigins,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Region = "us-west-2",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,15}$')]
    [string]$Environment = "prod",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$')]
    [string]$PortalDomain = "minapp.cloxs.jp",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+$')]
    [string]$LegacyPortalDomain = "portal.cloxs.jp",

    [Parameter(Mandatory = $false)]
    [bool]$ActivateCanonicalDomain = $true,

    [Parameter(Mandatory = $false)]
    [string]$StateBucket,

    [Parameter(Mandatory = $false)]
    [string]$CertificateArn,

    [Parameter(Mandatory = $false)]
    [string]$Route53ZoneId,

    [Parameter(Mandatory = $false)]
    [switch]$CreateStateBucket,

    [Parameter(Mandatory = $false)]
    [switch]$Apply
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

foreach ($command in @("aws", "terraform")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command was not found in PATH: $command"
    }
}

if ($TenantApiOrigins.Count -eq 0) {
    throw "TenantApiOrigins must contain at least one tenant API origin."
}

$tenantOriginPattern = '^https://[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?$'
$seenOrigins = @{}
foreach ($origin in $TenantApiOrigins) {
    if ($origin -notmatch $tenantOriginPattern) {
        throw "Tenant API origin must be a public HTTPS origin with no path, query, fragment, or trailing slash: $origin"
    }
    if ($seenOrigins.ContainsKey($origin)) {
        throw "TenantApiOrigins contains a duplicate origin: $origin"
    }
    $seenOrigins[$origin] = $true
}

if ([string]::IsNullOrWhiteSpace($Route53ZoneId) -and [string]::IsNullOrWhiteSpace($CertificateArn)) {
    throw "Provide CertificateArn for external DNS, or Route53ZoneId so Terraform can create and validate the portal certificate."
}
if (-not [string]::IsNullOrWhiteSpace($Route53ZoneId) -and $Route53ZoneId -notmatch '^Z[A-Z0-9]+$') {
    throw "Route53ZoneId must begin with Z and contain only uppercase letters and digits."
}
if (-not [string]::IsNullOrWhiteSpace($CertificateArn)) {
    $certificatePattern = "^arn:aws:acm:us-east-1:$ExpectedAccountId`:certificate/[0-9a-fA-F-]+$"
    if ($CertificateArn -notmatch $certificatePattern) {
        throw "CertificateArn must be an ACM certificate ARN from us-east-1 in account $ExpectedAccountId."
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$portalDir = Join-Path $repoRoot "infra\portal"
if (-not (Test-Path $portalDir -PathType Container)) {
    throw "Portal Terraform stack was not found: $portalDir"
}

& (Join-Path $PSScriptRoot "verify-aws-deploy-target.ps1") `
    -ExpectedAccountId $ExpectedAccountId `
    -Profile $Profile `
    -Region $Region

if ([string]::IsNullOrWhiteSpace($StateBucket)) {
    $StateBucket = "minapp-portal-terraform-state-$ExpectedAccountId-$Region"
}
if ($StateBucket.Length -gt 63 -or $StateBucket -notmatch '^[a-z0-9][a-z0-9.-]*[a-z0-9]$') {
    throw "StateBucket is not a valid S3 bucket name: $StateBucket"
}

Write-Host "Portal deployment target:"
Write-Host "  Account:       $ExpectedAccountId"
Write-Host "  Profile:       $Profile"
Write-Host "  Region:        $Region"
Write-Host "  Environment:   $Environment"
Write-Host "  PortalDomain:  $PortalDomain"
Write-Host "  LegacyDomain:  $LegacyPortalDomain"
Write-Host "  CanonicalLive: $ActivateCanonicalDomain"
Write-Host "  Directory API: $DirectoryApiBaseUrl"
Write-Host "  Tenant origins:"
$TenantApiOrigins | ForEach-Object { Write-Host "    $_" }
Write-Host "  StateBucket:   $StateBucket"

$bucketCheckArgs = @(
    "s3api", "get-bucket-location",
    "--bucket", $StateBucket,
    "--profile", $Profile,
    "--region", $Region,
    "--no-cli-pager"
)
& aws @bucketCheckArgs *> $null
$bucketAccessible = $LASTEXITCODE -eq 0

if (-not $bucketAccessible) {
    if (-not $CreateStateBucket) {
        throw "State bucket '$StateBucket' is not accessible. If it does not exist, re-run explicitly with -CreateStateBucket."
    }

    Write-Host "Creating portal state bucket..."
    $createArgs = @(
        "s3api", "create-bucket",
        "--bucket", $StateBucket,
        "--region", $Region,
        "--profile", $Profile,
        "--no-cli-pager"
    )
    if ($Region -ne "us-east-1") {
        $createArgs += @(
            "--create-bucket-configuration",
            "LocationConstraint=$Region"
        )
    }
    & aws @createArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create portal state bucket '$StateBucket'."
    }
}

& aws s3api put-bucket-versioning `
    --bucket $StateBucket `
    --versioning-configuration Status=Enabled `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to enable portal state bucket versioning."
}

& aws s3api put-bucket-encryption `
    --bucket $StateBucket `
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to enable portal state bucket encryption."
}

& aws s3api put-public-access-block `
    --bucket $StateBucket `
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to block public access to the portal state bucket."
}

$tfvarsPath = Join-Path $portalDir "terraform.tfvars"
$backendPath = Join-Path $portalDir "backend.hcl"

$tenantOriginsHcl = ($TenantApiOrigins | ForEach-Object { "  `"$_`"," }) -join "`n"
$certificateHcl = if ([string]::IsNullOrWhiteSpace($CertificateArn)) { "null" } else { "`"$CertificateArn`"" }
$route53ZoneHcl = if ([string]::IsNullOrWhiteSpace($Route53ZoneId)) { "null" } else { "`"$Route53ZoneId`"" }

@"
aws_region             = "$Region"
environment            = "$Environment"
operator_account_id    = "$ExpectedAccountId"
portal_domain          = "$PortalDomain"
legacy_portal_domain   = "$LegacyPortalDomain"
activate_canonical_domain = $($ActivateCanonicalDomain.ToString().ToLowerInvariant())
directory_api_base_url = "$DirectoryApiBaseUrl"
tenant_api_origins = [
$tenantOriginsHcl
]
certificate_arn = $certificateHcl
route53_zone_id = $route53ZoneHcl
"@ | Set-Content -Path $tfvarsPath -Encoding utf8

@"
bucket       = "$StateBucket"
key          = "portal/$Environment/terraform.tfstate"
region       = "$Region"
encrypt      = true
use_lockfile = true
"@ | Set-Content -Path $backendPath -Encoding utf8

$previousProfile = $env:AWS_PROFILE
try {
    $env:AWS_PROFILE = $Profile

    & terraform "-chdir=$portalDir" init -reconfigure -backend-config="backend.hcl"
    if ($LASTEXITCODE -ne 0) {
        throw "terraform init failed for the portal stack."
    }

    $planName = "tfplan-portal"
    $planPath = Join-Path $portalDir $planName
    & terraform "-chdir=$portalDir" plan "-out=$planName"
    if ($LASTEXITCODE -ne 0) {
        throw "terraform plan failed for the portal stack."
    }
    if (-not (Test-Path $planPath -PathType Leaf)) {
        throw "terraform plan did not create the expected plan file: $planPath"
    }

    $planJson = (& terraform "-chdir=$portalDir" show -json $planName) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($planJson)) {
        throw "terraform show -json failed for the portal plan."
    }

    try {
        $plan = $planJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "terraform show -json returned invalid JSON: $($_.Exception.Message)"
    }

    $deletes = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "delete" }
    )
    if ($deletes.Count -gt 0) {
        $addresses = $deletes | ForEach-Object { $_.address }
        throw "Portal plan contains delete/replacement actions and will not be applied:`n$($addresses -join "`n")"
    }

    $creates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "create" }
    ).Count
    $updates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "update" }
    ).Count
    Write-Host "Portal Terraform plan verified: $creates create, $updates update, 0 delete."

    if (-not $Apply) {
        Write-Host "Plan only. Re-run with -Apply after reviewing the plan."
        exit 0
    }

    & terraform "-chdir=$portalDir" apply $planName
    if ($LASTEXITCODE -ne 0) {
        throw "terraform apply failed for the portal stack."
    }

    Write-Host "Portal infrastructure deployment complete."
    & terraform "-chdir=$portalDir" output
    if ($LASTEXITCODE -ne 0) {
        throw "terraform output failed after portal apply."
    }
}
finally {
    if ($null -eq $previousProfile) {
        Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
    }
    else {
        $env:AWS_PROFILE = $previousProfile
    }
}
