[CmdletBinding()]
param(
    [string]$DeviceId = "HA2B7883",
    [string]$CreatorPortalBaseUrl = "https://minapp.cloxs.jp",
    [string]$DirectoryApiBaseUrl
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "apps\mobile"
$configureAndroidScript = Join-Path $PSScriptRoot "configure-mobile-android.ps1"

if (-not (Test-Path -LiteralPath $mobileDir -PathType Container)) {
    throw "Mobile app directory not found: $mobileDir"
}

if (-not (Test-Path -LiteralPath $configureAndroidScript -PathType Leaf)) {
    throw "Android configuration script not found: $configureAndroidScript"
}

if ($PSBoundParameters.ContainsKey('DirectoryApiBaseUrl') -and [string]::IsNullOrWhiteSpace($DirectoryApiBaseUrl)) {
    throw "DirectoryApiBaseUrl was explicitly provided but is empty."
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

    $flutterArgs = @(
        'run',
        '-d', $DeviceId,
        "--dart-define=MINAPP_CREATOR_PORTAL_BASE_URL=$CreatorPortalBaseUrl"
    )

    if ($PSBoundParameters.ContainsKey('DirectoryApiBaseUrl')) {
        $flutterArgs += "--dart-define=MINAPP_DIRECTORY_BASE_URL=$DirectoryApiBaseUrl"
    }

    flutter @flutterArgs

    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed. DeviceId=$DeviceId"
    }
}
finally {
    Pop-Location
}
