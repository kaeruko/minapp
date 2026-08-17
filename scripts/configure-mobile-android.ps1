$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
$androidRoot = Join-Path $repoRoot "apps\mobile\android"
$manifestPath = Join-Path $androidRoot "app\src\main\AndroidManifest.xml"

if (-not (Test-Path -LiteralPath $androidRoot -PathType Container)) {
    throw "Android platform directory does not exist: $androidRoot. Run .\scripts\bootstrap-mobile.ps1 first."
}
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "AndroidManifest.xml does not exist: $manifestPath"
}

$content = [System.IO.File]::ReadAllText($manifestPath)
$permission = 'android.permission.INTERNET'

if ($content.Contains($permission)) {
    Write-Host "Android INTERNET permission is already configured."
    exit 0
}

$manifestMatch = [regex]::Match($content, '<manifest\b[^>]*>')
if (-not $manifestMatch.Success) {
    throw "Could not find the opening <manifest> element in $manifestPath"
}

$insertAt = $manifestMatch.Index + $manifestMatch.Length
$insert = "`r`n    <uses-permission android:name=`"$permission`" />"
$updated = $content.Insert($insertAt, $insert)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($manifestPath, $updated, $utf8NoBom)

$verified = [System.IO.File]::ReadAllText($manifestPath)
if (-not $verified.Contains($permission)) {
    throw "Failed to add Android INTERNET permission to $manifestPath"
}

Write-Host "Configured Android INTERNET permission in $manifestPath"
