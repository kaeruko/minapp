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
    "girls-assets\ChatGPT Image 2026年9月6日 03_44_07.png",
    "girls-assets\logo.png",
    "girls-assets\brand_icon.png",
    "girls-assets\character.png",
    "girls-assets\mascot_pair.svg",
    "girls-assets\sidebar\header.png",
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

    $value = & terraform -chdir=$portalDir output -raw $Name
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to read Terraform output '$Name'."
    }

    $trimmed = $value.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        throw "Terraform output '$Name' was empty."
    }

    return $trimmed
}

$bucketName = Get-PortalTerraformOutput -Name "portal_bucket_name"
$distributionId = Get-PortalTerraformOutput -Name "cloudfront_distribution_id"

Write-Host "Publishing portal assets to s3://$bucketName ..."
foreach ($relativePath in $productionAssets) {
    $sourcePath = Join-Path $webDir $relativePath
    $s3Key = $relativePath.Replace("\\", "/")
    & aws s3 cp $sourcePath "s3://$bucketName/$s3Key" --profile $Profile --region $Region --only-show-errors
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to upload portal asset: $relativePath"
    }
}

Write-Host "Creating CloudFront invalidation for distribution $distributionId ..."
& aws cloudfront create-invalidation `
    --distribution-id $distributionId `
    --paths "/*" `
    --profile $Profile `
    --region $Region | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to create CloudFront invalidation."
}

Write-Host "Portal publish completed."
