param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Region = "us-west-2",

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[a-z][a-z0-9-]{1,15}$')]
    [string]$Environment = "dev",

    [Parameter(Mandatory = $false)]
    [string]$StateBucket,

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

$repoRoot = Split-Path -Parent $PSScriptRoot
$directoryDir = Join-Path $repoRoot "infra\directory"
if (-not (Test-Path $directoryDir)) {
    throw "Directory Terraform stack was not found: $directoryDir"
}

& (Join-Path $PSScriptRoot "verify-aws-deploy-target.ps1") `
    -ExpectedAccountId $ExpectedAccountId `
    -Profile $Profile

if ([string]::IsNullOrWhiteSpace($StateBucket)) {
    $StateBucket = "minapp-directory-terraform-state-$ExpectedAccountId-$Region"
}
if ($StateBucket.Length -gt 63 -or $StateBucket -notmatch '^[a-z0-9][a-z0-9.-]*[a-z0-9]$') {
    throw "StateBucket is not a valid S3 bucket name: $StateBucket"
}

Write-Host "Directory deployment target:"
Write-Host "  Account:     $ExpectedAccountId"
Write-Host "  Profile:     $Profile"
Write-Host "  Region:      $Region"
Write-Host "  Environment: $Environment"
Write-Host "  StateBucket: $StateBucket"

$bucketCheckArgs = @(
    "s3api", "get-bucket-location",
    "--bucket", $StateBucket,
    "--profile", $Profile,
    "--region", $Region,
    "--no-cli-pager"
)
& aws @bucketCheckArgs *> $null
$bucketExists = $LASTEXITCODE -eq 0

if (-not $bucketExists) {
    Write-Host "Creating Directory state bucket..."
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
        throw "Failed to create Directory state bucket '$StateBucket'."
    }
}
else {
    Write-Host "Directory state bucket already exists and is accessible."
}

& aws s3api put-bucket-versioning `
    --bucket $StateBucket `
    --versioning-configuration Status=Enabled `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to enable S3 bucket versioning."
}

& aws s3api put-bucket-encryption `
    --bucket $StateBucket `
    --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}' `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to enable S3 bucket encryption."
}

& aws s3api put-public-access-block `
    --bucket $StateBucket `
    --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true `
    --profile $Profile `
    --region $Region `
    --no-cli-pager
if ($LASTEXITCODE -ne 0) {
    throw "Failed to block public access to the state bucket."
}

$tfvarsPath = Join-Path $directoryDir "terraform.tfvars"
$backendPath = Join-Path $directoryDir "backend.hcl"

@"
aws_region          = "$Region"
environment         = "$Environment"
operator_account_id = "$ExpectedAccountId"

descriptor_ttl_seconds    = 86400
rate_limit_requests       = 60
rate_limit_window_seconds = 60
"@ | Set-Content -Path $tfvarsPath -Encoding utf8

@"
bucket       = "$StateBucket"
key          = "directory/$Environment/terraform.tfstate"
region       = "$Region"
encrypt      = true
use_lockfile = true
"@ | Set-Content -Path $backendPath -Encoding utf8

$previousProfile = $env:AWS_PROFILE
try {
    $env:AWS_PROFILE = $Profile

    & terraform "-chdir=$directoryDir" init -reconfigure -backend-config="backend.hcl"
    if ($LASTEXITCODE -ne 0) {
        throw "terraform init failed."
    }

    $planName = "tfplan-directory"
    & terraform "-chdir=$directoryDir" plan -out=$planName
    if ($LASTEXITCODE -ne 0) {
        throw "terraform plan failed."
    }

    $planJson = (& terraform "-chdir=$directoryDir" show -json $planName) -join "`n"
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($planJson)) {
        throw "terraform show -json failed."
    }
    $plan = $planJson | ConvertFrom-Json -ErrorAction Stop
    $deletes = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "delete" }
    )
    if ($deletes.Count -gt 0) {
        $addresses = $deletes | ForEach-Object { $_.address }
        throw "Directory plan contains delete actions and will not be applied:`n$($addresses -join "`n")"
    }

    $creates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "create" }
    ).Count
    $updates = @(
        $plan.resource_changes |
            Where-Object { @($_.change.actions) -contains "update" }
    ).Count
    Write-Host "Directory Terraform plan verified: $creates create, $updates update, 0 delete."

    if (-not $Apply) {
        Write-Host "Plan only. Re-run with -Apply after reviewing the plan."
        exit 0
    }

    & terraform "-chdir=$directoryDir" apply $planName
    if ($LASTEXITCODE -ne 0) {
        throw "terraform apply failed."
    }

    Write-Host "Directory deployment complete."
    & terraform "-chdir=$directoryDir" output
    if ($LASTEXITCODE -ne 0) {
        throw "terraform output failed after apply."
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
