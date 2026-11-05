[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$BuildName,

    [ValidateRange(1, 2100000000)]
    [Nullable[int]]$BuildNumber,

    [switch]$SkipChecks
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$mobileDir = Join-Path $repoRoot "apps\mobile"
$entrypoint = Join-Path $mobileDir "lib\main_kobo.dart"
$androidDir = Join-Path $mobileDir "android"
$androidAppDir = Join-Path $androidDir "app"
$keyPropertiesPath = Join-Path $androidDir "key.properties"
$manifestPath = Join-Path $androidAppDir "src\main\AndroidManifest.xml"
$outputPath = Join-Path $mobileDir "build\app\outputs\bundle\release\app-release.aab"
$mergedManifestPath = Join-Path $mobileDir "build\app\intermediates\merged_manifests\release\processReleaseManifest\AndroidManifest.xml"
$variantEnvironmentName = "ORG_GRADLE_PROJECT_minappVariant"
$previousVariant = [Environment]::GetEnvironmentVariable($variantEnvironmentName, "Process")

function Invoke-Flutter {
    param([Parameter(Mandatory)][string[]]$Arguments)

    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "flutter $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

if (-not (Test-Path -LiteralPath $mobileDir -PathType Container)) {
    throw "Mobile app directory does not exist: $mobileDir"
}
if (-not (Test-Path -LiteralPath $entrypoint -PathType Leaf)) {
    throw "Kobo entrypoint does not exist: $entrypoint"
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "AndroidManifest.xml does not exist: $manifestPath"
}
if (-not (Select-String -LiteralPath $manifestPath -SimpleMatch 'android.permission.INTERNET' -Quiet)) {
    throw "AndroidManifest.xml is missing android.permission.INTERNET: $manifestPath"
}
if (-not (Get-Command flutter -ErrorAction SilentlyContinue)) {
    throw "flutter was not found in PATH."
}
if (-not (Test-Path -LiteralPath $keyPropertiesPath -PathType Leaf)) {
    throw "Release signing configuration does not exist: $keyPropertiesPath"
}

$keyProperties = @{}
foreach ($line in Get-Content -LiteralPath $keyPropertiesPath) {
    $trimmed = $line.Trim()
    if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#') -or $trimmed.StartsWith('!')) {
        continue
    }

    $separator = $trimmed.IndexOf('=')
    if ($separator -lt 1) {
        throw "Unsupported key.properties line. Expected name=value."
    }

    $name = $trimmed.Substring(0, $separator).Trim()
    $value = $trimmed.Substring($separator + 1).Trim()
    if ($keyProperties.ContainsKey($name)) {
        throw "Duplicate key.properties entry: $name"
    }
    $keyProperties[$name] = $value
}

foreach ($requiredName in @('storePassword', 'keyPassword', 'keyAlias', 'storeFile')) {
    if (-not $keyProperties.ContainsKey($requiredName) -or
        [string]::IsNullOrWhiteSpace([string]$keyProperties[$requiredName])) {
        throw "Missing key.properties value: $requiredName"
    }
}

$storeFileValue = [string]$keyProperties['storeFile']
$storeFilePath = if ([IO.Path]::IsPathRooted($storeFileValue)) {
    $storeFileValue
}
else {
    Join-Path $androidAppDir $storeFileValue
}
if (-not (Test-Path -LiteralPath $storeFilePath -PathType Leaf)) {
    throw "Android release keystore does not exist: $storeFilePath"
}

$buildArguments = @(
    'build',
    'appbundle',
    '--release',
    '--target',
    'lib/main_kobo.dart'
)
if (-not [string]::IsNullOrWhiteSpace($BuildName)) {
    $buildArguments += @('--build-name', $BuildName)
}
if ($null -ne $BuildNumber) {
    $buildArguments += @('--build-number', $BuildNumber.ToString())
}

Push-Location $mobileDir
try {
    [Environment]::SetEnvironmentVariable($variantEnvironmentName, 'kobo', 'Process')

    Invoke-Flutter -Arguments @('pub', 'get')
    if (-not $SkipChecks) {
        Invoke-Flutter -Arguments @('analyze', '--no-pub')
        Invoke-Flutter -Arguments @('test', '--no-pub')
    }

    Invoke-Flutter -Arguments $buildArguments
}
finally {
    [Environment]::SetEnvironmentVariable(
        $variantEnvironmentName,
        $previousVariant,
        'Process'
    )
    Pop-Location
}

if (-not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
    throw "Flutter completed without producing the expected AAB: $outputPath"
}
if (-not (Test-Path -LiteralPath $mergedManifestPath -PathType Leaf)) {
    throw "Flutter completed without producing the merged release manifest: $mergedManifestPath"
}

[xml]$mergedManifest = Get-Content -LiteralPath $mergedManifestPath -Raw
$androidNamespace = 'http://schemas.android.com/apk/res/android'
$applicationId = $mergedManifest.manifest.package
$versionCode = $mergedManifest.manifest.GetAttribute('versionCode', $androidNamespace)
$versionName = $mergedManifest.manifest.GetAttribute('versionName', $androidNamespace)
$applicationLabel = $mergedManifest.manifest.application.GetAttribute('label', $androidNamespace)
$applicationIcon = $mergedManifest.manifest.application.GetAttribute('icon', $androidNamespace)

if ($applicationId -ne 'jp.cloxs.minapp.kobo') {
    throw "Unexpected release application ID: $applicationId"
}
if ($applicationLabel -ne 'みんアプ工房') {
    throw "Unexpected release application label: $applicationLabel"
}
if ($applicationIcon -ne '@mipmap/ic_launcher_kobo') {
    throw "Unexpected release application icon: $applicationIcon"
}
if ($null -ne $BuildNumber -and $versionCode -ne $BuildNumber.ToString()) {
    throw "Unexpected release version code: expected $BuildNumber, got $versionCode"
}
if (-not [string]::IsNullOrWhiteSpace($BuildName) -and $versionName -ne $BuildName) {
    throw "Unexpected release version name: expected $BuildName, got $versionName"
}

$output = Get-Item -LiteralPath $outputPath
$hash = Get-FileHash -LiteralPath $outputPath -Algorithm SHA256
Write-Host "Kobo release AAB created."
Write-Host "Path: $($output.FullName)"
Write-Host "Application ID: $applicationId"
Write-Host "Version: $versionName+$versionCode"
Write-Host "Size: $($output.Length) bytes"
Write-Host "SHA256: $($hash.Hash)"
