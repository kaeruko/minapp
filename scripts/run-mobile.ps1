[CmdletBinding()]
param(
    [string]$DeviceId
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent $PSScriptRoot
$mobileDir = Join-Path $repoRoot "apps\mobile"
$configPath = Join-Path $mobileDir "config\development.json"
$configureAndroidScript = Join-Path $PSScriptRoot "configure-mobile-android.ps1"

if (-not (Test-Path -LiteralPath $mobileDir -PathType Container)) {
    throw "Mobile app directory not found: $mobileDir"
}
if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Mobile development config not found: $configPath"
}
if (-not (Test-Path -LiteralPath $configureAndroidScript -PathType Leaf)) {
    throw "Android configuration script not found: $configureAndroidScript"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter was not found in PATH."
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
        "run",
        "--dart-define-from-file=$configPath"
    )
    if (-not [string]::IsNullOrWhiteSpace($DeviceId)) {
        $flutterArgs += @("-d", $DeviceId)
    }

    & flutter @flutterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "flutter run failed. DeviceId=$DeviceId"
    }
}
finally {
    Pop-Location
}
