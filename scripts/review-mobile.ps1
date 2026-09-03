param(
    [string]$DeviceId = "",
    [string]$PortalConfigUrl = "https://minapp.cloxs.jp/portal-config.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Command,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter(Mandatory = $true)]
        [string]$Description
    )

    Write-Host ""
    Write-Host "==> $Description"

    & $Command @Arguments

    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$mobileDir = Join-Path $repoRoot "apps\mobile"
$configureScript = Join-Path $repoRoot "scripts\configure-mobile-android.ps1"

if (-not (Test-Path $mobileDir -PathType Container)) {
    throw "Mobile directory not found: $mobileDir"
}

if (-not (Test-Path $configureScript -PathType Leaf)) {
    throw "Configure script not found: $configureScript"
}

Write-Host "Repo: $repoRoot"

# ----------------------------------------
# Production Directory API を取得
# ----------------------------------------

Write-Host ""
Write-Host "==> Loading production portal config"
Write-Host $PortalConfigUrl

try {
    $portalConfig = Invoke-RestMethod `
        -Uri $PortalConfigUrl `
        -Method Get `
        -ErrorAction Stop
}
catch {
    throw "Failed to load ${PortalConfigUrl}: $($_.Exception.Message)"
}

if ($null -eq $portalConfig.schema_version) {
    throw "portal-config.json does not contain schema_version"
}

if ($portalConfig.schema_version -ne 1) {
    throw "Unsupported portal-config schema_version: $($portalConfig.schema_version)"
}

$directoryApi = $portalConfig.directory_api_base_url

if ([string]::IsNullOrWhiteSpace($directoryApi)) {
    throw "portal-config.json does not contain directory_api_base_url"
}

$directoryUri = $null

if (-not [Uri]::TryCreate(
        $directoryApi,
        [UriKind]::Absolute,
        [ref]$directoryUri
    )) {
    throw "Invalid Directory API URL: $directoryApi"
}

if ($directoryUri.Scheme -ne "https") {
    throw "Directory API must use HTTPS: $directoryApi"
}

Write-Host "Directory API: $directoryApi"

# ----------------------------------------
# Android project configuration
# ----------------------------------------

Write-Host ""
Write-Host "==> Configuring Android"

& $configureScript

if (-not $?) {
    throw "configure-mobile-android.ps1 failed"
}

Set-Location $mobileDir

# ----------------------------------------
# Flutter checks
# ----------------------------------------

Invoke-Native `
    -Command "flutter" `
    -Arguments @("pub", "get") `
    -Description "flutter pub get"

Invoke-Native `
    -Command "flutter" `
    -Arguments @("analyze") `
    -Description "flutter analyze"

Invoke-Native `
    -Command "flutter" `
    -Arguments @("test") `
    -Description "flutter test"

# ----------------------------------------
# Android device detection
# ----------------------------------------

Write-Host ""
Write-Host "==> Detecting Android devices"

$devicesJson = & flutter devices --machine

if ($LASTEXITCODE -ne 0) {
    throw "flutter devices --machine failed with exit code $LASTEXITCODE"
}

try {
    $devices = @($devicesJson | ConvertFrom-Json)
}
catch {
    throw "Failed to parse output from flutter devices --machine: $($_.Exception.Message)"
}

$androidDevices = @(
    $devices | Where-Object {
        $_.targetPlatform -like "android-*"
    }
)

if ($androidDevices.Count -eq 0) {
    throw "No Android device found. Connect the Android device and retry."
}

if ([string]::IsNullOrWhiteSpace($DeviceId)) {

    if ($androidDevices.Count -ne 1) {
        Write-Host ""
        Write-Host "Android devices:"

        foreach ($device in $androidDevices) {
            Write-Host "  $($device.id)  $($device.name)"
        }

        throw "Multiple Android devices found. Specify one with -DeviceId."
    }

    $selectedDevice = $androidDevices[0]
}
else {
    $matches = @(
        $androidDevices | Where-Object {
            $_.id -eq $DeviceId
        }
    )

    if ($matches.Count -ne 1) {
        throw "Android device not found: $DeviceId"
    }

    $selectedDevice = $matches[0]
}

Write-Host "Device: $($selectedDevice.name)"
Write-Host "ID:     $($selectedDevice.id)"

# ----------------------------------------
# Run production-connected mobile app
# ----------------------------------------

Write-Host ""
Write-Host "========================================"
Write-Host " Review test"
Write-Host "========================================"
Write-Host "Classroom: MEJ6-HZF7-T6MS"
Write-Host "ID:        review"
Write-Host "Password:  123456"
Write-Host "========================================"
Write-Host ""

Invoke-Native `
    -Command "flutter" `
    -Arguments @(
        "run",
        "-d",
        $selectedDevice.id,
        "--dart-define=MINAPP_DIRECTORY_BASE_URL=$directoryApi"
    ) `
    -Description "flutter run"