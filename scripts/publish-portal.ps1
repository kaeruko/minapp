param(
    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAccountId = "314267685786",

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$Profile = "minapp-new",

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
    "girls_footer.css",
    "girls_sidebar_art.css",
    "girls-assets\login\frame.png",
    "girls-assets\login\pattern.png",
    "girls-assets\login\lace.png",
    "girls-assets\logo.png",
    "girls-assets\brand_icon.png",
    "girls-assets\character.png",
    "girls-assets\mascot_pair.svg",
    "girls-assets\sidebar\clouds.png",
    "girls-assets\sidebar\lace.png",
    "girls-assets\split_icons\weather.png",
    "girls-assets\split_icons\recipe.png",
    "girls-assets\split_icons\todo.png",
    "girls-assets\split_icons\rent_app.png",
    "girls-assets\split_icons\fortune_app.png",
    "girls-assets\split_icons\rei_app.png",
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
    "girls_portal_shell.js",
    "girls_footer.js"
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
        $destinationPath = Join-Path $stagingDir $relativePath
        $destinationDirectory = Split-Path -Parent $destinationPath
        if (-not (Test-Path $destinationDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        }

        Copy-Item `
            -LiteralPath (Join-Path $webDir $relativePath) `
            -Destination $destinationPath
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
