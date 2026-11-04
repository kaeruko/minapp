[CmdletBinding()]
param(
    [string[]]$AppName,
    [switch]$All,
    [string]$SourceRoot,
    [switch]$AllowDirtySource,
    [switch]$ForceOverwrite,
    [switch]$PlanHosted,
    [switch]$ApplyHosted
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Require-Command {
    param([Parameter(Mandatory = $true)][string]$Name)

    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command was not found in PATH: $Name"
    }
}

function Invoke-Checked {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Context
    )

    & $FilePath @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Context failed with exit code $exitCode."
    }
}

function Invoke-GitCapture {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $output = @(& git -C $Repository @Arguments)
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$Context failed with exit code $exitCode."
    }
    return (($output | ForEach-Object { [string]$_ }) -join "`n").Trim()
}

function Get-SyncBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $textExtensions = @(
        '.css',
        '.csv',
        '.html',
        '.htm',
        '.js',
        '.json',
        '.md',
        '.svg',
        '.txt',
        '.xml'
    )
    $extension = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($textExtensions -notcontains $extension) {
        return $bytes
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $utf8.GetString($bytes)
    }
    catch {
        throw "Text asset is not valid UTF-8: $Path"
    }

    $newline = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
    $normalized = $text.TrimEnd([char[]]"`r`n") + $newline
    return $utf8.GetBytes($normalized)
}

function Test-BytesEqual {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Left,
        [Parameter(Mandatory = $true)][byte[]]$Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index += 1) {
        if ($Left[$index] -ne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Test-HostOverlayRequired {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$TargetPath
    )

    if (-not (Test-Path -LiteralPath $TargetPath -PathType Leaf)) { return $false }
    $sourceText = [System.IO.File]::ReadAllText($SourcePath)
    $targetText = [System.IO.File]::ReadAllText($TargetPath)
    return (
        $targetText.Contains('MinAppBuiltinState') -and
        -not $sourceText.Contains('MinAppBuiltinState')
    )
}

$defaultFullDeployment = $PSBoundParameters.Count -eq 0
$requestedApps = @(
    $AppName |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { $_.Trim() } |
        Select-Object -Unique
)
if ($All -and $requestedApps.Count -ne 0) {
    throw 'Use either -AppName or -All, not both.'
}
if (-not $All -and $requestedApps.Count -eq 0) {
    $All = $true
}
if ($defaultFullDeployment) {
    $ApplyHosted = $true
}
if ($PlanHosted -and $ApplyHosted) {
    throw 'Use either -PlanHosted or -ApplyHosted, not both.'
}

Require-Command -Name 'git'
Require-Command -Name 'node'
Require-Command -Name 'flutter'
if ($PlanHosted -or $ApplyHosted) {
    Require-Command -Name 'terraform'
}

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$mobileRoot = Join-Path $repoRoot 'apps\mobile'
$pubspecPath = Join-Path $mobileRoot 'pubspec.yaml'
$builtinTestPath = Join-Path $mobileRoot 'test\builtin_apps_test.dart'
$hostedDeployScript = Join-Path $PSScriptRoot 'deploy-hosted.ps1'
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
    $SourceRoot = Join-Path $repoRoot '..\minapp_apps'
}
$SourceRoot = [System.IO.Path]::GetFullPath($SourceRoot)

if (-not (Test-Path -LiteralPath $pubspecPath -PathType Leaf)) {
    throw "Mobile pubspec was not found: $pubspecPath"
}
if (-not (Test-Path -LiteralPath $builtinTestPath -PathType Leaf)) {
    throw "Built-in test was not found: $builtinTestPath"
}
if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
    throw "minapp_apps checkout was not found: $SourceRoot"
}
if (($PlanHosted -or $ApplyHosted) -and -not (Test-Path -LiteralPath $hostedDeployScript -PathType Leaf)) {
    throw "Hosted deployment script was not found: $hostedDeployScript"
}

Write-Host '[1/6] Inspect minapp_apps source checkout'
$sourceBranch = Invoke-GitCapture `
    -Repository $SourceRoot `
    -Arguments @('branch', '--show-current') `
    -Context 'minapp_apps branch lookup'
if ([string]::IsNullOrWhiteSpace($sourceBranch)) {
    throw 'minapp_apps is in detached HEAD state. Switch to an explicit branch first.'
}
$sourceStatus = Invoke-GitCapture `
    -Repository $SourceRoot `
    -Arguments @('status', '--porcelain') `
    -Context 'minapp_apps status lookup'
if (-not [string]::IsNullOrWhiteSpace($sourceStatus) -and -not $AllowDirtySource) {
    throw @"
minapp_apps has local changes. Commit or stash them before syncing.

Repository: $SourceRoot
Branch:     $sourceBranch

Use -AllowDirtySource only when deploying the current working tree is intentional.
"@
}
if ($sourceBranch -eq 'main' -and -not $AllowDirtySource) {
    Write-Host '  clean main checkout: pulling latest minapp_apps with --ff-only'
    Invoke-Checked `
        -FilePath 'git' `
        -Arguments @('-C', $SourceRoot, 'pull', '--ff-only') `
        -Context 'minapp_apps fast-forward pull'
}
$sourceCommit = Invoke-GitCapture `
    -Repository $SourceRoot `
    -Arguments @('rev-parse', '--short', 'HEAD') `
    -Context 'minapp_apps commit lookup'
Write-Host "  branch=$sourceBranch commit=$sourceCommit"
if (-not [string]::IsNullOrWhiteSpace($sourceStatus)) {
    Write-Warning 'Using a dirty minapp_apps working tree because -AllowDirtySource was specified.'
}

Write-Host '[2/6] Discover registered built-in assets from pubspec.yaml'
$registeredApps = [ordered]@{}
$assetPattern = '^\s*-\s+assets/builtin/(?<app>[a-z0-9_-]+)/(?<file>[^#]+?)\s*$'
foreach ($line in [System.IO.File]::ReadAllLines($pubspecPath)) {
    $match = [System.Text.RegularExpressions.Regex]::Match($line, $assetPattern)
    if (-not $match.Success) {
        continue
    }
    $registeredName = $match.Groups['app'].Value
    $relativeFile = $match.Groups['file'].Value.Trim()
    if (-not $registeredApps.Contains($registeredName)) {
        $registeredApps[$registeredName] = [System.Collections.Generic.List[string]]::new()
    }
    $registeredApps[$registeredName].Add($relativeFile)
}
if ($registeredApps.Count -eq 0) {
    throw "No assets/builtin entries were found in $pubspecPath"
}

$selectedApps = if ($All) {
    @($registeredApps.Keys)
}
else {
    @($requestedApps)
}
foreach ($selectedApp in $selectedApps) {
    if ($selectedApp -notmatch '^[a-z0-9_-]+$') {
        throw "Invalid app directory name: $selectedApp"
    }
    if (-not $registeredApps.Contains($selectedApp)) {
        $available = @($registeredApps.Keys) -join ', '
        throw "Built-in '$selectedApp' is not registered in pubspec.yaml. Available: $available"
    }
    $sourceDirectory = Join-Path $SourceRoot $selectedApp
    if (-not (Test-Path -LiteralPath $sourceDirectory -PathType Container)) {
        throw "Source directory for '$selectedApp' was not found: $sourceDirectory"
    }
    Write-Host "  ${selectedApp}: $($registeredApps[$selectedApp].Count) file(s)"
}

Write-Host '[3/6] Run source regression tests'
$sourceTests = [System.Collections.Generic.List[string]]::new()
foreach ($selectedApp in $selectedApps) {
    $sourceDirectory = Join-Path $SourceRoot $selectedApp
    foreach ($testFile in @(Get-ChildItem -LiteralPath $sourceDirectory -File -Filter 'test_*.js' | Sort-Object Name)) {
        $sourceTests.Add($testFile.FullName)
    }
}
if ($sourceTests.Count -eq 0) {
    Write-Host '  No test_*.js files found; skipped.'
}
else {
    Invoke-Checked `
        -FilePath 'node' `
        -Arguments (@('--test') + @($sourceTests)) `
        -Context 'Built-in source tests'
}

Write-Host '[4/6] Synchronize registered runtime assets'
$changedCount = 0
$unchangedCount = 0
$preservedOverlayCount = 0
$targetRelativePaths = [System.Collections.Generic.List[string]]::new()
foreach ($selectedApp in $selectedApps) {
    foreach ($relativeFile in $registeredApps[$selectedApp]) {
        $sourcePath = Join-Path (Join-Path $SourceRoot $selectedApp) $relativeFile
        $targetRelativePath = "apps/mobile/assets/builtin/$selectedApp/$relativeFile"
        $targetPath = Join-Path $repoRoot ($targetRelativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Registered source asset is missing: $sourcePath"
        }

        $targetExists = Test-Path -LiteralPath $targetPath -PathType Leaf
        if ($targetExists -and (Test-HostOverlayRequired -SourcePath $sourcePath -TargetPath $targetPath)) {
            $preservedOverlayCount += 1
            $targetRelativePaths.Add($targetRelativePath)
            Write-Host "  preserved Host overlay in $targetRelativePath"
            continue
        }

        $sourceBytes = @(Get-SyncBytes -Path $sourcePath)
        $targetBytes = if ($targetExists) { @([System.IO.File]::ReadAllBytes($targetPath)) } else { @() }
        $matches = $targetExists -and (Test-BytesEqual -Left $sourceBytes -Right $targetBytes)
        $targetStatus = Invoke-GitCapture `
            -Repository $repoRoot `
            -Arguments @('status', '--porcelain', '--', $targetRelativePath) `
            -Context "Target status lookup for $targetRelativePath"
        if (-not $matches -and -not [string]::IsNullOrWhiteSpace($targetStatus) -and -not $ForceOverwrite) {
            throw @"
Target asset has local changes that differ from minapp_apps:
  $targetRelativePath

Review the file first. Use -ForceOverwrite only when replacing it is intentional.
"@
        }
        if ($matches) {
            $unchangedCount += 1
            $targetRelativePaths.Add($targetRelativePath)
            continue
        }

        $targetDirectory = [System.IO.Path]::GetDirectoryName($targetPath)
        [System.IO.Directory]::CreateDirectory($targetDirectory) | Out-Null
        [System.IO.File]::WriteAllBytes($targetPath, $sourceBytes)
        $changedCount += 1
        $targetRelativePaths.Add($targetRelativePath)
        Write-Host "  updated $targetRelativePath"
    }
}
Write-Host "  changed=$changedCount unchanged=$unchangedCount preservedHostOverlays=$preservedOverlayCount"

Write-Host '[5/6] Verify the Flutter bundle and Git diff'
Push-Location $mobileRoot
try {
    Invoke-Checked `
        -FilePath 'flutter' `
        -Arguments @('test', 'test/builtin_apps_test.dart') `
        -Context 'Flutter built-in app tests'
}
finally {
    Pop-Location
}
Invoke-Checked `
    -FilePath 'git' `
    -Arguments (@('-C', $repoRoot, 'diff', '--check', '--') + @($targetRelativePaths)) `
    -Context 'Built-in asset diff check'

Write-Host '[6/6] Hosted AWS action'
if ($ApplyHosted) {
    Write-Host '  Applying the reviewed Hosted Terraform plan.'
    & $hostedDeployScript -Apply
}
elseif ($PlanHosted) {
    Write-Host '  Creating a Hosted Terraform plan only; AWS will not be changed.'
    & $hostedDeployScript
}
else {
    Write-Host '  Skipped. Use -PlanHosted to review AWS changes or -ApplyHosted to apply them.'
}

Write-Host ''
Write-Host 'Built-in synchronization complete.'
Write-Host "Source: $SourceRoot ($sourceBranch@$sourceCommit)"
Write-Host "Apps:   $($selectedApps -join ', ')"
Write-Host 'Review and commit the minapp repository changes. Android release remains a separate step.'
