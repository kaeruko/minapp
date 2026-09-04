param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Region = "us-west-2"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

foreach ($command in @("aws", "terraform")) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
        throw "Required command was not found in PATH: $command"
    }
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$portalDir = Join-Path $repoRoot "infra\portal"
$webDir = Join-Path $repoRoot "apps\web"

if (-not (Test-Path $portalDir -PathType Container)) {
    throw "Portal Terraform stack was not found: $portalDir"
}
if (-not (Test-Path $webDir -PathType Container)) {
    throw "Web application directory was not found: $webDir"
}

& (Join-Path $PSScriptRoot "verify-aws-deploy-target.ps1") `
    -ExpectedAccountId $ExpectedAccountId `
    -Profile $Profile `
    -Region $Region

$productionAssets = @(
    "index.html",
    "girls.html",
    "styles.css",
    "preauth.css",
    "phase2.css",
    "phase4.css",
    "student_dashboard.css",
    "teacher_dashboard.css",
    "moderation_actions.css",
    "display_names.css",
    "portal_shell.css",
    "girls_portal.css",
    "girls_portal_base.css",
    "girls_login_frame.png",
    "girls_login_pattern.png",
    "girls_login_lace.png",
    "girls_logo.png",
    "girls_mascot_pair.svg",
    "portal_routing.js",
    "single_html_zip.js",
    "app.js",
    "phase2.js",
    "phase2_transport.js",
    "phase4.js",
    "student_dashboard.js",
    "teacher_dashboard.js",
    "custom_student_login.js",
    "moderation_actions.js",
    "display_names.js",
    "portal_shell.js",
    "girls_portal.js",
    "girls_portal_shell.js"
)

foreach ($relativePath in $productionAssets) {
    $sourcePath = Join-Path $webDir $relativePath
    if (-not (Test-Path $sourcePath -PathType Leaf)) {
        throw "Required production Web asset is missing: $sourcePath"
    }
}

function Get-PortalTerraformOutput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $value = (& terraform "-chdir=$portalDir" output -raw $Name) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read Terraform output '$Name'. Run deploy-portal.ps1 successfully first."
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "Terraform output '$Name' was empty."
    }
    return $value
}

$previousProfile = $env:AWS_PROFILE
$stagingDir = Join-Path ([System.IO.Path]::GetTempPath()) ("minapp-portal-" + [guid]::NewGuid().ToString("N"))

try {
    $env:AWS_PROFILE = $Profile

    $bucket = Get-PortalTerraformOutput -Name "portal_bucket_name"
    $distribution = Get-PortalTerraformOutput -Name "cloudfront_distribution_id"
    $portalUrl = Get-PortalTerraformOutput -Name "portal_url"

    foreach ($configKey in @("portal-config.json", "girls-config.json")) {
        & aws s3api head-object `
            --bucket $bucket `
            --key $configKey `
            --profile $Profile `
            --region $Region `
            --no-cli-pager *> $null
        if ($LASTEXITCODE -ne 0) {
            throw "Terraform-managed $configKey is missing from s3://$bucket. Refusing to publish Web assets."
        }
    }

    New-Item -ItemType Directory -Path $stagingDir | Out-Null
    foreach ($relativePath in $productionAssets) {
        Copy-Item `
            -LiteralPath (Join-Path $webDir $relativePath) `
            -Destination (Join-Path $stagingDir $relativePath)
    }

    Write-Host "Publishing production Web assets only:"
    $productionAssets | ForEach-Object { Write-Host "  $_" }
    Write-Host "Protected Terraform objects: portal-config.json, girls-config.json"
    Write-Host "Destination bucket: $bucket"

    & aws s3 sync `
        $stagingDir `
        "s3://$bucket" `
        --delete `
        --exclude "portal-config.json" `
        --exclude "girls-config.json" `
        --profile $Profile `
        --region $Region `
        --no-progress
    if ($LASTEXITCODE -ne 0) {
        throw "Portal asset upload failed."
    }

    $invalidationJson = (& aws cloudfront create-invalidation `
        --distribution-id $distribution `
        --paths "/*" `
        --profile $Profile `
        --output json `
        --no-cli-pager) -join "`n"
    if ($LASTEXITCODE -ne 0) {
        throw "CloudFront invalidation creation failed."
    }
    if ([string]::IsNullOrWhiteSpace($invalidationJson)) {
        throw "CloudFront invalidation returned an empty response."
    }

    try {
        $invalidation = $invalidationJson | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "CloudFront invalidation returned invalid JSON: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace([string]$invalidation.Invalidation.Id)) {
        throw "CloudFront invalidation response did not contain an invalidation ID."
    }

    Write-Host "Portal publication complete."
    Write-Host "  URL:             $portalUrl"
    Write-Host "  Girls URL:       $portalUrl/girls.html"
    Write-Host "  Distribution:    $distribution"
    Write-Host "  Invalidation ID: $($invalidation.Invalidation.Id)"
}
finally {
    if (Test-Path $stagingDir) {
        Remove-Item -LiteralPath $stagingDir -Recurse -Force
    }

    if ($null -eq $previousProfile) {
        Remove-Item Env:AWS_PROFILE -ErrorAction SilentlyContinue
    }
    else {
        $env:AWS_PROFILE = $previousProfile
    }
}
