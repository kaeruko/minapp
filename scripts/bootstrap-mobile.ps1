$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$mobileRoot = Join-Path $repoRoot "apps\mobile"
$androidTarget = Join-Path $mobileRoot "android"

if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter command was not found in PATH. Install/configure Flutter before running this script."
}

if (-not (Test-Path -LiteralPath $mobileRoot -PathType Container)) {
    throw "Mobile project directory does not exist: $mobileRoot"
}

if (Test-Path -LiteralPath $androidTarget) {
    throw "Android platform directory already exists: $androidTarget"
}

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("minapp-flutter-" + [Guid]::NewGuid().ToString("N"))

try {
    flutter create --platforms=android --org jp.cloxs --project-name min $tempRoot
    if ($LASTEXITCODE -ne 0) {
        throw "flutter create failed with exit code $LASTEXITCODE"
    }

    $generatedAndroid = Join-Path $tempRoot "android"
    if (-not (Test-Path -LiteralPath $generatedAndroid -PathType Container)) {
        throw "flutter create completed but android directory was not generated: $generatedAndroid"
    }

    $applicationIdMatches = Get-ChildItem -LiteralPath $generatedAndroid -Recurse -File |
        Where-Object { $_.Name -like "build.gradle*" } |
        Select-String -SimpleMatch 'jp.cloxs.min'

    if (-not $applicationIdMatches) {
        throw "Generated Android project does not contain expected application id jp.cloxs.min"
    }

    Copy-Item -LiteralPath $generatedAndroid -Destination $androidTarget -Recurse

    if (-not (Test-Path -LiteralPath $androidTarget -PathType Container)) {
        throw "Android platform copy did not produce the expected target directory: $androidTarget"
    }

    & (Join-Path $PSScriptRoot "configure-mobile-android.ps1")

    Write-Host "Generated apps/mobile/android with package id jp.cloxs.min"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}
