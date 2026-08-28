[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsProfile,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9]{12}$')]
    [string]$ExpectedAwsAccountId,

    [Parameter(Mandatory = $false)]
    [ValidateNotNullOrEmpty()]
    [string]$AwsRegion = "us-west-2",

    [string]$DeviceId = "HA2B7883",
    [string]$CreatorPortalBaseUrl = "https://portal.cloxs.jp"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "apps\mobile"
$directoryTerraformDir = Join-Path $repoRoot "infra\directory"
$configureAndroidScript = Join-Path $PSScriptRoot "configure-mobile-android.ps1"
$awsDevScript = Join-Path $PSScriptRoot "aws-dev.ps1"

if (-not (Test-Path -LiteralPath $mobileDir -PathType Container)) {
    throw "Mobile app directory not found: $mobileDir"
}

if (-not (Test-Path -LiteralPath $directoryTerraformDir -PathType Container)) {
    throw "Directory Terraform directory not found: $directoryTerraformDir"
}

if (-not (Test-Path -LiteralPath $configureAndroidScript -PathType Leaf)) {
    throw "Android configuration script not found: $configureAndroidScript"
}

if (-not (Test-Path -LiteralPath $awsDevScript -PathType Leaf)) {
    throw "AWS setup script not found: $awsDevScript"
}

& $awsDevScript `
    -Profile $AwsProfile `
    -ExpectedAccountId $ExpectedAwsAccountId `
    -Region $AwsRegion

if ($LASTEXITCODE -ne 0) {
    throw "AWS environment setup failed."
}

$directoryApi = & terraform "-chdir=$directoryTerraformDir" output -raw directory_api_base_url
if ($LASTEXITCODE -ne 0) {
    throw "Failed to get directory_api_base_url from Terraform."
}

$directoryApi = $directoryApi.Trim()
if ([string]::IsNullOrWhiteSpace($directoryApi)) {
    throw "Terraform returned an empty directory_api_base_url."
}

& $configureAndroidScript
if ($LASTEXITCODE -ne 0) {
    throw "Android configuration failed."
}

Push-Location $mobileDir
try {
    flutter pub get
    if ($LASTEXITCODE -ne 0) {
        throw "flutter pub get failed."
    }

    flutter run `
        -d $DeviceId `
        --dart-define="MINAPP_DIRECTORY_BASE_URL=$directoryApi" `
        --dart-define="MINAPP_CREATOR_PORTAL_BASE_URL=$CreatorPortalBaseUrl"

    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed. DeviceId=$DeviceId"
    }
}
finally {
    Pop-Location
}
